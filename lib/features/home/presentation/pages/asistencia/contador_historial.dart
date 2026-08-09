import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// HISTORIAL DE ASISTENCIA
// Cualquier usuario puede ver y reenviar. No permite editar.
// ─────────────────────────────────────────────────────────────

class AsistenciaHistorialScreen extends StatefulWidget {
  const AsistenciaHistorialScreen({super.key});

  @override
  State<AsistenciaHistorialScreen> createState() =>
      _AsistenciaHistorialScreenState();
}

class _AsistenciaHistorialScreenState extends State<AsistenciaHistorialScreen> {
  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('asistencia_historial')
      .orderBy('creadoEn', descending: true)
      .snapshots();

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.t('attendance_copied')),
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  Future<void> _reenviarWhatsApp(String texto) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(texto)}',
    );
    try {
      final abierto =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abierto) _mostrarError();
    } catch (_) {
      _mostrarError();
    }
  }

  void _mostrarError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.t('attendance_share_error')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('attendance_history'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                context.t('error_generic'),
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history,
                      color: Colors.grey, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    context.t('attendance_history_empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _buildTarjeta(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildTarjeta(Map<String, dynamic> data) {
    final dia = (data['dia'] ?? '') as String;
    final hora = (data['hora'] ?? '') as String;
    final nombre = (data['nombre'] ?? '') as String;
    final hispanos = (data['hispanos'] ?? 0) as int;
    final locales = (data['locales'] ?? 0) as int;
    final total = (data['total'] ?? 0) as int;
    final texto = (data['texto'] ?? '') as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFF1B5E20), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  color: Color(0xFF1B5E20), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dia,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              const Icon(Icons.schedule, color: Colors.grey, size: 15),
              const SizedBox(width: 4),
              Text(
                hora,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          if (nombre.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    color: Colors.grey, size: 15),
                const SizedBox(width: 6),
                Text(
                  context.t('attendance_registered_by', args: [nombre]),
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _chip('${context.t('attendance_hispanos')}: $hispanos',
                  const Color(0xFF1B5E20)),
              _chip('${context.t('attendance_locales')}: $locales',
                  const Color(0xFF0277BD)),
              _chip('${context.t('attendance_total')}: $total',
                  const Color(0xFFE65100)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copiar(texto),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(
                    context.t('attendance_copy'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B5E20),
                    side: const BorderSide(color: Color(0xFF1B5E20)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _reenviarWhatsApp(texto),
                  icon: const Icon(Icons.share, size: 16),
                  label: Text(
                    context.t('attendance_resend'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }
}