import 'package:flutter/material.dart';
// Traducciones
import '../../../core/l10n/translation_service.dart';
import 'ecosistema2_placeholder.dart';
import 'ecosistema2_mantenimiento.dart';

// ─────────────────────────────────────────────────────────────
// ECOSISTEMA 2 · PANEL PRINCIPAL
// Submódulo independiente de la app. Front con datos de muestra.
// No toca nada del ecosistema principal.
// ─────────────────────────────────────────────────────────────

const Color kEco2Verde = Color(0xFF1B5E20);
const Color kEco2VerdeClaro = Color(0xFF43A047);
const Color kEco2Azul = Color(0xFF0277BD);

class Ecosistema2HomeScreen extends StatelessWidget {
  const Ecosistema2HomeScreen({super.key});

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pantalla),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kEco2Verde, kEco2Azul],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCabecera(context),
              const SizedBox(height: 20),
              Text(
                context.t('eco2_sections').toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.groups_outlined,
                titulo: context.t('eco2_section_publishers'),
                descripcion: context.t('eco2_section_publishers_desc'),
                dato: '12',
                color: kEco2Verde,
                onTap: () => _abrir(
                  context,
                  const Ecosistema2PlaceholderScreen(
                    tituloClave: 'eco2_section_publishers',
                    icono: Icons.groups_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.event_note_outlined,
                titulo: context.t('eco2_section_assignments'),
                descripcion: context.t('eco2_section_assignments_desc'),
                dato: '8',
                color: kEco2Azul,
                onTap: () => _abrir(
                  context,
                  const Ecosistema2PlaceholderScreen(
                    tituloClave: 'eco2_section_assignments',
                    icono: Icons.event_note_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.assessment_outlined,
                titulo: context.t('eco2_section_reports'),
                descripcion: context.t('eco2_section_reports_desc'),
                dato: '4',
                color: kEco2VerdeClaro,
                onTap: () => _abrir(
                  context,
                  const Ecosistema2PlaceholderScreen(
                    tituloClave: 'eco2_section_reports',
                    icono: Icons.assessment_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.map_outlined,
                titulo: context.t('eco2_section_territories'),
                descripcion: context.t('eco2_section_territories_desc'),
                dato: '6',
                color: Colors.blueGrey,
                onTap: () => _abrir(
                  context,
                  const Ecosistema2PlaceholderScreen(
                    tituloClave: 'eco2_section_territories',
                    icono: Icons.map_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTarjetaAcceso(
                context,
                icono: Icons.build_outlined,
                titulo: context.t('eco2_section_maintenance'),
                descripcion: context.t('eco2_section_maintenance_desc'),
                dato: null,
                color: Colors.deepOrange,
                onTap: () => _abrir(
                  context,
                  const Ecosistema2MantenimientoScreen(),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  context.t('eco2_disclaimer'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCabecera(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kEco2Verde, kEco2VerdeClaro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kEco2Verde.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildLogoSalon(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('eco2_salon_titulo'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('eco2_salon_subtitulo'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Logo del Salón del Reino: sin cruz, solo edificio con logo JW.
  Widget _buildLogoSalon() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_work_outlined,
              color: kEco2Verde,
              size: 24,
            ),
            const SizedBox(height: 2),
            const Text(
              'JW',
              style: TextStyle(
                color: kEco2Verde,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaAcceso(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String descripcion,
    required String? dato,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF263238),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descripcion,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (dato != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dato,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}