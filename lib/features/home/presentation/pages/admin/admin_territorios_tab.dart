import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'territorios_tab.dart';
import 'temporales_tab.dart';
import 'devueltas_tab_original.dart';
import 'estadisticas_tab.dart';

class AdminTerritoriosTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String? territorioId;
  final String? territorioNombre;

  const AdminTerritoriosTab({
    super.key,
    required this.usuarioData,
    this.territorioId,
    this.territorioNombre,
  });

  @override
  State<AdminTerritoriosTab> createState() => _AdminTerritoriosTabState();
}

class _AdminTerritoriosTabState extends State<AdminTerritoriosTab> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: const [
                  Icon(Icons.map, color: Color(0xFF4A148C)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Territorios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              child: TabBar(
                indicatorColor: Color(0xFF4A148C),
                labelColor: Color(0xFF4A148C),
                unselectedLabelColor: Colors.black54,
                tabs: [
                  Tab(
                    icon: Icon(Icons.map, color: Color(0xFF4A148C)),
                    text: 'Territorios',
                  ),
                  Tab(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('territorios')
                          .doc('temporales')
                          .collection('tarjetas')
                          .snapshots(),
                      builder: (context, snap) {
                        final count = snap.data?.docs.length ?? 0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  Icons.timer,
                                  color: count > 0 ? Colors.orange : const Color(0xFF4A148C),
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: -6,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Temporales',
                              style: TextStyle(
                                color: count > 0 ? Colors.orange : const Color(0xFF4A148C),
                                fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Tab(
                    icon: Icon(Icons.delete_sweep, color: Color(0xFF4A148C)),
                    text: 'Devueltas',
                  ),
                  Tab(
                    icon: Icon(Icons.bar_chart, color: Color(0xFF4A148C)),
                    text: 'Estadísticas',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  TerritoriosTab(usuarioData: widget.usuarioData),
                  TemporalesTab(usuarioData: widget.usuarioData),
                  DevueltasTab(usuarioData: widget.usuarioData),
                  EstadisticasTab(usuarioData: widget.usuarioData),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
