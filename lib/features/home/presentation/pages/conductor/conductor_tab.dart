import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';
import '../../../../../core/services/offline_sync_service.dart';

class ConductorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;
  final VoidCallback onSolicitarTerritorio;

  const ConductorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
    required this.onSolicitarTerritorio,
  });

  @override
  State<ConductorTab> createState() => _ConductorTabState();
}

class _ConductorTabState extends State<ConductorTab> {
  // Controla, por id de tarjeta, si se está mostrando su lista de direcciones
  final Map<String, bool> _tarjetasExpandidas = {};

  @override
  void initState() {
    super.initState();
    // Calienta la consulta que usa el selector "Enviar a publicador" mientras
    // todavía hay conexión, para poder abrirla desde la caché en el territorio.
    unawaited(_precargarPublicadores());
  }

  Future<void> _precargarPublicadores() async {
    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .where('es_publicador', isEqualTo: true)
          .where('estado', isEqualTo: 'aprobado')
          .get();
    } catch (_) {
      // La consulta se vuelve a intentar al pulsar Enviar.
    }
  }

  /// Una tarjeta pertenece al período si se envió o se asignó este mes.
  /// Los documentos antiguos sin fecha se mantienen para no perderlos.
  bool _tarjetaDelMes(
    Map<String, dynamic> data,
    String mesClave, {
    DateTime? fechaRespaldo,
  }) {
    final enviado = data['enviado_en'];
    final asignado = data['asignado_en'];
    final Timestamp? fecha =
        enviado is Timestamp ? enviado : (asignado is Timestamp ? asignado : null);
    final f = fecha?.toDate() ?? fechaRespaldo;
    // Documentos antiguos sin ninguna fecha se mantienen para no perderlos.
    if (f == null) return true;
    return '${f.year}-${f.month.toString().padLeft(2, '0')}' == mesClave;
  }

  Widget _barraProgreso(
      String label, int valor, int total, Color color, double pct) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$valor/$total',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF1B5E20)),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          Text(title, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _enviarTarjetaConductorAPublicador(
    String territorioId,
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    try {
      final publicadoresQuery = FirebaseFirestore.instance
          .collection('usuarios')
          .where('es_publicador', isEqualTo: true)
          .where('estado', isEqualTo: 'aprobado');
      QuerySnapshot<Map<String, dynamic>> publicadoresSnapshot;
      try {
        publicadoresSnapshot = OfflineSyncService.instance.isOffline
            ? await publicadoresQuery.get(
                const GetOptions(source: Source.cache),
              )
            : await publicadoresQuery.get();
      } catch (_) {
        // Si la conexión falla después de comprobarla, recurrir al caché local.
        try {
          publicadoresSnapshot = await publicadoresQuery.get(
            const GetOptions(source: Source.cache),
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'No hay publicadores guardados en el dispositivo. Conéctate para cargar la lista.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (publicadoresSnapshot.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay publicadores disponibles'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show selection dialog
      final publicadores = publicadoresSnapshot.docs.toList();
      String textoBusqueda = '';
      final selectedPublicador = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final filtrados = publicadores.where((doc) {
                if (textoBusqueda.isEmpty) return true;
                final data = doc.data();
                final nombre = ((data['nombre'] ?? '') as String).toLowerCase();
                final email = ((data['email'] ?? '') as String).toLowerCase();
                final q = textoBusqueda.toLowerCase();
                return nombre.contains(q) || email.contains(q);
              }).toList();

              return AlertDialog(
                title: const Text('Seleccionar Publicador'),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: double.maxFinite,
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Buscar publicador o email...',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                        onChanged: (v) =>
                            setDialogState(() => textoBusqueda = v),
                      ),
                      const SizedBox(height: 10),
                      if (filtrados.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No se encontraron publicadores.'),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtrados.length,
                            itemBuilder: (context, index) {
                              final doc = filtrados[index];
                              final data = doc.data();
                              final nombre = data['nombre'] ?? 'Sin nombre';
                              final email = data['email'] ?? 'Sin email';

                              return ListTile(
                                title: Text(nombre),
                                subtitle: Text(email),
                                onTap: () => Navigator.pop(context, data),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (selectedPublicador == null) return;

      final nombreElegido = selectedPublicador['nombre'] ?? 'Publicador';

      // Show confirmation dialog
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Envío'),
          content: Text(
            '¿Enviar tarjeta "$tarjetaNombre" a $nombreElegido?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      if (confirmado != true) return;

      final db = FirebaseFirestore.instance;
      final territorioNombre = await _nombreTerritorioEnCache(territorioId);
      final tarjetaRef = db
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId);

      // Las consultas de agregación no tienen resultado offline. La consulta
      // normal de direcciones sí usa la caché que ya alimenta esta tarjeta.
      QuerySnapshot<Map<String, dynamic>>? direccionesSnapshot;
      try {
        final query = db
            .collection('direcciones_globales')
            .where('tarjeta_id', isEqualTo: tarjetaId);
        direccionesSnapshot = OfflineSyncService.instance.isOffline
            ? await query.get(const GetOptions(source: Source.cache))
            : await query.get();
      } catch (_) {
        try {
          direccionesSnapshot = await db
              .collection('direcciones_globales')
              .where('tarjeta_id', isEqualTo: tarjetaId)
              .get(const GetOptions(source: Source.cache));
        } catch (_) {
          // La transferencia de la tarjeta no depende de contar sus direcciones.
          // Si aún no estaban cacheadas, se deja intacto el contador anterior.
        }
      }

      final batch = db.batch();
      batch.update(tarjetaRef, {
        'asignado_a': nombreElegido,
        'asignado_en': Timestamp.now(),
        'enviado_a': selectedPublicador['email'] ?? '',
        'enviado_nombre': nombreElegido,
        'publicador_email': selectedPublicador['email'] ?? '',
        'publicador_nombre': nombreElegido,
        'enviado_en': Timestamp.now(),
        'completada': false,
        'bloqueado': false,
        'disponible_para_publicadores': false,
        'territorio_nombre': territorioNombre,
        'enviado_tipo': 'publicador',
        if (direccionesSnapshot != null) ...{
          'cantidad_direcciones': direccionesSnapshot.size,
          'totalDirecciones': direccionesSnapshot.size,
        },
        // Limpiar estado stale de un dueño anterior (igual que el admin).
        'tomado_en': null,
        'tomado_por': null,
      });

      if (direccionesSnapshot != null) {
        for (final doc in direccionesSnapshot.docs) {
          batch.update(doc.reference, {'asignado_a': nombreElegido});
        }
      }

      // Firestore aplica el batch al caché local enseguida y lo conserva para
      // reenviarlo al servidor cuando vuelva la señal. No esperamos el ACK de
      // red para que el conductor pueda seguir trabajando.
      unawaited(batch.commit().catchError((Object error) {
        debugPrint('Transferencia pendiente/no confirmada: $error');
      }));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(OfflineSyncService.instance.isOffline
              ? 'Tarjeta "$tarjetaNombre" guardada en este dispositivo; se enviará al recuperar conexión.'
              : 'Tarjeta "$tarjetaNombre" enviada a $nombreElegido'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _nombreTerritorioEnCache(String territorioId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .get(const GetOptions(source: Source.cache));
      return (doc.data()?['nombre'] as String?) ?? territorioId;
    } catch (_) {
      return territorioId;
    }
  }

  /// Una dirección sigue pendiente si no fue removida y no se predicó.
  /// Mismo criterio que el selector "Solicitar tarjeta".
  bool _direccionPendiente(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d['estado'] == 'removida') return false;
    return !(d['predicado'] == true ||
        d['estado_predicacion'] == 'completada');
  }

  String _textoDireccion(Map<String, dynamic> d) {
    final directa =
        (d['direccion'] ?? d['texto_direccion'] ?? '').toString().trim();
    if (directa.isNotEmpty) return directa;
    final partes = [d['calle'], d['numero'], d['complemento']]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .toList();
    return partes.isEmpty ? '(sin texto)' : partes.join(' ');
  }

  /// Atajo bajo "Solicitar tarjeta": muestra solo la dirección (o las dos)
  /// pendiente de tarjetas del conductor que ya casi están completas. Al
  /// enviar se usa el flujo normal de tarjeta completa, así que si el
  /// publicador no la completa vuelve a aparecer aquí.
  Widget _buildAccesosRapidos() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('territorios').snapshots(),
        builder: (context, terSnap) {
          final nombresTerritorio = <String, String>{};
          final territoriosBase = <String>{};
          final territoriosAjenos = <String>{};
          if (terSnap.hasData) {
            for (final ter in terSnap.data!.docs) {
              final td = (ter.data() as Map<String, dynamic>?) ?? const {};
              if (td['tipo'] == 'base') {
                territoriosBase.add(ter.id);
                continue;
              }
              nombresTerritorio[ter.id] = (td['nombre'] as String?) ?? ter.id;
              // Territorio asignado a otro conductor: no se ofrece aquí.
              final duenoTerritorio =
                  (td['conductor_email'] ?? td['enviado_a'] ?? '').toString();
              if (duenoTerritorio.isNotEmpty &&
                  duenoTerritorio != widget.usuarioEmail) {
                territoriosAjenos.add(ter.id);
              }
            }
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collectionGroup('tarjetas')
                .snapshots(),
            builder: (context, tarSnap) {
              if (!tarSnap.hasData) return const SizedBox.shrink();

              final candidatas = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              for (final tarjetaDoc in tarSnap.data!.docs) {
                final d = tarjetaDoc.data();
                final terId = tarjetaDoc.reference.parent.parent?.id ?? '';
                if (territoriosBase.contains(terId)) continue;
                if (territoriosAjenos.contains(terId)) continue;
                if (d['completada'] == true || d['bloqueado'] == true) {
                  continue;
                }
                if (d['programado_para'] != null) continue;
                // Con un publicador u otro conductor: no es un envío directo.
                if ((d['asignado_a'] as String?)?.isNotEmpty == true) continue;
                if ((d['publicador_email'] as String?)?.isNotEmpty == true) {
                  continue;
                }
                final duenoTarjeta =
                    (d['conductor_email'] ?? d['enviado_a'] ?? '').toString();
                if (duenoTarjeta.isNotEmpty &&
                    duenoTarjeta != widget.usuarioEmail) {
                  continue;
                }
                candidatas.add(tarjetaDoc);
              }

              if (candidatas.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: candidatas
                    .map(
                      (tarjetaDoc) =>
                          _accesoRapidoTarjeta(tarjetaDoc, nombresTerritorio),
                    )
                    .toList(),
              );
            },
          );
        },
      ),
    );
  }

  Widget _accesoRapidoTarjeta(
    QueryDocumentSnapshot<Map<String, dynamic>> tarjetaDoc,
    Map<String, String> territorios,
  ) {
    final d = tarjetaDoc.data();
    final terId = tarjetaDoc.reference.parent.parent?.id ?? '';
    final terNombre = territorios[terId] ??
        (d['territorio_nombre'] as String?) ??
        terId;
    final tarjetaNombre = (d['nombre'] as String?) ?? tarjetaDoc.id;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaDoc.id)
          .snapshots(),
      builder: (context, dirSnap) {
        if (!dirSnap.hasData) return const SizedBox.shrink();
        final pendientes =
            dirSnap.data!.docs.where(_direccionPendiente).toList();
        // Solo tarjetas con una o dos direcciones pendientes.
        if (pendientes.isEmpty || pendientes.length > 2) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt,
                      size: 13, color: Color(0xFF1B5E20)),
                  const SizedBox(width: 3),
                  Text(
                    'Lista para enviar',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...pendientes.map((dirDoc) {
                final texto = _textoDireccion(dirDoc.data());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 16, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          texto,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tarjeta $tarjetaNombre · Territorio $terNombre',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _enviarTarjetaConductorAPublicador(
                      terId,
                      tarjetaDoc.id,
                      tarjetaNombre,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Enviar',
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: CustomScrollView(
        slivers: [
          // Statistics Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .snapshots(),
                    builder: (context, snap) {
                      final todas = snap.data?.docs ?? [];

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, terSnap) {
                          final territoriosDelConductor = <String>{};
                          final territoriosBase = <String>{};
                          if (terSnap.hasData) {
                            for (final ter in terSnap.data!.docs) {
                              final td =
                                  (ter.data() as Map<String, dynamic>?) ?? {};
                              // Los territorios BASE solo almacenan direcciones
                              // en el directorio global; no se cuentan en stats.
                              if (td['tipo'] == 'base') {
                                territoriosBase.add(ter.id);
                                continue;
                              }
                              if (td['enviado_a'] == widget.usuarioEmail ||
                                  td['conductor_email'] ==
                                      widget.usuarioEmail) {
                                territoriosDelConductor.add(ter.id);
                              }
                            }
                          }

                          // Recibidas: tarjetas en territorios del conductor
                          // + tarjetas enviadas directamente al conductor
                          int recibidas = 0;
                          int enviadas = 0;
                          int devueltas = 0;

                          for (final tarjDoc in todas) {
                            final data =
                                (tarjDoc.data() as Map<String, dynamic>?) ?? {};
                            final territorioId =
                                tarjDoc.reference.parent.parent?.id ?? '';

                            if (territoriosBase.contains(territorioId))
                              continue;

                            final esDelConductor = data['conductor_email'] ==
                                    widget.usuarioEmail ||
                                data['enviado_a'] == widget.usuarioEmail ||
                                territoriosDelConductor.contains(territorioId);

                            if (!esDelConductor) continue;

                            recibidas++;

                            // Enviada = el conductor la pasó a un publicador
                            final asignadoA =
                                (data['asignado_a'] as String?) ?? '';
                            final enviadoTipo =
                                (data['enviado_tipo'] as String?) ?? '';
                            if (asignadoA.isNotEmpty &&
                                enviadoTipo == 'publicador') {
                              enviadas++;
                            }

                            // Devuelta
                            if ((data['devuelto_por'] as String?)?.isNotEmpty ==
                                true) {
                              devueltas++;
                            }
                          }

                          return Row(
                            children: [
                              Expanded(
                                  child: _statCard(
                                      'Recibidas', recibidas, Icons.download)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      'Enviadas', enviadas, Icons.upload)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      'Devueltas', devueltas, Icons.undo)),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Resumen del mes actual — datos reales
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('tarjetas')
                        .snapshots(),
                    builder: (context, snapTarjetas) {
                      final mesActual =
                          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
                      final todas = snapTarjetas.data?.docs ?? [];

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .snapshots(),
                        builder: (context, terSnap) {
                          final territoriosBase = <String>{};
                          final territoriosDelConductor = <String>{};
                          // Fecha en que el territorio llegó al conductor: las
                          // tarjetas del territorio no llevan fecha propia.
                          final fechaTerritorio = <String, DateTime>{};
                          if (terSnap.hasData) {
                            for (final ter in terSnap.data!.docs) {
                              final td =
                                  (ter.data() as Map<String, dynamic>?) ?? {};
                              if (td['tipo'] == 'base') {
                                territoriosBase.add(ter.id);
                                continue;
                              }
                              if (td['enviado_a'] == widget.usuarioEmail ||
                                  td['conductor_email'] ==
                                      widget.usuarioEmail) {
                                territoriosDelConductor.add(ter.id);
                                final ts =
                                    td['enviado_en'] ?? td['asignado_en'];
                                if (ts is Timestamp) {
                                  fechaTerritorio[ter.id] = ts.toDate();
                                }
                              }
                            }
                          }

                          // Tarjetas del conductor este mes: enviadas
                          // directamente o pertenecientes a sus territorios.
                          final delConductor = todas.where((t) {
                            final d = (t.data() as Map<String, dynamic>?) ?? {};
                            final territorioId =
                                t.reference.parent.parent?.id ?? '';
                            if (territoriosBase.contains(territorioId)) {
                              return false;
                            }
                            final esSuyo = d['conductor_email'] ==
                                    widget.usuarioEmail ||
                                d['enviado_a'] == widget.usuarioEmail ||
                                territoriosDelConductor.contains(territorioId);
                            return esSuyo &&
                                _tarjetaDelMes(
                                  d,
                                  mesActual,
                                  fechaRespaldo:
                                      fechaTerritorio[territorioId],
                                );
                          }).toList();

                          final total = delConductor.length;
                          final enviadas = delConductor.where((t) {
                            final d = (t.data() as Map<String, dynamic>?) ?? {};
                            return d['completada'] != true &&
                                (d['asignado_a'] as String?)?.isNotEmpty ==
                                    true &&
                                d['enviado_tipo'] == 'publicador';
                          }).length;
                          final completadas = delConductor.where((t) {
                            final d = (t.data() as Map<String, dynamic>?) ?? {};
                            return d['completada'] == true;
                          }).length;
                          // Las completadas ya no están disponibles para enviar.
                          final disponibles = total - enviadas - completadas;

                          final pctEnviadas =
                              total > 0 ? enviadas / total : 0.0;
                          final pctCompletadas =
                              total > 0 ? completadas / total : 0.0;

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Progreso del mes',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[700])),
                                    Text(mesActual,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500])),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Barra enviadas
                                _barraProgreso('Enviadas', enviadas, total,
                                    const Color(0xFF1B5E20), pctEnviadas),
                                const SizedBox(height: 8),
                                // Barra completadas
                                _barraProgreso('Completadas', completadas,
                                    total, Colors.blue, pctCompletadas),
                                const SizedBox(height: 8),
                                // Disponibles
                                Row(
                                  children: [
                                    Icon(Icons.inbox_outlined,
                                        size: 14, color: Colors.grey[400]),
                                    const SizedBox(width: 6),
                                    Text('$disponibles disponibles para enviar',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500])),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Botón Solicitar Tarjeta — igual que publicador
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: GestureDetector(
                onTap: widget.onSolicitarTerritorio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_location_alt,
                          color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text('Solicitar tarjeta',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Atajo: direcciones de tarjetas con 1–2 pendientes
          SliverToBoxAdapter(child: _buildAccesosRapidos()),

          // Territories Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'TERRITORIOS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('territorios')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Text(context.t('loading'),
                        style: TextStyle(color: Colors.grey));
                  }
                  // Territorios donde el conductor recibió el envío
                  // Solo territorios que aún tienen tarjetas pendientes de enviar
                  final todosTerritorios = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    if (d['tipo'] == 'base') return false;
                    return d['enviado_a'] == widget.usuarioEmail ||
                        d['conductor_email'] == widget.usuarioEmail;
                  }).toList();

// Usamos FutureBuilder por territorio para verificar tarjetas pendientes
// pero para mantener el stream reactivo, filtramos con un set local
                  final docs = todosTerritorios; // Se filtra visualmente abajo

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                            left: BorderSide(
                                color: const Color(0xFF1B5E20), width: 4)),
                      ),
                      child: const Center(
                        child: Text('No hay territorios recibidos',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre =
                          (data['nombre'] as String?) ?? 'Territorio';
                      final enviadoNombre =
                          (data['enviado_nombre'] as String?) ?? '';
                      final enviadoEn = data['enviado_en'] as Timestamp?;
                      String fechaHora = '';
                      if (enviadoEn != null) {
                        final dt = enviadoEn.toDate();
                        fechaHora =
                            '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('territorios')
                            .doc(doc.id)
                            .collection('tarjetas')
                            .snapshots(),
                        builder: (context, tarjCheck) {
                          if (!tarjCheck.hasData)
                            return const SizedBox.shrink();
                          final todasCheck = tarjCheck.data!.docs;
                          // Mostrar el territorio mientras tenga alguna tarjeta
                          // sin completar (aunque ya esté con un publicador).
                          final pendientesCheck = todasCheck.where((t) {
                            final td =
                                (t.data() as Map<String, dynamic>?) ?? {};
                            return td['completada'] != true;
                          }).toList();
                          if (todasCheck.isEmpty || pendientesCheck.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border(
                                  left: BorderSide(
                                      color: const Color(0xFF1B5E20),
                                      width: 4)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ExpansionTile(
                              leading: const Icon(Icons.map,
                                  color: Color(0xFF1B5E20)),
                              title: Text(nombre,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              subtitle: enviadoNombre.isNotEmpty
                                  ? Text(
                                      'Cond: $enviadoNombre${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    )
                                  : null,
                              children: [
                                // Devolver el territorio completo al Admin
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.undo, size: 14),
                                      label: const Text('Devolver territorio',
                                          style: TextStyle(fontSize: 12)),
                                      onPressed: () async {
                                        final pendientesConPublicador =
                                            await FirebaseFirestore.instance
                                                .collection('territorios')
                                                .doc(doc.id)
                                                .collection('tarjetas')
                                                .where('asignado_a',
                                                    isNotEqualTo: '')
                                                .get();
                                        if (pendientesConPublicador
                                            .docs.isNotEmpty) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'No se puede devolver: hay tarjetas de este territorio con un publicador. Espera a que las devuelva primero.'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          }
                                          return;
                                        }
                                        final confirmar =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            title: const Text(
                                                'Confirmar devolución'),
                                            content: Text(
                                                '¿Devolver el territorio "$nombre" completo? '
                                                'Volverá a estar disponible para el Admin de Territorios.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange),
                                                child: const Text('Devolver'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmar == true) {
                                          await FirebaseFirestore.instance
                                              .collection('territorios')
                                              .doc(doc.id)
                                              .update({
                                            'enviado_a': null,
                                            'conductor_email': null,
                                            'enviado_nombre': null,
                                            'enviado_en': null,
                                            'estatus_envio': 'devuelto',
                                            'devuelto_en':
                                                FieldValue.serverTimestamp(),
                                            'devuelto_por':
                                                widget.usuarioData['nombre'] ??
                                                    widget.usuarioEmail,
                                          });
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange,
                                        side: const BorderSide(
                                            color: Colors.orange),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                      ),
                                    ),
                                  ),
                                ),
                                // Lista de tarjetas del territorio
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('territorios')
                                      .doc(doc.id)
                                      .collection('tarjetas')
                                      .snapshots(),
                                  builder: (context, tarjSnap) {
                                    if (!tarjSnap.hasData) {
                                      return const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    final todasTarjetas = tarjSnap.data!.docs;
                                    // El conductor ve TODAS las tarjetas del territorio
                                    // mientras no estén completadas, incluso las que ya
                                    // están en manos de un publicador u otro conductor.
                                    final tarjetasRelevantes =
                                        todasTarjetas.where((t) {
                                      final td =
                                          (t.data() as Map<String, dynamic>?) ??
                                              {};
                                      return td['completada'] != true;
                                    }).toList();

                                    // Ocultar territorio solo si no hay tarjetas en absoluto
                                    if (todasTarjetas.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    return Column(
                                      children:
                                          tarjetasRelevantes.map((tarjDoc) {
                                        final td = tarjDoc.data()
                                            as Map<String, dynamic>;
                                        final tarjNombre =
                                            (td['nombre'] as String?) ??
                                                tarjDoc.id;
                                        final asignadoA =
                                            (td['asignado_a'] as String?) ?? '';
                                        final conductorEmail =
                                            (td['conductor_email']
                                                    as String?) ??
                                                '';
                                        final enviadoTipo =
                                            (td['enviado_tipo'] as String?) ??
                                                '';
                                        final enviadoNombre =
                                            (td['enviado_nombre'] as String?) ??
                                                '';
                                        final yaEnviada =
                                            asignadoA.isNotEmpty ||
                                                conductorEmail.isNotEmpty ||
                                                enviadoNombre.isNotEmpty;
                                        final nombreDueno =
                                            enviadoNombre.isNotEmpty
                                                ? enviadoNombre
                                                : (asignadoA.isNotEmpty
                                                    ? asignadoA
                                                    : 'conductor');

                                        return Container(
                                          margin: const EdgeInsets.fromLTRB(
                                              12, 4, 12, 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: yaEnviada
                                                ? Colors.green.shade50
                                                : Colors.grey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: yaEnviada
                                                  ? Colors.green.shade200
                                                  : Colors.grey.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.credit_card,
                                                  color: yaEnviada
                                                      ? Colors.green
                                                      : Colors.blue,
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(tarjNombre,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 13)),
                                                    StreamBuilder<
                                                        QuerySnapshot>(
                                                      stream: FirebaseFirestore
                                                          .instance
                                                          .collection(
                                                              'direcciones_globales')
                                                          .where('tarjeta_id',
                                                              isEqualTo:
                                                                  tarjDoc.id)
                                                          .snapshots(),
                                                      builder:
                                                          (context, dirSnap) {
                                                        // Filtrado en memoria para
                                                        // no perder docs sin
                                                        // `estado`.
                                                        final count = dirSnap
                                                                .data?.docs
                                                                .where((d) {
                                                              final m = d.data()
                                                                  as Map<String,
                                                                      dynamic>?;
                                                              return (m?['estado']
                                                                      as String?) !=
                                                                  'removida';
                                                            }).length ??
                                                            0;
                                                        return Text(
                                                          '$count direcciones',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey),
                                                        );
                                                      },
                                                    ),
                                                    if (yaEnviada)
                                                      Text(
                                                        enviadoTipo ==
                                                                'conductor'
                                                            ? 'Con conductor: $nombreDueno'
                                                            : 'Con publicador: $nombreDueno',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.green
                                                                .shade700),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              // Botón enviar tarjeta individual
                                              ElevatedButton(
                                                onPressed: () =>
                                                    _enviarTarjetaConductorAPublicador(
                                                  doc.id,
                                                  tarjDoc.id,
                                                  tarjNombre,
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF1B5E20),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: const Text(
                                                  'Enviar',
                                                  style:
                                                      TextStyle(fontSize: 11),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        }, // cierre StreamBuilder outer
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          // Cards Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'TARJETAS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

          // Cards Received
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final esParaEste = d['enviado_a'] == widget.usuarioEmail ||
                        d['enviado_a'] == (widget.usuarioData['nombre'] ?? '');
                    if (!esParaEste) return false;
                    // Excluir tarjetas ya reenviadas a un publicador
                    final publicadorEmail =
                        d['publicador_email']?.toString() ?? '';
                    if (publicadorEmail.isNotEmpty) return false;
                    // Excluir tarjetas devueltas o completadas
                    if (d['estatus_envio']?.toString() == 'devuelto')
                      return false;
                    if (d['completada'] == true) return false;
                    // Excluir tarjetas que vienen dentro de un territorio
                    // (esas se ven en la sección TERRITORIOS)
                    final terId = doc.reference.parent.parent?.id ?? '';
                    final territorioEnviado = snapshot.data!.docs.any((t) =>
                        t.id == terId &&
                        ((t.data() as Map<String, dynamic>)['enviado_a'] ==
                                widget.usuarioEmail ||
                            (t.data() as Map<String, dynamic>)[
                                    'conductor_email'] ==
                                widget.usuarioEmail));
                    return !territorioEnviado;
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          left: BorderSide(color: Colors.blue, width: 4),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay tarjetas recibidas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nombre = data['nombre'] ?? 'Tarjeta';
                      final enviadoA = data['enviado_a'] ?? '';
                      final terId = doc.reference.parent.parent?.id ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            left: BorderSide(color: Colors.blue, width: 4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabecera (tocar para ver/ocultar direcciones)
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    _tarjetasExpandidas[doc.id] =
                                        !(_tarjetasExpandidas[doc.id] ?? false);
                                  });
                                },
                                child: Row(
                                  children: [
                                    const Icon(Icons.credit_card,
                                        color: Colors.blue),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombre,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                          ),
                                          Text(
                                            'Territorio: ${(data['territorio_nombre'] as String?)?.isNotEmpty == true ? data['territorio_nombre'] : terId}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54),
                                          ),
                                          StreamBuilder<QuerySnapshot>(
                                            stream: FirebaseFirestore.instance
                                                .collection(
                                                    'direcciones_globales')
                                                .where('tarjeta_id',
                                                    isEqualTo: doc.id)
                                                .snapshots(),
                                            builder: (context, dirSnap) {
                                              // Filtrado en memoria para no
                                              // perder docs sin `estado`.
                                              final count =
                                                  dirSnap.data?.docs.where((d) {
                                                        final m = d.data()
                                                                as Map<String,
                                                                    dynamic>? ??
                                                            const {};
                                                        return (m['estado']
                                                                as String?) !=
                                                            'removida';
                                                      }).length ??
                                                      0;
                                              return Text(
                                                '$count direcciones',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      (_tarjetasExpandidas[doc.id] ?? false)
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                              // Lista de direcciones vinculadas (solo si está expandida)
                              if (_tarjetasExpandidas[doc.id] ?? false) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('direcciones_globales')
                                      .where('tarjeta_id', isEqualTo: doc.id)
                                      .snapshots(),
                                  builder: (context, dirSnap) {
                                    if (!dirSnap.hasData) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      );
                                    }
                                    final dirDocs =
                                        dirSnap.data!.docs.where((d) {
                                      final m =
                                          d.data() as Map<String, dynamic>? ??
                                              const {};
                                      return (m['estado'] as String?) !=
                                          'removida';
                                    }).toList();
                                    if (dirDocs.isEmpty) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'Sin direcciones registradas',
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey),
                                        ),
                                      );
                                    }
                                    return Column(
                                      children: dirDocs.map((dDoc) {
                                        final dd =
                                            dDoc.data() as Map<String, dynamic>;
                                        final texto = (dd['direccion'] ??
                                                dd['texto_direccion'] ??
                                                dd['calle'] ??
                                                '')
                                            .toString();
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                  Icons.location_on_outlined,
                                                  size: 14,
                                                  color: Colors.blueGrey),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  texto.isEmpty
                                                      ? '(sin texto)'
                                                      : texto,
                                                  style: const TextStyle(
                                                      fontSize: 12),
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
                              // Badge enviado por
                              if (enviadoA.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Builder(builder: (context) {
                                  final enviadoEn = data['enviado_en'];
                                  String fechaHora = '';
                                  if (enviadoEn != null) {
                                    final dt =
                                        (enviadoEn as Timestamp).toDate();
                                    fechaHora =
                                        ' · ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  }
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Enviado por: ${data['enviado_nombre'] ?? enviadoA}$fechaHora',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900),
                                    ),
                                  );
                                }),
                              ],
                              const SizedBox(height: 12),
                              // Botones en fila
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.send, size: 14),
                                      label: const Text(
                                        'Enviar',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      onPressed: () =>
                                          _enviarTarjetaConductorAPublicador(
                                              terId, doc.id, nombre),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1B5E20),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.undo, size: 14),
                                      label: const Text('Devolver',
                                          style: TextStyle(fontSize: 12)),
                                      onPressed: () async {
                                        final confirmar =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text(
                                                'Confirmar devolución'),
                                            content: Text(
                                                '¿Devolver la tarjeta "$nombre"? Volverá a estar disponible.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange),
                                                child: const Text('Devolver'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmar == true) {
                                          final tarjetaRef = FirebaseFirestore
                                              .instance
                                              .collection('territorios')
                                              .doc(terId)
                                              .collection('tarjetas')
                                              .doc(doc.id);
                                          final write = tarjetaRef.update({
                                            'asignado_a': null,
                                            'asignado_en': null,
                                            'conductor_email': null,
                                            'publicador_email': null,
                                            'publicador_nombre': null,
                                            'enviado_a': null,
                                            'enviado_nombre': null,
                                            'enviado_en': null,
                                            'enviado_tipo': null,
                                            'bloqueado': false,
                                            'disponible_para_publicadores':
                                                true,
                                            'estatus_envio': 'devuelto',
                                            'devuelto_en': Timestamp.now(),
                                            'devuelto_por':
                                                widget.usuarioData['nombre'] ??
                                                    widget.usuarioEmail,
                                            'tomado_por': null,
                                            'tomado_en': null,
                                          });
                                          unawaited(
                                              write.catchError((Object error) {
                                            debugPrint(
                                                'Devolución de tarjeta pendiente: $error');
                                          }));
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(OfflineSyncService
                                                        .instance.isOffline
                                                    ? 'Devolución guardada; se sincronizará al recuperar conexión.'
                                                    : 'Tarjeta devuelta.'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange,
                                        side: const BorderSide(
                                            color: Colors.orange),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
