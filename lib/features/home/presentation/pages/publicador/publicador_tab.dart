import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PublicadorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;
  final bool campanaEspecialActiva;
  final String nombreCampanaEspecial;
  final bool campanaGeneralActiva;
  final String anuncioGeneral;

  const PublicadorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
    required this.campanaEspecialActiva,
    required this.nombreCampanaEspecial,
    required this.campanaGeneralActiva,
    required this.anuncioGeneral,
  });

  @override
  State<PublicadorTab> createState() => _PublicadorTabState();
}

class _PublicadorTabState extends State<PublicadorTab> {
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

  Widget _alertaBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _devolverTarjeta(String territorioId, String tarjetaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'estatus_envio': 'disponible',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarjeta devuelta correctamente'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildDireccionesTarjeta(String tarjetaId) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Sin direcciones.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return Column(
          children: [
            ...snapshot.data!.docs.map((dirDoc) {
              final data = dirDoc.data() as Map<String, dynamic>;
              final fullAddress =
                  '${data['calle'] ?? ''}${(data['complemento'] ?? '').isNotEmpty ? ' · ${data['complemento']}' : ''}';
              final selectedValue = data['estado_predicacion'] ?? 'pendiente';

              return StatefulBuilder(
                builder: (context, setState) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullAddress,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            RadioGroup<String>(
                              groupValue: selectedValue,
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    // Update local state immediately
                                  });
                                  await FirebaseFirestore.instance
                                      .collection('direcciones_globales')
                                      .doc(dirDoc.id)
                                      .update({
                                    'estado_predicacion': value,
                                    'predicado': value == 'completada',
                                    'fecha_predicacion': value == 'completada'
                                        ? FieldValue.serverTimestamp()
                                        : null,
                                  });
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<String>(
                                    title: const Text('Se predicó'),
                                    value: 'completada',
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('No se predicó'),
                                    value: 'no_predicado',
                                  ),
                                  RadioListTile<String>(
                                    title:
                                        const Text('No vive hispanohablante'),
                                    value: 'no_hispano',
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('Otro'),
                                    value: 'otro',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombrePublicador = widget.usuarioData['nombre'] ?? 'Publicador';
    final iniciales =
        nombrePublicador.isNotEmpty ? nombrePublicador[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('direcciones_globales')
            .snapshots(),
        builder: (context, snapshot) {
          final todasDirecciones = snapshot.data?.docs ?? [];

          // Obtener direcciones del usuario
          final direccionesUsuario = todasDirecciones.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['publicador_email'] == widget.usuarioEmail;
          }).toList();

          // Obtener tarjetas asignadas al usuario
          final tarjetasUsuario = direccionesUsuario
              .map((doc) => doc['tarjeta_id'] as String? ?? '')
              .toSet();

          // Contar todas las direcciones dentro de las tarjetas asignadas
          final direccionesEnTarjetasUsuario = todasDirecciones.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return tarjetasUsuario
                .contains(data['tarjeta_id'] as String? ?? '');
          }).toList();

          final total = direccionesEnTarjetasUsuario.length;
          final completadas = direccionesEnTarjetasUsuario.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['estado_predicacion'] == 'completada' ||
                data['predicado'] == true;
          }).length;
          final pendientes = total - completadas;

          return CustomScrollView(
            slivers: [
              // ── HEADER ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.85),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          iniciales,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, $nombrePublicador',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$completadas de $total direcciones completadas ($pendientes pendientes)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── ALERTAS ─────────────────────────────────────────
              if (widget.campanaEspecialActiva ||
                  (widget.campanaGeneralActiva &&
                      widget.anuncioGeneral.trim().isNotEmpty))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (widget.campanaEspecialActiva)
                        _alertaBanner(
                          icon: Icons.campaign,
                          color: const Color(0xFFE65100),
                          bgColor: const Color(0xFFFFF3E0),
                          title: 'Campaña especial activa',
                          body: widget.nombreCampanaEspecial,
                        ),
                      if (widget.campanaGeneralActiva &&
                          widget.anuncioGeneral.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _alertaBanner(
                          icon: Icons.info_outline,
                          color: const Color(0xFF1565C0),
                          bgColor: const Color(0xFFE3F2FD),
                          title: 'Anuncio',
                          body: widget.anuncioGeneral,
                        ),
                      ],
                    ]),
                  ),
                ),

              // ── STATS ────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .where(
                          'asignado_a',
                          isEqualTo: widget.usuarioData['nombre'] ?? '',
                        )
                        .snapshots(),
                    builder: (context, tarjetasSnap) {
                      // Total direcciones en tarjetas asignadas al usuario
                      int totalDirAsignadas = 0;
                      List<String> tarjetaIds = [];

                      if (tarjetasSnap.hasData) {
                        for (final t in tarjetasSnap.data!.docs) {
                          final d = t.data() as Map<String, dynamic>;
                          totalDirAsignadas +=
                              ((d['cantidad_direcciones'] ?? 0) as int);
                          tarjetaIds.add(t.id);
                        }
                      }

                      return FutureBuilder<QuerySnapshot?>(
                        future: tarjetaIds.isEmpty
                            ? Future.value(null)
                            : FirebaseFirestore.instance
                                .collection('direcciones_globales')
                                .where(
                                  'tarjeta_id',
                                  whereIn: tarjetaIds.take(10).toList(),
                                )
                                .get(),
                        builder: (context, dirsSnap) {
                          // Filtrar por mes actual usando mes_predicacion
                          final mesActual =
                              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

                          final completadas = dirsSnap.data?.docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return data['predicado'] == true &&
                                    data['mes_predicacion'] == mesActual;
                              }).length ??
                              0;

                          final pendientes = totalDirAsignadas - completadas;

                          return Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  'Dir Asignadas',
                                  totalDirAsignadas,
                                  Icons.home_work_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  'Dir Completadas',
                                  completadas,
                                  Icons.check_circle_outline,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  'Dir Pendientes',
                                  pendientes < 0 ? 0 : pendientes,
                                  Icons.schedule_outlined,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // ── PROGRESO ─────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('direcciones_globales')
                        .snapshots(),
                    builder: (context, snapTotal) {
                      final totalExistentes = snapTotal.data?.docs.length ?? 0;
                      final completadasGlobal =
                          snapTotal.data?.docs.where((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                return d['predicado'] == true;
                              }).length ??
                              0;
                      final pendientesGlobal =
                          totalExistentes - completadasGlobal;
                      final avance = totalExistentes > 0
                          ? completadasGlobal / totalExistentes
                          : 0.0;

                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Progreso mensual',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF263238),
                                  ),
                                ),
                                Text(
                                  '${(avance * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF1B5E20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: avance,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFE8F5E9),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1B5E20),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Tres contadores
                            Row(
                              children: [
                                Expanded(
                                  child: _miniStat(
                                    'Existentes',
                                    totalExistentes,
                                    Icons.home_work_outlined,
                                    Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _miniStat(
                                    'Completadas',
                                    completadasGlobal,
                                    Icons.check_circle_outline,
                                    const Color(0xFF1B5E20),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _miniStat(
                                    'Pendientes',
                                    pendientesGlobal,
                                    Icons.schedule_outlined,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── MIS TARJETAS ──────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MIS TARJETAS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collectionGroup('tarjetas')
                            .where(
                              'asignado_a',
                              isEqualTo: widget.usuarioData['nombre'] ??
                                  '', // Usar nombre para búsqueda
                            )
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  'No tienes tarjetas asignadas.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: snapshot.data!.docs.map((tarjetaDoc) {
                              final data =
                                  tarjetaDoc.data() as Map<String, dynamic>;
                              final nombre = data['nombre'] ?? tarjetaDoc.id;
                              final cantDir = data['cantidad_direcciones'] ?? 0;
                              final territorioId =
                                  tarjetaDoc.reference.parent.parent?.id ?? '';
                              final asignadoEn =
                                  data['asignado_en'] as Timestamp?;
                              final fecha = asignadoEn != null
                                  ? '${asignadoEn.toDate().day}/${asignadoEn.toDate().month}/${asignadoEn.toDate().year}'
                                  : '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ExpansionTile(
                                  leading: const Icon(
                                    Icons.credit_card,
                                    color: Colors.blue,
                                  ),
                                  title: Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$cantDir direcciones · $territorioId${fecha.isNotEmpty ? ' · $fecha' : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      final confirmar = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Devolver tarjeta'),
                                          content: Text(
                                            '¿Devolver "$nombre"? Quedará disponible para otros.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancelar'),
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
                                        await _devolverTarjeta(
                                          territorioId,
                                          tarjetaDoc.id,
                                        );
                                      }
                                    },
                                    child: const Text(
                                      'Devolver',
                                      style: TextStyle(color: Colors.orange),
                                    ),
                                  ),
                                  children: [
                                    _buildDireccionesTarjeta(tarjetaDoc.id),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── DIRECCIONES ──────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MIS DIRECCIONES',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (direccionesUsuario.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sin direcciones asignadas',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...direccionesUsuario.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final calle = data['calle'] ?? 'Dirección';
                          final predicado = data['predicado'] ?? false;
                          final notas = data['notas'] ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
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
                                      Checkbox(
                                        value: predicado,
                                        onChanged: (value) async {
                                          await FirebaseFirestore.instance
                                              .collection(
                                                'direcciones_globales',
                                              )
                                              .doc(doc.id)
                                              .update({
                                            'predicado': value ?? false,
                                            'estado_predicacion':
                                                (value ?? false)
                                                    ? 'completada'
                                                    : 'pendiente',
                                            'fecha_predicacion': (value ??
                                                    false)
                                                ? FieldValue.serverTimestamp()
                                                : null,
                                          });
                                        },
                                        activeColor: const Color(0xFF1B5E20),
                                      ),
                                      Expanded(
                                        child: Text(
                                          calle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: predicado
                                              ? const Color(0xFFE8F5E9)
                                              : const Color(0xFFFFF8E1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          predicado
                                              ? 'Completada'
                                              : 'Pendiente',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: predicado
                                                ? const Color(0xFF1B5E20)
                                                : const Color(0xFFE65100),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.campanaEspecialActiva) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFE65100,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Campaña especial:',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFE65100),
                                            ),
                                          ),
                                          TextField(
                                            controller: TextEditingController(
                                              text: data['campo_extra'] ?? '',
                                            ),
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Ingresa dato de campaña...',
                                              hintStyle: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                            onChanged: (value) async {
                                              await FirebaseFirestore.instance
                                                  .collection(
                                                    'direcciones_globales',
                                                  )
                                                  .doc(doc.id)
                                                  .update({
                                                'campo_extra': value,
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: TextEditingController(
                                      text: notas,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Agregar notas...',
                                      hintStyle: const TextStyle(fontSize: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    onChanged: (value) async {
                                      await FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .doc(doc.id)
                                          .update({'notas': value});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
