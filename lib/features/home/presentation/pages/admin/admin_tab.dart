import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_territorios_tab.dart';
import 'comunicacion_tab.dart';
import 'usuarios_tab.dart';

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
  Future<void> _logicaReinicio() async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      // Reiniciar progreso mensual en direcciones_globales
      final direccionesSnapshot = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();
      for (final doc in direccionesSnapshot.docs) {
        batch.update(doc.reference, {
          'visitado': false,
          'predicado': false,
          'asignado_a': null,
          'asignado_en': null,
          'entregado_a': null,
          'entregado_en': null,
          'devuelto': false,
          'devuelto_por': null,
          'devuelto_en': null,
        });
      }

      // Reiniciar tarjetas de territorios
      final territoriosSnapshot =
          await FirebaseFirestore.instance.collection('territorios').get();
      for (final territorio in territoriosSnapshot.docs) {
        final tarjetasSnapshot = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();

        for (final tarjeta in tarjetasSnapshot.docs) {
          batch.update(tarjeta.reference, {
            'disponible_para_publicadores': false,
            'bloqueado': true,
            'asignado_a': null,
            'asignado_en': null,
            'entregado_a': null,
            'entregado_en': null,
            'devuelto': false,
            'devuelto_por': null,
            'devuelto_en': null,
            'estatus_envio': null,
            'hora_programada': null,
          });
        }

        // Reiniciar estado del territorio
        batch.update(territorio.reference, {
          'disponible_para_publicadores': false,
          'asignado_a': null,
          'asignado_en': null,
          'enviado_a': null,
          'enviado_en': null,
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sistema reiniciado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error reiniciando sistema: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _levantarArchivoCSV() async {
    // Implementación simulada - en el código original habría lógica para subir archivos
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Función de subir CSV no implementada en esta versión'),
        backgroundColor: Colors.orange,
      ),
    );
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

  Future<void> _mostrarDialogoCrearTarjeta(
      BuildContext context, String terId) async {}
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('⚠️ Reiniciar Sistema Completo'),
                          content: const Text(
                            '¿Estás seguro? Esto reiniciará:\n\n• Progreso mensual (visitado, predicado)\n• Asignaciones de tarjetas y direcciones\n• Estados de envío y entrega\n\nLas estadísticas y direcciones removidas se mantendrán.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Reiniciar'),
                            ),
                          ],
                        ),
                      );
                      if (confirmar == true) {
                        await _logicaReinicio();
                      }
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      'Reiniciar Sistema',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
