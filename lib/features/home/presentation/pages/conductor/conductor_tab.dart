import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConductorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;

  const ConductorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
  });

  @override
  State<ConductorTab> createState() => _ConductorTabState();
}

class _ConductorTabState extends State<ConductorTab> {
  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF1B5E20)),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          Text(title, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _devolverTerritorio(String territorioId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .update({
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'estatus_envio': 'disponible',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Territorio devuelto correctamente'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver territorio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _enviarTarjetaConductorAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      // Query publicadores
      final publicadoresSnapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('es_publicador', isEqualTo: true)
          .where('estado', isEqualTo: 'aprobado')
          .get();

      if (publicadoresSnapshot.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay publicadores disponibles'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show selection dialog
      final selectedPublicador = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seleccionar Publicador'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: publicadoresSnapshot.docs.length,
              itemBuilder: (context, index) {
                final doc = publicadoresSnapshot.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final nombre = data['nombre'] ?? 'Sin nombre';
                final email = data['email'] ?? 'Sin email';

                return ListTile(
                  title: Text(nombre),
                  subtitle: Text(email),
                  onTap: () => Navigator.pop(context, data),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedPublicador == null) return;

      final nombreElegido = selectedPublicador['nombre'] ?? 'Publicador';

      // Show confirmation dialog
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Envío'),
          content: Text(
            '¿Enviar tarjeta "$tarjetaNombre" a $nombreElegido?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      if (confirmado != true) return;

      // Update tarjeta document
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': nombreElegido,
        'enviado_nombre': nombreElegido,
        'enviado_en': FieldValue.serverTimestamp(),
        'disponible_para_publicadores': false,
      });

      // Update all direcciones_globales with tarjeta_id
      final direccionesSnapshot = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in direccionesSnapshot.docs) {
        batch.update(doc.reference, {'asignado_a': nombreElegido});
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tarjeta "$tarjetaNombre" enviada a $nombreElegido'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: CustomScrollView(
        slivers: [
          // Statistics Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard('Recibidos', 0, Icons.download),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Enviados', 0, Icons.upload)),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Devueltos', 0, Icons.undo)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Simple bar chart simulation
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Actividad Mensual',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(6, (index) {
                              final heights = [0.3, 0.7, 0.5, 0.9, 0.6, 0.8];
                              return Container(
                                width: 20,
                                height: 60 * heights[index],
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1B5E20,
                                  ).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Territories Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'TERRITORIOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // Territories Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('territorios')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return d['enviado_a'] == widget.usuarioEmail;
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(
                            color: const Color(0xFF1B5E20),
                            width: 4,
                          ),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay territorios recibidos',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Territorio';
                      final enviadoA = data['enviado_a'] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(
                              color: const Color(0xFF1B5E20),
                              width: 4,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.map,
                                    color: Color(0xFF1B5E20),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (enviadoA.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Enviado a: $enviadoA',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Botones de acción
                              if (enviadoA.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Territorio recibido — envía las tarjetas individualmente',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),

                              if (enviadoA.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _devolverTerritorio(doc.id),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.orange,
                                          side: const BorderSide(
                                            color: Colors.orange,
                                          ),
                                        ),
                                        child: const Text('Devolver'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            null, // Deshabilitado ya que está enviado
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Ya enviado'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          // Cards Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'TARJETAS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

          // Cards Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    // Recibe por email O por nombre
                    return d['enviado_a'] == widget.usuarioEmail ||
                        d['enviado_a'] == (widget.usuarioData['nombre'] ?? '');
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(color: Colors.blue, width: 4),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay tarjetas recibidas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Tarjeta';
                      final enviadoA = data['enviado_a'] ?? '';
                      final terId = doc.reference.parent.parent?.id ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(color: Colors.blue, width: 4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: const Icon(
                            Icons.credit_card,
                            color: Colors.blue,
                          ),
                          title: Text(
                            nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Territorio: $terId'),
                              if (enviadoA.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final enviadoEn = data['enviado_en'];
                                      String fechaHora = '';
                                      if (enviadoEn != null) {
                                        final dt =
                                            (enviadoEn as Timestamp).toDate();
                                        fechaHora =
                                            ' · ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                      }
                                      return Text(
                                        'Enviado por: ${data['enviado_nombre'] ?? enviadoA}$fechaHora',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Botón de enviar rápido - IconButton azul
                              IconButton(
                                icon: const Icon(Icons.send),
                                color: Colors.blue,
                                onPressed: () =>
                                    _enviarTarjetaConductorAPublicador(
                                  terId,
                                  doc.id,
                                  nombre,
                                ),
                                tooltip: 'Enviar a publicador',
                              ),
                              // Botón Enviar — siempre visible con estado apropiado
                              if ((data['enviado_nombre'] ?? '')
                                  .toString()
                                  .isEmpty)
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.send, size: 14),
                                  label: const Text(
                                    'Enviar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () =>
                                      _enviarTarjetaConductorAPublicador(
                                    terId,
                                    doc.id,
                                    nombre,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text(
                                    'Reenviar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () =>
                                      _enviarTarjetaConductorAPublicador(
                                    terId,
                                    doc.id,
                                    nombre,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              // Botón Devolver — siempre visible
                              OutlinedButton.icon(
                                icon: const Icon(Icons.undo, size: 14),
                                label: const Text(
                                  'Devolver',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () async {
                                  final confirmar = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Confirmar devolución'),
                                      content: Text(
                                        '¿Devolver la tarjeta "$nombre"? Volverá a estar disponible en el territorio.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text(
                                            'Cancelar',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                          ),
                                          child: const Text('Devolver'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    await FirebaseFirestore.instance
                                        .collection('territorios')
                                        .doc(terId)
                                        .collection('tarjetas')
                                        .doc(doc.id)
                                        .update({
                                      'enviado_a': null,
                                      'enviado_nombre': null,
                                      'enviado_en': null,
                                      'estatus_envio': 'devuelto',
                                      'devuelto_en':
                                          FieldValue.serverTimestamp(),
                                      'devuelto_por':
                                          widget.usuarioData['nombre'] ??
                                              widget.usuarioEmail,
                                    });
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
