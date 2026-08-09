import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// CONTADOR DE ASISTENCIA
// ─────────────────────────────────────────────────────────────

class AsistenciaCounterScreen extends StatefulWidget {
  const AsistenciaCounterScreen({super.key, this.nombreUsuario});

  final String? nombreUsuario;

  @override
  State<AsistenciaCounterScreen> createState() =>
      _AsistenciaCounterScreenState();
}

class _AsistenciaCounterScreenState extends State<AsistenciaCounterScreen> {
  int _hispanos = 0;
  int _locales = 0;

  int get _total => _hispanos + _locales;

  String get _nombre => (widget.nombreUsuario?.isNotEmpty ?? false)
      ? widget.nombreUsuario!
      : '';

  String _formatearFechaHora(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String get _textoResultado {
    final ahora = _formatearFechaHora(DateTime.now());
    final cabecera = _nombre.isNotEmpty ? '$_nombre\n$ahora\n' : '$ahora\n';
    return '$cabecera'
        'Hispanos: $_hispanos\n'
        'Locales: $_locales\n\n'
        'Total: $_total';
  }

  Future<void> _reiniciar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.t('attendance_reset')),
        content: Text(context.t('attendance_reset_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() {
      _hispanos = 0;
      _locales = 0;
    });
  }

  Future<void> _decrementar(String tipo) async {
    if ((tipo == 'hispanos' && _hispanos == 0) ||
        (tipo == 'locales' && _locales == 0)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.t('attendance_no_negative')),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      return;
    }
    setState(() {
      if (tipo == 'hispanos') {
        _hispanos--;
      } else {
        _locales--;
      }
    });
  }

  Future<void> _copiarTexto() async {
    await Clipboard.setData(ClipboardData(text: _textoResultado));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.t('attendance_copied')),
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  Future<void> _compartirWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(_textoResultado)}',
    );
    try {
      final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abierto) {
        _mostrarErrorCompartir();
      }
    } catch (_) {
      _mostrarErrorCompartir();
    }
  }

  void _mostrarErrorCompartir() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.t('attendance_share_error')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  // ─────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────

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
          context.t('attendance_counter'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: context.t('attendance_reset'),
            onPressed: _reiniciar,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (_nombre.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          color: Color(0xFF1B5E20), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF263238),
                          ),
                        ),
                      ),
                      const Icon(Icons.schedule,
                          color: Color(0xFF1B5E20), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _formatearFechaHora(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildContadorCarta(
                titulo: context.t('attendance_hispanos'),
                valor: _hispanos,
                icono: Icons.people_alt_outlined,
                colorAcento: const Color(0xFF1B5E20),
                onMenos: () => _decrementar('hispanos'),
                onMas: () => setState(() => _hispanos++),
              ),
              const SizedBox(height: 16),
              _buildContadorCarta(
                titulo: context.t('attendance_locales'),
                valor: _locales,
                icono: Icons.home_outlined,
                colorAcento: const Color(0xFF0277BD),
                onMenos: () => _decrementar('locales'),
                onMas: () => setState(() => _locales++),
              ),
              const SizedBox(height: 16),
              _buildCartaTotal(),
              const Spacer(),
              _buildBotonesAccion(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContadorCarta({
    required String titulo,
    required int valor,
    required IconData icono,
    required Color colorAcento,
    required VoidCallback onMenos,
    required VoidCallback onMas,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: colorAcento, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: colorAcento.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorAcento.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: colorAcento, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF263238),
              ),
            ),
          ),
          IconButton(
            onPressed: onMenos,
            icon: const Icon(Icons.remove_circle_outline, size: 32),
            color: Colors.redAccent,
            tooltip: '-',
          ),
          SizedBox(
            width: 80,
            child: Text(
              '$valor',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Color(0xFF263238),
              ),
            ),
          ),
          IconButton(
            onPressed: onMas,
            icon: const Icon(Icons.add_circle, size: 32),
            color: Colors.green,
            tooltip: '+',
          ),
        ],
      ),
    );
  }

  Widget _buildCartaTotal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            context.t('attendance_total'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonesAccion() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _copiarTexto,
            icon: const Icon(Icons.copy, size: 18),
            label: Text(
              context.t('attendance_copy'),
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              side: const BorderSide(color: Color(0xFF1B5E20)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _compartirWhatsApp,
            icon: const Icon(Icons.share, size: 18),
            label: Text(
              context.t('attendance_share_whatsapp'),
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}