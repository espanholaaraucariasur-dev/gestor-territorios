import 'package:flutter/material.dart';
import 'territorios_tab.dart';
// PUNTO 3: la pestaña de temporales queda oculta (código comentado, no visible).
// import 'temporales_tab.dart';
import 'comentarios_tab.dart';
import 'devueltas_tab_original.dart';
import 'estadisticas_tab.dart';
import 'package:araucaria_sur/core/l10n/translation_service.dart';

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
                  const Tab(
                    icon: Icon(Icons.map, color: Color(0xFF4A148C)),
                    text: 'Territorios',
                  ),
                  // PUNTO 3: pestaña "Temporales" oculta (comentada, no visible).
                  // const Tab(
                  //   icon: Icon(Icons.timer, color: Color(0xFF4A148C)),
                  //   text: 'Temporales',
                  // ),
                  const Tab(
                    icon: Icon(Icons.comment, color: Color(0xFF4A148C)),
                    text: 'Comentarios',
                  ),
                  const Tab(
                    icon: Icon(Icons.delete_sweep, color: Color(0xFF4A148C)),
                    text: 'Removidas',
                  ),
                  Tab(
                    icon: const Icon(Icons.bar_chart, color: Color(0xFF4A148C)),
                    text: context.t('territory_statistics_tab'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(), // Deshabilita el Swipe
                children: [
                  TerritoriosTab(usuarioData: widget.usuarioData),
                  // PUNTO 3: TemporalesTab oculta (comentada, no visible).
                  // TemporalesTab(usuarioData: widget.usuarioData),
                  ComentariosTab(usuarioData: widget.usuarioData),
                  RemovidasTab(usuarioData: widget.usuarioData),
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