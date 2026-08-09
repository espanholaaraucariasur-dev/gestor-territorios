import 'package:flutter/material.dart';
// Traducciones
import '../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// ECOSISTEMA 2 · MANTENIMIENTO
// Botón principal: elegir qué usuarios pueden ver el Ecosistema 2.
// Front solo con datos de muestra (backend al final).
// ─────────────────────────────────────────────────────────────

class Ecosistema2MantenimientoScreen extends StatefulWidget {
  const Ecosistema2MantenimientoScreen({super.key});

  @override
  State<Ecosistema2MantenimientoScreen> createState() =>
      _Ecosistema2MantenimientoScreenState();
}

class _Ecosistema2MantenimientoScreenState
    extends State<Ecosistema2MantenimientoScreen> {
  bool _soloAdmin = true;

  void _abrirSelectorAcceso() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _buildSelectorAcceso(c),
    );
  }

  Widget _buildSelectorAcceso(BuildContext c) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(c).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.visibility_outlined,
                    color: Color(0xFF1B5E20), size: 22),
                const SizedBox(width: 8),
                Text(
                  c.t('eco2_visibilidad_titulo'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF263238),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              c.t('eco2_visibilidad_desc'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            _buildOpcionAcceso(
              c,
              icono: Icons.shield_outlined,
              titulo: c.t('eco2_visibilidad_solo_admin'),
              descripcion: c.t('eco2_visibilidad_solo_admin_desc'),
              activo: _soloAdmin,
              onTap: () => setState(() => _soloAdmin = true),
            ),
            const SizedBox(height: 10),
            _buildOpcionAcceso(
              c,
              icono: Icons.groups_outlined,
              titulo: c.t('eco2_visibilidad_admin_colab'),
              descripcion: c.t('eco2_visibilidad_admin_colab_desc'),
              activo: !_soloAdmin,
              onTap: () => setState(() => _soloAdmin = false),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(c);
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(context.t('eco2_visibilidad_guardado')),
                          backgroundColor: const Color(0xFF1B5E20),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  }
                },
                icon: const Icon(Icons.check, size: 18),
                label: Text(context.t('save')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpcionAcceso(
    BuildContext c, {
    required IconData icono,
    required String titulo,
    required String descripcion,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: activo
          ? const Color(0xFF1B5E20).withValues(alpha: 0.08)
          : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icono,
                  color: activo ? const Color(0xFF1B5E20) : Colors.grey,
                  size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: activo
                            ? const Color(0xFF1B5E20)
                            : Colors.grey.shade700,
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
              Icon(
                activo ? Icons.radio_button_checked : Icons.radio_button_off,
                color: activo ? const Color(0xFF1B5E20) : Colors.grey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
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
              colors: [Color(0xFF1B5E20), Color(0xFF0277BD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_section_maintenance'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('eco2_maintenance_desc'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            // ── Botón principal: visibilidad ──────────────────
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _abrirSelectorAcceso,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF1B5E20), width: 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF1B5E20).withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B5E20)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.visibility_outlined,
                            color: Color(0xFF1B5E20), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t('eco2_visibilidad_boton'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF263238),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.t('eco2_visibilidad_boton_desc'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t('eco2_maintenance_nota'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}