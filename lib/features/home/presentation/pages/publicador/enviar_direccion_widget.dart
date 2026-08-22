import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../../core/services/notificacion_service.dart';
import '../../../../../core/l10n/translation_service.dart';
import '../../../../../core/themes/theme_extensions.dart';

/// Widget simple para que un publicador envíe una dirección nueva.
/// Comprueba si ya existe en `direcciones_globales`; si existe muestra
/// un mensaje, si no muestra el formulario para enviarla a revisión.
class EnviarDireccionWidget extends StatefulWidget {
  final String usuarioEmail;
  final String usuarioNombre;

  const EnviarDireccionWidget({
    super.key,
    required this.usuarioEmail,
    required this.usuarioNombre,
  });

  @override
  State<EnviarDireccionWidget> createState() => _EnviarDireccionWidgetState();
}

class _EnviarDireccionWidgetState extends State<EnviarDireccionWidget> {
  final TextEditingController _calleCtrl = TextEditingController();
  final TextEditingController _complementoCtrl = TextEditingController();
  final TextEditingController _detallesCtrl = TextEditingController();

  bool _verificando = false;
  bool _existe = false;
  bool _verificado = false;
  bool _enviando = false;

  // Normaliza igual que el resto de la app: minúsculas, sin tildes ni símbolos.
  String _normalizar(String s) {
    if (s.isEmpty) return '';
    const accentMap = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    var t = s.toLowerCase();
    t = t.splitMapJoin('', onNonMatch: (ch) => accentMap[ch] ?? ch);
    t = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return t;
  }

  Future<void> _verificar() async {
    final calle = _calleCtrl.text.trim();
    if (calle.isEmpty) {
      _snack(context.t('enviar_dir_vacio'), Colors.orange);
      return;
    }
    setState(() => _verificando = true);
    try {
      final norm = _normalizar(calle);
      bool existe = false;

      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('calle_normalizada', isEqualTo: norm)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        existe = true;
      } else {
        final snap2 = await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .where('calle', isEqualTo: calle)
            .limit(1)
            .get();
        if (snap2.docs.isNotEmpty) existe = true;
      }

      setState(() {
        _verificando = false;
        _verificado = true;
        _existe = existe;
      });
    } catch (e) {
      setState(() => _verificando = false);
      _snack('Error: $e', Colors.red);
    }
  }

  Future<void> _enviar() async {
    final calle = _calleCtrl.text.trim();
    if (calle.isEmpty) {
      _snack(context.t('enviar_dir_vacio'), Colors.orange);
      return;
    }

    setState(() => _enviando = true);

    double? latSol;
    double? lngSol;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      latSol = pos.latitude;
      lngSol = pos.longitude;
    } catch (_) {}

    try {
      await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .add({
        'direccion_original': calle,
        'direccion_normalizada': _normalizar(calle),
        'complemento': _complementoCtrl.text.trim(),
        'detalles': _detallesCtrl.text.trim(),
        'solicitante_email': widget.usuarioEmail,
        'estado': 'pendiente',
        if (latSol != null) 'lat': latSol,
        if (lngSol != null) 'lng': lngSol,
        'created_at': FieldValue.serverTimestamp(),
      });

      await NotificacionService.enviarAAdminTerritorios(
        titulo: '📍 Nueva dirección reportada',
        cuerpo: '${widget.usuarioNombre} envió una dirección nueva: "$calle"'
            '${_complementoCtrl.text.isNotEmpty ? ' · ${_complementoCtrl.text}' : ''}',
        tipo: TipoNotificacion.solicitudDireccion,
        extra: {'solicitante': widget.usuarioEmail, 'direccion': calle},
      );

      setState(() {
        _enviando = false;
        _verificado = false;
        _existe = false;
      });
      _calleCtrl.clear();
      _complementoCtrl.clear();
      _detallesCtrl.clear();

      if (mounted) _snack(context.t('enviar_dir_enviado'), Colors.green.shade700);
    } catch (e) {
      setState(() => _enviando = false);
      if (mounted) _snack('Error: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _calleCtrl.dispose();
    _complementoCtrl.dispose();
    _detallesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verde = context.verde;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_location_alt_outlined, color: verde, size: 20),
              const SizedBox(width: 8),
              Text(
                context.t('enviar_dir_titulo'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF263238),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.t('enviar_dir_desc'),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _calleCtrl,
            decoration: InputDecoration(
              hintText: context.t('enviar_dir_hint'),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _verificando ? null : _verificar,
              icon: _verificando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_verificando ? context.t('enviar_dir_enviando') : context.t('enviar_dir_verificar')),
              style: ElevatedButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // ── Resultado de la verificación ──
          if (_verificado && _existe) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t('enviar_dir_existe'),
                      style: const TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_verificado && !_existe) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: verde.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: verde.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: verde, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.t('enviar_dir_noexiste'),
                          style: TextStyle(color: verde, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _complementoCtrl,
                    decoration: InputDecoration(
                      hintText: context.t('enviar_dir_complemento'),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _detallesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: context.t('enviar_dir_detalles'),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _enviando ? null : _enviar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, size: 18),
                      label: Text(_enviando ? context.t('enviar_dir_enviando') : context.t('enviar_dir_enviar')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
