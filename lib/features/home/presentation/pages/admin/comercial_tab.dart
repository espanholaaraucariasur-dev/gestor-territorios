import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/services/comercial_service.dart';
import '../../../../../core/services/mapbox_geocoding_service.dart';

/// Vista del ADMIN para un territorio COMERCIAL.
///
/// Permite:
///  - Crear tarjetas ZONA-N a partir de direcciones libres de los territorios
///    base (modal de 3 pasos con vista previa y re-agrupación).
///  - Actualizar: reorganizar TODAS las direcciones (bases + zonas actuales),
///    geocodificando las que faltan y re-agrupando por cercanía mezclando
///    categorías. Reemplaza las tarjetas ZONA existentes.
///  - Desplegar cada ZONA con sus direcciones, distancia al centro y mezcla de
///    categorías.
class ComercialTab extends StatefulWidget {
  final String territorioId;
  final String territorioNombre;
  final Map<String, dynamic> usuarioData;

  const ComercialTab({
    super.key,
    required this.territorioId,
    required this.territorioNombre,
    required this.usuarioData,
  });

  /// Abre la vista del territorio comercial desde admin_tab.
  static Future<void> abrir(
    BuildContext context,
    String territorioId,
    String territorioNombre,
    Map<String, dynamic> usuarioData,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(12),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92),
          child: ComercialTab(
            territorioId: territorioId,
            territorioNombre: territorioNombre,
            usuarioData: usuarioData,
          ),
        ),
      ),
    );
  }

  @override
  State<ComercialTab> createState() => _ComercialTabState();
}

class _ComercialTabState extends State<ComercialTab> {
  final ComercialService _motor = ComercialService();
  final Set<String> _expandidas = {};

  // ─────────────────────────────────────────────────────────
  // CREAR TARJETAS ZONA-N (modal 3 pasos)
  // ─────────────────────────────────────────────────────────

  Future<void> _crearZonas() async {
    final db = FirebaseFirestore.instance;

    // PASO 1 — Elegir bases (usar las fuentes configuradas del comercial)
    final territorioDoc =
        await db.collection('territorios').doc(widget.territorioId).get();
    final fuentesBase =
        List<String>.from((territorioDoc.data()?['fuentes_base'] ?? []));

    final basesSnap = await db
        .collection('territorios')
        .where('tipo', isEqualTo: 'base')
        .get();
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> baseSnap =
        fuentesBase.isEmpty
            ? basesSnap.docs
            : basesSnap.docs
                .where((d) => fuentesBase.contains(d.id))
                .toList();

    if (baseSnap.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este comercial no tiene bases configuradas.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final categoriaPorBase = <String, String>{
      for (final b in baseSnap)
        b.id: (b.data()['categoria'] as String?) ?? 'comercio',
    };

    // TODAS las direcciones de cada base (estén o no asignadas a una tarjeta
    // de la base) se reagrupan en ZONA-N del territorio comercial.
    final Map<String, int> libresPorBase = {};
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsDisponibles = [];
    for (final fb in baseSnap) {
      final fbId = fb.id;
      final snap = await db
          .collection('direcciones_globales')
          .where('territorio_id', isEqualTo: fbId)
          .get();
      final direcciones = snap.docs.toList();
      if (direcciones.isNotEmpty) {
        libresPorBase[fb.id] = direcciones.length;
        docsDisponibles.addAll(direcciones);
      }
    }
    if (libresPorBase.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay direcciones en las bases seleccionadas.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // Estado compartido para el modal.
    final Set<String> baseSel = {};
    int minZona = 4, maxZona = 6;
    bool configurable = false;
    String prefixo = 'ZONA';
    int variante = 0;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          // Vista previa de propuesta calculada con las bases seleccionadas.
          Map<String, List<Map<String, dynamic>>>? propuesta;
          if (baseSel.isNotEmpty) {
            final candidatas = docsDisponibles
                .where((d) => baseSel.contains(d.data()['territorio_id']))
                .map((d) => d.data()
                  ..['id'] = d.id)
                .toList();
            final sinGeo = <Map<String, dynamic>>[];
            final asignacion = _motor.agruparEnZonas(
              candidatas,
              minPorZona: minZona,
              maxPorZona: maxZona,
              direccionesSinGeo: sinGeo,
              variante: variante,
            );
            final agrupadas = <String, List<Map<String, dynamic>>>{};
            for (final dir in candidatas) {
              final zonaId = asignacion[dir['id']];
              if (zonaId != null) {
                agrupadas.putIfAbsent(zonaId, () => []).add(dir);
              }
            }
            propuesta = agrupadas;
          }

          return AlertDialog(
            title: const Text('Crear tarjetas ZONA-N'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PASO 1 — Bases
                    const Text('1. Bases que usarás:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...libresPorBase.entries.map((e) {
                      final nombre = baseSnap
                          .firstWhere((d) => d.id == e.key,
                              orElse: () => baseSnap.first)
                          .data()['nombre'] as String?;
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '$nombre (${e.value} direcciones)',
                            style: const TextStyle(fontSize: 13)),
                        value: baseSel.contains(e.key),
                        activeColor: const Color(0xFF4A148C),
                        onChanged: (v) => setDlgState(() {
                          if (v == true) {
                            baseSel.add(e.key);
                          } else {
                            baseSel.remove(e.key);
                          }
                        }),
                      );
                    }),
                    const SizedBox(height: 12),
                    // PASO 2 — Tamaño
                    const Text('2. Tamaño de zona:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fijo: 4-6 direcciones',
                          style: TextStyle(fontSize: 13)),
                      value: 'fijo',
                      groupValue: configurable ? 'conf' : 'fijo',
                      activeColor: const Color(0xFF4A148C),
                      onChanged: (_) => setDlgState(() {
                        configurable = false;
                        minZona = 4;
                        maxZona = 6;
                      }),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Configurar manualmente',
                          style: TextStyle(fontSize: 13)),
                      value: configurable,
                      activeColor: const Color(0xFF4A148C),
                      onChanged: (v) => setDlgState(() {
                        configurable = v ?? false;
                      }),
                    ),
                    if (configurable) ...[
                      const SizedBox(height: 4),
                      Text('Mínimo: $minZona',
                          style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: minZona.toDouble(),
                        min: 3,
                        max: 6,
                        divisions: 3,
                        activeColor: const Color(0xFF4A148C),
                        label: '$minZona',
                        onChanged: (v) => setDlgState(() {
                          minZona = v.toInt();
                          if (maxZona < minZona) maxZona = minZona;
                        }),
                      ),
                      Text('Máximo: $maxZona',
                          style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: maxZona.toDouble(),
                        min: minZona.toDouble(),
                        max: 8,
                        divisions: 8 - minZona,
                        activeColor: const Color(0xFF4A148C),
                        onChanged: (v) => setDlgState(() {
                          maxZona = v.toInt();
                        }),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Nombre base
                    const Text('3. Nombre de las tarjetas:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey(prefixo),
                          controller: TextEditingController(text: prefixo),
                          decoration: const InputDecoration(
                            labelText: 'Prefijo',
                            hintText: 'ZONA',
                            isDense: true,
                          ),
                          onChanged: (v) => setDlgState(() {
                            prefixo = v.trim().isEmpty ? 'ZONA' : v.trim();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$prefixo-1, $prefixo-2…',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    // Vista previa (PASO 3)
                    const Text('4. Vista previa:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    if (baseSel.isEmpty)
                      const Text('Selecciona al menos una base.',
                          style: TextStyle(color: Colors.grey, fontSize: 12))
                    else if (propuesta == null || propuesta.isEmpty)
                      const Text('Sin direcciones en esas bases.',
                          style: TextStyle(color: Colors.grey, fontSize: 12))
                    else ...[
                      ...propuesta.entries.map((e) {
                        final zona = _motor.calcularGeometriaZona(e.value);
                        final cats = e.value
                            .map((d) => _categoriaDe(d, categoriaPorBase))
                            .toSet()
                            .toList();
                        final ref = _direccionRef(e.value);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.place,
                                  size: 13, color: Color(0xFF4A148C)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${e.key} · ${e.value.length} dirs · ~${zona.distanciaMediaMetros.round()}m · ${cats.join('+')} · $ref',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      Text(
                        'Se crearán ${propuesta.length} tarjetas',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A148C)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: propuesta == null || propuesta.isEmpty
                    ? null
                    : () => setDlgState(() {
                          variante++;
                        }),
                // Ícono en vez de "↺": ese glifo (U+21BA) no está en
                // NotoEmoji ni en NotoSansSymbols2, así que se renderizaba
                // vacío. Un Material Icon siempre está disponible.
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 6),
                    Text('Re-agrupar'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: propuesta == null || propuesta.isEmpty
                    ? null
                    : () async {
                        final prop = propuesta!;
                        Navigator.pop(dlgCtx);
                        await _confirmarYGuardar(prop, categoriaPorBase);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A148C),
                    foregroundColor: Colors.white),
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Confirma y guarda las zonas propuestas (crea tarjetas y asigna direcciones).
Future<void> _confirmarYGuardar(
    Map<String, List<Map<String, dynamic>>> propuesta,
    Map<String, String> categoriaPorBase) async {
    // El primer clic en "✅ Crear" re-pide confirmación del total.
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar creación'),
        content: Text(
            'Se crearán ${propuesta.length} tarjetas con '
            '${propuesta.values.fold(0, (a, l) => a + l.length)} direcciones. '
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A148C),
                foregroundColor: Colors.white),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      var index = 0;
      for (final e in propuesta.entries) {
        index++;
        final nombreTarjeta = 'ZONA-$index';
        final geos = _motor.calcularGeometriaZona(e.value);
        final cats = e.value
            .map((d) => _categoriaDe(d, categoriaPorBase))
            .toSet()
            .toList();
        final ref = _direccionRef(e.value);

        // Crear tarjeta en territorios/{comercial}/tarjetas
        batch.set(
          db
              .collection('territorios')
              .doc(widget.territorioId)
              .collection('tarjetas')
              .doc(nombreTarjeta),
          {
            'nombre': nombreTarjeta,
            'territorio_id': widget.territorioId,
            'territorio_nombre': widget.territorioNombre,
            'tipo': 'zona',
            'origen_base_id': widget.territorioId,
            'cantidad_direcciones': e.value.length,
            'totalDirecciones': e.value.length,
            'barrio': ref,
            'centroide_lat': geos.latCentro,
            'centroide_lng': geos.lngCentro,
            'radio_km': geos.radioKm,
            'distancia_media_m': geos.distanciaMediaMetros,
            'categorias': cats,
            'creado_por_ia': true,
            'completada': false,
            'bloqueado': true,
            'disponible_para_publicadores': false,
            'estatus_envio': 'disponible',
            'asignado_a': null,
            'asignado_en': null,
            'enviado_a': null,
            'enviado_nombre': null,
            'enviado_tipo': null,
            'enviado_en': null,
            'conductor_email': null,
            'publicador_email': null,
            'estado': 'disponible',
            'created_at': FieldValue.serverTimestamp(),
          },
        );

        // Asignar direcciones
        for (final dir in e.value) {
          final idDir = dir['id'] as String?;
          if (idDir == null) continue;
          final cat = _categoriaDe(dir, categoriaPorBase);
          batch.update(
            db.collection('direcciones_globales').doc(idDir),
            {
              'tarjeta_id': nombreTarjeta,
              'territorio_id': widget.territorioId,
              'territorio_nombre': widget.territorioNombre,
              if ((dir['categoria'] ?? '').toString().isEmpty)
                'categoria': cat,
            },
          );
        }
      }
      await batch.commit();

      // Sincronizar Algolia con las direcciones actualizadas (calle no cambia,
      // por lo que no es estrictamente necesario; los campos territorio sí).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('✅ ${propuesta.length} tarjetas ZONA creadas'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error creando zonas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Resuelve la categoría de una dirección: usa la propia si existe, si no
  /// la de la base a la que pertenece.
  String _categoriaDe(
      Map<String, dynamic> dir, Map<String, String> categoriaPorBase) {
    final propia = (dir['categoria'] ?? '').toString().trim();
    if (propia.isNotEmpty) return propia;
    final baseId = (dir['territorio_id'] ?? '').toString();
    if (baseId.isNotEmpty && categoriaPorBase.containsKey(baseId)) {
      return categoriaPorBase[baseId]!;
    }
    return 'comercio';
  }

  /// Devuelve una referencia corta (calle+número) de la dirección más cercana
  /// al centro del grupo.
  String _direccionRef(List<Map<String, dynamic>> dirs) {
    if (dirs.isEmpty) return '';
    final geo = _motor.calcularGeometriaZona(dirs);
    if (geo.latCentro == 0 && geo.lngCentro == 0) {
      final d0 = dirs.first;
      return '${d0['calle'] ?? ''} ${d0['numero'] ?? ''}'.trim();
    }
    Map<String, dynamic>? mejor;
    double mejorDist = double.infinity;
    for (final d in dirs) {
      final lat = d['lat'];
      final lng = d['lng'];
      if (lat is! num || lng is! num) continue;
      final dist = _motor.distanciaMetros(
          geo.latCentro,
          geo.lngCentro,
          lat.toDouble(),
          lng.toDouble());
      if (dist < mejorDist) {
        mejorDist = dist;
        mejor = d;
      }
    }
    final ref = mejor ?? dirs.first;
    final calle = ref['calle'] ?? '';
    final numero = ref['numero'] ?? ref['complemento'] ?? '';
    return '$calle $numero'.trim();
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.storefront,
                  color: Color(0xFF4A148C), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.territorioNombre,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF263238))),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A148C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('COMERCIAL',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Color(0xFF4A148C))),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Botones de acción
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _crearZonas,
                  icon: const Icon(Icons.grid_on, size: 18),
                  label: const Text('Crear ZONA-N',
                      style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A148C),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _actualizarZonas,
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Actualizar',
                      style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4A148C),
                    side: const BorderSide(color: Color(0xFF4A148C)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Lista de zonas (tarjetas tipo 'zona')
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('territorios')
                .doc(widget.territorioId)
                .collection('tarjetas')
                .where('tipo', isEqualTo: 'zona')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('❌ Error leyendo zonas: ${snapshot.error}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.redAccent),
                      const SizedBox(height: 10),
                      Text(
                        'Error al leer las zonas: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey[700], fontSize: 13),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              // Ordenar en memoria para evitar depender de un índice compuesto
              // en Firestore (where + orderBy). Las zonas viejas no tienen una
              // fecha fiable de todos modos.
              final docs = [...snapshot.data!.docs];
              docs.sort((a, b) {
                final ta =
                    (a.data()['created_at'] as Timestamp?)?.millisecondsSinceEpoch ??
                        0;
                final tb =
                    (b.data()['created_at'] as Timestamp?)?.millisecondsSinceEpoch ??
                        0;
                return tb.compareTo(ta);
              });
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'Aún no hay zonas. Toca "Crear ZONA-N"\npara agrupar las direcciones de las bases.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final zona = docs[index];
                  return _buildZonaCard(zona);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // TARJETA ZONA (expansible)
  // ─────────────────────────────────────────────────────────

  Widget _buildZonaCard(QueryDocumentSnapshot<Map<String, dynamic>> zona) {
    final data = zona.data();
    final nombre = (data['nombre'] ?? zona.id).toString();
    final cantidad = (data['cantidad_direcciones'] as num?)?.toInt() ?? 0;
    final distMedia = (data['distancia_media_m'] as num?)?.toDouble() ?? 0;
    final ref = (data['barrio'] ?? '').toString();
    final categorias = List<String>.from(data['categorias'] ?? []);
    final expandida = _expandidas.contains(zona.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!_expandidas.remove(zona.id)) {
                _expandidas.add(zona.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A148C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.store, color: Color(0xFF4A148C)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          '$cantidad dirs · ~${distMedia.round()}m'
                          '${ref.isNotEmpty ? ' · $ref' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                        if (categorias.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: categorias.map((c) {
                              final colores = {
                                'farmacia': Colors.teal,
                                'mercado': Colors.orange,
                                'mecanica': Colors.blueGrey,
                                'escuela': Colors.indigo,
                              };
                              final color = colores[c.toLowerCase()] ??
                                  const Color(0xFF4A148C);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  c.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: color),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(expandida ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey),
                ],
              ),
            ),
          ),
          // Desplegable con las direcciones de la zona
          if (expandida)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .where('tarjeta_id', isEqualTo: zona.id)
                  .snapshots(),
              builder: (context, dirSnap) {
                if (dirSnap.hasError) {
                  debugPrint(
                      '❌ Error leyendo direcciones de $nombre: ${dirSnap.error}');
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Error al leer las direcciones',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.redAccent)),
                  );
                }
                if (!dirSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final geos = _motor.calcularGeometriaZona(
                  dirSnap.data!.docs.map((d) => d.data()).toList(),
                );
                return Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A148C).withOpacity(0.03),
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dirSnap.data!.docs.map((d) {
                      final data = d.data();
                      final calle = (data['calle'] ?? '').toString();
                      final cat =
                          (data['categoria'] ?? 'comercio').toString();
                      final lat = data['lat'];
                      final lng = data['lng'];
                      String dist = '';
                      if (lat is num &&
                          lng is num &&
                          geos.latCentro != 0) {
                        dist =
                            ' · ${_motor.distanciaMetros(geos.latCentro, geos.lngCentro, lat.toDouble(), lng.toDouble()).round()}m';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 13, color: Color(0xFF4A148C)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '$calle$dist · ${cat[0].toUpperCase()}${cat.substring(1)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ACTUALIZAR DIRECCIONES NUEVAS
  // ─────────────────────────────────────────────────────────

  Future<void> _actualizarZonas() async {
    final db = FirebaseFirestore.instance;

    // 1. Cargar fuentes del comercial y las bases configuradas.
    final territorioDoc = await db
        .collection('territorios')
        .doc(widget.territorioId)
        .get();
    final fuentes =
        List<String>.from((territorioDoc.data()?['fuentes_base'] ?? []));

    final basesSnap = await db
        .collection('territorios')
        .where('tipo', isEqualTo: 'base')
        .get();
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> baseSnap =
        fuentes.isEmpty
            ? basesSnap.docs
            : basesSnap.docs
                .where((d) => fuentes.contains(d.id))
                .toList();

    if (baseSnap.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este comercial no tiene bases configuradas.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final categoriaPorBase = <String, String>{
      for (final b in baseSnap)
        b.id: (b.data()['categoria'] as String?) ?? 'comercio',
    };

    // 2. Reunir TODAS las direcciones: las que siguen en la base (nuevas) y
    //    las que ya pertenecen a alguna ZONA del comercial (actuales).
    final direccionesPorId = <String, Map<String, dynamic>>{};
    for (final fb in baseSnap) {
      final snap = await db
          .collection('direcciones_globales')
          .where('territorio_id', isEqualTo: fb.id)
          .get();
      for (final d in snap.docs) {
        direccionesPorId[d.id] = d.data()..['id'] = d.id;
      }
    }
    // Direcciones que ya fueron movidas al comercial (territorio_id == comercial).
    final enComercialSnap = await db
        .collection('direcciones_globales')
        .where('territorio_id', isEqualTo: widget.territorioId)
        .get();
    for (final d in enComercialSnap.docs) {
      direccionesPorId[d.id] = d.data()..['id'] = d.id;
    }

    if (direccionesPorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sin direcciones para reorganizar.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // 3. Geocodificar las que aún no tienen coordenadas (fuente: Mapbox).
    final todaviaSinGeo = direccionesPorId.values
        .where((d) => d['lat'] is! num || d['lng'] is! num)
        .toList();
    var geocodificadas = 0;
    if (todaviaSinGeo.isNotEmpty) {
      if (!mounted) return;
      await _geocodificarLoteConProgreso(
        todaviaSinGeo,
        onProgreso: (procesadas) {},
      );
      for (final d in todaviaSinGeo) {
        final lat = d['lat'];
        final lng = d['lng'];
        if (lat is num && lng is num) geocodificadas++;
      }
    }

    // 4. Agrupar TODO junto por cercanía (las sin GPS caen por barrio).
    final candidatas = direccionesPorId.values.toList();
    final sinGeo = <Map<String, dynamic>>[];
    final asignacion = _motor.agruparEnZonas(
      candidatas,
      minPorZona: 4,
      maxPorZona: 6,
      direccionesSinGeo: sinGeo,
    );
    final agrupadas = <String, List<Map<String, dynamic>>>{};
    for (final dir in candidatas) {
      final zonaId = asignacion[dir['id']];
      if (zonaId != null) {
        agrupadas.putIfAbsent(zonaId, () => []).add(dir);
      }
    }

    // 5. Confirmar la reorganización.
    if (!mounted) return;
    final zonasPreviasSnap = await db
        .collection('territorios')
        .doc(widget.territorioId)
        .collection('tarjetas')
        .where('tipo', isEqualTo: 'zona')
        .get();
    final totalZonasActuales = zonasPreviasSnap.docs.length;
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reorganizar zonas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se reorganizarán ${candidatas.length} direcciones en '
                  '${agrupadas.length} tarjeta(s) ZONA, '
                  'mezclando categorías por cercanía real.\n\n',
                  style: const TextStyle(fontSize: 14),
                ),
                if (geocodificadas > 0)
                  Text(
                    '📍 $geocodificadas dirección(es) se geocodificaron '
                    'para poder agruparse por distancia.\n\n',
                    style: TextStyle(fontSize: 13, color: Colors.green[700]),
                  ),
                Text(
                  'Las tarjetas existentes ($totalZonasActuales) serán '
                  'reemplazadas por las nuevas agrupaciones.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A148C),
                  foregroundColor: Colors.white),
              child: const Text('Reorganizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true || !mounted) return;

    // 6. Guardar: reemplazar tarjetas y reasignar direcciones.
    try {
      final batch = db.batch();

      // 6a. Borrar zonas existentes del territorio (ya obtenidas arriba).
      for (final z in zonasPreviasSnap.docs) {
        batch.delete(z.reference);
      }

      // 6b. Crear nuevas zonas y asignar direcciones.
      var index = 0;
      for (final e in agrupadas.entries) {
        index++;
        final nombreTarjeta = 'ZONA-$index';
        final geos = _motor.calcularGeometriaZona(e.value);
        final cats = e.value
            .map((d) => _categoriaDe(d, categoriaPorBase))
            .toSet()
            .toList();
        final ref = _direccionRef(e.value);

        batch.set(
          db
              .collection('territorios')
              .doc(widget.territorioId)
              .collection('tarjetas')
              .doc(nombreTarjeta),
          {
            'nombre': nombreTarjeta,
            'territorio_id': widget.territorioId,
            'territorio_nombre': widget.territorioNombre,
            'tipo': 'zona',
            'origen_base_id': widget.territorioId,
            'cantidad_direcciones': e.value.length,
            'totalDirecciones': e.value.length,
            'barrio': ref,
            'centroide_lat': geos.latCentro,
            'centroide_lng': geos.lngCentro,
            'radio_km': geos.radioKm,
            'distancia_media_m': geos.distanciaMediaMetros,
            'categorias': cats,
            'creado_por_ia': true,
            'completada': false,
            'bloqueado': true,
            'disponible_para_publicadores': false,
            'estatus_envio': 'disponible',
            'asignado_a': null,
            'asignado_en': null,
            'enviado_a': null,
            'enviado_nombre': null,
            'enviado_tipo': null,
            'enviado_en': null,
            'conductor_email': null,
            'publicador_email': null,
            'estado': 'disponible',
            'created_at': FieldValue.serverTimestamp(),
          },
        );

        for (final dir in e.value) {
          final idDir = dir['id'] as String?;
          if (idDir == null) continue;
          final cat = _categoriaDe(dir, categoriaPorBase);
          batch.update(
            db.collection('direcciones_globales').doc(idDir),
            {
              'tarjeta_id': nombreTarjeta,
              'territorio_id': widget.territorioId,
              'territorio_nombre': widget.territorioNombre,
              if ((dir['categoria'] ?? '').toString().isEmpty)
                'categoria': cat,
            },
          );
        }
      }

      batch.update(
        db.collection('territorios').doc(widget.territorioId),
        {'zonas_creadas': agrupadas.length},
      );

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${agrupadas.length} tarjetas ZONA reorganizadas'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error reorganizando zonas: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Geocodifica en lote las direcciones sin coordenadas usando Mapbox
  /// (con reintento en 429), actualizando lat/lng en cada documento y en el
  /// mapa local [lote]. Muestra un diálogo de progreso no bloqueante.
  Future<void> _geocodificarLoteConProgreso(
    List<Map<String, dynamic>> lote, {
    void Function(int procesadas)? onProgreso,
  }) async {
    final db = FirebaseFirestore.instance;
    var procesadas = 0;
    final progreso = ValueNotifier<int>(0);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => ValueListenableBuilder<int>(
        valueListenable: progreso,
        builder: (_, p, __) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Geocodificando $p/${lote.length}...\n'
                  'Obteniendo coordenadas para agrupar por cercanía.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    for (final d in lote) {
      final texto = _textoDireccionParaGeocodificar(d);
      if (texto.isNotEmpty) {
        try {
          final geo = await _geocodificarConReintento(texto);
          if (geo != null) {
            await db.collection('direcciones_globales').doc(d['id']).update({
              'lat': geo['lat'],
              'lng': geo['lng'],
              if ((geo['cep'] ?? '') != '') 'cep': geo['cep'],
              if ((geo['barrio'] ?? '') != '') 'barrio': geo['barrio'],
              'geocodingSource': 'comercial_reorganizar',
              'geocodedAt': FieldValue.serverTimestamp(),
            });
            d['lat'] = geo['lat'];
            d['lng'] = geo['lng'];
          }
        } catch (_) {
          // Sin GPS: la dirección caerá en el agrupado por barrio.
        }
      }
      procesadas++;
      progreso.value = procesadas;
      onProgreso?.call(procesadas);
    }
    if (mounted) Navigator.pop(context); // cerrar diálogo de progreso
  }

  /// Ensambla el texto de búsqueda para Mapbox a partir de los campos de la
  /// dirección (calle + número + barrio + Araucária).
  String _textoDireccionParaGeocodificar(Map<String, dynamic> d) {
    final calle = (d['calle'] ?? d['direccion'] ?? '').toString().trim();
    final numero = (d['numero'] ?? '').toString().trim();
    final barrio = (d['barrio'] ?? '').toString().trim();
    var texto = '$calle $numero'.trim();
    if (barrio.isNotEmpty) texto = '$texto - $barrio';
    texto = '$texto, Araucária, PR';
    return texto.trim();
  }

  /// Reintenta una vez con backoff si Mapbox responde 429 (rate limit).
  Future<Map<String, dynamic>?> _geocodificarConReintento(
      String direccion) async {
    try {
      return await MapboxGeocodingService.geocodificarDireccion(direccion);
    } on MapboxRateLimitException {
      await Future.delayed(const Duration(seconds: 2));
      try {
        return await MapboxGeocodingService.geocodificarDireccion(direccion);
      } on MapboxRateLimitException {
        return null;
      }
    }
  }
}