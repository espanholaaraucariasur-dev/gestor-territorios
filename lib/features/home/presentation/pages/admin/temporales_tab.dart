import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/utils/direccion_utils.dart';
import '../../../../../core/utils/transferencia_tarjeta.dart';
import '../../../../../core/services/historial_temporales_service.dart';

class TemporalesTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const TemporalesTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<TemporalesTab> createState() => _TemporalesTabState();
}

class _TemporalesTabState extends State<TemporalesTab> {
  int _sliderValue = 5;
  final Set<String> _tarjetasExpandidas = {};

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CREAR TARJETA TEMPORAL
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _crearTarjetaTemporal(
    String territorioId,
    String territorioNombre,
    List<DocumentSnapshot> direccionesDisponibles,
  ) async {
    final cantidad = _sliderValue.clamp(1, direccionesDisponibles.length);
    final seleccionadas = direccionesDisponibles.take(cantidad).toList();

    // Nombre secuencial: T-TERRITORIO-001, T-TERRITORIO-002, etc.
    // Por territorio el número nunca se repite: sube hasta 999 y al llegar
    // se reinicia a 001. También se reinicia al cambiar el año teocrático
    // (que comienza en septiembre).
    final tarjetasExistentes = await FirebaseFirestore.instance
        .collection('territorios')
        .doc('temporales')
        .collection('tarjetas')
        .where('territorio_origen_id', isEqualTo: territorioId)
        .get();

    // Ciclo teocrático actual: septiembre → agosto (p.ej. 2026/2027).
    final hoyCiclo = DateTime.now();
    final ciclos = hoyCiclo.month >= 9
        ? '${hoyCiclo.year}/${hoyCiclo.year + 1}'
        : '${hoyCiclo.year - 1}/${hoyCiclo.year}';

    int maxNumero = 0;
    for (final t in tarjetasExistentes.docs) {
      final tData = t.data();
      String ciclosTarjeta = (tData['ciclo_teocratico'] as String?) ?? '';
      if (ciclosTarjeta.isEmpty) {
        final creada = tData['created_at'];
        if (creada is Timestamp) {
          final dt = creada.toDate();
          ciclosTarjeta = dt.month >= 9
              ? '${dt.year}/${dt.year + 1}'
              : '${dt.year - 1}/${dt.year}';
        }
      }
      // Solo las tarjetas del ciclo actual suman para la numeración
      if (ciclosTarjeta != ciclos) continue;

      final nombreT = (tData['nombre'] as String?) ?? t.id;
      final regexN = RegExp(r'(\d{3})$');
      final matchN = regexN.firstMatch(nombreT);
      if (matchN != null) {
        final n = int.tryParse(matchN.group(1)!) ?? 0;
        if (n > maxNumero) maxNumero = n;
      }
    }
    final numero =
        maxNumero >= 999 ? '001' : (maxNumero + 1).toString().padLeft(3, '0');
    final nombreTarjeta = 'T-$territorioNombre-$numero';

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // Estado global de liberación para heredar en la nueva tarjeta
      DocumentSnapshot<Map<String, dynamic>> estadoGlobal;
      try {
        estadoGlobal =
            await db.collection('territorios').doc('temporales').get();
      } catch (_) {
        estadoGlobal = await db
            .collection('territorios')
            .doc('temporales')
            .get(const GetOptions(source: Source.cache));
      }
      final gData = estadoGlobal.data() ?? {};
      final liberadoGlobal =
          (gData['disponible_para_publicadores'] as bool?) ?? false;
      final soloConductoresGlobal =
          (gData['solo_conductores'] as bool?) ?? false;

      // 1. Crear tarjeta en territorios/temporales/tarjetas
      final tarjetaRef = db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(nombreTarjeta);

      batch.set(tarjetaRef, {
        'nombre': nombreTarjeta,
        'territorio_id': 'temporales',
        'territorio_nombre': territorioNombre,
        'territorio_origen_id': territorioId,
        'territorio_origen_nombre': territorioNombre,
        'ciclo_teocratico': ciclos,
        'es_temporal': true,
        'cantidad_direcciones': seleccionadas.length,
        'completada': false,
        'bloqueado': !liberadoGlobal,
        'disponible_para_publicadores': liberadoGlobal,
        'solo_conductores': liberadoGlobal ? soloConductoresGlobal : false,
        'estatus_envio': 'disponible',
        'asignado_a': null,
        'asignado_en': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'conductor_email': null,
        'publicador_email': null,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 2. Actualizar cada dirección seleccionada
      // tarjeta_id_origen se mantiene, tarjeta_id apunta a nueva tarjeta temporal
      //
      // `nuevasEnBandeja` recoge solo las direcciones que ENTRAN en la bandeja
      // con este movimiento. Si una ya estaba en la bandeja (estado 'temporal'
      // o 'temporal_asignada') y lo único que se le hace es asignarle una
      // tarjeta concreta, no cuenta como entrada: es una reorganización interna
      // y sumarla inflaría las entradas.
      final nuevasEnBandeja = <(String, Map<String, dynamic>)>[];
      for (final dir in seleccionadas) {
        final data = (dir.data() as Map<String, dynamic>?) ?? {};
        final tarjetaIdOriginal =
            (data['tarjeta_id_origen'] as String?)?.isNotEmpty == true
                ? data['tarjeta_id_origen'] as String
                : ((data['tarjeta_id'] as String?) ?? '');

        final estadoPrevio = (data['estado'] as String?) ?? '';
        final yaEstabaEnTemporal = estadoPrevio == 'temporal' ||
            estadoPrevio == 'temporal_asignada' ||
            (data['territorio_id']?.toString() ?? '') == 'temporales';

        // Guardar el territorio REAL antes de pisarlo con 'temporales'.
        //
        // Antes este bloque sobreescribía `territorio_id` y no guardaba el
        // valor anterior en ningún lado. Cuando el publicador después marcaba
        // la dirección como predicha e intentaba devolverla a su tarjeta de
        // origen, ya no quedaba rastro de a qué territorio pertenecía: quedaba
        // 'temporales', que no es un territorio, y el publicador la dejaba en
        // 'Sin territorio' sin tarjeta. Esa dirección ya no se podía
        // reconectar sola.
        final esTerritorioReal = (String v) {
          final t = v.trim().toLowerCase();
          return t.isNotEmpty && t != 'temporales' && t != 'sin territorio';
        };
        final territorioOrigenPrevioId =
            esTerritorioReal((data['territorio_origen_id'] as String?) ?? '')
                ? (data['territorio_origen_id'] as String).trim()
                : (esTerritorioReal(data['territorio_id']?.toString() ?? '')
                    ? data['territorio_id'].toString().trim()
                    : '');
        final territorioOrigenPrevioNombre = esTerritorioReal(
                (data['territorio_origen_nombre'] as String?) ?? '')
            ? (data['territorio_origen_nombre'] as String).trim()
            : (esTerritorioReal(data['territorio_nombre']?.toString() ?? '')
                ? data['territorio_nombre'].toString().trim()
                : '');

        // El origen se guarda tal cual venga, incluso si es otra temporal. Al mover
        // una dirección de `T-...-001` a `T-...-002` ese valor es el único
        // rastro de que pasó por la primera, y filtrar las `T-` lo borraba:
        // la cadena se perdía en cada reasignación dentro de la bandeja.
        batch.update(dir.reference, {
          'tarjeta_id': nombreTarjeta, // apunta a tarjeta temporal
          if (tarjetaIdOriginal.trim().isNotEmpty)
            'tarjeta_id_origen': tarjetaIdOriginal.trim(),
          'territorio_id': 'temporales',
          if (territorioOrigenPrevioId.isNotEmpty)
            'territorio_origen_id': territorioOrigenPrevioId,
          if (territorioOrigenPrevioNombre.isNotEmpty)
            'territorio_origen_nombre': territorioOrigenPrevioNombre,
          'estado': 'temporal_asignada',
          'estado_predicacion': 'pendiente',
        });

        if (!yaEstabaEnTemporal) nuevasEnBandeja.add((dir.id, data));
      }

      await batch.commit();

      // Registrar la entrada de cada dirección que realmente entró a la
      // bandeja. Antes no se registraba nada, y esas direcciones quedaban
      // invisibles para las estadísticas.
      var fallos = 0;
      for (final nueva in nuevasEnBandeja) {
        final ok = await registrarMovimientoTemporal(
          tipo: 'entrada',
          direccionId: nueva.$1,
          territorioOrigenId: nueva.$2['territorio_id']?.toString() ?? '',
          territorioOrigenNombre:
              nueva.$2['territorio_nombre']?.toString() ?? '',
          calle: nueva.$2['calle']?.toString(),
          motivo: 'asignada_tarjeta_temporal',
          por: widget.usuarioData['nombre']?.toString(),
        );
        if (!ok) fallos++;
      }

      if (mounted) {
        final nuevas = nuevasEnBandeja.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  fallos > 0 ? Icons.warning_amber : Icons.check_circle,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nuevas == 0
                        ? 'Tarjeta "$nombreTarjeta" creada con ${seleccionadas.length} direcciones'
                        : 'Tarjeta "$nombreTarjeta" creada con ${seleccionadas.length} direcciones '
                            '($nuevas nuevas en temporales)'
                            '${fallos > 0 ? ' · $fallos sin registrar en estadísticas' : ''}',
                  ),
                ),
              ],
            ),
            backgroundColor:
                fallos > 0 ? Colors.orange : const Color(0xFF4A148C),
            duration: Duration(seconds: fallos > 0 ? 6 : 3),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear tarjeta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ENVIAR TARJETA TEMPORAL
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // ──────────────────────────────────────────────
  // LIBERAR / BLOQUEAR TODAS LAS TARJETAS TEMPORALES
  // ──────────────────────────────────────────────

  Future<void> _liberarObloquearTodas() async {
    final db = FirebaseFirestore.instance;
    final temporalesRef = db.collection('territorios').doc('temporales');

    // Estado global actual
    DocumentSnapshot<Map<String, dynamic>> estadoGlobal;
    try {
      estadoGlobal = await temporalesRef.get();
    } catch (_) {
      estadoGlobal =
          await temporalesRef.get(const GetOptions(source: Source.cache));
    }
    final gData = estadoGlobal.data() ?? {};
    final yaLiberado =
        (gData['disponible_para_publicadores'] as bool?) ?? false;
    final soloConductores = (gData['solo_conductores'] as bool?) ?? false;

    // Tarjetas temporales reales (excluye folders)
    final tarjetasSnap = await temporalesRef.collection('tarjetas').get();
    final tarjetas = tarjetasSnap.docs
        .where((d) =>
            (d.data())['tipo'] != 'folder_temporal')
        .toList();

    if (!mounted) return;

    final eleccion = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tarjetas temporales'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              yaLiberado
                  ? soloConductores
                      ? 'Actualmente: liberadas para conductores.'
                      : 'Actualmente: liberadas para todos.'
                  : 'Actualmente: bloqueadas.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.drive_eta, color: Color(0xFF1B5E20)),
            title: const Text('Liberar para conductores'),
            onTap: () => Navigator.pop(context, 'conductores'),
          ),
          ListTile(
            leading: const Icon(Icons.group, color: Colors.green),
            title: const Text('Liberar para todos'),
            onTap: () => Navigator.pop(context, 'todos'),
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.red),
            title: const Text('Cerrar / bloquear tarjetas'),
            onTap: () => Navigator.pop(context, 'bloquear'),
          ),
        ],
      ),
    );

    if (eleccion == null) return;

    try {
      final batch = db.batch();
      final bloqueando = eleccion == 'bloquear';
      final soloConductoresNuevo = !bloqueando && eleccion == 'conductores';

      for (final t in tarjetas) {
        if ((t.data())['tipo'] == 'folder_temporal')
          continue;
        batch.update(t.reference, {
          'bloqueado': bloqueando ? true : false,
          'disponible_para_publicadores': bloqueando ? false : true,
          'solo_conductores': soloConductoresNuevo,
        });
      }

      batch.set(
          temporalesRef,
          {
            'nombre': 'Tarjetas temporales',
            'disponible_para_publicadores': !bloqueando,
            'solo_conductores': soloConductoresNuevo,
          },
          SetOptions(merge: true));

      await batch.commit();

      if (mounted) {
        final msg = bloqueando
            ? 'Tarjetas temporales bloqueadas'
            : eleccion == 'conductores'
                ? 'Tarjetas temporales liberadas para conductores'
                : 'Tarjetas temporales liberadas para todos';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: bloqueando ? Colors.red : const Color(0xFF1B5E20),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _toggleBloqueoTarjetaTemporal(String tarjetaId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(tarjetaId);
      final snap = await ref.get();
      final data = snap.data() ?? {};
      final actual = (data['bloqueado'] as bool?) ?? false;
      await ref.update({
        'bloqueado': !actual,
        'disponible_para_publicadores': actual ? true : false,
        if (actual) 'solo_conductores': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(actual ? '$tarjetaId liberada' : '$tarjetaId bloqueada'),
          backgroundColor:
              actual ? const Color(0xFF1B5E20) : Colors.grey.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _enviarTarjetaTemporal(
    String tarjetaId,
    String tarjetaNombre,
  ) async {
    // Cargar conductores y publicadores
    final conductoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    final publicadoresSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_publicador', isEqualTo: true)
        .where('estado', isEqualTo: 'aprobado')
        .get();

    if (!mounted) return;

    final buscarCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) {
          final texto = buscarCtrl.text.trim().toLowerCase();
          final conductores = conductoresSnap.docs.where((doc) {
            final d = doc.data();
            final n = (d['nombre'] ?? '').toString().toLowerCase();
            final e = (d['email'] ?? '').toString().toLowerCase();
            return texto.isEmpty || n.contains(texto) || e.contains(texto);
          }).toList();
          final publicadores = publicadoresSnap.docs.where((doc) {
            final d = doc.data();
            final n = (d['nombre'] ?? '').toString().toLowerCase();
            final e = (d['email'] ?? '').toString().toLowerCase();
            return texto.isEmpty || n.contains(texto) || e.contains(texto);
          }).toList();
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Enviar: $tarjetaNombre'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: double.maxFinite,
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Búsqueda por nombre o email
                    TextField(
                      controller: buscarCtrl,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre o email...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    const SizedBox(height: 8),
                    if (conductores.isNotEmpty) ...[
                      const Text('Conductores:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      ...conductores.map((doc) {
                        final data = doc.data();
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.drive_eta,
                              color: Color(0xFF1B5E20)),
                          title: Text(data['nombre'] ?? ''),
                          subtitle: Text(data['email'] ?? ''),
                          onTap: () async {
                            Navigator.pop(context);
                            await _ejecutarEnvioTemporal(
                              tarjetaId: tarjetaId,
                              tarjetaNombre: tarjetaNombre,
                              destinatarioEmail: data['email'],
                              destinatarioNombre: data['nombre'],
                              tipo: 'conductor',
                            );
                          },
                        );
                      }),
                      const Divider(),
                    ],
                    const Text('Publicadores:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (publicadores.isEmpty)
                      const Text('No hay publicadores disponibles.',
                          style: TextStyle(color: Colors.grey))
                    else
                      ...publicadores.map((doc) {
                        final data = doc.data();
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person, color: Colors.blue),
                          title: Text(data['nombre'] ?? ''),
                          subtitle: Text(data['email'] ?? ''),
                          onTap: () async {
                            Navigator.pop(context);
                            await _ejecutarEnvioTemporal(
                              tarjetaId: tarjetaId,
                              tarjetaNombre: tarjetaNombre,
                              destinatarioEmail: data['email'],
                              destinatarioNombre: data['nombre'],
                              tipo: 'publicador',
                            );
                          },
                        );
                      }),
                  ],
                ),
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
      ),
    ).whenComplete(buscarCtrl.dispose);
  }

  Future<void> _ejecutarEnvioTemporal({
    required String tarjetaId,
    required String tarjetaNombre,
    required String destinatarioEmail,
    required String destinatarioNombre,
    required String tipo,
  }) async {
    try {
      // ── Leer el dueño ACTUAL antes de escribir ──────────────────────────
      // `asignado_a` es la única fuente de propiedad. Si lo sobreescribimos
      // sin avisar, la tarjeta desaparece de la lista del publicador anterior
      // sin que él reciba ningún aviso (el bug).
      String? duenoAnterior;
      try {
        final tarjetaDoc = await FirebaseFirestore.instance
            .collection('territorios')
            .doc('temporales')
            .collection('tarjetas')
            .doc(tarjetaId)
            .get();
        duenoAnterior = TransferenciaTarjeta.leerDuenoActual(tarjetaDoc.data());
      } catch (_) {}

      final esTransferencia = tipo == 'publicador' &&
          TransferenciaTarjeta.esTransferenciaReal(
              duenoAnterior, destinatarioNombre);

      if (esTransferencia) {
        final ok = await TransferenciaTarjeta.confirmarTransferencia(
          context: context,
          tarjetaNombre: tarjetaNombre,
          duenoActual: duenoAnterior,
          nuevoDueno: destinatarioNombre,
          nuevoEmail: destinatarioEmail,
        );
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Transferencia cancelada. La tarjeta sigue intacta.'),
                backgroundColor: Colors.grey,
              ),
            );
          }
          return;
        }
      }

      await FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'conductor_email': tipo == 'conductor' ? destinatarioEmail : null,
        'publicador_email': tipo == 'publicador' ? destinatarioEmail : null,
        'asignado_a': tipo == 'publicador' ? destinatarioNombre : null,
        'asignado_en':
            tipo == 'publicador' ? FieldValue.serverTimestamp() : null,
        'enviado_a': destinatarioEmail,
        'enviado_nombre': destinatarioNombre,
        'enviado_tipo': tipo,
        'enviado_en': FieldValue.serverTimestamp(),
        'estatus_envio': 'enviado',
        // Campos que quedaban STALE con el publicador anterior.
        'publicador_nombre': tipo == 'publicador' ? destinatarioNombre : null,
        'tomado_por': null,
        'tomado_en': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$tarjetaNombre" enviada a $destinatarioNombre'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (esTransferencia) {
        unawaited(TransferenciaTarjeta.notificarTransferencia(
          duenoAnterior: duenoAnterior,
          nuevoDueno: destinatarioNombre,
          tarjetaNombre: tarjetaNombre,
        ));
        unawaited(TransferenciaTarjeta.notificarnuevoDueno(
          nuevoDueno: destinatarioNombre,
          tarjetaNombre: tarjetaNombre,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _traerTarjetaATemporales(String tarjetaId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Traer de vuelta a temporales'),
        content: const Text(
            '¿Liberar esta tarjeta? Quedará disponible de nuevo para conductores y publicadores.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Liberar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'conductor_email': null,
        'publicador_email': null,
        'publicador_nombre': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'enviado_tipo': null,
        'completada': false,
        'bloqueado': false,
        'disponible_para_publicadores': true,
        'estatus_envio': 'devuelto',
        'devuelto_por': widget.usuarioData['nombre'] ?? '',
        'devuelto_en': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tarjeta liberada de nuevo en temporales'),
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al liberar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Sub-tabs
          Container(
            color: Colors.white,
            child: TabBar(
              indicatorColor: const Color(0xFF4A148C),
              labelColor: const Color(0xFF4A148C),
              unselectedLabelColor: Colors.grey,
              tabs: [
                const Tab(
                    text: 'Direcciones',
                    icon: Icon(Icons.location_on, size: 16)),
                Tab(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('territorios')
                        .doc('temporales')
                        .collection('tarjetas')
                        .where('completada', isNotEqualTo: true)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = (snap.data?.docs ?? [])
                          .where((d) =>
                              (d.data() as Map<String, dynamic>)['tipo'] !=
                              'folder_temporal')
                          .length;
                      final hasItems = count > 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.credit_card,
                                  size: 16,
                                  color:
                                      hasItems ? Colors.orange : Colors.grey),
                              if (hasItems)
                                Positioned(
                                  right: -6,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text('$count',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 6),
                          Text('Tarjetas T.',
                              style: TextStyle(
                                  color: hasItems ? Colors.orange : Colors.grey,
                                  fontWeight: hasItems
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.healing, size: 18, color: Color(0xFF4A148C)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Analiza las direcciones en temporales y devuelve '
                    'automáticamente las que tengan origen a su tarjeta.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _repararYDevolverTodas,
                  icon: const Icon(Icons.settings_backup_restore, size: 16),
                  label: const Text('Reparar y devolver',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A148C),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              physics:
                  const NeverScrollableScrollPhysics(), // Deshabilita el Swipe
              children: [
                _buildVistaAgruparDirecciones(),
                _buildVistaTarjetasTemporales(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // VISTA 1 — Direcciones agrupadas por territorio
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildVistaAgruparDirecciones() {
    return Column(
      children: [
        // Slider global
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                  const Icon(Icons.tune, color: Color(0xFF4A148C), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Direcciones por tarjeta',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A148C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_sliderValue dir.',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A148C),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _sliderValue.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: const Color(0xFF4A148C),
                onChanged: (value) =>
                    setState(() => _sliderValue = value.toInt()),
              ),
            ],
          ),
        ),

        // Lista de territorios con direcciones temporales
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('direcciones_globales')
                .where('estado', isEqualTo: 'temporal')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay direcciones temporales',
                        style: TextStyle(color: Colors.grey[500], fontSize: 15),
                      ),
                    ],
                  ),
                );
              }

              // Agrupar por territorio_nombre
              final Map<String, List<DocumentSnapshot>> porTerritorio = {};
              for (final doc in docs) {
                final data = (doc.data() as Map<String, dynamic>?) ?? {};
                final terNombre = (data['territorio_nombre'] as String?)
                            ?.isNotEmpty ==
                        true
                    ? data['territorio_nombre'] as String
                    : (data['barrio'] as String?)?.isNotEmpty == true
                        ? data['barrio'] as String
                        : (data['territorio_id'] as String?)?.isNotEmpty == true
                            ? data['territorio_id'] as String
                            : 'Sin territorio';
                final terId = (data['territorio_id'] as String?) ?? 'sin_id';
                final key = '$terId||$terNombre';
                porTerritorio.putIfAbsent(key, () => []).add(doc);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: porTerritorio.length,
                itemBuilder: (context, index) {
                  final key = porTerritorio.keys.elementAt(index);
                  final parts = key.split('||');
                  final terId = parts[0];
                  final terNombre = parts.length > 1 ? parts[1] : key;
                  final dirs = porTerritorio[key]!;
                  final disponibles = _sliderValue.clamp(1, dirs.length);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(
                        left: BorderSide(
                            color: const Color(0xFF4A148C), width: 4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4A148C).withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF4A148C).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.timer,
                                    color: Color(0xFF4A148C), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      terNombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF263238),
                                      ),
                                    ),
                                    Text(
                                      '${dirs.length} direcciones pendientes',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _crearTarjetaTemporal(
                                  terId,
                                  terNombre,
                                  dirs,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(
                                  'Crear T. ($disponibles)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A148C),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Direcciones con acciones por dirección
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: dirs.map((d) {
                              final data =
                                  (d.data() as Map<String, dynamic>?) ?? {};
                              final calle = (data['calle'] as String?) ?? '';
                              final motivo =
                                  (data['motivo_temporal'] as String?) ?? '';
                              final reportadoPor =
                                  (data['reportado_por'] as String?) ?? '';
                              final tieneMotivo = motivo.isNotEmpty &&
                                  motivo != 'no_predicado' &&
                                  motivo != 'no_hispano';
                              final puedeRestaurar =
                                  (data['tarjeta_id_origen'] as String?)
                                          ?.isNotEmpty ??
                                      false;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                                decoration: BoxDecoration(
                                  color: tieneMotivo
                                      ? Colors.orange.shade50
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: tieneMotivo
                                      ? Border.all(
                                          color: Colors.orange.shade300)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            calle,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black87),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (tieneMotivo)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.info_outline,
                                                      size: 11,
                                                      color: Colors.orange),
                                                  const SizedBox(width: 3),
                                                  Expanded(
                                                    child: Text(
                                                      motivo,
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.orange,
                                                          fontStyle:
                                                              FontStyle.italic),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (reportadoPor.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                      Icons.person_outline,
                                                      size: 11,
                                                      color: Color(0xFF4A148C)),
                                                  const SizedBox(width: 3),
                                                  Expanded(
                                                    child: Text(
                                                      'Reportada por: $reportadoPor',
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Color(0xFF6A1B9A),
                                                          fontStyle:
                                                              FontStyle.italic),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: puedeRestaurar
                                          ? () => _restaurarDireccion(d)
                                          : null,
                                      icon: const Icon(Icons.restore,
                                          size: 16, color: Colors.green),
                                      tooltip: 'Restaurar a tarjeta original',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _moverDireccionADevueltas(d),
                                      icon: const Icon(Icons.delete_forever,
                                          size: 16, color: Colors.red),
                                      tooltip: 'Mover a devueltas',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // VISTA 2 — Tarjetas temporales creadas
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildVistaTarjetasTemporales() {
    return Column(
      children: [
        _panelCandadoGlobal(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('territorios')
                .doc('temporales')
                .collection('tarjetas')
                .where('completada', isNotEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final tarjetas = snapshot.data!.docs
                  .where((d) =>
                      (d.data() as Map<String, dynamic>)['tipo'] !=
                      'folder_temporal')
                  .toList();

              if (tarjetas.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.credit_card_off_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay tarjetas temporales',
                        style: TextStyle(color: Colors.grey[500], fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Crea tarjetas desde la pestaña Direcciones',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tarjetas.length,
                itemBuilder: (context, index) {
                  final doc = tarjetas[index];
                  final data = (doc.data() as Map<String, dynamic>?) ?? {};
                  final nombre = (data['nombre'] as String?) ?? doc.id;
                  final territorioOrigen =
                      (data['territorio_origen_nombre'] as String?) ?? '';
                  final enviadoNombre =
                      (data['enviado_nombre'] as String?) ?? '';
                  final yaEnviada = enviadoNombre.isNotEmpty;
                  final enviadoEn = data['enviado_en'] as Timestamp?;
                  String fechaHora = '';
                  if (enviadoEn != null) {
                    final dt = enviadoEn.toDate();
                    fechaHora =
                        '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  }
                  final bloqueada = (data['bloqueado'] as bool?) ?? false;
                  final disponiblePub =
                      (data['disponible_para_publicadores'] as bool?) ?? false;
                  final soloCond = (data['solo_conductores'] as bool?) ?? false;
                  final devueltoPor = (data['devuelto_por'] as String?) ?? '';
                  final devueltoEn = data['devuelto_en'] as Timestamp?;
                  String fechaDevuelto = '';
                  if (devueltoEn != null) {
                    final dt = devueltoEn.toDate();
                    fechaDevuelto =
                        '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  }
                  final tomadoPor = (data['tomado_por'] as String?) ?? '';
                  final tomadoEn = data['tomado_en'] as Timestamp?;
                  String fechaTomado = '';
                  if (tomadoEn != null) {
                    final dt = tomadoEn.toDate();
                    fechaTomado =
                        '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(
                        left: BorderSide(
                          color: yaEnviada
                              ? Colors.green
                              : const Color(0xFF4A148C),
                          width: 4,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: (yaEnviada
                                          ? Colors.green
                                          : const Color(0xFF4A148C))
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  yaEnviada
                                      ? Icons.outgoing_mail
                                      : Icons.credit_card,
                                  color: yaEnviada
                                      ? Colors.green
                                      : const Color(0xFF4A148C),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    if (!_tarjetasExpandidas.remove(doc.id)) {
                                      _tarjetasExpandidas.add(doc.id);
                                    }
                                  }),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF263238),
                                        ),
                                      ),
                                      if (territorioOrigen.isNotEmpty)
                                        Text(
                                          'Origen: $territorioOrigen',
                                          style: const TextStyle(
                                              fontSize: 11, color: Colors.grey),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Contador de direcciones
                              FutureBuilder<QuerySnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('direcciones_globales')
                                    .where('tarjeta_id', isEqualTo: doc.id)
                                    .get(),
                                builder: (context, dirSnap) {
                                  final count = dirSnap.data?.docs.length ?? 0;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count dir.',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          // Badge estado liberación
                          if (!yaEnviada) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: bloqueada
                                    ? Colors.grey.shade100
                                    : disponiblePub
                                        ? Colors.orange.shade50
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: bloqueada
                                      ? Colors.grey.shade300
                                      : disponiblePub
                                          ? Colors.orange.shade200
                                          : Colors.grey.shade300,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    bloqueada ? Icons.lock : Icons.lock_open,
                                    size: 12,
                                    color: bloqueada
                                        ? Colors.grey
                                        : disponiblePub
                                            ? Colors.orange.shade800
                                            : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    bloqueada
                                        ? 'Bloqueada'
                                        : disponiblePub
                                            ? soloCond
                                                ? 'Liberada · Conductores'
                                                : 'Liberada · Todos'
                                            : 'Disponible',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: bloqueada
                                            ? Colors.grey
                                            : disponiblePub
                                                ? Colors.orange.shade800
                                                : Colors.grey,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Badge enviado
                          if (yaEnviada) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green.shade200, width: 1),
                              ),
                              child: Text(
                                'Enviada a: $enviadoNombre${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.green.shade800),
                              ),
                            ),
                          ],

                          // Badge devuelta
                          if (devueltoPor.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.orange.shade300, width: 1),
                              ),
                              child: Text(
                                'Devuelta por: $devueltoPor${fechaDevuelto.isNotEmpty ? ' · $fechaDevuelto' : ''}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade800),
                              ),
                            ),
                          ],

                          // Badge tomada
                          if (tomadoPor.isNotEmpty && !yaEnviada) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.pink.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.pink.shade200, width: 1),
                              ),
                              child: Text(
                                'Tomada por: $tomadoPor${fechaTomado.isNotEmpty ? ' · $fechaTomado' : ''}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.pink.shade700),
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),

                          // Direcciones contenidas (desplegable al tocar el título)
                          if (_tarjetasExpandidas.contains(doc.id)) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF4A148C).withOpacity(0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      const Color(0xFF4A148C).withOpacity(0.15),
                                ),
                              ),
                              child: StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('direcciones_globales')
                                    .where('tarjeta_id', isEqualTo: doc.id)
                                    .snapshots(),
                                builder: (context, dirSnap) {
                                  final dirs = dirSnap.data?.docs ?? [];
                                  if (!dirSnap.hasData) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    );
                                  }
                                  if (dirs.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text(
                                        'Sin direcciones.',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: dirs.map((d) {
                                      final dd =
                                          (d.data() as Map<String, dynamic>?) ??
                                              {};
                                      final calle =
                                          (dd['calle'] as String?) ?? '';
                                      final complemento =
                                          (dd['complemento'] as String?) ?? '';
                                      final reportadoPor =
                                          (dd['reportado_por'] as String?) ??
                                              '';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Padding(
                                                  padding:
                                                      EdgeInsets.only(top: 3),
                                                  child: Icon(
                                                    Icons.location_on_outlined,
                                                    size: 13,
                                                    color: Color(0xFF4A148C),
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Expanded(
                                                  child: Text(
                                                    '$calle${complemento.isNotEmpty ? ' · $complemento' : ''}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black87),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (reportadoPor.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 18, top: 1),
                                                child: Text(
                                                  'Reportada por: $reportadoPor',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Color(0xFF6A1B9A)),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),
                          ],

                          // Botones
                          Row(
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _toggleBloqueoTarjetaTemporal(doc.id),
                                icon: Icon(
                                  bloqueada ? Icons.lock : Icons.lock_open,
                                  size: 18,
                                  color:
                                      bloqueada ? Colors.grey : Colors.orange,
                                ),
                                tooltip: bloqueada
                                    ? 'Liberar tarjeta'
                                    : 'Bloquear tarjeta',
                                style: IconButton.styleFrom(
                                  backgroundColor: bloqueada
                                      ? Colors.grey.shade100
                                      : Colors.orange.shade50,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (yaEnviada ||
                                  tomadoPor.isNotEmpty ||
                                  devueltoPor.isNotEmpty) ...[
                                IconButton(
                                  onPressed: () =>
                                      _traerTarjetaATemporales(doc.id),
                                  icon: const Icon(Icons.arrow_upward,
                                      size: 18, color: Color(0xFF4A148C)),
                                  tooltip:
                                      'Traer de vuelta a temporales (liberar)',
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFF4A148C)
                                        .withOpacity(0.08),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _enviarTarjetaTemporal(doc.id, nombre),
                                  icon: Icon(
                                    yaEnviada ? Icons.refresh : Icons.send,
                                    size: 15,
                                  ),
                                  label: Text(
                                    yaEnviada ? 'Reenviar' : 'Enviar',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: yaEnviada
                                        ? Colors.orange
                                        : const Color(0xFF4A148C),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final confirmar = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Eliminar tarjeta'),
                                        content: Text(
                                            '¿Eliminar "$nombre"? Las direcciones volverán al estado temporal.'),
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
                                                backgroundColor: Colors.red),
                                            child: const Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmar == true) {
                                      await _eliminarTarjetaTemporal(
                                          doc.id, doc);
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline,
                                      size: 15),
                                  label: const Text('Eliminar',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
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
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // PANEL CANDADO GLOBAL
  // ──────────────────────────────────────────────

  Widget _panelCandadoGlobal() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .snapshots(),
      builder: (context, snapshot) {
        final gData = snapshot.data?.data() ?? {};
        final liberado =
            (gData['disponible_para_publicadores'] as bool?) ?? false;
        final soloConductores = (gData['solo_conductores'] as bool?) ?? false;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: liberado
                  ? (soloConductores ? Colors.orange : const Color(0xFF1B5E20))
                  : Colors.grey.shade300,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                liberado
                    ? (soloConductores ? Icons.lock_open : Icons.group)
                    : Icons.lock,
                color: liberado
                    ? (soloConductores
                        ? Colors.orange
                        : const Color(0xFF1B5E20))
                    : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liberación global',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF263238),
                      ),
                    ),
                    Text(
                      liberado
                          ? soloConductores
                              ? 'Liberadas para conductores'
                              : 'Liberadas para todos (conductores y publicadores)'
                          : 'Bloqueadas',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _liberarObloquearTodas,
                icon: const Icon(Icons.lock_open, color: Color(0xFF4A148C)),
                tooltip: 'Liberar o bloquear todas las tarjetas',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF4A148C).withOpacity(0.08),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // RESTAURAR DIRECCIÓN A SU TARJETA ORIGINAL
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _restaurarDireccion(DocumentSnapshot dir) async {
    try {
      final data = (dir.data() as Map<String, dynamic>?) ?? {};
      final origenTarjeta = (data['tarjeta_id_origen'] as String?) ?? '';
      if (origenTarjeta.isEmpty) return;

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restaurar dirección'),
          content: Text(
              '¿Devolver esta dirección a su tarjeta original ("$origenTarjeta")?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;

      final territorioOrigenId =
          (data['territorio_origen_id'] as String?) ?? '';
      final territorioOrigenNombre =
          (data['territorio_origen_nombre'] as String?) ?? '';

      await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .doc(dir.id)
          .update({
        'tarjeta_id': origenTarjeta,
        'estado': 'activa',
        'estado_predicacion': '',
        if (territorioOrigenId.isNotEmpty) 'territorio_id': territorioOrigenId,
        if (territorioOrigenNombre.isNotEmpty)
          'territorio_nombre': territorioOrigenNombre,
        'tarjeta_id_origen': FieldValue.delete(),
        'territorio_origen_id': FieldValue.delete(),
        'territorio_origen_nombre': FieldValue.delete(),
        'motivo_temporal': FieldValue.delete(),
        'fecha_temporal': FieldValue.delete(),
      });

      await registrarMovimientoTemporal(
        tipo: 'salida',
        direccionId: dir.id,
        territorioOrigenId: territorioOrigenId,
        territorioOrigenNombre: territorioOrigenNombre,
        calle: data['calle']?.toString(),
        motivo: 'restaurada',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección restaurada a su tarjeta original'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al restaurar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // REPARACIÓN POR LOTES: devolver direcciones a su tarjeta origen
  // ─────────────────────────────────────────────────────────────

  Future<void> _repararYDevolverTodas() async {
    final db = FirebaseFirestore.instance;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reparar y devolver direcciones'),
        content: const Text(
          'Se buscarán todas las direcciones en carpetas temporales, se '
          'detectará su tarjeta de origen y se devolverán marcadas como '
          'predicadas.\n\n'
          'Las que no tengan origen válido quedarán en temporales y se te '
          'informará cuántas son.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Analizar y devolver'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    int devueltas = 0;
    int sinOrigen = 0;

    try {
      // 1) Recorrer todas las carpetas temporales del territorio 'temporales'
      final carpetasSnap = await db
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .get();

      final ahora = DateTime.now();
      final mesActual =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';

      WriteBatch batch = db.batch();
      int pendientes = 0;

      // Direcciones que efectivamente salen de la bandeja en esta reparación.
      // Se registran DESPUÉS de confirmar los batches, igual que en el resto de
      // rutas: antes se perdían por completo y las estadísticas nunca se enteraban
      // de estas salidas.
      final salidas = <(String, String, String, String)>[];
      var fallosRegistro = 0;

      for (final carpeta in carpetasSnap.docs) {
        // Ignorar carpetas que no son de direcciones (comercios_cerrados, etc.)
        if (carpeta.id == 'comercios_cerrados') continue;

        final dirsSnap =
            await carpeta.reference.collection('direcciones').get();

        for (final dir in dirsSnap.docs) {
          final data = (dir.data() as Map<String, dynamic>?) ?? {};

          final origenTarjeta = (data['tarjeta_id_origen'] as String?) ?? '';
          final territorioOrigenId =
              (data['territorio_origen_id'] as String?) ?? '';
          final territorioOrigenNombre =
              (data['territorio_origen_nombre'] as String?) ?? '';

          // ── Validar que tenemos origen y que la tarjeta existe ──
          if (origenTarjeta.isEmpty) {
            sinOrigen++;
            continue;
          }

          final tarjetaExiste = await db
              .collection('territorios')
              .doc(territorioOrigenId.isEmpty
                  ? 'temporales'
                  : territorioOrigenId)
              .collection('tarjetas')
              .doc(origenTarjeta)
              .get();

          if (!tarjetaExiste.exists) {
            sinOrigen++;
            continue;
          }

          // ── Devolver a la tarjeta origen, marcada como predicada ──
          batch.update(db.collection('direcciones_globales').doc(dir.id), {
            'tarjeta_id': origenTarjeta,
            'estado': 'activa',
            'estado_predicacion': 'completada',
            'predicado': true,
            'fecha_predicacion': FieldValue.serverTimestamp(),
            'mes_predicacion': mesActual,
            if (territorioOrigenId.isNotEmpty)
              'territorio_id': territorioOrigenId,
            if (territorioOrigenNombre.isNotEmpty)
              'territorio_nombre': territorioOrigenNombre,
            'tarjeta_id_origen': FieldValue.delete(),
            'territorio_origen_id': FieldValue.delete(),
            'territorio_origen_nombre': FieldValue.delete(),
            'motivo_temporal': FieldValue.delete(),
            'fecha_temporal': FieldValue.delete(),
          });

          // Limpiar la copia en la carpeta temporal
          batch.delete(dir.reference);
          devueltas++;
          salidas.add((
            dir.id,
            territorioOrigenId,
            territorioOrigenNombre,
            (data['calle'] ?? '').toString(),
          ));

          if (++pendientes >= 400) {
            await batch.commit();
            batch = db.batch();
            pendientes = 0;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
      if (pendientes > 0) await batch.commit();

      // Registrar la salida de cada dirección devuelta a su tarjeta origen.
      for (final s in salidas) {
        final ok = await registrarMovimientoTemporal(
          tipo: 'salida',
          direccionId: s.$1,
          territorioOrigenId: s.$2,
          territorioOrigenNombre: s.$3,
          calle: s.$4,
          motivo: 'reparacion_por_lotes',
          por: widget.usuarioData['nombre']?.toString(),
        );
        if (!ok) fallosRegistro++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✔ $devueltas devueltas a su tarjeta origen · '
              '⚠️ $sinOrigen sin origen válido (quedan en temporales)'
              '${fallosRegistro > 0 ? ' · $fallosRegistro sin registrar en estadísticas' : ''}',
            ),
            backgroundColor:
                sinOrigen == 0 ? const Color(0xFF1B5E20) : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reparar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MOVER DIRECCIÓN A DEVUELTAS
  // ─────────────────────────────────────────────────────────────

  Future<void> _moverDireccionADevueltas(DocumentSnapshot dir) async {
    try {
      final db = FirebaseFirestore.instance;
      final data = (dir.data() as Map<String, dynamic>?) ?? {};

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Mover a devueltas'),
          content: const Text(
              '¿Mover esta dirección a devueltas? Será eliminada de la lista temporal.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Mover a devueltas'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;

      final territorioOrigenId =
          (data['territorio_origen_id'] as String?) ?? '';
      final territorioOrigenNombre =
          (data['territorio_origen_nombre'] as String?) ?? '';

      final batch = db.batch();
      batch.set(db.collection('direcciones_removidas').doc(dir.id), {
        'calle': data['calle'],
        'complemento': data['complemento'],
        'direccion_normalizada': _normalizarDireccionTemporal(
            '${data['calle'] ?? ''} ${data['complemento'] ?? ''}'),
        'territorio_id': territorioOrigenId,
        'territorio_nombre': territorioOrigenNombre,
        'tarjeta_id_origen': data['tarjeta_id_origen'] ?? '',
        'motivo': 'otro',
        'motivo_texto': data['motivo_temporal'] ?? '',
        'removida_por': widget.usuarioData['nombre'] ?? '',
        'removida_en': FieldValue.serverTimestamp(),
        'doc_id_original': dir.id,
        'alerta_30_enviada': false,
        'alerta_60_enviada': false,
      });
      batch.delete(dir.reference);
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección movida a devueltas'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al mover: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _normalizarDireccionTemporal(String direccion) {
    return normalizarDireccion(direccion);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ELIMINAR TARJETA TEMPORAL
  // devuelve las direcciones a estado: temporal
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _eliminarTarjetaTemporal(
      String tarjetaId, DocumentSnapshot tarjetaDoc) async {
    try {
      final db = FirebaseFirestore.instance;
      final data = (tarjetaDoc.data() as Map<String, dynamic>?) ?? {};
      final territorioOrigenId =
          (data['territorio_origen_id'] as String?) ?? '';

      // Recuperar direcciones de esta tarjeta temporal
      final dirsSnap = await db
          .collection('direcciones_globales')
          .where('tarjeta_id', isEqualTo: tarjetaId)
          .get();

      final batch = db.batch();

      // Restaurar direcciones a estado temporal con tarjeta_id_origen
      for (final dir in dirsSnap.docs) {
        final d = (dir.data() as Map<String, dynamic>?) ?? {};
        final tarjetaIdOrigen = (d['tarjeta_id_origen'] as String?) ?? '';

        batch.update(dir.reference, {
          'tarjeta_id': tarjetaIdOrigen,
          'tarjeta_id_origen': null,
          'territorio_id': territorioOrigenId,
          'estado': 'temporal',
          'estado_predicacion': 'temporal',
        });
      }

      // Eliminar tarjeta temporal
      batch.delete(tarjetaDoc.reference);

      await batch.commit();

      // NO se registra ninguna 'salida' aquí: las direcciones vuelven a
      // 'temporal' (arriba), es decir que siguen en la bandeja de temporales,
      // solo que sin tarjeta asignada. Antes se registraba una 'salida' por
      // dirección y eso inflaba las salidas de las estadísticas con
      // direcciones que nunca se fueron.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tarjeta eliminada — direcciones devueltas a la bandeja de '
              'temporales (siguen contando como temporales)',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
