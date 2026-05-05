import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';

class LocalizadorTab extends StatefulWidget {
  final String usuarioEmail;

  const LocalizadorTab({
    super.key,
    required this.usuarioEmail,
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
  String _mensaje = '';
  Map<String, dynamic>? _direccionEncontrada;
  final List<String> _unidades = [];

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

  // ─────────────────────────────────────────────────────────
  // BUSCAR — lógica de subcadena igual al Google Script
  // ─────────────────────────────────────────────────────────

  Future<void> _buscar() async {
    final consulta = _calleCtrl.text.trim();
    if (consulta.isEmpty) return;

    setState(() {
      _buscando = true;
      _buscado = false;
      _encontrada = false;
      _mostrarFormulario = false;
      _direccionEncontrada = null;
      _mensaje = '';
    });

    final consultaNorm = _normalizar(consulta);

    // Mínimo 5 caracteres normalizados (igual que el Google Script)
    if (consultaNorm.length < 5) {
      setState(() {
        _buscando = false;
        _buscado = true;
        _encontrada = false;
        _mostrarFormulario = false;
        _mensaje = 'Dirección demasiado corta para buscar.';
      });
      return;
    }

    try {
      // Cargar todas las direcciones
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .limit(500)
          .get();

      // Búsqueda por tokens: cada palabra del usuario debe estar en la dirección
      // Igual que el Google Script pero más flexible — busca token por token
      Map<String, dynamic>? encontrada;
      int mejorScore = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final calle = data['calle']?.toString() ?? '';
        final comp  = data['complemento']?.toString() ?? '';
        final full  = '$calle $comp';
        final norm  = _normalizar(full);

        // Dividir la consulta en tokens significativos
        // Mapear abreviaciones comunes antes de tokenizar
        final consultaExpandida = consultaNorm
            .replaceAll('rua', 'r')
            .replaceAll('avenida', 'av')
            .replaceAll('alameda', 'al');

        // Tokens: números y palabras de 2+ caracteres
        final tokens = consultaExpandida
            .replaceAll(RegExp(r'(\d+)'), ' \$1 ')
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.length >= 2)
            .toList();

        if (tokens.isEmpty) continue;

        // Contar cuántos tokens coinciden
        int score = 0;
        for (final token in tokens) {
          if (norm.contains(token)) score++;
        }

        // Coincidencia total o muy alta
        if (score == tokens.length && score > mejorScore) {
          mejorScore = score;
          encontrada = data;
        }
      }

      // Si no hay coincidencia total, intentar con 70% de tokens
      if (encontrada == null) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final calle = data['calle']?.toString() ?? '';
          final comp  = data['complemento']?.toString() ?? '';
          final full  = '$calle $comp';
          final norm  = _normalizar(full);

          final consultaExpandida = consultaNorm
              .replaceAll('rua', 'r')
              .replaceAll('avenida', 'av')
              .replaceAll('alameda', 'al');

          final tokens = consultaExpandida
              .replaceAll(RegExp(r'(\d+)'), ' \$1 ')
              .trim()
              .split(RegExp(r'\s+'))
              .where((t) => t.length >= 2)
              .toList();

          if (tokens.isEmpty) continue;

          // El número de calle DEBE coincidir si está presente
          final numerosConsulta = tokens.where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
          final numerosDir = RegExp(r'\d+').allMatches(norm).map((m) => m.group(0)!).toList();

          bool numeroOk = numerosConsulta.isEmpty ||
              numerosConsulta.any((n) => numerosDir.contains(n));

          if (!numeroOk) continue;

          int score = 0;
          for (final token in tokens) {
            if (norm.contains(token)) score++;
          }

          final umbral = (tokens.length * 0.6).ceil();
          if (score >= umbral && score > mejorScore) {
            mejorScore = score;
            encontrada = data;
          }
        }
      }

      if (encontrada != null) {
        final calle = encontrada['calle']?.toString() ?? '';
        final comp  = encontrada['complemento']?.toString() ?? '';
        setState(() {
          _buscando = false;
          _buscado = true;
          _encontrada = true;
          _direccionEncontrada = encontrada;
          _mensaje = '$calle${comp.isNotEmpty ? ' · $comp' : ''}';
          _mostrarFormulario = false;
        });
        return;
      }

      // No encontrada — verificar si ya fue solicitada
      final pendientes = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('direccion_normalizada', isEqualTo: consultaNorm)
          .where('estado', isEqualTo: 'pendiente')
          .get();

      if (pendientes.docs.isNotEmpty) {
        setState(() {
          _buscando = false;
          _buscado = true;
          _encontrada = false;
          _mostrarFormulario = false;
          _mensaje = context.t('already_requested');
        });
        return;
      }

      setState(() {
        _buscando = false;
        _buscado = true;
        _encontrada = false;
        _mostrarFormulario = true;
        _mensaje = context.t('address_not_found');
      });

    } catch (e) {
      setState(() {
        _buscando = false;
        _buscado = true;
        _encontrada = false;
        _mostrarFormulario = true;
        _mensaje = context.t('address_not_found');
      });
    }
  }


  String _tiempoRelativo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'hace unos segundos';
    if (diff.inMinutes < 60) return 'hace \${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace \${diff.inHours}h';
    if (diff.inDays < 7) return 'hace \${diff.inDays}d';
    if (diff.inDays < 30) return 'hace \${(diff.inDays / 7).floor()}sem';
    if (diff.inDays < 365) return 'hace \${(diff.inDays / 30).floor()}m';
    return 'hace \${(diff.inDays / 365).floor()}a';
  }

    // ─────────────────────────────────────────────────────────
  // AGREGAR UNIDAD DE CONDOMINIO
  // ─────────────────────────────────────────────────────────

  void _agregarUnidad() {
    final u = _unidadCtrl.text.trim();
    if (u.isEmpty) return;
    if (_unidades.contains(u)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('unit_already_added', args: [u])),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _unidades.add(u);
      _unidadCtrl.clear();
    });
  }

  // ─────────────────────────────────────────────────────────
  // ENVIAR SOLICITUD
  // ─────────────────────────────────────────────────────────

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
        'created_at': FieldValue.serverTimestamp(),
      });

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
  void dispose() {
    _calleCtrl.dispose();
    _complementoCtrl.dispose();
    _detallesCtrl.dispose();
    _unidadCtrl.dispose();
    super.dispose();
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
                                  icon: const Icon(Icons.clear,
                                      color: Colors.grey, size: 18),
                                  onPressed: () {
                                    _calleCtrl.clear();
                                    setState(() {
                                      _buscado = false;
                                      _mostrarFormulario = false;
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
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _buscar(),
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
              if (tarjeta.isNotEmpty)
                _infoBadge(Icons.credit_card, tarjeta, Colors.blue),
              if (estado.isNotEmpty)
                _infoBadge(
                  estado == 'completada' ? Icons.check_circle : Icons.schedule,
                  estado,
                  estado == 'completada' ? _verde : Colors.orange,
                ),
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
            if (snap.connectionState == ConnectionState.waiting) {
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
