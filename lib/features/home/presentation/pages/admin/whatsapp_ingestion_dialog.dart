import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:araucaria_sur/core/services/groq_territory_service.dart';
import 'package:araucaria_sur/core/services/mapbox_geocoding_service.dart';

/// Modal para pegar fragmentos de chats de WhatsApp y cargar direcciones
/// de forma masiva. El texto se envía a Groq para extraer un array JSON,
/// se geocodifica cada dirección con Mapbox y, tras confirmación, se guardan
/// en la tarjeta destino.
class WhatsAppIngestionDialog extends StatefulWidget {
  final Map<String, dynamic>? usuarioData;

  const WhatsAppIngestionDialog({Key? key, this.usuarioData}) : super(key: key);

  @override
  State<WhatsAppIngestionDialog> createState() => _WhatsAppIngestionDialogState();
}

class _WhatsAppIngestionDialogState extends State<WhatsAppIngestionDialog> {
  final TextEditingController _textoCtrl = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _procesando = false;
  String _estadoTexto = '';
  List<Map<String, dynamic>> _direccionesExtraidas = [];
  Map<String, dynamic> _tarjetaDestino = {};
  String? _tarjetaIdDestino;
  bool _guardando = false;
  List<DropdownMenuItem<String>> _tarjetasDrop = [];
  Map<String, Map<String, dynamic>> _mapaTarjetas = {};

  @override
  void initState() {
    super.initState();
    _cargarTarjetas();
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTarjetas() async {
    try {
      // Las tarjetas viven en la subcolección territorios/{terId}/tarjetas.
      // Se recorren todos los territorios para ofrecerlas en el selector.
      final ters = await _firestore.collection('territorios').get();
      final drop = <DropdownMenuItem<String>>[];
      final mapa = <String, Map<String, dynamic>>{};
      String? primero;
      for (final ter in ters.docs) {
        final terNombre = (ter.data()['nombre']?.toString() ?? ter.id);
        final sub = await _firestore
            .collection('territorios')
            .doc(ter.id)
            .collection('tarjetas')
            .get();
        for (final doc in sub.docs) {
          final nombre = (doc.data()['nombre'] as String?) ?? doc.id;
          final key = '${ter.id}/${doc.id}';
          final t = {
            'id': doc.id,
            'nombre': nombre,
            'territorio_id': ter.id,
            'territorio_nombre': terNombre,
          };
          mapa[key] = t;
          drop.add(DropdownMenuItem(
            value: key,
            child: Text('$nombre ($terNombre)',
                overflow: TextOverflow.ellipsis),
          ));
          primero ??= key;
        }
      }
      if (mounted) {
        setState(() {
          _tarjetasDrop = drop;
          _mapaTarjetas = mapa;
          _tarjetaIdDestino = primero;
        });
      }
    } catch (_) {}
  }

  Future<void> _extraerYGeocodificar() async {
    final texto = _textoCtrl.text.trim();
    if (texto.isEmpty) return;

    setState(() {
      _procesando = true;
      _estadoTexto = 'Consultando a la IA para extraer direcciones...';
    });

    try {
      // 1. Groq extrae el array de direcciones
      final extraidas =
          await GroqTerritoryService.extraerDireccionesWhatsApp(textoWhatsApp: texto);

      if (extraidas.isEmpty) {
        if (mounted) {
          setState(() {
            _procesando = false;
            _estadoTexto = 'No se encontraron direcciones en el texto.';
          });
        }
        return;
      }

      // 2. Normalizar el texto (Groq, en lotes) y geocodificar con Mapbox
      // (obteniendo CEP, no solo coordenadas). Antes acá se armaba
      // 'direccion_normalizada' con una concatenación cruda
      // ('$calle $numero $barrio'.trim()) que NO pasaba por Groq: no
      // corregía abreviaturas ni garantizaba ciudad/estado/CEP.
      setState(() => _estadoTexto =
          'Normalizando y geocodificando ${extraidas.length} direcciones...');

      final conCoordenadas = <Map<String, dynamic>>[];
      final tamLote = GroqTerritoryService.maxDireccionesPorLoteGeocoding;
      for (var inicio = 0; inicio < extraidas.length; inicio += tamLote) {
        final fin = (inicio + tamLote > extraidas.length)
            ? extraidas.length
            : inicio + tamLote;
        final lote = extraidas.sublist(inicio, fin);

        final crudas = <Map<String, dynamic>>[];
        for (var i = 0; i < lote.length; i++) {
          final dir = lote[i];
          crudas.add({
            'id': i.toString(), // índice LOCAL al lote, no un id real de Firestore
            'calle': dir['direccion'] ?? '',
            'numero': dir['numero'] ?? '',
            'complemento': dir['observaciones'] ?? '',
            'barrio': dir['barrio'] ?? '',
          });
        }

        List<Map<String, dynamic>> normalizadas = [];
        try {
          normalizadas =
              await GroqTerritoryService.normalizarDireccionesParaGeocoding(crudas);
        } catch (_) {
          // Sin conexión/error de Groq: se sigue con el texto crudo para
          // este lote en vez de bloquear toda la carga masiva.
        }
        final normalizadasPorIndice = {
          for (final n in normalizadas)
            int.tryParse(n['id']?.toString() ?? ''): n
        };

        for (var i = 0; i < lote.length; i++) {
          final dir = lote[i];
          final direccionTexto = (dir['direccion'] ?? '').toString();
          final numero = (dir['numero'] ?? '').toString();
          final direccionNormalizada =
              normalizadasPorIndice[i]?['direccion_normalizada']?.toString() ??
                  [direccionTexto, if (numero.isNotEmpty) numero, dir['barrio']?.toString()]
                      .where((s) => s != null && s.isNotEmpty)
                      .join(', ');

          Map<String, dynamic>? geo;
          try {
            geo = await MapboxGeocodingService.geocodificarDireccion(direccionNormalizada);
          } catch (_) {
            geo = null;
          }

          conCoordenadas.add({
            ...dir,
            'lat': geo?['lat'],
            'lng': geo?['lng'],
            'cep': geo?['cep'] ?? '',
            'completo': direccionNormalizada,
            'direccionNormalizada': direccionNormalizada,
          });
        }
      }

      if (mounted) {
        setState(() {
          _direccionesExtraidas = conCoordenadas;
          _procesando = false;
          _estadoTexto =
              'Se extrajeron ${conCoordenadas.length} direcciones. Revisa antes de guardar.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _procesando = false;
          _estadoTexto = 'Error al procesar: $e';
        });
      }
    }
  }

  Future<void> _guardarEnTarjeta() async {
    if (_direccionesExtraidas.isEmpty) return;
    setState(() => _guardando = true);

    final email = widget.usuarioData?['email']?.toString() ??
        widget.usuarioData?['usuario_email'] ??
        'sistema';

    final batch = _firestore.batch();

    // Resolver la tarjeta destino por su clave compuesta territorio/tarjeta.
    _tarjetaDestino = _mapaTarjetas[_tarjetaIdDestino] ?? _tarjetaDestino;
    final terId = _tarjetaDestino['territorio_id']?.toString() ?? '';
    final cardId = _tarjetaDestino['id']?.toString() ?? '';
    if (terId.isEmpty || cardId.isEmpty) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _estadoTexto = 'Selecciona una tarjeta destino válida.';
        });
      }
      return;
    }
    final tarjetaRef = _firestore
        .collection('territorios')
        .doc(terId)
        .collection('tarjetas')
        .doc(cardId);

    var incremento = 0;
    for (final dir in _direccionesExtraidas) {
      final dirRef = _firestore.collection('direcciones_globales').doc();
      // Preferir el texto YA normalizado (Groq + Mapbox) calculado en
      // _extraerYGeocodificar; si por algún motivo no está (falló la red),
      // caer al campo crudo en vez de dejarlo vacío.
      final calle = (dir['direccionNormalizada'] ?? dir['direccion'] ?? '').toString();
      final numero = (dir['numero'] ?? '').toString();
      final barrio = (dir['barrio'] ?? _tarjetaDestino['territorio_nombre'] ?? '')
          .toString();
      final observ = (dir['observaciones'] ?? '').toString();
      final cep = (dir['cep'] ?? '').toString();

      final data = {
        'calle': calle,
        'numero': numero,
        'complemento': observ,
        'direccionNormalizada': calle,
        if (cep.isNotEmpty) 'cep': cep,
        'territorio_id': _tarjetaDestino['territorio_id'] ?? '',
        'territorio_nombre': _tarjetaDestino['territorio_nombre'] ?? '',
        // CRÍTICO: antes acá se guardaba _tarjetaIdDestino, que es la clave
        // COMPUESTA "territorioId/tarjetaId" del dropdown — no el id real
        // de la tarjeta. Eso hacía que la dirección nunca pudiera coincidir
        // con la consulta del publicador (que filtra por el id plano).
        'tarjeta_id': cardId,
        'barrio': barrio,
        // 'asignada' (no 'activa'): el mismo valor que usan el admin, el
        // auditor y la auto-asignación en todo el resto del sistema.
        'estado': 'asignada',
        'estado_predicacion': 'pendiente',
        'predicado': false,
        'es_hispano': true,
        'solicitada_por': email,
        'origen': 'whatsapp',
        'lat': dir['lat'],
        'lng': dir['lng'],
        'creado_el': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      };
      batch.set(dirRef, data);
      incremento++;
    }

    // Actualizar contador de la tarjeta destino
    batch.update(tarjetaRef, {
      'totalDirecciones': FieldValue.increment(incremento),
      'cantidad_direcciones': FieldValue.increment(incremento),
    });

    // Registrar el evento en historial_reorganizaciones
    batch.set(_firestore.collection('historial_reorganizaciones').doc(), {
      'tipo': 'CARGA_MASIVA_WHATSAPP',
      'tarjeta_id': cardId,
      'territorio_id': terId,
      'tarjeta_nombre': _tarjetaDestino['nombre'],
      'cantidad': incremento,
      'usuario': email,
      'detalle': 'Carga masiva desde WhatsApp (ingestión)',
      'created_at': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _estadoTexto = 'Error al guardar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.message, color: Color(0xFF1B4D2E)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Carga Masiva desde WhatsApp',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textoCtrl,
              maxLines: 8,
              minLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'Pega aquí el fragmento del chat de WhatsApp con las direcciones...',
              ),
            ),
            const SizedBox(height: 8),
            if (_estadoTexto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (_procesando)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_procesando) const SizedBox(width: 8),
                    Expanded(
                      child: Text(_estadoTexto,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            // Selector de tarjeta destino (solo tras extraer direcciones)
            if (_direccionesExtraidas.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Guardar en tarjeta:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _tarjetaIdDestino,
                isExpanded: true,
                items: _tarjetasDrop,
                onChanged: (val) {
                  setState(() {
                    _tarjetaIdDestino = val;
                    _tarjetaDestino = _mapaTarjetas[val] ?? {};
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('Selecciona una tarjeta'),
              ),
            ],
            const SizedBox(height: 8),
            if (_direccionesExtraidas.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Direcciones extraídas:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _direccionesExtraidas.length,
                  itemBuilder: (context, i) {
                    final d = _direccionesExtraidas[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        d['lat'] != null
                            ? Icons.location_on
                            : Icons.location_off,
                        color: d['lat'] != null ? Colors.green : Colors.red,
                      ),
                      title: Text(d['completo'] ?? '',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        'Obs: ${d['observaciones'] ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _procesando || _guardando || _textoCtrl.text.trim().isEmpty
                          ? null
                          : _extraerYGeocodificar,
                  child: const Text('Extraer direcciones'),
                ),
                const SizedBox(width: 8),
                if (_direccionesExtraidas.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4D2E),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _guardando || _tarjetaIdDestino == null
                        ? null
                        : _guardarEnTarjeta,
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text('Guardar (${_direccionesExtraidas.length})'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}