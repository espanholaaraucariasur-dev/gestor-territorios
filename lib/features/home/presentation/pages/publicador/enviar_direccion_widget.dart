import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../../core/services/notificacion_service.dart';
import '../../../../../core/services/mapbox_service.dart';
import '../../../../../core/l10n/translation_service.dart';
import '../../../../../core/themes/theme_extensions.dart';

/// Widget para que un publicador envíe una dirección nueva.
/// Busca en `direcciones_globales` con coincidencia robusta (abreviaturas, normalización).
/// Si existe y es condominio, muestra unidades existentes y permite añadir nueva.
/// Si no existe, permite enviar solicitud estándar.
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
  // Controllers para condominio
  final TextEditingController _bloqueCtrl = TextEditingController();
  final TextEditingController _pisoCtrl = TextEditingController();
  final TextEditingController _aptoCtrl = TextEditingController();

  bool _buscando = false;
  bool _verificado = false;
  bool _existe = false;
  bool _esCondominio = false;
  bool _mostrarFormularioCondominio = false;
  bool _enviando = false;

  DocumentSnapshot? _direccionEncontrada;
  List<Map<String, dynamic>> _unidadesExistentes = [];

  // ─── Normalización robusta (igual que backend) ───
  String _normalizarDireccion(String s) {
    if (s.isEmpty) return '';
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    t = t.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    t = t.replaceAll(RegExp(r'\b(n\.?|no\.?|nº|n°)\b'), ' ');
    // Expandir abreviaturas comunes ANTES de limpiar
    t = _expandirAbreviaturas(t);
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    t = t.replaceAll('apto', 'apartamento');
    t = t.replaceAll('apt', 'apartamento');
    t = t.replaceAll('ap.', 'apartamento');
    t = t.replaceAll('dpto', 'departamento');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  String _expandirAbreviaturas(String t) {
    final Map<String, String> abrev = {
      // Rua
      r'^\br\.?\b': 'rua',
      r'^\bru\b': 'rua',
      // Avenida
      r'^\bav\.?\b': 'avenida',
      r'^\gave\b': 'avenida',
      // Travessa
      r'^\btrv?\.?\b': 'travessa',
      r'^\btrav\b': 'travessa',
      // Praça
      r'^\bpc\.?\b': 'praca',
      r'^\bpca\b': 'praca',
      // Alameda
      r'^\bal\.?\b': 'alameda',
      // Rodovia
      r'^\brod\.?\b': 'rodovia',
      r'^\bbr\b': 'rodovia',
      // Vila
      r'^\bvq\b': 'vila',
      // Condomínio
      r'^\bcond\.?\b': 'condominio',
      r'^\bres\b': 'residencial',
      // Prolongamento
      r'^\bpd\b': 'prolongamento',
      r'^\bprol\b': 'prolongamento',
      // Loteamento
      r'^\blm\b': 'loteamento',
      r'^\blot\b': 'loteamento',
      // Quadra
      r'^\bqd\b': 'quadra',
      r'^\bq\b': 'quadra',
      // Chácara
      r'^\bch\b': 'chacara',
      // Estrada
      r'^\best\b': 'estrada',
      r'^\brdo\b': 'rodovia',
    };
    for (final entry in abrev.entries) {
      t = t.replaceAll(RegExp(entry.key), entry.value);
    }
    return t;
  }

  // Coincidencia robusta token-set
  bool _coincide(String entrada, String almacenada) {
    if (entrada.isEmpty || almacenada.isEmpty) return false;
    final eTok = entrada.split(' ').where((w) => w.isNotEmpty).toSet();
    final aTok = almacenada.split(' ').where((w) => w.isNotEmpty).toSet();
    // Números
    final eNums = eTok.where((w) => RegExp(r'^\d+$').hasMatch(w)).toSet();
    final aNums = aTok.where((w) => RegExp(r'^\d+$').hasMatch(w)).toSet();
    if (eNums.isNotEmpty && aNums.isNotEmpty) {
      if (!eNums.any((n) => aNums.contains(n))) return false;
    }
    // Palabras (sin números)
    final eWords = eTok.where((w) => !RegExp(r'^\d+$').hasMatch(w)).toSet();
    final aWords = aTok.where((w) => !RegExp(r'^\d+$').hasMatch(w)).toSet();
    if (eWords.isEmpty) return false;
    final comunes = eWords.intersection(aWords).length;
    final ratioE = comunes / eWords.length;
    final ratioA = aWords.isEmpty ? 0 : comunes / aWords.length;
    return ratioE >= 0.75 && ratioA >= 0.5; // umbrales robustos
  }

  Future<void> _buscar() async {
    final calle = _calleCtrl.text.trim();
    if (calle.isEmpty) {
      _snack(context.t('enviar_dir_vacio'), Colors.orange);
      return;
    }
    setState(() => _buscando = true);
    try {
      // ─── 1. Validar dirección con Mapbox (geocodificación real) ───
      final mapboxResultado = await MapboxService.validarDireccion(calle);

      DocumentSnapshot? match;

      if (mapboxResultado != null) {
        // Mapbox encontró la dirección → buscar en Firestore por similitud
        final placeName = mapboxResultado['place_name'] as String? ?? '';
        match = await _buscarFirestorePorMapbox(placeName, calle);
      }

      // ─── 2. Fallback: búsqueda local robusta en Firestore ───
      if (match == null) {
        match = await _buscarFirestoreFallback(calle);
      }

      // ─── 3. Si Mapbox dio coordenadas, guardarlas para envío ───
      Map<String, double>? coords;
      if (mapboxResultado != null) {
        final center = mapboxResultado['center'] as List?;
        if (center != null && center.length == 2) {
          coords = {'lat': center[1] as double, 'lng': center[0] as double};
        }
      }
      _coordsMapbox = coords;

      setState(() {
        _buscando = false;
        _verificado = true;
        _existe = match != null;
        if (match != null) {
          _direccionEncontrada = match;
          final data = match!.data() as Map<String, dynamic>;
          _esCondominio = data['es_condominio'] == true;
          if (_esCondominio) {
            _unidadesExistentes = List<Map<String, dynamic>>.from(
                data['condominio_unidades'] ?? []);
            _unidadesExistentes.sort((a, b) =>
                (a['bloque'] ?? '').toString().compareTo((b['bloque'] ?? '').toString()));
          }
        }
      });
    } catch (e) {
      setState(() => _buscando = false);
      _snack('Error: $e', Colors.red);
    }
  }

  Map<String, double>? _coordsMapbox;

  // Fallback robusto usando Firestore (normalización + token matching)
  Future<DocumentSnapshot?> _buscarFirestoreFallback(String calle) async {
    final busqueda = _normalizarDireccion(calle);
    if (busqueda.isEmpty) return null;

    // Prefijo: primera palabra no numérica
    final tokens = busqueda.split(' ').where((w) => w.isNotEmpty).toList();
    String prefijo = '';
    for (final tk in tokens) {
      if (!RegExp(r'^\d+$').hasMatch(tk)) {
        prefijo = tk;
        break;
      }
    }
    if (prefijo.isEmpty) prefijo = busqueda;

    // Rango por prefijo en direccion_normalizada
    final snap = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('direccion_normalizada', isGreaterThanOrEqualTo: prefijo)
        .where('direccion_normalizada', isLessThanOrEqualTo: '$prefijo\uf8ff')
        .limit(200)
        .get();

    for (final doc in snap.docs) {
      final almacenada = (doc.data()?['direccion_normalizada'] as String?) ?? '';
      if (_coincide(busqueda, almacenada)) return doc;
    }

    // Fallback exacto en calle
    final snap2 = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('calle', isEqualTo: calle)
        .limit(1)
        .get();
    if (snap2.docs.isNotEmpty) return snap2.docs.first;

    return null;
  }

  // Búsqueda en Firestore usando el place_name de Mapbox
  Future<DocumentSnapshot?> _buscarFirestorePorMapbox(String placeName, String calleOriginal) async {
    // Normalizar el place_name de Mapbox para buscar
    final busqueda = _normalizarDireccion(placeName);
    if (busqueda.isEmpty) return null;

    // Prefijo: primera palabra no numérica
    final tokens = busqueda.split(' ').where((w) => w.isNotEmpty).toList();
    String prefijo = '';
    for (final tk in tokens) {
      if (!RegExp(r'^\d+$').hasMatch(tk)) {
        prefijo = tk;
        break;
      }
    }
    if (prefijo.isEmpty) prefijo = busqueda;

    // Rango por prefijo en direccion_normalizada
    final snap = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('direccion_normalizada', isGreaterThanOrEqualTo: prefijo)
        .where('direccion_normalizada', isLessThanOrEqualTo: '$prefijo\uf8ff')
        .limit(200)
        .get();

    for (final doc in snap.docs) {
      final almacenada = (doc.data()?['direccion_normalizada'] as String?) ?? '';
      if (_coincide(busqueda, almacenada)) return doc;
    }

    // Fallback: búsqueda exacta en calle original
    final snap2 = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .where('calle', isEqualTo: calleOriginal)
        .limit(1)
        .get();
    if (snap2.docs.isNotEmpty) return snap2.docs.first;

    return null;
  }

  Future<void> _enviar() async {
    final calle = _calleCtrl.text.trim();
    if (calle.isEmpty) {
      _snack(context.t('enviar_dir_vacio'), Colors.orange);
      return;
    }

    // Si es condominio, validar campos de unidad
    if (_esCondominio && _mostrarFormularioCondominio) {
      if (_bloqueCtrl.text.trim().isEmpty ||
          _pisoCtrl.text.trim().isEmpty ||
          _aptoCtrl.text.trim().isEmpty) {
        _snack('Completa bloque, piso y apartamento', Colors.orange);
        return;
      }
      // Verificar que la unidad no exista ya
      final nuevaUnidad = {
        'bloque': _bloqueCtrl.text.trim(),
        'piso': _pisoCtrl.text.trim(),
        'apto': _aptoCtrl.text.trim(),
      };
      final yaExiste = _unidadesExistentes.any((u) =>
          u['bloque'] == nuevaUnidad['bloque'] &&
          u['piso'] == nuevaUnidad['piso'] &&
          u['apto'] == nuevaUnidad['apto']);
      if (yaExiste) {
        _snack('Esa unidad ya existe en el condominio', Colors.orange);
        return;
      }
    }

    setState(() => _enviando = true);

    double? latSol;
    double? lngSol;

    // Usar coordenadas de Mapbox si están disponibles, si no GPS del dispositivo
    if (_coordsMapbox != null) {
      latSol = _coordsMapbox!['lat'];
      lngSol = _coordsMapbox!['lng'];
    } else {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        latSol = pos.latitude;
        lngSol = pos.longitude;
      } catch (_) {}
    }

    try {
      // Si es condominio y usuario quiere añadir unidad → solicitud especial
      if (_esCondominio && _mostrarFormularioCondominio) {
        await FirebaseFirestore.instance.collection('solicitudes_localizador').add({
          'direccion_original': calle,
          'direccion_normalizada': _normalizarDireccion(calle),
          'complemento': _complementoCtrl.text.trim(),
          'detalles': _detallesCtrl.text.trim(),
          'solicitante_email': widget.usuarioEmail,
          'estado': 'pendiente',
          'tipo_solicitud': 'condominio_nueva_unidad',
          'condominio_direccion_id': _direccionEncontrada!.id,
          'condominio_unidad': {
            'bloque': _bloqueCtrl.text.trim(),
            'piso': _pisoCtrl.text.trim(),
            'apto': _aptoCtrl.text.trim(),
          },
          if (latSol != null) 'lat': latSol,
          if (lngSol != null) 'lng': lngSol,
          'created_at': FieldValue.serverTimestamp(),
        });
      } else {
        // Solicitud estándar
        await FirebaseFirestore.instance.collection('solicitudes_localizador').add({
          'direccion_original': calle,
          'direccion_normalizada': _normalizarDireccion(calle),
          'complemento': _complementoCtrl.text.trim(),
          'detalles': _detallesCtrl.text.trim(),
          'solicitante_email': widget.usuarioEmail,
          'estado': 'pendiente',
          if (latSol != null) 'lat': latSol,
          if (lngSol != null) 'lng': lngSol,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      await NotificacionService.enviarAAdminTerritorios(
        titulo: _esCondominio && _mostrarFormularioCondominio
            ? '🏢 Nueva unidad en condominio'
            : '📍 Nueva dirección reportada',
        cuerpo: _esCondominio && _mostrarFormularioCondominio
            ? '${widget.usuarioNombre} solicita añadir unidad en condominio: "$calle" '
                'Bloque ${_bloqueCtrl.text} Piso ${_pisoCtrl.text} Apto ${_aptoCtrl.text}'
            : '${widget.usuarioNombre} envió una dirección nueva: "$calle"'
                '${_complementoCtrl.text.isNotEmpty ? ' · ${_complementoCtrl.text}' : ''}',
        tipo: TipoNotificacion.solicitudDireccion,
        extra: {
          'solicitante': widget.usuarioEmail,
          'direccion': calle,
          if (_esCondominio && _mostrarFormularioCondominio)
            'condominio_id': _direccionEncontrada!.id,
        },
      );

      setState(() {
        _enviando = false;
        _verificado = false;
        _existe = false;
        _esCondominio = false;
        _mostrarFormularioCondominio = false;
        _direccionEncontrada = null;
        _unidadesExistentes = [];
      });
      _calleCtrl.clear();
      _complementoCtrl.clear();
      _detallesCtrl.clear();
      _bloqueCtrl.clear();
      _pisoCtrl.clear();
      _aptoCtrl.clear();

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
    _bloqueCtrl.dispose();
    _pisoCtrl.dispose();
    _aptoCtrl.dispose();
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
              onPressed: _buscando ? null : _buscar,
              icon: _buscando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 18),
              label: Text(_buscando ? context.t('enviar_dir_enviando') : context.t('enviar_dir_enviar')),
              style: ElevatedButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // ── Resultado de la búsqueda ──
          if (_verificado && _existe) ...[
            const SizedBox(height: 12),
            if (_esCondominio) ...[
              // ── CONDOMINIO ENCONTRADO ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.apartment, color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dirección encontrada: Condominio / Conjunto residencial',
                            style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_unidadesExistentes.isNotEmpty) ...[
                      const Text('Unidades registradas:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _unidadesExistentes.map((u) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Bl. ${u['bloque']} • Piso ${u['piso']} • Apto ${u['apto']}',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // Botón para añadir nueva unidad
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _mostrarFormularioCondominio = true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Añadir nueva unidad (bloque/piso/apto)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_mostrarFormularioCondominio) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nueva unidad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bloqueCtrl,
                              decoration: InputDecoration(
                                labelText: 'Bloque',
                                hintText: 'A, B, 1...',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _pisoCtrl,
                              decoration: InputDecoration(
                                labelText: 'Piso',
                                hintText: '1, 2...',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _aptoCtrl,
                        decoration: InputDecoration(
                          labelText: 'Apartamento',
                          hintText: '01, 02, 101...',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _mostrarFormularioCondominio = false),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _enviando ? null : _enviar,
                              icon: _enviando
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.send, size: 16),
                              label: Text(_enviando ? context.t('enviar_dir_enviando') : 'Enviar solicitud'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: verde,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              // ── DIRECCIÓN EXISTENTE (NO CONDOMINIO) ──
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, size: 18),
                      label: Text(_enviando ? context.t('enviar_dir_enviando') : context.t('enviar_dir_enviar')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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