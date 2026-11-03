import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'comunicacion_tab.dart';
import 'comercial_tab.dart';
import 'usuarios_tab.dart';
import 'auditor_panel_page.dart';
import 'mantenimiento_tab.dart';
import '../../../../../core/services/csv_upload.dart';
import '../../../../../core/services/algolia_service.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';
import '../../../../../core/utils/direccion_utils.dart';
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
    return normalizarDireccion(direccion);
  }

  List<String> _parsearLineaCSV(String linea) {
    final comas = _contarSeparador(linea, ',');
    final puntosComa = _contarSeparador(linea, ';');
    final separador = puntosComa > comas ? ';' : ',';
    return _dividirPorSeparador(linea, separador);
  }

  int _contarSeparador(String linea, String sep) {
    int conteo = 0;
    bool dentroComillas = false;
    for (int i = 0; i < linea.length; i++) {
      final char = linea[i];
      if (char == '"') {
        dentroComillas = !dentroComillas;
      } else if (char == sep && !dentroComillas) {
        conteo++;
      }
    }
    return conteo;
  }

  List<String> _dividirPorSeparador(String linea, String separador) {
    List<String> resultado = [];
    bool dentroComillas = false;
    StringBuffer campo = StringBuffer();
    for (int i = 0; i < linea.length; i++) {
      final char = linea[i];
      if (char == '"') {
        dentroComillas = !dentroComillas;
      } else if (char == separador && !dentroComillas) {
        resultado.add(campo.toString());
        campo.clear();
      } else {
        campo.write(char);
      }
    }
    resultado.add(campo.toString());
    return resultado;
  }

  bool _esFilaEncabezado(String campo) {
    final c = campo.toUpperCase();
    return c.contains('CALLES') ||
        c.contains('HAGA CLICK') ||
        c.contains('DIRECCIONES') ||
        c.contains('DEVOLUCION') ||
        c.contains('HTTP');
  }

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
      context,
      (String contenidoDelArchivo) async {
        try {
          List<String> lineas = contenidoDelArchivo.split('\n');
          if (lineas.isNotEmpty) lineas.removeAt(0);

          Map<String, List<Map<String, String>>> tarjetasMap = {};

          for (var linea in lineas) {
            if (linea.trim().isEmpty) continue;

            List<String> columnas = _parsearLineaCSV(linea);

            if (columnas.length >= 3) {
              final tarjeta = columnas[0].trim();
              final calle = columnas.length > 2 ? columnas[2].trim() : '';
              final complemento = columnas.length > 3 ? columnas[3].trim() : '';

              if (tarjeta.isNotEmpty && calle.isNotEmpty) {
                tarjetasMap.putIfAbsent(tarjeta, () => []);
                tarjetasMap[tarjeta]!.add({
                  'calle': calle,
                  'complemento': complemento,
                });
              }
            }
          }

          if (tarjetasMap.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudieron extraer datos del CSV'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          _mostrarSelectorTerritorioParaCSV(tarjetasMap);
        } catch (e) {
          debugPrint('Error procesando CSV: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al procesar archivo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

  /// Direcciones ya presentes en una tarjeta, normalizadas, para no volver a
  /// crearlas al importar. El set se usa como filtro: `add` devuelve `false` si
  /// el valor ya estaba, lo que además detecta duplicados dentro del mismo
  /// archivo importado.
  Future<Set<String>> _direccionesNormalizadasDeTarjeta(
    String tarjetaId,
    String territorioId,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();
      final out = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['territorio_id'] ?? '').toString() != territorioId) continue;
        final n = (data['direccion_normalizada'] ?? '').toString().trim();
        if (n.isNotEmpty) out.add(n);
      }
      return out;
    } catch (_) {
      // Si no se puede leer, se importan todas: es preferible un duplicado
      // occasional a perder direcciones por un fallo de red.
      return <String>{};
    }
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
      int duplicadasOmitidas = 0;
      final Map<String, Map<String, dynamic>> direccionesParaAlgolia = {};
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

        // El id del documento lleva un timestamp, así que el mismo `batch.set`
        // NUNCA colisiona: cargar dos veces el mismo archivo crea un documento
        // duplicado por dirección y eso infla los conteos. Se comprueba antes
        // qué direcciones ya existen en esta tarjeta para saltarlas en vez de
        // duplicarlas.
        final yaExistentes = await _direccionesNormalizadasDeTarjeta(
          nombreTarjeta,
          territorioId,
        );
        var duplicadas = 0;

        for (final dir in direcciones) {
          final calle = dir['calle'] ?? '';
          final complemento = dir['complemento'] ?? '';
          final normalizada =
              _normalizarDireccion('$calle $complemento').trim();
          if (normalizada.isNotEmpty && !yaExistentes.add(normalizada)) {
            duplicadas++;
            continue;
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final complementoSlug = complemento.isNotEmpty
              ? '_${complemento.replaceAll(' ', '_')}'
              : '';
          final docId =
              '${territorioId}_${nombreTarjeta}_${calle.replaceAll(' ', '_')}${complementoSlug}_$timestamp';

          final Map<String, dynamic> data = {
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
          };

          batch.set(
            FirebaseFirestore.instance
                .collection('direcciones_globales')
                .doc(docId),
            data,
          );
          direccionesParaAlgolia[docId] = data;
          totalDirecciones++;
        }
        duplicadasOmitidas += duplicadas;
        await batch.commit();

        for (final entry in direccionesParaAlgolia.entries) {
          await AlgoliaService.sincronizarUna(entry.key, entry.value);
        }

        totalTarjetas++;
      }
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ CSV importado'),
            content: Text(
                '$totalTarjetas tarjetas creadas\n$totalDirecciones direcciones agregadas'
                '${duplicadasOmitidas > 0 ? '\n$duplicadasOmitidas omitidas por ya existir' : ''}'
                '\n\nTerritorio: $territorioId'),
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
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Directorio Global',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20))),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                TextField(
                  controller: ctrl,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Buscar dirección... (ej: Rua Ivai, Rua Itopoa)',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setDlgState(() {}),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('direcciones_globales')
                      .orderBy('created_at', descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                          child: Text('No hay direcciones.',
                              style: TextStyle(color: Colors.grey)));
                    }

                    final textoBusqueda = ctrl.text.trim().toLowerCase();
                    final docsFiltrados = textoBusqueda.isEmpty
                        ? docs
                        : docs.where((doc) {
                            final d =
                                (doc.data() as Map<String, dynamic>?) ?? {};
                            final calle = (d['calle'] as String?) ?? '';
                            final complemento =
                                (d['complemento'] as String?) ?? '';
                            final tarjetaId =
                                (d['tarjeta_id'] as String?) ?? '';
                            final texto =
                                _normalizarDireccion('$calle $complemento $tarjetaId')
                                    .toLowerCase();
                            return texto.contains(textoBusqueda);
                          }).toList();

                    if (docsFiltrados.isEmpty) {
                      return Center(
                          child: Text('Sin resultados para "$textoBusqueda".',
                              style: const TextStyle(color: Colors.grey)));
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            docsFiltrados.length == docs.length
                                ? '${docs.length} direcciones en total'
                                : '${docsFiltrados.length} de ${docs.length} direcciones',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: docsFiltrados.length,
                            itemBuilder: (context, i) {
                              final d = (docsFiltrados[i].data()
                                  as Map<String, dynamic>?) ??
                                  {};
                              final calle = (d['calle'] as String?) ?? '';
                              final complemento =
                                  (d['complemento'] as String?) ?? '';
                              final tarjetaId =
                                  (d['tarjeta_id'] as String?) ?? '-';
                              final estado =
                                  (d['estado_predicacion'] as String?) ??
                                      'pendiente';
                              final predicado =
                                  (d['predicado'] as bool?) ?? false;
                              final territorioId =
                                  (d['territorio_id'] as String?) ?? '';
                              final territorioNombreDir =
                                  (d['territorio_nombre'] as String?) ?? '';

                              return ListTile(
                                dense: true,
                                onTap: () {
                                  if (territorioId.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Esta dirección aún no está asignada a ningún territorio.'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.pop(context);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _abrirTerritorio(
                                      territorioId,
                                      territorioNombreDir.isNotEmpty
                                          ? territorioNombreDir
                                          : territorioId,
                                      tarjetaParaExpandir:
                                          tarjetaId != '-' ? tarjetaId : null,
                                      direccionParaResaltar:
                                          docsFiltrados[i].id,
                                    );
                                  });
                                },
                                leading: Icon(
                                  Icons.location_on,
                                  color: predicado
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 18,
                                ),
                                title: Text(
                                  '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  'Tarjeta: $tarjetaId · $estado',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: predicado
                                        ? Colors.green.shade100
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    predicado ? 'Predicada' : 'Pendiente',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: predicado
                                          ? Colors.green.shade800
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

Future<void> _mostrarDialogoCrearTerritorio() async {
    final ctrl = TextEditingController();
    String tipoSeleccionado = 'normal';
    final Set<String> fuentesSeleccionadas = {};

    final territoriosSnap = await FirebaseFirestore.instance
        .collection('territorios')
        .get();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDlgState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.create_new_folder, color: Color(0xFF1B5E20)),
            SizedBox(width: 8),
            Text('Crear Nuevo Territorio'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nombre del territorio',
                      hintText: 'Ej: Norte, Centro, Barrio Sur',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFF1B5E20), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tipo de territorio',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  ...['normal', 'comercial', 'base'].map((tipo) {
                    final labels = {
                      'normal': 'Normal (residencial)',
                      'comercial': 'Comercial (genera tarjetas ZONA-N)',
                      'base': 'Base (solo almacena direcciones)',
                    };
                    return RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(labels[tipo]!,
                          style: const TextStyle(fontSize: 13)),
                      value: tipo,
                      groupValue: tipoSeleccionado,
                      activeColor: const Color(0xFF1B5E20),
                      onChanged: (v) => setDlgState(() {
                        tipoSeleccionado = v!;
                      }),
                    );
                  }),
                  if (tipoSeleccionado == 'comercial') ...[
                    const SizedBox(height: 8),
                    const Text('Usar direcciones de (bases):',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    if (territoriosSnap.docs
                        .where((d) => d.data()['tipo'] == 'base')
                        .isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Aún no hay territorios base. Crea uno y conviértelo a base o usa "Convertir en Base".',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      )
                    else
                      ...territoriosSnap.docs
                          .where((d) => d.data()['tipo'] == 'base')
                          .map((doc) {
                        final nombre =
                            doc.data()['nombre'] ?? doc.id;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(nombre.toString(),
                              style: const TextStyle(fontSize: 13)),
                          value: fuentesSeleccionadas.contains(doc.id),
                          activeColor: const Color(0xFF1B5E20),
                          onChanged: (v) => setDlgState(() {
                            if (v == true) {
                              fuentesSeleccionadas.add(doc.id);
                            } else {
                              fuentesSeleccionadas.remove(doc.id);
                            }
                          }),
                        );
                      }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white),
              child: const Text('Crear'),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isEmpty) return;
                if (tipoSeleccionado == 'comercial' &&
                    fuentesSeleccionadas.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Selecciona al menos una base.'),
                        backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(dialogCtx);
                try {
                  await FirebaseFirestore.instance
                      .collection('territorios')
                      .doc(nombre.toUpperCase().replaceAll(' ', '_'))
                      .set({
                    'nombre': nombre,
                    'tipo': tipoSeleccionado,
                    if (tipoSeleccionado == 'comercial')
                      'fuentes_base': fuentesSeleccionadas.toList(),
                    'created_at': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Territorio "$nombre" creado'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Error creando territorio: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
);
  }

  Widget _buildTarjetaCupo(int count) {
    Color fondo;
    Color texto;
    String etiqueta;
    if (count > 8) {
      fondo = Colors.red.shade100;
      texto = Colors.red.shade900;
      etiqueta = 'Saturada (>8) · Requiere división';
    } else if (count >= 4 && count <= 6) {
      fondo = Colors.green.shade100;
      texto = Colors.green.shade900;
      etiqueta = 'Capacidad recomendada (4-6)';
    } else if (count == 7 || count == 8) {
      fondo = Colors.orange.shade100;
      texto = Colors.orange.shade900;
      etiqueta = 'Límite máximo (hasta 8)';
    } else {
      fondo = Colors.grey.shade100;
      texto = Colors.grey.shade700;
      etiqueta = 'Baja ocupación';
    }
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: texto),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 8) const Icon(Icons.warning, color: Colors.red, size: 12),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: 10,
                color: texto,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirTerritorio(String territorioId, String nombre,
      {bool readOnly = false, String? tarjetaParaExpandir, String? direccionParaResaltar}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final tarjetaKey = GlobalKey();
        bool scrollHecho = false;
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
                              final esTarjetaObjetivo =
                                  tarjetaId == tarjetaParaExpandir;
                              if (esTarjetaObjetivo && !scrollHecho) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!scrollHecho &&
                                      tarjetaKey.currentContext != null) {
                                    scrollHecho = true;
                                    Scrollable.ensureVisible(
                                      tarjetaKey.currentContext!,
                                      alignment: 0.05,
                                      duration:
                                          const Duration(milliseconds: 400),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                });
                              }
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: esTarjetaObjetivo
                                    ? Colors.orange.shade100
                                    : Colors.blue.shade50,
                                elevation: esTarjetaObjetivo ? 4 : 2,
                                child: ExpansionTile(
                                  key: esTarjetaObjetivo ? tarjetaKey : null,
                                  initiallyExpanded: esTarjetaObjetivo,
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
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildTarjetaCupo(count),
                                          Text('Dir. vinculadas: $count'),
                                        ],
                                      );
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
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaId)
                                          .snapshots(),
                                      builder: (context, dirSnap) {
                                        if (!dirSnap.hasData) {
                                          return const LinearProgressIndicator();
                                        }
                                        final dirs = dirSnap.data!.docs;
                                        if (dirs.isEmpty) {
                                          return const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Text(
                                                'Sin direcciones vinculadas',
                                                style: TextStyle(
                                                    color: Colors.grey)),
                                          );
                                        }
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
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                ListTile(
                                                  dense: true,
                                                  selected:
                                                      dir.id == direccionParaResaltar,
                                                  leading: const Icon(
                                                      Icons.location_on,
                                                      color: Colors.blue,
                                                      size: 18),
                                                  title: Text(calle,
                                                      style: const TextStyle(
                                                          fontSize: 13)),
                                                  subtitle: complemento
                                                          .isNotEmpty
                                                      ? Text(complemento,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 11))
                                                      : null,
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 5,
                                                            vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              estado == 'completada'
                                                                  ? Colors.green
                                                                      .shade100
                                                                  : Colors.grey
                                                                      .shade100,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                  5),
                                                        ),
                                                        child: Text(estado,
                                                            style: TextStyle(
                                                                fontSize: 9,
                                                                color: estado ==
                                                                        'completada'
                                                                    ? Colors.green
                                                                        .shade800
                                                                    : Colors.grey
                                                                        .shade700)),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit,
                                                            color: Colors.orange,
                                                            size: 16),
                                                        padding: EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        onPressed: () =>
                                                            _editarDireccion(
                                                                dir.id, d),
                                                        tooltip: 'Editar',
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons.delete_forever,
                                                            color: Colors.redAccent,
                                                            size: 16),
                                                        padding: EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        onPressed: () =>
                                                            _eliminarDireccion(
                                                                dir.id,
                                                                territorioId,
                                                                tarjetaId),
                                                        tooltip: 'Eliminar',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
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

  /// Abre la vista del territorio comercial (ZONA-N).
  void _abrirVistaComercial(String territorioId, String nombre) {
    ComercialTab.abrir(context, territorioId, nombre, widget.usuarioData);
  }

  void _mostrarDialogoCrearTarjeta(BuildContext parentContext, String terId) {
    final ctrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (dialogCtx) {
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
                        fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? const Color(0xFFF5F5F5),
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
                            final nombreTarjeta = ctrl.text.trim();
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
                            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('✅ ¡Tarjeta creada con éxito!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            debugPrint('❌ Error creando tarjeta: $e');
                            if (mounted) {
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
                  onPressed: () => Navigator.pop(dialogCtx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editarDireccion(String docId, Map<String, dynamic> data) async {
    final calleCtrl =
        TextEditingController(text: data['calle'] as String? ?? '');
    final complementoCtrl =
        TextEditingController(text: data['complemento'] as String? ?? '');
    final informacionCtrl =
        TextEditingController(text: data['informacion'] as String? ?? '');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.edit_location_alt, color: Color(0xFF1B5E20)),
          SizedBox(width: 8),
          Text('Editar dirección'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: calleCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Calle *',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF1B5E20), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: complementoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Complemento',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF1B5E20), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: informacionCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Información',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF1B5E20), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    final calle = calleCtrl.text.trim();
    if (calle.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(docId)
          .update({
        'calle': calle,
        'complemento': complementoCtrl.text.trim(),
        'informacion': informacionCtrl.text.trim(),
        'direccion_normalizada':
            _normalizarDireccion('$calle ${complementoCtrl.text.trim()}'),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Dirección actualizada'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('❌ Error editando dirección: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
      // Al eliminar una dirección hay que descontarla de los contadores de la
      // tarjeta; si no, `cantidad_direcciones`/`totalDirecciones` quedan
      // inflados (antes nunca bajaban). Se hace en un batch con el delete.
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(docId));
      if (territorioId.isNotEmpty && tarjetaId.isNotEmpty) {
        final tarjetaRef = FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorioId)
            .collection('tarjetas')
            .doc(tarjetaId);
        if ((await tarjetaRef.get()).exists) {
          batch.update(tarjetaRef, {
            'cantidad_direcciones': FieldValue.increment(-1),
            'totalDirecciones': FieldValue.increment(-1),
          });
        }
      }
      await batch.commit();
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

  Future<void> _agregarDireccionesATarjeta(
    BuildContext parentContext,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    final calleCtrl = TextEditingController();
    final complementoCtrl = TextEditingController();
    final detallesCtrl = TextEditingController();

    await showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> guardarDireccion() async {
              final calle = calleCtrl.text.trim();
              if (calle.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('La dirección es obligatoria')),
                );
                return;
              }
              try {
                final complemento = complementoCtrl.text.trim();
                final ts = DateTime.now().millisecondsSinceEpoch;
                final slug = complemento.isNotEmpty
                    ? '_${complemento.replaceAll(' ', '_')}'
                    : '';
                final docId =
                    '${terId}_${tarjetaId}_${calle.replaceAll(' ', '_').replaceAll(',', '')}${slug}_$ts';

                await FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .doc(docId)
                    .set({
                  'calle': calle,
                  'complemento': complemento,
                  'informacion': detallesCtrl.text.trim(),
                  'direccion_normalizada':
                      _normalizarDireccion('$calle $complemento'),
                  'barrio': terId,
                  'territorio_id': terId,
                  'tarjeta_id': tarjetaId,
                  'estado': 'activa',
                  'estado_predicacion': 'pendiente',
                  'predicado': false,
                  'visitado': false,
                  'asignado_a': null,
                  'tipo': 'manual',
                  'created_at': FieldValue.serverTimestamp(),
                });

                calleCtrl.clear();
                complementoCtrl.clear();
                detallesCtrl.clear();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Dirección guardada — agrega otra'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Agregar direcciones\n$tarjetaNombre',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _subirCSVATarjeta(
                            context, terId, tarjetaId, tarjetaNombre),
                        icon: const Icon(Icons.cloud_upload,
                            color: Color(0xFF1B5E20)),
                        label: const Text('SUBIR CSV',
                            style: TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF1B5E20)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: calleCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Dirección *',
                        hintText: 'Ej: R. Pedro Budziak, 49',
                        prefixIcon: const Icon(Icons.location_on,
                            color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1B5E20), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: complementoCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Complemento',
                        hintText: 'Ej: Apto 12, Casa fondo',
                        prefixIcon:
                            const Icon(Icons.home, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1B5E20), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detallesCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Detalles',
                        hintText: 'Notas adicionales...',
                        prefixIcon:
                            const Icon(Icons.notes, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1B5E20), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.check_circle,
                                color: Colors.grey),
                            label: const Text('Terminar',
                                style: TextStyle(color: Colors.grey)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: guardarDireccion,
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'Guardar y agregar otra',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _editarNombreTarjeta(
      String terId, String tarjetaId, String nombre) async {
    final ctrl = TextEditingController(text: nombre);
    final nuevoNombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nombre de tarjeta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevoNombre == null || nuevoNombre.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({'nombre': nuevoNombre});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Nombre actualizado'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('❌ Error editando tarjeta: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editarNombreTerritorio(DocumentSnapshot doc) async {
    final nombreActual =
        (doc.data() as Map<String, dynamic>)['nombre'] ?? 'Sin nombre';
    final ctrl = TextEditingController(text: nombreActual.toString());
    final nuevoNombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nombre de territorio'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nombre',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFF1B5E20), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nuevoNombre == null || nuevoNombre.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      // 1. Actualizar el nombre del territorio
      await db
          .collection('territorios')
          .doc(doc.id)
          .update({'nombre': nuevoNombre});

      // 2. Propagar el nuevo nombre a sus tarjetas
      final tarjetas = await db
          .collection('territorios')
          .doc(doc.id)
          .collection('tarjetas')
          .get();
      final batch = db.batch();
      for (final t in tarjetas.docs) {
        batch.update(t.reference, {'territorio_nombre': nuevoNombre});
      }

      // 3. Propagar el nuevo nombre a las direcciones del territorio
      //    (directorio global que referencia este territorio)
      final direcciones = await db
          .collection('direcciones_globales')
          .where('territorio_id', isEqualTo: doc.id)
          .get();
      for (final d in direcciones.docs) {
        batch.update(d.reference, {'territorio_nombre': nuevoNombre});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Nombre de territorio actualizado'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('❌ Error editando territorio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _convertirEnBase(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nombre = (data['nombre'] ?? doc.id).toString();
    final yaBase = data['tipo'] == 'base';
    if (yaBase) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este territorio ya es Base.'),
            backgroundColor: Colors.grey),
      );
      return;
    }
    if (!mounted) return;
    String? categoria = 'farmacia';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: const Text('Convertir en Base'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'El territorio "$nombre" pasará a ser BASE: solo almacenará direcciones en el directorio global y no se enviará a publicadores.\n\nLas direcciones ya existentes se conservan. ¿Continuar?'),
              const SizedBox(height: 16),
              const Text('¿Qué tipo de comercios contiene?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...['farmacia', 'mercado', 'mecanica', 'escuela'].map((cat) {
                final colores = {
                  'farmacia': Colors.teal,
                  'mercado': Colors.orange,
                  'mecanica': Colors.blueGrey,
                  'escuela': Colors.indigo,
                };
                return RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      cat[0].toUpperCase() + cat.substring(1),
                      style: const TextStyle(fontSize: 14)),
                  value: cat,
                  groupValue: categoria,
                  activeColor: colores[cat],
                  onChanged: (v) => setSt(() => categoria = v),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white),
              child: const Text('Convertir'),
            ),
          ],
        ),
      ),
    );
    if (confirmar != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(doc.id)
          .update({
        'tipo': 'base',
        'categoria': categoria,
      });
      // Propagar la categoría a las direcciones existentes de la base.
      final dirs = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('territorio_id', isEqualTo: doc.id)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in dirs.docs) {
        batch.update(d.reference, {'categoria': categoria});
      }
      if (dirs.docs.isNotEmpty) await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ "$nombre" ahora es base (${dirs.docs.length} dirs marcadas como $categoria)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error convirtiendo a base: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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

  void _subirCSVATarjeta(
    BuildContext context,
    String terId,
    String tarjetaId,
    String tarjetaNombre,
  ) {
    startCsvUpload(
      context,
      (String contenido) async {
        List<String> lineas = contenido.split('\n');

        int idxCalle = 1;
        int idxComplemento = 8;
        int idxInfo = 11;

        for (var l in lineas) {
          final upper = l.toUpperCase();
          if (upper.contains('CALLES')) {
            final h = _parsearLineaCSV(l);
            for (var i = 0; i < h.length; i++) {
              final col = h[i].trim().toUpperCase();
              if (col == 'CALLES') idxCalle = i;
              if (col == 'COMPLEMENTO') idxComplemento = i;
              if (col == 'INFORMACIONES' || col == 'INFO') idxInfo = i;
            }
            break;
          }
        }

        List<Map<String, String>> direcciones = [];
        for (var linea in lineas) {
          linea = linea.trim().replaceAll('\r', '');
          if (linea.isEmpty) continue;

          final partes = _parsearLineaCSV(linea);
          if (idxCalle >= partes.length) continue;

          final calle = partes[idxCalle].trim();
          if (calle.isEmpty || _esFilaEncabezado(calle)) continue;

          final complemento =
              idxComplemento < partes.length ? partes[idxComplemento].trim() : '';
          final informacion =
              idxInfo < partes.length ? partes[idxInfo].trim() : '';

          direcciones.add({
            'calle': calle,
            'complemento': complemento,
            'informacion': informacion,
          });
        }

        if (direcciones.isEmpty) {
          if (context.mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se encontraron direcciones')),
            );
          return;
        }
        if (context.mounted)
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => const AlertDialog(
              content: Row(children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Importando direcciones...')),
              ]),
            ),
          );
        try {
          final batch = FirebaseFirestore.instance.batch();
          final Map<String, Map<String, dynamic>> direccionesParaAlgolia = {};

          // Igual que en el importador de CSVs: el id lleva timestamp, así que
          // hay que filtrar a mano lo que ya existe en la tarjeta.
          final yaExistentes =
              await _direccionesNormalizadasDeTarjeta(tarjetaId, terId);
          var duplicadasOmitidas = 0;

          for (final dir in direcciones) {
            final calle = dir['calle'] ?? '';
            final complemento = dir['complemento'] ?? '';
            final normalizada =
                _normalizarDireccion('$calle $complemento').trim();
            if (normalizada.isNotEmpty && !yaExistentes.add(normalizada)) {
              duplicadasOmitidas++;
              continue;
            }
            final ts = DateTime.now().millisecondsSinceEpoch;
            final slug = complemento.isNotEmpty
                ? '_${complemento.replaceAll(' ', '_')}'
                : '';
            final docId =
                '${terId}_${tarjetaId}_${calle.replaceAll(' ', '_').replaceAll(',', '')}${slug}_$ts';
            final data = {
              'calle': calle,
              'complemento': complemento,
              'informacion': dir['informacion'] ?? '',
              'direccion_normalizada':
                  _normalizarDireccion('$calle $complemento'),
              'barrio': terId,
              'territorio_id': terId,
              'tarjeta_id': tarjetaId,
              'estado': 'activa',
              'estado_predicacion': 'pendiente',
              'predicado': false,
              'visitado': false,
              'asignado_a': null,
              'tipo': 'csv',
              'created_at': FieldValue.serverTimestamp(),
            };
            batch.set(
              FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .doc(docId),
              data,
            );
            direccionesParaAlgolia[docId] = data;
          }
          await batch.commit();

          for (final entry in direccionesParaAlgolia.entries) {
            await AlgoliaService.sincronizarUna(entry.key, entry.value);
          }

          if (context.mounted) {
            Navigator.pop(context);
            final importadas = direcciones.length - duplicadasOmitidas;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ $importadas direcciones importadas a $tarjetaNombre'
                  '${duplicadasOmitidas > 0 ? ' · $duplicadasOmitidas omitidas por ya existir' : ''}',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('❌ Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
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
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Color(0xFF1B5E20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.t('administration'),
                        style: const TextStyle(
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
              tabs: [
                Tab(
                  icon: const Icon(Icons.folder_copy, color: Color(0xFF1B5E20)),
                  text: context.t('structure'),
                ),
                Tab(
                  icon: const Icon(Icons.campaign, color: Color(0xFF1B5E20)),
                  text: context.t('communication'),
                ),
                Tab(
                  icon: const Icon(Icons.people_outline, color: Color(0xFF1B5E20)),
                  text: context.t('users'),
                ),
                const Tab(
                  icon: Icon(Icons.precision_manufacturing, color: Color(0xFF1B5E20)),
                  text: 'Auditoría',
                ),
                Tab(
                  icon: const Icon(Icons.build, color: Color(0xFF1B5E20)),
                  text: context.t('maintenance'),
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
                          color: Color(0xFF263238),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: _verDirectorioGlobal,
                          icon: const Icon(Icons.list_alt,
                              color: Color(0xFF1B5E20)),
                          label: const Text(
                            'Ver Directorio Global',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            foregroundColor: const Color(0xFF1B5E20),
                            side: const BorderSide(color: Color(0xFF1B5E20)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text(
                        '2. Gestión de Territorios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
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
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF1B5E20))),
                            );
                          }
                          if (snapshot.hasError) {
                            debugPrint(
                                'Error cargando territorios: ${snapshot.error}');
                            return Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Center(
                                  child: Text('Error: ${snapshot.error}',
                                      style:
                                          const TextStyle(color: Colors.red))),
                            );
                          }
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
                                onTap: () {
                                  final tipoDoc = (doc.data()
                                          as Map<String, dynamic>)['tipo'];
                                  final nombreDoc = (doc.data()
                                          as Map<String, dynamic>)['nombre'] ??
                                      doc.id;
                                  if (tipoDoc == 'comercial') {
                                    _abrirVistaComercial(doc.id, nombreDoc);
                                  } else {
                                    _abrirTerritorio(doc.id, nombreDoc);
                                  }
                                },
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
                                        final tipo = (doc.data()
                                                as Map<String, dynamic>)[
                                            'tipo'];
                                        final esBase = tipo == 'base';
                                        final esComercial = tipo == 'comercial';
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tarjetas vinculadas: $cantidadTarjetas',
                                            ),
                                            if (esBase || esComercial) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: esComercial
                                                      ? Colors.purple
                                                          .withOpacity(0.12)
                                                      : Colors.teal
                                                          .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  esComercial
                                                      ? 'COMERCIAL'
                                                      : 'BASE (depósito)',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.8,
                                                    color: esComercial
                                                        ? Colors.purple
                                                        : Colors.teal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if ((doc.data() as Map<String,
                                                    dynamic>)['tipo'] !=
                                            'base') ...[
                                          IconButton(
                                            icon: const Icon(
                                              Icons.vertical_align_bottom,
                                              color: Colors.teal,
                                            ),
                                            tooltip: 'Convertir en Base',
                                            onPressed: () =>
                                                _convertirEnBase(doc),
                                          ),
                                        ],
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
                ComunicacionTab(usuarioData: widget.usuarioData),
                UsuariosTab(usuarioData: widget.usuarioData),
                AuditorPanelPage(usuarioData: widget.usuarioData),
                MantenimientoTab(usuarioData: widget.usuarioData),
              ],
            ),
          ),
        ],
      ),
    );
  }
}