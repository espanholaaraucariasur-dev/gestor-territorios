import 'dart:async';
import '../../../../../core/services/notificacion_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';
// Mapbox
import '../../../../../core/services/mapbox_service.dart';

class LocalizadorTab extends StatefulWidget {
  final String usuarioEmail;
  final String usuarioNombre;

  const LocalizadorTab({
    super.key,
    required this.usuarioEmail,
    required this.usuarioNombre,
  });

  @override
  State<LocalizadorTab> createState() => _LocalizadorTabState();
}

class _LocalizadorTabState extends State<LocalizadorTab>
    with SingleTickerProviderStateMixin {
  final TextEditingController _calleCtrl = TextEditingController();
  final TextEditingController _complementoCtrl = TextEditingController();
  final TextEditingController _detallesCtrl = TextEditingController();
  final TextEditingController _unidadCtrl = TextEditingController();

  bool _buscando = false;
  bool _buscado = false;
  bool _encontrada = false;
  bool _mostrarFormulario = false;
  bool _enviando = false;
  bool _esCondominio = false;
  bool _buscandoGps = false;
  String _mensaje = '';
  Map<String, dynamic>? _direccionEncontrada;
  final List<String> _unidades = [];
  List<Map<String, dynamic>> _sugerencias = [];
  Timer? _debounceTimer;

  // Cache de posición GPS para sugerencias contextuales
  double? _gpsLat;
  double? _gpsLng;
  bool _gpsCargado = false;
  List<Map<String, dynamic>> _dirsLocales = []; // dirs cercanas precargadas

  static const Color _verde = Color(0xFF1B5E20);
  static const Color _verdeClaro = Color(0xFF2E7D32);

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────
  // NORMALIZACIÓN — port exacto del Google Script
  // Elimina tildes, puntuación, espacios. Solo letras y números.
  // ─────────────────────────────────────────────────────────

  String _normalizar(String s) {
    if (s.isEmpty) return '';
    var t = s.toLowerCase();

    // Eliminar tildes y diacríticos
    const withAccent    = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
    const withoutAccent = 'aaaааeeeeiiiioooooeuuuucn';
    // Mapa de sustitución carácter a carácter
    final Map<String, String> accentMap = {
      'á':'a','à':'a','ã':'a','â':'a','ä':'a',
      'é':'e','è':'e','ê':'e','ë':'e',
      'í':'i','ì':'i','î':'i','ï':'i',
      'ó':'o','ò':'o','õ':'o','ô':'o','ö':'o',
      'ú':'u','ù':'u','û':'u','ü':'u',
      'ç':'c','ñ':'n',
    };
    t = t.splitMapJoin('', onNonMatch: (ch) => accentMap[ch] ?? ch);

    // Eliminar todo excepto letras a-z y dígitos 0-9
    t = t.replaceAll(RegExp(r'[^a-z0-9]'), '');

    return t;
  }

  String _normalizarBusqueda(String s) {
    return s.toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íìî]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úùû]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        ((lat2 - lat1) * p / 2).abs() +
        ((lat1 * p).abs()) *
            ((lat2 * p).abs()) *
            ((lon2 - lon1) * p / 2).abs();
    return 12742 * (a < 0 ? -a : a);
  }

  // Genera lista de tokens para guardar en palabras_clave
  List<String> _generarTokens(String texto) {
    var t = _normalizarBusqueda(texto);
    // Normalizar abreviaturas comunes
    t = t.replaceAll(RegExp(r'\br\b'), 'rua');
    t = t.replaceAll(RegExp(r'\bav\b'), 'avenida');
    t = t.replaceAll(RegExp(r'\balameda\b'), 'al');
    final tokens = t.split(' ')
        .where((w) => w.length >= 2)
        .toSet() // eliminar duplicados
        .toList();
    return tokens;
  }

  // ─────────────────────────────────────────────────────────
  // BUSCAR CON ARRAY-CONTAINS-ANY + FALLBACK RANGE QUERY
  // ─────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────
  // AUTOCOMPLETADO — busca en dirs locales primero (sin lat/lng)
  // luego en Firestore con múltiples estrategias
  // ─────────────────────────────────────────────────────────
  Future<void> _actualizarSugerencias(String texto) async {
    final query = texto.trim();
    if (query.isEmpty) {
      if (mounted && _sugerencias.isNotEmpty) setState(() => _sugerencias = []);
      return;
    }

    try {
      // Normalizar la búsqueda: sin tildes, minúsculas, permite espacios
      final norm = _normalizarBusqueda(query); // "rua ivai 68"
      final queryLower = query.toLowerCase();  // "rua ivaí 68"

      final callesVistas = <String>{};
      final sugs = <Map<String, dynamic>>[];

      // ── Estrategia 1 (LOCAL): buscar en dirs precargadas ─────────────────
      // Funciona desde 1 letra, sin llamadas a Firestore
      if (_dirsLocales.isNotEmpty) {
        for (final d in _dirsLocales) {
          final calle = (d['calle'] as String?) ?? '';
          if (calle.isEmpty) continue;

          // Comparar con versión normalizada Y versión original
          final calleNorm = _normalizarBusqueda(calle);
          final calleLower = calle.toLowerCase();
          final calleNormFields = (d['calle_normalizada'] as String?) ?? calleNorm;

          // Match si CUALQUIER palabra del query aparece en la calle
          // "rua C" → busca "rua" Y "c" en la calle
          final queryWords = norm.split(' ').where((w) => w.isNotEmpty).toList();
          final queryWordsOrig = queryLower.split(' ').where((w) => w.isNotEmpty).toList();
          
          bool match = false;
          if (queryWords.length == 1) {
            // Una sola palabra: buscar como prefijo o contiene
            final w = queryWords[0];
            match = calleNorm.contains(w) || calleLower.contains(queryWordsOrig[0]);
          } else {
            // Múltiples palabras: TODAS deben aparecer en la calle
            match = queryWords.every((w) => calleNorm.contains(w)) ||
                    queryWordsOrig.every((w) => calleLower.contains(w));
          }

          if (match && !callesVistas.contains(calle)) {
            callesVistas.add(calle);
            sugs.add(d);
            if (sugs.length >= 6) break;
          }
        }
      }

      // ── Estrategia 2 (FIRESTORE): calle_normalizada range query ──────────
      if (sugs.length < 5 && norm.length >= 2) {
        final snap = await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .where('calle_normalizada', isGreaterThanOrEqualTo: norm)
            .where('calle_normalizada', isLessThanOrEqualTo: '$norm')
            .limit(15)
            .get();

        for (final doc in snap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final calle = (d['calle'] as String?) ?? '';
          if (calle.isEmpty || callesVistas.contains(calle)) continue;
          callesVistas.add(calle);
          sugs.add(d);
          if (sugs.length >= 6) break;
        }
      }

      // ── Estrategia 3 (FIRESTORE): palabras_clave arrayContainsAny ────────
      if (sugs.length < 5 && norm.length >= 2) {
        final tokens = norm.split(' ').where((t) => t.length >= 2).toList();
        if (tokens.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('palabras_clave', arrayContainsAny: tokens.take(5).toList())
              .limit(15)
              .get();

          for (final doc in snap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final calle = (d['calle'] as String?) ?? '';
            if (calle.isEmpty || callesVistas.contains(calle)) continue;
            callesVistas.add(calle);
            sugs.add(d);
            if (sugs.length >= 6) break;
          }
        }
      }

      // ── Estrategia 4 (FIRESTORE): múltiples variantes del query ──────────
      if (sugs.length < 5 && query.length >= 2) {
        // Genera variantes: "rua c" → ["Rua C", "Rua c", "rua C"]
        final variants = <String>{
          query,
          query[0].toUpperCase() + query.substring(1),
          query.toUpperCase(),
          // Capitalizar cada palabra: "rua costa" → "Rua Costa"
          query.split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' '),
        };
        
        for (final variant in variants) {
          if (sugs.length >= 6) break;
          final snap = await FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('calle', isGreaterThanOrEqualTo: variant)
              .where('calle', isLessThanOrEqualTo: '$variant')
              .limit(10)
              .get();

          for (final doc in snap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final calle = (d['calle'] as String?) ?? '';
            if (calle.isEmpty || callesVistas.contains(calle)) continue;
            // Verificar que realmente contiene el query (no solo tiene el mismo prefijo)
            final calleN = _normalizarBusqueda(calle);
            final queryN = _normalizarBusqueda(query);
            if (!calleN.contains(queryN.split(' ')[0])) continue;
            callesVistas.add(calle);
            sugs.add(d);
            if (sugs.length >= 6) break;
          }
        }
      }

      debugPrint('🔍 Sugerencias para "$query" (norm:"$norm"): ${sugs.length} (${_dirsLocales.length} locales)');
      if (mounted) setState(() => _sugerencias = sugs);
    } catch (e) {
      debugPrint('Autocompletado error: $e');
      if (mounted) setState(() => _sugerencias = []);
    }
  }

  // Buscar por GPS — encuentra la dirección más cercana al usuario
  Future<void> _buscarPorGps() async {
    setState(() { _buscandoGps = true; _sugerencias = []; });
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final lat = pos.latitude;
      final lng = pos.longitude;

      // Buscar dirección más cercana en radio de 100m
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('lat', isGreaterThan: lat - 0.001)
          .where('lat', isLessThan: lat + 0.001)
          .limit(30)
          .get();

      Map<String, dynamic>? masNear;
      double menorDist = double.infinity;
      for (final doc in snap.docs) {
        final d = doc.data();
        final dLat = (d['lat'] as num?)?.toDouble();
        final dLng = (d['lng'] as num?)?.toDouble();
        if (dLat == null || dLng == null) continue;
        final dist = _distanciaMetros(lat, lng, dLat, dLng);
        if (dist < menorDist) { menorDist = dist; masNear = d; }
      }

      if (masNear != null && menorDist < 150) {
        final calle = masNear['calle']?.toString() ?? '';
        _calleCtrl.text = calle;
        setState(() {
          _buscandoGps = false;
          _buscando = false; _buscado = true; _encontrada = true;
          _direccionEncontrada = masNear;
          final comp = masNear!['complemento']?.toString() ?? '';
          _mensaje = comp.isNotEmpty ? '$calle · $comp' : calle;
          _mostrarFormulario = false;
        });
      } else {
        setState(() { _buscandoGps = false; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 No se encontró ninguna dirección cercana (radio 150m)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() { _buscandoGps = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error GPS: $e'), backgroundColor: Colors.red),
      );
    }
  }

  double _distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * 3.14159265358979 / 180;
    final dLng = (lng2 - lng1) * 3.14159265358979 / 180;
    final a = (dLat / 2) * (dLat / 2) +
        (lat1 * 3.14159265358979 / 180) * (lat2 * 3.14159265358979 / 180) *
            (dLng / 2) * (dLng / 2);
    return r * 2 * (a < 1 ? a : 1);
  }

  Future<void> _buscar() async {
    final consulta = _calleCtrl.text.trim();
    if (consulta.isEmpty) return;

    if (consulta.length < 3) {
      setState(() {
        _buscando = false; _buscado = true; _encontrada = false;
        _mostrarFormulario = false;
        _mensaje = 'Ingresa al menos 3 caracteres.';
      });
      return;
    }

    setState(() {
      _buscando = true; _buscado = false; _encontrada = false;
      _mostrarFormulario = false; _direccionEncontrada = null; _mensaje = '';
    });

    try {
      // Generar tokens de la consulta del usuario
      final tokens = _generarTokens(consulta);
      if (tokens.isEmpty) {
        setState(() { _buscando = false; _buscado = true; _mostrarFormulario = true; _mensaje = context.t('address_not_found'); });
        return;
      }

      // ── Estrategia 1: array-contains-any con palabras_clave ──
      final tokensQuery = tokens.take(10).toList();
      final snap1 = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('palabras_clave', arrayContainsAny: tokensQuery)
          .limit(50)
          .get();

      if (snap1.docs.isNotEmpty) {
        // Extraer el número de la consulta (último token numérico)
        final numeroConsulta = tokens.lastWhere(
          (t) => RegExp(r'^\d+$').hasMatch(t), orElse: () => '');

        int mejorScore = -1;
        Map<String, dynamic>? encontrada;

        for (final doc in snap1.docs) {
          final data = doc.data();
          final keywords = List<String>.from(data['palabras_clave'] ?? []);
          final calleDir = _normalizarBusqueda(data['calle']?.toString() ?? '');

          // Si la consulta tiene número, debe coincidir EXACTAMENTE
          if (numeroConsulta.isNotEmpty) {
            final tieneNumeroExacto = keywords.contains(numeroConsulta) ||
                calleDir.contains(numeroConsulta);
            if (!tieneNumeroExacto) continue; // descarta si el número no coincide
          }

          int coinciden = tokens.where((t) => keywords.contains(t)).length;
          // Bonus si la calle completa contiene todos los tokens de texto
          final tokensTexto = tokens.where((t) => !RegExp(r'^\d+$').hasMatch(t)).toList();
          int bonusTexto = tokensTexto.every((t) => calleDir.contains(t)) ? 20 : 0;
          int score = tokens.isEmpty ? 0 : (coinciden * 100 ~/ tokens.length) + bonusTexto;

          if (score > mejorScore) { mejorScore = score; encontrada = data; }
        }

        if (encontrada != null && mejorScore >= 60) {
          final calle = encontrada['calle']?.toString() ?? '';
          final comp = encontrada['complemento']?.toString() ?? '';
          setState(() {
            _buscando = false; _buscado = true; _encontrada = true;
            _direccionEncontrada = encontrada;
            _mensaje = comp.isNotEmpty ? '$calle · $comp' : calle;
            _mostrarFormulario = false;
          });
          return;
        }
      }

      // ── Estrategia 2: range query en calle_normalizada ──
      final consultaNorm = _normalizarBusqueda(consulta);
      final prefijoTokens = consultaNorm.split(' ').where((t) => t.length >= 2).toList();
      if (prefijoTokens.isNotEmpty) {
        for (int n = prefijoTokens.length.clamp(1, 3); n >= 1; n--) {
          final prefijo = prefijoTokens.take(n).join(' ');
          final snap2 = await FirebaseFirestore.instance
              .collection('direcciones_globales')
              .where('calle_normalizada', isGreaterThanOrEqualTo: prefijo)
              .where('calle_normalizada', isLessThanOrEqualTo: prefijo + '\uf8ff')
              .limit(20)
              .get();
          if (snap2.docs.isNotEmpty) {
            int mejorScore = -1;
            Map<String, dynamic>? encontrada;
            for (final doc in snap2.docs) {
              final data = doc.data();
              final calleNorm = (data['calle_normalizada'] as String?) ?? _normalizarBusqueda(data['calle']?.toString() ?? '');
              int coinciden = prefijoTokens.where((t) => calleNorm.contains(t)).length;
              int score = (coinciden * 100 ~/ prefijoTokens.length);
              if (score > mejorScore) { mejorScore = score; encontrada = data; }
            }
            if (encontrada != null && mejorScore >= 60) {
              final calle = encontrada['calle']?.toString() ?? '';
              final comp = encontrada['complemento']?.toString() ?? '';
              setState(() {
                _buscando = false; _buscado = true; _encontrada = true;
                _direccionEncontrada = encontrada;
                _mensaje = comp.isNotEmpty ? '$calle · $comp' : calle;
                _mostrarFormulario = false;
              });
              return;
            }
          }
        }
      }

      // ── Estrategia 3: Mapbox geocoding ──
      final coords = await MapboxService.geocodificar(consulta);
      if (coords != null) {
        final snap3 = await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .where('lat', isGreaterThan: coords[0] - 0.003)
            .where('lat', isLessThan: coords[0] + 0.003)
            .limit(15).get();
        for (final doc in snap3.docs) {
          final data = doc.data();
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null && _distanciaKm(coords[0], coords[1], lat, lng) < 0.1) {
            final calle = data['calle']?.toString() ?? '';
            final comp = data['complemento']?.toString() ?? '';
            setState(() {
              _buscando = false; _buscado = true; _encontrada = true;
              _direccionEncontrada = data;
              _mensaje = comp.isNotEmpty ? '$calle · $comp' : calle;
              _mostrarFormulario = false;
            });
            return;
          }
        }
      }

      // ── No encontrada ──
      final normalizada = _normalizar(consulta);
      final pendientes = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('direccion_normalizada', isEqualTo: normalizada)
          .where('estado', isEqualTo: 'pendiente').get();
      if (pendientes.docs.isNotEmpty) {
        setState(() { _buscando = false; _buscado = true; _encontrada = false; _mostrarFormulario = false; _mensaje = context.t('already_requested'); });
        return;
      }
      setState(() { _buscando = false; _buscado = true; _encontrada = false; _mostrarFormulario = true; _mensaje = context.t('address_not_found'); });

    } catch (e) {
      setState(() { _buscando = false; _buscado = true; _encontrada = false; _mostrarFormulario = true; _mensaje = context.t('address_not_found'); });
    }
  }

  Future<void> _enviarSolicitud() async {
    final calle = _calleCtrl.text.trim();
    if (calle.isEmpty) return;
    if (_esCondominio && _unidades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('add_min_one_unit')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    final normalizada = _normalizar(calle);

    // Obtener coordenadas actuales si están disponibles
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
        'direccion_normalizada': normalizada,
        'complemento': _complementoCtrl.text.trim(),
        'detalles': _detallesCtrl.text.trim(),
        'es_condominio': _esCondominio,
        'unidades_condominio': _esCondominio ? _unidades : [],
        'solicitante_email': widget.usuarioEmail,
        'estado': 'pendiente',
        if (latSol != null) 'lat': latSol,
        if (lngSol != null) 'lng': lngSol,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Notificar a todos los admins y admin_territorios
      await NotificacionService.enviarAAdminTerritorios(
        titulo: '📍 Nueva dirección reportada',
        cuerpo: '${widget.usuarioNombre} envió una dirección nueva: "$calle"'
            '${_complementoCtrl.text.isNotEmpty ? ' · ${_complementoCtrl.text}' : ''}',
        tipo: TipoNotificacion.solicitudDireccion,
        extra: {'solicitante': widget.usuarioEmail, 'direccion': calle},
      );

      setState(() {
        _enviando = false;
        _buscado = false;
        _mostrarFormulario = false;
        _esCondominio = false;
        _unidades.clear();
        _calleCtrl.clear();
        _complementoCtrl.clear();
        _detallesCtrl.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _esCondominio
                        ? '✅ Condominio reportado con ${_unidades.length} unidades'
                        : '✅ Dirección enviada al administrador',
                  ),
                ),
              ],
            ),
            backgroundColor: _verde,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      setState(() => _enviando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _precargarDirsCercanas();
  }

  /// Pre-carga GPS + TODAS las dirs (para busqueda local sin depender de lat/lng)
  Future<void> _precargarDirsCercanas() async {
    try {
      // Intentar GPS (no bloquea si falla)
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) await Geolocator.requestPermission();
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        if (mounted) { _gpsLat = pos.latitude; _gpsLng = pos.longitude; _gpsCargado = true; }
      } catch (_) { _gpsCargado = false; }

      // Cargar TODAS las dirs sin orderBy (evita problemas de índice)
      // Ordenar en memoria después
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .limit(500)
          .get();

      if (!mounted) return;
      setState(() {
        _dirsLocales = snap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList();
      });
      debugPrint('📍 ${_dirsLocales.length} dirs precargadas (GPS: $_gpsCargado)');
    } catch (e) {
      debugPrint('Preload error: $e');
      // Fallback: intentar sin orderBy
      try {
        final snap = await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .limit(500)
            .get();
        if (mounted) {
          setState(() {
            _dirsLocales = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          });
          debugPrint('📍 ${_dirsLocales.length} dirs precargadas (fallback)');
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _calleCtrl.dispose();
    _complementoCtrl.dispose();
    _detallesCtrl.dispose();
    _unidadCtrl.dispose();
    super.dispose();
  }

  void _agregarUnidad() {
    final unidad = _unidadCtrl.text.trim();
    if (unidad.isEmpty) return;
    setState(() {
      _unidades.add(unidad);
      _unidadCtrl.clear();
    });
  }

  String _tiempoRelativo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'hace unos segundos';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    if (diff.inDays < 30) return 'hace ${(diff.inDays / 7).floor()}sem';
    if (diff.inDays < 365) return 'hace ${(diff.inDays / 30).floor()}m';
    return 'hace ${(diff.inDays / 365).floor()}a';
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── HEADER ──────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_verde, _verdeClaro],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.location_searching,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('locator'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            context.t('spanish_speakers_directory'),
                            style:
                                const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        ),

        // ── BUSCADOR ─────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _verde,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.t('search_address'),
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _verde,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Campo de búsqueda
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _verde.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Campo de búsqueda con botón GPS
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _calleCtrl,
                              decoration: InputDecoration(
                                hintText: context.t('address_example'),
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                prefixIcon: const Icon(Icons.search, color: _verde),
                                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _calleCtrl,
                                  builder: (context, value, child) {
                                    return value.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                            onPressed: () {
                                              _calleCtrl.clear();
                                              setState(() {
                                                _buscado = false;
                                                _mostrarFormulario = false;
                                                _sugerencias = [];
                                              });
                                            },
                                          )
                                        : const SizedBox.shrink();
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: _verde, width: 2),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onChanged: (v) {
                                _debounceTimer?.cancel();
                                // Desde 1 caracter si hay dirs locales, 2+ si no
                                final minChars = _dirsLocales.isNotEmpty ? 1 : 2;
                                if (v.trim().length < minChars) {
                                  if (_sugerencias.isNotEmpty) setState(() => _sugerencias = []);
                                  return;
                                }
                                _debounceTimer = Timer(
                                  const Duration(milliseconds: 300),
                                  () async {
                                    if (mounted) await _actualizarSugerencias(v);
                                  },
                                );
                              },
                              onSubmitted: (_) {
                                setState(() => _sugerencias = []);
                                _buscar();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón GPS
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)],
                            ),
                            child: IconButton(
                              onPressed: _buscandoGps ? null : _buscarPorGps,
                              icon: _buscandoGps
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: _verde))
                                  : const Icon(Icons.my_location, color: _verde),
                              tooltip: 'Buscar por mi ubicación',
                            ),
                          ),
                        ],
                      ),

                      // Sugerencias de autocompletado
                      if (_sugerencias.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                          ),
                          child: Column(
                            children: _sugerencias.map((sug) {
                              final calle = sug['calle'] as String? ?? '';
                              final comp = sug['complemento'] as String? ?? '';
                              // Calcular distancia si hay GPS
                              final dLat = (sug['lat'] as num?)?.toDouble();
                              final dLng = (sug['lng'] as num?)?.toDouble();
                              String distStr = '';
                              if (_gpsCargado && _gpsLat != null && dLat != null && dLng != null) {
                                final dist = _distanciaMetros(_gpsLat!, _gpsLng!, dLat, dLng);
                                distStr = dist < 1000
                                    ? '${dist.round()}m'
                                    : '${(dist / 1000).toStringAsFixed(1)}km';
                              }
                              final territorio = (sug['barrio'] as String?) ?? (sug['territorio_id'] as String?) ?? '';

                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on_outlined, color: _verde, size: 18),
                                title: Text(calle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                subtitle: Row(
                                  children: [
                                    if (comp.isNotEmpty)
                                      Expanded(child: Text(comp, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                                    if (territorio.isNotEmpty)
                                      Text(territorio, style: const TextStyle(fontSize: 10, color: _verde)),
                                    if (distStr.isNotEmpty) ...[ 
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _verde.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(distStr, style: const TextStyle(fontSize: 10, color: _verde, fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ],
                                ),
                                onTap: () {
                                  _calleCtrl.text = calle;
                                  setState(() => _sugerencias = []);
                                  _buscar();
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _buscando ? null : _buscar,
                    icon: _buscando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search, size: 18),
                    label: Text(_buscando
                        ? context.t('searching')
                        : context.t('search')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _verde,
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
        ),

        // ── RESULTADO ────────────────────────────────────
        if (_buscado)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _encontrada
                  ? _buildResultadoEncontrado()
                  : _buildResultadoNoEncontrado(),
            ),
          ),

        // ── FORMULARIO SOLICITUD ─────────────────────────
        if (_mostrarFormulario)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _buildFormularioSolicitud(),
            ),
          ),

        // ── HISTORIAL ────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          sliver: SliverToBoxAdapter(
            child: _buildHistorial(),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // RESULTADO ENCONTRADO
  // ─────────────────────────────────────────────────────────

  Widget _buildResultadoEncontrado() {
    final data = _direccionEncontrada ?? {};
    final teritorio = (data['territorio_nombre'] as String?) ??
        (data['barrio'] as String?) ??
        'Sin territorio';
    final tarjeta = (data['tarjeta_id'] as String?) ?? '';
    final estado = (data['estado_predicacion'] as String?) ?? '';
    final esCondominio = (data['es_condominio'] as bool?) ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade50,
            Colors.green.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _verde,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Dirección encontrada!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _verde,
                      ),
                    ),
                    Text(
                      'Registrada en el directorio',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ),
              if (esCondominio)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.apartment, size: 12, color: Colors.blue),
                      SizedBox(width: 4),
                      Text('Cond.',
                          style: TextStyle(fontSize: 10, color: Colors.blue)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _mensaje,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF263238),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (teritorio.isNotEmpty)
                _infoBadge(Icons.map, teritorio, _verde),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // RESULTADO NO ENCONTRADO
  // ─────────────────────────────────────────────────────────

  Widget _buildResultadoNoEncontrado() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.info_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _mensaje,
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // FORMULARIO DE SOLICITUD
  // ─────────────────────────────────────────────────────────

  Widget _buildFormularioSolicitud() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _verde.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.add_location_alt, color: _verde, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Reportar nueva dirección',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Complemento
          _campo(
            ctrl: _complementoCtrl,
            hint: context.t('complement_example'),
            icon: Icons.home_outlined,
          ),
          const SizedBox(height: 10),

          // Detalles
          _campo(
            ctrl: _detallesCtrl,
            hint: context.t('reference_details'),
            icon: Icons.notes,
            maxLines: 2,
          ),
          const SizedBox(height: 14),

          // Toggle condominio
          GestureDetector(
            onTap: () => setState(() {
              _esCondominio = !_esCondominio;
              if (!_esCondominio) _unidades.clear();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _esCondominio
                    ? Colors.blue.withOpacity(0.08)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _esCondominio
                      ? Colors.blue.shade300
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.apartment,
                      color: _esCondominio ? Colors.blue : Colors.grey,
                      size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('is_condominium_building'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color:
                                _esCondominio ? Colors.blue : Colors.grey[700],
                          ),
                        ),
                        Text(
                          context.t('multiple_units_same_address'),
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _esCondominio,
                    onChanged: (v) => setState(() {
                      _esCondominio = v;
                      if (!v) _unidades.clear();
                    }),
                    activeColor: Colors.blue,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ),

          // Unidades del condominio
          if (_esCondominio) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('condominium_units'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t('add_unit_separated'),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _unidadCtrl,
                          decoration: InputDecoration(
                            hintText: 'Ej: Apto 101, Casa A...',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.blue.shade200),
                            ),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _agregarUnidad(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _agregarUnidad,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                  if (_unidades.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _unidades
                          .map((u) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      u,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _unidades.remove(u)),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 14),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_unidades.length} unidad${_unidades.length == 1 ? '' : 'es'} agregada${_unidades.length == 1 ? '' : 's'}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.blue.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Botón enviar
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _enviarSolicitud,
              icon: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text(_enviando
                  ? context.t('sending')
                  : _esCondominio
                      ? context
                          .t('send_condominium', args: ['${_unidades.length}'])
                      : context.t('send_admin')),
              style: ElevatedButton.styleFrom(
                backgroundColor: _verde,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HISTORIAL
  // ─────────────────────────────────────────────────────────

  Widget _buildHistorial() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: _verde,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'MIS SOLICITUDES',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: _verde,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('solicitudes_localizador')
              .where('solicitante_email', isEqualTo: widget.usuarioEmail)
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            // Solo mostrar spinner en la primera carga, no en cada rebuild
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = (snap.data?.docs ?? [])
              ..sort((a, b) {
                final aTs = (a.data() as Map)['created_at'];
                final bTs = (b.data() as Map)['created_at'];
                if (aTs == null || bTs == null) return 0;
                return (bTs as Timestamp).compareTo(aTs as Timestamp);
              });

            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 36, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text('Sin solicitudes aún',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: docs.map((doc) {
                final data = (doc.data() as Map<String, dynamic>?) ?? {};
                final calle = (data['direccion_original'] as String?) ?? '';
                final estado = (data['estado'] as String?) ?? 'pendiente';
                final esCondominio = (data['es_condominio'] as bool?) ?? false;
                final unidades = (data['unidades_condominio'] as List?) ?? [];
                final createdAt = (data['created_at'] as Timestamp?)?.toDate();

                Color estadoColor = Colors.orange;
                IconData estadoIcon = Icons.schedule;
                if (estado == 'aprobada') {
                  estadoColor = _verde;
                  estadoIcon = Icons.check_circle;
                } else if (estado == 'rechazada') {
                  estadoColor = Colors.red;
                  estadoIcon = Icons.cancel;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: esCondominio ? Colors.blue : estadoColor,
                        width: 4,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        esCondominio ? Icons.apartment : Icons.location_on,
                        color: esCondominio ? Colors.blue : estadoColor,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              calle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Color(0xFF263238),
                              ),
                            ),
                            Row(
                              children: [
                                if (esCondominio)
                                  Text(
                                    '🏢 ${unidades.length} unidades · ',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.blue),
                                  ),
                                if (createdAt != null)
                                  Text(
                                    _tiempoRelativo(createdAt),
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: estadoColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(estadoIcon, size: 12, color: estadoColor),
                            const SizedBox(width: 3),
                            Text(
                              estado.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: estadoColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS VISUALES
  // ─────────────────────────────────────────────────────────

  Widget _statChip(IconData icon, String valor, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 3),
            Text(
              valor,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _verde, width: 2),
        ),
        isDense: true,
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
