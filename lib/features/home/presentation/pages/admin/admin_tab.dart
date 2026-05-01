import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'comunicacion_tab.dart';
import 'usuarios_tab.dart';
import 'mantenimiento_tab.dart';
import '../../../../../core/services/csv_upload.dart';

class AdminTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final TabController tabController;

  const AdminTab({
    super.key,
    required this.usuarioData,
    required this.tabController,
  });

  @override
  State<AdminTab> createState() => _AdminTabState();
}

class _AdminTabState extends State<AdminTab> {
  bool _mantenimientoDesbloqueado = false;
  int _tabAnterior = 0;

  String _normalizarDireccion(String direccion) {
    var texto = direccion.toLowerCase();
    texto = texto.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    texto = texto.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    texto = texto.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    texto = texto.replaceAll('apto', 'apartamento');
    texto = texto.replaceAll('apt', 'apartamento');
    texto = texto.replaceAll('dpto', 'departamento');
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
  }

  List<String> _parsearLineaCSV(String linea) {
    List<String> resultado = [];
    bool dentroComillas = false;
    StringBuffer campo = StringBuffer();
    for (int i = 0; i < linea.length; i++) {
      final char = linea[i];
      if (char == '"') {
        dentroComillas = !dentroComillas;
      } else if (char == ',' && !dentroComillas) {
        resultado.add(campo.toString());
        campo.clear();
      } else {
        campo.write(char);
      }
    }
    resultado.add(campo.toString());
    return resultado;
  }

  // _logicaReinicio moved to MantenimientoTab

  // _limpiarDatosDinamicos moved to MantenimientoTab

  // _limpiarDireccionesHuerfanas moved to MantenimientoTab

  // _restaurarTarjetaIds moved to MantenimientoTab

  Future<bool> _pedirSenaMantenimiento() async {
    final controller = TextEditingController();
    final correcto = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Color(0xFF1B5E20)),
            SizedBox(width: 8),
            Text('Acceso a Mantenimiento'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingrese la contraseña para acceder a Mantenimiento:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF1B5E20), width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = controller.text.trim();
              Navigator.pop(context, password == '272700');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            child: const Text('Acceder'),
          ),
        ],
      ),
    );
    return correcto ?? false;
  }

  void _levantarArchivoCSV() {
    startCsvUpload(
      (String contenidoDelArchivo) {
        List<String> lineas = contenidoDelArchivo.split('\n');
        if (lineas.isNotEmpty) lineas.removeAt(0);
        Map<String, List<Map<String, String>>> tarjetasMap = {};
        for (var linea in lineas) {
          if (linea.trim().isEmpty) continue;
          List<String> columnas = linea.split(',');
          if (columnas.length < 3) continue;
          final tarjeta = columnas[0].trim();
          final calle = columnas[2].trim();
          final complemento = columnas.length > 3 ? columnas[3].trim() : '';
          if (tarjeta.isEmpty || calle.isEmpty) continue;
          tarjetasMap.putIfAbsent(tarjeta, () => []);
          tarjetasMap[tarjeta]!
              .add({'calle': calle, 'complemento': complemento});
        }
        if (tarjetasMap.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No se pudieron extraer datos del CSV')),
          );
          return;
        }
        _mostrarSelectorTerritorioParaCSV(tarjetasMap);
      },
    );
  }

  void _mostrarSelectorTerritorioParaCSV(
    Map<String, List<Map<String, String>>> tarjetasMap,
  ) async {
    final territoriosSnap =
        await FirebaseFirestore.instance.collection('territorios').get();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿A qué territorio pertenece este CSV?'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: territoriosSnap.docs.map((doc) {
              final nombre = (doc.data())['nombre'] ?? doc.id;
              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF1B5E20)),
                title: Text(nombre),
                onTap: () {
                  Navigator.pop(context);
                  _procesarCSVEnTerritorio(doc.id, tarjetasMap);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
        ],
      ),
    );
  }

  Future<void> _procesarCSVEnTerritorio(
    String territorioId,
    Map<String, List<Map<String, String>>> tarjetasMap,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Creando tarjetas y direcciones...')),
        ]),
      ),
    );
    try {
      int totalTarjetas = 0;
      int totalDirecciones = 0;
      for (final entry in tarjetasMap.entries) {
        final nombreTarjeta = entry.key;
        final direcciones = entry.value;
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(nombreTarjeta)
            .set({
          'nombre': nombreTarjeta,
          'territorio_id': territorioId,
          'estado': 'disponible',
          'cantidad_direcciones': direcciones.length,
          'barrio': '',
          'created_at': FieldValue.serverTimestamp(),
          'bloqueado': true,
          'disponible_para_publicadores': false,
          'asignado_a': '',
          'asignado_en': null,
        }, SetOptions(merge: true));
        final batch = FirebaseFirestore.instance.batch();
        for (final dir in direcciones) {
          final calle = dir['calle'] ?? '';
          final complemento = dir['complemento'] ?? '';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final complementoSlug = complemento.isNotEmpty
              ? '_${complemento.replaceAll(' ', '_')}'
              : '';
          final docId =
              '${territorioId}_${nombreTarjeta}_${calle.replaceAll(' ', '_')}${complementoSlug}_$timestamp';
          batch.set(
            FirebaseFirestore.instance
                .collection('direcciones_globales')
                .doc(docId),
            {
              'calle': calle,
              'complemento': complemento,
              'direccion_normalizada':
                  _normalizarDireccion('$calle $complemento'),
              'informacion': '',
              'barrio': territorioId,
              'lat': '0',
              'lon': '0',
              'estado': 'activa',
              'territorio_id': territorioId,
              'tarjeta_id': nombreTarjeta,
              'created_at': FieldValue.serverTimestamp(),
              'tipo': 'csv',
              'estado_predicacion': 'pendiente',
              'predicado': false,
              'no_predicado': false,
              'es_hispano': true,
              'entrego_invitacion': false,
              'campana_especial': false,
              'asignado_a': null,
            },
          );
          totalDirecciones++;
        }
        await batch.commit();
        totalTarjetas++;
      }
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ CSV importado'),
            content: Text(
                '$totalTarjetas tarjetas creadas\n$totalDirecciones direcciones agregadas\n\nTerritorio: $territorioId'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'))
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _verDirectorioGlobal() {
    // Implementación simulada - en el código original habría navegación
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Ver Directorio Global - Función no implementada en esta versión'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _mostrarDialogoCrearTerritorio() {
    // Implementación simulada - en el código original habría diálogo
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Crear Territorio - Función no implementada en esta versión'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _abrirTerritorio(String territorioId, String nombre,
      {bool readOnly = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text(nombre,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1B5E20)))),
                        IconButton(
                            icon: const Icon(Icons.close, size: 28),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(thickness: 2),
                    if (!readOnly) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () => _mostrarDialogoCrearTarjeta(
                              context, territorioId),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Crear Nueva Tarjeta',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text('Tarjetas en este Territorio:',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .doc(territorioId)
                            .collection('tarjetas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                                child: CircularProgressIndicator());
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                            return const Center(
                                child: Text('No hay tarjetas creadas aún.',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic)));
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              final tarjeta = snapshot.data!.docs[index];
                              final tarjetaId = tarjeta.id;
                              final tarjetaMap =
                                  tarjeta.data() as Map<String, dynamic>;
                              final tarjetaNombre =
                                  tarjetaMap['nombre'] as String? ??
                                      'Sin nombre';
                              final cantidadDir =
                                  tarjetaMap['cantidad_direcciones'] ?? 0;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: Colors.blue.shade50,
                                elevation: 2,
                                child: ExpansionTile(
                                  leading: const Icon(Icons.folder,
                                      color: Colors.blue),
                                  title: Text(tarjetaNombre,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('direcciones_globales')
                                        .where('tarjeta_id',
                                            isEqualTo: tarjetaId)
                                        .snapshots(),
                                    builder: (context, dirSnap) {
                                      final count =
                                          dirSnap.data?.docs.length ?? 0;
                                      return Text('Dir. vinculadas: $count');
                                    },
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          icon: const Icon(Icons.add_circle,
                                              color: Colors.green, size: 20),
                                          onPressed: () =>
                                              _agregarDireccionesATarjeta(
                                                  context,
                                                  territorioId,
                                                  tarjetaId,
                                                  tarjetaNombre),
                                          tooltip: 'Agregar dirección'),
                                      IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.orange, size: 20),
                                          onPressed: () => _editarNombreTarjeta(
                                              territorioId,
                                              tarjetaId,
                                              tarjetaNombre),
                                          tooltip: 'Editar'),
                                      IconButton(
                                          icon: const Icon(Icons.delete_forever,
                                              color: Colors.redAccent,
                                              size: 20),
                                          onPressed: () async {
                                            final confirmar = await showDialog<
                                                    bool>(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                        title: const Text(
                                                            'Eliminar Tarjeta'),
                                                        content: Text(
                                                            '¿Eliminar "$tarjetaNombre"?'),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      c, false),
                                                              child: const Text(
                                                                  'Cancelar')),
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      c, true),
                                                              child: const Text(
                                                                  'Sí, Eliminar',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .red)))
                                                        ]));
                                            if (confirmar == true)
                                              await FirebaseFirestore.instance
                                                  .collection('territorios')
                                                  .doc(territorioId)
                                                  .collection('tarjetas')
                                                  .doc(tarjetaId)
                                                  .delete();
                                          },
                                          tooltip: 'Eliminar'),
                                    ],
                                  ),
                                  children: [
                                    FutureBuilder<QuerySnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaId)
                                          .get(),
                                      builder: (context, dirSnap) {
                                        if (!dirSnap.hasData)
                                          return const LinearProgressIndicator();
                                        final dirs = dirSnap.data!.docs;
                                        if (dirs.isEmpty)
                                          return const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Text(
                                                'Sin direcciones vinculadas',
                                                style: TextStyle(
                                                    color: Colors.grey)),
                                          );
                                        return Column(
                                          children: dirs.map((dir) {
                                            final d = dir.data()
                                                as Map<String, dynamic>;
                                            final calle =
                                                d['calle'] as String? ?? '';
                                            final complemento =
                                                d['complemento'] as String? ??
                                                    '';
                                            final estado =
                                                d['estado_predicacion']
                                                        as String? ??
                                                    'pendiente';
                                            return ListTile(
                                              dense: true,
                                              leading: const Icon(
                                                  Icons.location_on,
                                                  color: Colors.blue,
                                                  size: 18),
                                              title: Text(calle,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                              subtitle: complemento.isNotEmpty
                                                  ? Text(complemento,
                                                      style: const TextStyle(
                                                          fontSize: 11))
                                                  : null,
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: estado == 'completada'
                                                      ? Colors.green.shade100
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(estado,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: estado ==
                                                                'completada'
                                                            ? Colors
                                                                .green.shade800
                                                            : Colors.grey
                                                                .shade700)),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarDialogoCrearTarjeta(BuildContext parentContext, String terId) {
    final ctrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 40, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text('Crear Nueva Tarjeta',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ctrl,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Ej: A01 - CENTRO 1',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1B5E20), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) return;
                          try {
                            String nombreTarjeta = ctrl.text.trim();
                            await FirebaseFirestore.instance
                                .collection('territorios')
                                .doc(terId)
                                .collection('tarjetas')
                                .doc(nombreTarjeta)
                                .set({
                              'nombre': nombreTarjeta,
                              'territorio_id': terId,
                              'estado': 'disponible',
                              'cantidad_direcciones': 0,
                              'barrio': '',
                              'created_at': FieldValue.serverTimestamp(),
                              'bloqueado': true,
                              'disponible_para_publicadores': false,
                              'asignado_a': '',
                              'asignado_en': null,
                            });
                            if (context.mounted) Navigator.pop(context);
                            if (parentContext.mounted) {
                              await Future.delayed(
                                  const Duration(milliseconds: 500));
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('✅ ¡Tarjeta creada con éxito!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('❌ Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Crear Tarjeta',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _eliminarDireccion(
      String docId, String territorioId, String tarjetaId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.delete_forever, color: Colors.red),
          SizedBox(width: 8),
          Text('Eliminar Dirección'),
        ]),
        content: const Text(
          '¿Eliminar esta dirección? Se eliminará del directorio global inmediatamente.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      // Delete directly from direcciones_globales — removes from everywhere instantly
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dirección eliminada del directorio global'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _agregarDireccionesATarjeta(BuildContext context, String terId,
      String tarjetaId, String nombre) async {}
  Future<void> _editarNombreTarjeta(
      String terId, String tarjetaId, String nombre) async {}
  void _editarNombreTerritorio(DocumentSnapshot doc) {
    // Implementación simulada - en el código original habría diálogo
    final nombre =
        (doc.data() as Map<String, dynamic>)['nombre'] ?? 'Sin nombre';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Editar Territorio: $nombre'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _borrarTerritorio(
      String territorioId, String nombreTerritorio) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar Territorio'),
        content: Text(
          '¿Eliminar el territorio "$nombreTerritorio"? Esto NO eliminará las direcciones del directorio global.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorioId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Territorio "$nombreTerritorio" eliminado'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando territorio: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarDialogoEnviar({required String terId, required String nombre}) {
    // Implementación simulada - en el código original habría diálogo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Enviar Territorio: $nombre'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              children: [
                Row(
                  children: const [
                    Icon(Icons.admin_panel_settings, color: Color(0xFF1B5E20)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Administración',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: widget.tabController,
              indicatorColor: const Color(0xFF1B5E20),
              indicatorWeight: 3,
              labelColor: const Color(0xFF1B5E20),
              unselectedLabelColor: Colors.black54,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              onTap: (index) {
                if (index == 4 && !_mantenimientoDesbloqueado) {
                  widget.tabController.animateTo(_tabAnterior);
                  _pedirSenaMantenimiento().then((correcto) {
                    if (correcto && mounted) {
                      setState(() => _mantenimientoDesbloqueado = true);
                      widget.tabController.animateTo(4);
                    }
                  });
                } else if (index != 4) {
                  setState(() => _tabAnterior = index);
                }
              },
              tabs: const [
                Tab(
                  icon: Icon(Icons.folder_copy, color: Color(0xFF1B5E20)),
                  text: 'Estructura',
                ),
                Tab(
                  icon: Icon(Icons.map, color: Color(0xFF1B5E20)),
                  text: 'Territorios',
                ),
                Tab(
                  icon: Icon(Icons.campaign, color: Color(0xFF1B5E20)),
                  text: 'Comunicación',
                ),
                Tab(
                  icon: Icon(Icons.people_outline, color: Color(0xFF1B5E20)),
                  text: 'Usuarios',
                ),
                Tab(
                  icon: Icon(Icons.build, color: Color(0xFF1B5E20)),
                  text: 'Mantenimiento',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: widget.tabController,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1. Directorio Maestro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: _levantarArchivoCSV,
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                            'Subir CSV a Directorio Maestro',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _verDirectorioGlobal,
                        icon: const Icon(
                          Icons.list_alt,
                          color: Color(0xFF1B5E20),
                        ),
                        label: const Text(
                          'Ver contenido del Directorio Global',
                          style: TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text(
                        '2. Gestión de Territorios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _mostrarDialogoCrearTerritorio,
                          icon: const Icon(Icons.create_new_folder),
                          label: const Text(
                            'Crear Nuevo Territorio',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Territorios Creados:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: Text(
                                  'No hay territorios creados aún.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return GestureDetector(
                                onTap: () => _abrirTerritorio(
                                  doc.id,
                                  (doc.data()
                                          as Map<String, dynamic>)['nombre'] ??
                                      doc.id,
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  color: Colors.green.shade50,
                                  elevation: 2,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.folder,
                                      color: Color(0xFF1B5E20),
                                    ),
                                    title: Text(
                                      (doc.data() as Map<String, dynamic>)[
                                              'nombre'] ??
                                          doc.id,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('territorios')
                                          .doc(doc.id)
                                          .collection('tarjetas')
                                          .snapshots(),
                                      builder: (context, tarjetasSnapshot) {
                                        int cantidadTarjetas = tarjetasSnapshot
                                                .data?.docs.length ??
                                            0;
                                        return Text(
                                          'Tarjetas vinculadas: $cantidadTarjetas',
                                        );
                                      },
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.orange,
                                          ),
                                          onPressed: () =>
                                              _editarNombreTerritorio(doc),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_forever,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () => _borrarTerritorio(
                                            doc.id,
                                            (doc.data() as Map<String,
                                                    dynamic>)['nombre'] ??
                                                doc.id,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Territorios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: Text(
                                  'No hay territorios creados aún.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var doc = snapshot.data!.docs[index];
                              return InkWell(
                                onTap: () => _abrirTerritorio(
                                  doc.id,
                                  (doc.data()
                                          as Map<String, dynamic>)['nombre'] ??
                                      doc.id,
                                  readOnly: true,
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: const Icon(
                                                Icons.folder,
                                                color: Color(0xFF1B5E20),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (doc.data() as Map<String,
                                                                dynamic>)[
                                                            'nombre'] ??
                                                        doc.id,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  StreamBuilder<QuerySnapshot>(
                                                    stream: FirebaseFirestore
                                                        .instance
                                                        .collection(
                                                          'territorios',
                                                        )
                                                        .doc(doc.id)
                                                        .collection('tarjetas')
                                                        .snapshots(),
                                                    builder: (
                                                      context,
                                                      tarjetasSnapshot,
                                                    ) {
                                                      int cantidadTarjetas =
                                                          tarjetasSnapshot
                                                                  .data
                                                                  ?.docs
                                                                  .length ??
                                                              0;
                                                      return Text(
                                                        'Tarjetas vinculadas: $cantidadTarjetas',
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.arrow_forward_ios,
                                              size: 18,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _mostrarDialogoEnviar(
                                              terId: doc.id,
                                              nombre: (doc.data() as Map<String,
                                                      dynamic>)['nombre'] ??
                                                  doc.id,
                                            ),
                                            icon: const Icon(
                                              Icons.send,
                                              color: Colors.green,
                                            ),
                                            label: const Text(
                                              'Enviar territorio completo',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green,
                                              side: const BorderSide(
                                                color: Colors.green,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                ComunicacionTab(usuarioData: widget.usuarioData),
                UsuariosTab(usuarioData: widget.usuarioData),
                const MantenimientoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
