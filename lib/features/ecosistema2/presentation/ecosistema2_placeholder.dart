import 'package:flutter/material.dart';
// Traducciones
import '../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// ECOSISTEMA 2 · PANTALLA PLACEHOLDER
// Se usa para las secciones que aún no tienen contenido real.
// ─────────────────────────────────────────────────────────────

class Ecosistema2PlaceholderScreen extends StatelessWidget {
  const Ecosistema2PlaceholderScreen({
    super.key,
    required this.tituloClave,
    required this.icono,
    this.color = const Color(0xFF1B5E20),
  });

  final String tituloClave;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, const Color(0xFF0277BD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t(tituloClave),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 32, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('eco2_en_desarrollo'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                context.t('eco2_en_desarrollo_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}