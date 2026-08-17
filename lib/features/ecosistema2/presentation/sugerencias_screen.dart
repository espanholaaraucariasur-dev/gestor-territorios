import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Traducciones
import '../../../core/l10n/translation_service.dart';
// Notificaciones
import '../../../core/services/notificacion_service.dart';

// ─────────────────────────────────────────────────────────────
// SUGERENCIAS · Ecosistema 2
// El usuario envía una sugerencia que el administrador recibe
// en la sección de anuncios del panel de administración.
// ─────────────────────────────────────────────────────────────

const Color _kVerde = Color(0xFF1B5E20);

class SugerenciasScreen extends StatefulWidget {
  final String usuarioEmail;
  final String usuarioNombre;

  const SugerenciasScreen({
    super.key,
    required this.usuarioEmail,
    required this.usuarioNombre,
  });

  @override
  State<SugerenciasScreen> createState() => _SugerenciasScreenState();
}

class _SugerenciasScreenState extends State<SugerenciasScreen> {
  final TextEditingController _sugerenciaCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _sugerenciaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _sugerenciaCtrl.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('sugerencias_vacio')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await FirebaseFirestore.instance.collection('sugerencias').add({
        'texto': texto,
        'usuario_email': widget.usuarioEmail,
        'usuario_nombre': widget.usuarioNombre,
        'leida': false,
        'created_at': FieldValue.serverTimestamp(),
      });

      await NotificacionService.enviarAAdminTerritorios(
        titulo: '💡 Nueva sugerencia',
        cuerpo: '${widget.usuarioNombre} envió una sugerencia: "$texto"',
        tipo: TipoNotificacion.motivacional,
        extra: {'sugerencia': texto, 'usuario': widget.usuarioEmail},
      );

      _sugerenciaCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('sugerencias_enviada')),
            backgroundColor: _kVerde,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('sugerencias_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _enviando = false);
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
              colors: [_kVerde, Color(0xFF0277BD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('sugerencias_title'),
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
            // ── Cabecera ─────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border(
                  left: BorderSide(
                    color: _kVerde.withValues(alpha: 0.4),
                    width: 4,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kVerde.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: _kVerde, size: 28),
                  const SizedBox(height: 10),
                  Text(
                    context.t('sugerencias_desc'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF263238),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Formulario ──────────────────────────────────
            TextField(
              controller: _sugerenciaCtrl,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: context.t('sugerencias_hint'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _kVerde, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(
                  _enviando
                      ? context.t('sugerencias_enviando')
                      : context.t('sugerencias_enviar'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kVerde,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}