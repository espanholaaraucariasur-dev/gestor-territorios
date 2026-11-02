import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../core/services/groq_territory_service.dart';
import '../../../../../core/services/mapbox_service.dart';
import '../../../../../core/services/notificacion_service.dart' as notif;
import '../../../../../core/services/offline_sync_service.dart';

/// Un "complemento" opcional que describe una unidad dentro de un mismo
/// terreno/condominio (p. ej. Bloque 1 / Piso 1 / Apto 3). Cada complemento
/// se convierte en una dirección SEPARADA al enviarse.
class _Unidad {
  final TextEditingController bloque = TextEditingController();
  final TextEditingController piso = TextEditingController();
  final TextEditingController apto = TextEditingController();
  final TextEditingController extra = TextEditingController();

  /// Complemento armado según el modo.
  /// - Condominio: usa los prefijos 'blo'/'piso'/'apt' (coherente con la UI).
  /// - Varias casas: NO se usan 'blo'/'apt' (una casa no se describe con
  ///   bloque ni apartamiento). Solo se une el número de casa y el extra.
  String textoCompuesto({required bool esCondominio}) {
    if (esCondominio) {
      return [
        if (bloque.text.trim().isNotEmpty) 'blo ${bloque.text.trim()}',
        if (piso.text.trim().isNotEmpty) 'piso ${piso.text.trim()}',
        if (apto.text.trim().isNotEmpty) 'apt ${apto.text.trim()}',
        if (extra.text.trim().isNotEmpty) extra.text.trim(),
      ].join(' ');
    }
    // Varias casas: complemento natural "Casa {n°} {descriptor}". El campo
    // "Casa" (bloque) es el descriptor (ej. "del fondo") y "N° casa" (apto)
    // es el número. Sin prefijos 'blo'/'apt' y sin duplicar "casa".
    final num = apto.text.trim();
    var desc = bloque.text.trim();
    if (desc.isNotEmpty) {
      desc = desc
          .replaceFirst(RegExp(r'^casa\b[\s:]*', caseSensitive: false), '')
          .trim();
    }
    final casa =
        ['Casa', if (num.isNotEmpty) num, if (desc.isNotEmpty) desc].join(' ');
    return [
      if (num.isNotEmpty || desc.isNotEmpty) casa,
      if (extra.text.trim().isNotEmpty) extra.text.trim(),
    ].join(', ');
  }

  bool get vacia =>
      bloque.text.trim().isEmpty &&
      piso.text.trim().isEmpty &&
      apto.text.trim().isEmpty &&
      extra.text.trim().isEmpty;

  void dispose() {
    bloque.dispose();
    piso.dispose();
    apto.dispose();
    extra.dispose();
  }
}

/// Tarjeta rápida para que un publicador envíe direcciones nuevas a la bandeja
/// del Auditor. Guarda en la colección /sugerencias con estado
/// 'PENDIENTE_AUDITORIA'.
///
/// Soporta una dirección simple o, si se marcan los checkboxes de
/// "varias casas / mismo terreno" o "condominio", permite agregar varias
/// unidades (bloque / piso / apartamento / casa). CADA unidad se guarda como
/// una dirección separada con su propio complemento.
class EnviarDireccionCard extends StatefulWidget {
  final String usuarioEmail;
  final String usuarioNombre; // ✅ NUEVO: nombre para mostrar en notificaciones

  const EnviarDireccionCard({
    Key? key,
    required this.usuarioEmail,
    required this.usuarioNombre, // ✅ NUEVO
  }) : super(key: key);

  @override
  State<EnviarDireccionCard> createState() => _EnviarDireccionCardState();
}

class _EnviarDireccionCardState extends State<EnviarDireccionCard> {
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _complementoController = TextEditingController();
  bool _enviando = false;

  // Modos compuestos
  bool _multiplesCasas = false;
  bool _condominio = false;
  final List<_Unidad> _unidades = [
    _Unidad(),
  ];

  // Modo comercial
  bool _esComercial = false;
  String? _categoriaComercial;
  bool _criarCategoria = false;
  final TextEditingController _categoriaNovaController =
      TextEditingController();

  static const _categoriasComerciales = [
    ('farmacia', 'Farmácia'),
    ('mercado', 'Mercado'),
    ('mecanica', 'Mecânica'),
    ('escola', 'Escola'),
  ];

  static const _coresCategoria = {
    'farmacia': Colors.teal,
    'mercado': Colors.orange,
    'mecanica': Colors.blueGrey,
    'escola': Colors.indigo,
  };

  String get _categoriaComercialFinal {
    if (_criarCategoria) return _categoriaNovaController.text.trim();
    return _categoriaComercial ?? '';
  }

  bool get _modalidadMultiples => _multiplesCasas || _condominio;

  void _toggleModalidad(String tipo, bool valor) {
    setState(() {
      if (tipo == 'casas') {
        _multiplesCasas = valor;
        if (valor) _condominio = false;
      } else {
        _condominio = valor;
        if (valor) _multiplesCasas = false;
      }
      // Asegurar al menos una línea + una vacía para agregar.
      if (_modalidadMultiples &&
          _unidades.length == 1 &&
          !_unidades.first.vacia) {
        _unidades.add(_Unidad());
      }
    });
  }

  void _agregarUnidad() {
    setState(() => _unidades.add(_Unidad()));
  }

  void _quitarUnidad(int index) {
    setState(() {
      _unidades[index].dispose();
      _unidades.removeAt(index);
      if (_unidades.isEmpty) _unidades.add(_Unidad());
    });
  }

  String _construirTextoBase() {
    var base = _direccionController.text.trim();
    // Normaliza: se conserva tal cual la base (calle + número).
    return base;
  }

  /// Genera la lista de direcciones a enviar (base + complemento por unidad).
  List<Map<String, String>> _generarDirecciones() {
    final base = _construirTextoBase();
    if (base.isEmpty) return [];

    if (!_modalidadMultiples) {
      return [
        {
          'texto': base,
          'tipo': 'normal',
          'complemento': _complementoController.text.trim(),
          'categoria': _categoriaComercialFinal,
        }
      ];
    }

    // Varias unidades (casas o apartamentos): SOLO se crean las líneas que
    // tienen complemento. No se agrega una entrada "base" sin complemento:
    // si el terreno tiene 2 casas, se crean 2 direcciones, no 3.
    final resultado = <Map<String, String>>[];
    for (final u in _unidades) {
      if (u.vacia) continue;
      final comp = u.textoCompuesto(esCondominio: _condominio);
      resultado.add({
        // La CALLE validada/geocodificada NUNCA lleva el complemento: si se
        // appende aquí, Mapbox/Groq lo funden dentro del domicilio y llega a
        // la bandeja como "…, Blo Casa Del Fondo Apt, 2 - …". El complemento
        // viaja solo en su propio campo y el auditor lo ve separado.
        'texto': base,
        'tipo': _condominio ? 'condominio' : 'multiples_casas',
        'complemento': comp,
        'categoria': _categoriaComercialFinal,
      });
    }
    return resultado;
  }

  /// True si el texto contiene al menos un dígito (nº de puerta/casa).
  static bool _tieneNumero(String s) => s.contains(RegExp(r'\d'));

  Future<void> _enviarDirecciones() async {
    final base = _construirTextoBase();
    if (base.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Escribe la calle y número de la dirección.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // La calle base SIEMPRE debe llevar número (nº de puerta/casa). Sin número
    // la dirección es ambigua y el geocodificador no la puede ubicar bien.
    if (!_tieneNumero(base)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Falta el número: escribe la calle junto al nº (ej: Rua das Flores 123).'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // En modo "varias casas/condominio" no hay dirección base: se envían solo
    // las unidades cargadas. Si no hay ninguna, avisar.
    final direcciones = _generarDirecciones();
    if (direcciones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Agrega al menos una casa/unidad con su complemento.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    if (_esComercial && _categoriaComercialFinal.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Selecciona o crea una categoría comercial.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final resumenBase = _construirTextoBase();
    setState(() => _enviando = true);

    try {
      // 1) Validar realidad (Mapbox), igual que el resto de la app: solo se
      //    guardan direcciones confirmadas (nivel calle/POI, dentro de la
      //    región). Sin conexión se dejan como sugerencias pendientes para que
      //    Mapbox/auditoría las validen cuando el dispositivo vuelva a estar en
      //    línea; no se asignan directamente a un territorio.
      final offline = OfflineSyncService.instance.isOffline;
      final validas = <Map<String, dynamic>>[];
      final rechazadas = <String>[];
      for (final d in direcciones) {
        final texto = (d['texto'] ?? '').trim();
        if (offline) {
          validas.add({
            'texto': texto,
            'complemento': d['complemento'] ?? '',
            'tipo': d['tipo'] ?? 'normal',
            'categoria': d['categoria'] ?? '',
            'lat': null,
            'lng': null,
            'lugar': '',
          });
          continue;
        }
        final v = await MapboxService.validarDireccion(texto);
        if (v['ok'] != true) {
          rechazadas
              .add('$texto (${(v['motivo'] as String?) ?? 'no validada'})');
          continue;
        }
        validas.add({
          'texto': texto,
          'complemento': d['complemento'] ?? '',
          'tipo': d['tipo'] ?? 'normal',
          'categoria': d['categoria'] ?? '',
          'lat': v['lat'],
          'lng': v['lng'],
          'lugar': (v['lugar'] ?? '').toString(),
        });
      }

      // 2) Normalizar el texto con el mismo motor que usa la app (Groq):
      //    completa ciudad/estado y corrige abreviaturas. Si falla, se guarda
      //    el texto original para no bloquear el envío por un error de red.
      if (validas.isNotEmpty && !offline) {
        try {
          final normalizadas =
              await GroqTerritoryService.normalizarDireccionesParaGeocoding([
            for (int i = 0; i < validas.length; i++)
              {
                'id': '$i',
                // Solo la CALLE va al geocodificador/normalizador. El
                // complemento (apto/casa/bloque) NO se manda: si se incluye,
                // Groq lo fusiona en "direccion_normalizada" y vuelve a
                // quedar embebido en la calle de la bandeja. Su valor ya se
                // conserva aparte en el campo 'complemento'.
                'calle': validas[i]['texto'],
              },
          ]);
          for (final n in normalizadas) {
            final idx = int.tryParse(n['id']?.toString() ?? '');
            final texto = n['direccion_normalizada']?.toString() ?? '';
            if (idx != null &&
                idx >= 0 &&
                idx < validas.length &&
                texto.isNotEmpty) {
              validas[idx]['texto'] = texto;
            }
          }
        } catch (_) {}
      }

      // 3) Guardar en la bandeja del Auditor (PENDIENTE_AUDITORIA).
      if (validas.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in validas) {
          final ref =
              FirebaseFirestore.instance.collection('sugerencias').doc();
          batch.set(ref, {
            'texto_direccion': d['texto'],
            'complemento': d['complemento'],
            'tipo_entrega': d['tipo'],
            'categoria': d['categoria'],
            'es_comercial': _esComercial,
            if (d['lat'] != null) 'lat': d['lat'],
            if (d['lng'] != null) 'lng': d['lng'],
            'lugar_validado': d['lugar'],
            'fecha_ingreso': Timestamp.now(),
            'enviado_por': widget.usuarioEmail,
            'enviado_por_nombre': widget.usuarioNombre,
            'estado': 'PENDIENTE_AUDITORIA',
            'origen': 'APP_PUBLICADOR',
            if (offline) 'validacion_pendiente_online': true,
          });
        }
        final write = batch.commit();
        if (offline) {
          unawaited(write.catchError((Object error) {
            debugPrint('Sugerencias pendientes de sincronizar: $error');
          }));
        } else {
          await write;
        }
      }

      // Nada válido: avisar y conservar el formulario para poder corregir.
      if (validas.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Ninguna dirección pasó la validación: ${rechazadas.join(' · ')}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      _direccionController.clear();
      _complementoController.clear();
      _categoriaNovaController.clear();
      for (final u in _unidades) {
        u.dispose();
      }
      setState(() {
        _multiplesCasas = false;
        _condominio = false;
        _esComercial = false;
        _categoriaComercial = null;
        _criarCategoria = false;
        _unidades
          ..clear()
          ..add(_Unidad());
      });

      // Notificar al auditor de las nuevas direcciones recibidas.
      unawaited(notif.NotificacionService.enviarAAuditores(
        titulo: validas.length == 1
            ? 'Nueva dirección enviada'
            : '${validas.length} direcciones enviadas',
        cuerpo:
            '${widget.usuarioNombre} envió ${validas.length} dirección(es): '
            '$resumenBase',
        tipo: notif.TipoNotificacion.solicitudDireccion,
        extra: {'origen': 'APP_PUBLICADOR', 'cantidad': validas.length},
      ).catchError((Object error) {
        debugPrint('Notificación de dirección pendiente: $error');
      }));

      if (mounted) {
        final avisoRechazadas = rechazadas.isEmpty
            ? ''
            : ' · ${rechazadas.length} no válida(s): ${rechazadas.join('; ')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(offline
                ? 'Dirección guardada en este dispositivo; se enviará al Auditor y validará al recuperar conexión.'
                : validas.length == 1
                    ? '¡Dirección enviada con éxito al Auditor!$avisoRechazadas'
                    : '¡${validas.length} direcciones enviadas con éxito al Auditor!$avisoRechazadas'),
            backgroundColor: rechazadas.isEmpty ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al enviar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _direccionController.dispose();
    _complementoController.dispose();
    _categoriaNovaController.dispose();
    for (final u in _unidades) {
      u.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.add_location_alt_outlined, color: Color(0xFF1B5E20)),
                SizedBox(width: 8),
                Text(
                  'Enviar dirección nueva',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _direccionController,
              decoration: InputDecoration(
                hintText: 'Calle y número (ej: Rua das Flores 123)',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _complementoController,
              decoration: InputDecoration(
                hintText: 'Complemento (opcional). Ex: casa 5, bloco B, apto 3',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildModalidadSelector(),
            if (_modalidadMultiples) ...[
              const SizedBox(height: 10),
              _buildUnidadesEditor(),
            ],
            const SizedBox(height: 6),
            _buildSelectorComercial(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviarDirecciones,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                icon: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _enviando
                      ? 'Enviando...'
                      : _modalidadMultiples
                          ? 'Enviar ${_generarDirecciones().length} direcciones'
                          : 'Enviar dirección',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalidadSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Varias casas en el mismo terreno o un condominio?',
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _multiplesCasas,
                activeColor: const Color(0xFF1B5E20),
                onChanged: (v) => _toggleModalidad('casas', v ?? false),
                title: const Text('Varias casas',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _condominio,
                activeColor: const Color(0xFF1B5E20),
                onChanged: (v) => _toggleModalidad('condominio', v ?? false),
                title: const Text('Condominio',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Checkbox "Comercial" + selector de categoría (farmacia, mercado, etc.).
  /// Solo afecta a los datos que se guardan: `es_comercial` y `categoria`.
  Widget _buildSelectorComercial() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _esComercial,
          activeColor: const Color(0xFF1B5E20),
          onChanged: (v) => setState(() {
            _esComercial = v ?? false;
            if (!_esComercial) {
              _categoriaComercial = null;
              _criarCategoria = false;
              _categoriaNovaController.clear();
            }
          }),
          title: const Text('Comercial (farmacia, mercado, etc.)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        if (_esComercial)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._categoriasComerciales.map((c) {
                      final seleccionada =
                          !_criarCategoria && _categoriaComercial == c.$1;
                      return ChoiceChip(
                        label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                        selected: seleccionada,
                        selectedColor: _coresCategoria[c.$1]!.shade100,
                        onSelected: (_) => setState(() {
                          _criarCategoria = false;
                          _categoriaComercial = c.$1;
                        }),
                      );
                    }),
                    ChoiceChip(
                      label: const Text('Crear...',
                          style: TextStyle(fontSize: 12)),
                      selected: _criarCategoria,
                      onSelected: (_) => setState(() {
                        _criarCategoria = true;
                        _categoriaComercial = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_criarCategoria)
                  TextField(
                    controller: _categoriaNovaController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Ej: óptica, panadería, lavadero...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _categoriaComercialFinal.isEmpty
                          ? 'Selecciona una categoría comercial.'
                          : 'Categoría: $_categoriaComercialFinal',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _categoriaComercialFinal.isEmpty
                            ? Colors.grey
                            : _coresCategoria[_categoriaComercial] ??
                                Colors.green.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Editor de unidades: cada fila tiene 4 apartados (bloque, piso, apt/casa,
  /// extra) y un botón + para agregar otra fila. Cada fila = 1 dirección.
  Widget _buildUnidadesEditor() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _condominio
                ? 'Unidad por apartamento/casa del condominio (bloque, piso, apto):'
                : 'Cada casa del mismo terreno se envía por separado:',
            style: TextStyle(fontSize: 12, color: Colors.green.shade900),
          ),
          const SizedBox(height: 6),
          ..._unidades.asMap().entries.map((entry) {
            final index = entry.key;
            final u = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _miniCampo(
                      hint: _condominio ? 'Bloque' : 'Casa',
                      controller: u.bloque,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_condominio) ...[
                    Expanded(
                      child: _miniCampo(hint: 'Piso', controller: u.piso),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: _miniCampo(
                      hint: _condominio ? 'Apto' : 'N° casa',
                      controller: u.apto,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _miniCampo(hint: 'Extra', controller: u.extra),
                  ),
                  const SizedBox(width: 2),
                  // Botón + al final de la última fila, − para las demás.
                  if (index == _unidades.length - 1)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle,
                          color: Color(0xFF1B5E20), size: 22),
                      tooltip: 'Agregar más casas/apartamentos',
                      onPressed: _agregarUnidad,
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.redAccent, size: 22),
                      tooltip: 'Quitar',
                      onPressed: () => _quitarUnidad(index),
                    ),
                ],
              ),
            );
          }),
          Text(
            'Cada línea se guarda como una dirección aparte. '
            'Ej: $_vistaEjemplo',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String get _vistaEjemplo {
    final base =
        _construirTextoBase() == '' ? 'Rua Teste' : _construirTextoBase();
    if (_condominio) {
      return '$base blo 1 piso 1 apt 3, $base blo 1 piso 1 apt 2, '
          '$base blo 1 piso 1 apt 12 → 3 direcciones';
    }
    return '$base casa 1, $base casa 2 → 2 direcciones';
  }

  Widget _miniCampo({
    required String hint,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
