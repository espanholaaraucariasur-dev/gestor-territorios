import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio de reinicio automático del primer día de cada mes.
class RestauracionMensual {
  /// Días de gracia para ejecutar el reinicio si nadie abrió la app el día 1.
  /// Pasada la ventana no se ejecuta, para no borrar avance del mes en curso.
  static const int _diasDeGracia = 3;

  static Future<bool> debeEjecutarse() async {
    final hoy = DateTime.now();
    if (hoy.day > _diasDeGracia) return false;
    final mesActual = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sistema')
          .doc('restauracion_mensual')
          .get();
      if (doc.exists) {
        final ultimoMes = doc.data()?['ultimo_mes'] as String?;
        if (ultimoMes == mesActual) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Normaliza un nombre de territorio para comparar sin tildes, guiones bajos
  /// ni espacios de más. Tiene que coincidir con la normalización de
  /// `SesionesTerritorioService`: si difiere, el "100%" que se calcula acá y el
  /// que muestra la pantalla serían dos números distintos.
  static String _norm(String? v) => (v ?? '')
      .trim()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toUpperCase();

  /// Índice `nombre normalizado -> id de territorio`, para resolver a qué
  /// territorio pertenece cada dirección.
  static Map<String, String> _indexTerritorios(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final porNorm = <String, String>{};
    for (final d in docs) {
      if (const ['removidas', 'estadisticas', 'campanas']
          .contains(d.id)) {
        continue;
      }
      porNorm[_norm(d.id)] = d.id;
      porNorm[_norm(d.data()['nombre'] as String?)] = d.id;
    }
    return porNorm;
  }

  /// Territorio al que pertenece una dirección, o `null` si no se puede
  /// resolver. `null` significa "no se toca": adivinar sería el error que este
  /// paso ya cometió una vez.
  static String? _territorioDe(
    Map<String, dynamic> d,
    Map<String, String> porNorm,
  ) {
    for (final campo in const [
      'territorio_id',
      'barrio',
      'territorio_nombre',
    ]) {
      final hit = porNorm[_norm(d[campo] as String?)];
      if (hit != null) return hit;
    }
    return null;
  }

  static Future<void> ejecutar(BuildContext context) async {
    try {
      debugPrint('🗓️ Reinicio automático de mes...');
      final ahora = DateTime.now();
      final mesAnterior =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';

      // ── MARCAR COMO EJECUTADO AL INICIO (evita race condition) ──────────
      // Si dos usuarios abren la app al mismo tiempo el día 1,
      // el segundo verá que ya está marcado y no ejecutará de nuevo.
      try {
        await FirebaseFirestore.instance
            .collection('sistema')
            .doc('restauracion_mensual')
            .set({
          'ultimo_mes': mesAnterior,
          'ejecutado_en': FieldValue.serverTimestamp(),
          'estado': 'en_progreso',
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error marcando inicio: $e');
        return; // Si no puede marcar, mejor no ejecutar
      }
      // ────────────────────────────────────────────────────────────────────
      final nuevoMes = ahora.month == 12
          ? DateTime(ahora.year + 1, 1, 1)
          : DateTime(ahora.year, ahora.month + 1, 1);
      final nuevoMesStr =
          '${nuevoMes.year}-${nuevoMes.month.toString().padLeft(2, '0')}';

      // PASO 1: Estadísticas
      final dirs = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();
      final predicadas =
          dirs.docs.where((d) => d.data()['predicado'] == true).length;
      final noPredicadas = dirs.docs
          .where((d) =>
              d.data()['predicado'] != true && d.data()['estado'] == 'activa')
          .length;

      await FirebaseFirestore.instance
          .collection('estadisticas')
          .doc(mesAnterior)
          .set({
        'mes': mesAnterior,
        'total_direcciones': dirs.docs.length,
        'predicadas': predicadas,
        'no_predicadas': noPredicadas,
        'creado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Se escribe en `configuracion`, no en `configuraciones`. Todo el resto
      // del proyecto usa `configuracion` (campañas, estadísticas, código de
      // acceso); `configuraciones` quedó como una colección fantasma de una
      // versión anterior y este documento era el único que la alimentaba.
      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('mes_actual')
          .set({
        'inicio_mes': Timestamp.fromDate(nuevoMes),
        'mes_str': nuevoMesStr,
        'actualizado_en': FieldValue.serverTimestamp(),
      });

      // Reinicia el período que mide "Completadas este mes": el contador que
      // muestra `publicador_tab` cuenta las direcciones predicadas después de
      // este `inicio`. Si no se actualizara acá, el baseline que se creó una
      // sola vez quedaría fijo y el contador nunca volvería a cero. El nuevo
      // período arranca con el mes en curso.
      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('progreso_mensual')
          .set({
        'inicio': Timestamp.fromDate(DateTime(ahora.year, ahora.month, 1)),
        'actualizado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── PASO 2: Direcciones ────────────────────────────────────────────────
      //
      // ANTES, este paso devolvía TODAS las direcciones activas a `pendiente`,
      // sin importar el territorio. Ese fue el error del 2026-10-04: 119
      // direcciones que estaban `completada` volvieron a cero y la sección
      // "Progreso de territorio completo" de Estadísticas bajó a 0.0% en los 7
      // territorios, con el denominador lleno y cero direcciones predicadas.
      //
      // AHORA, el avance de un territorio se reinicia cuando ese territorio
      // termina, no porque cambió el calendario. Solo entran las direcciones de
      // los territorios que están al 100%. Un territorio a medio camino sigue
      // con su avance y su ciclo continúa: el mes nuevo no borra trabajo que
      // todavía está en la calle.
      //
      // Regla de avance: cuenta como predicha la que tiene
      // `estado_predicacion == 'completada'` o `predicado == true`. Las
      // retiradas (`comercio_cerrado`) no cuentan ni entran en el denominador:
      // si no, un territorio descartado nunca llegaría al 100%.
      final territoryDocs =
          (await FirebaseFirestore.instance.collection('territorios').get()).docs;
      final porNorm = _indexTerritorios(territoryDocs);
      final totalPorTerritorio = <String, int>{};
      final predichasPorTerritorio = <String, int>{};
      for (final doc in dirs.docs) {
        final d = doc.data();
        if (d['estado'] == 'comercio_cerrado' ||
            d['estado_predicacion'] == 'comercio_cerrado') {
          continue;
        }
        final t = _territorioDe(d, porNorm);
        if (t == null) continue;
        totalPorTerritorio[t] = (totalPorTerritorio[t] ?? 0) + 1;
        if (d['estado_predicacion'] == 'completada' || d['predicado'] == true) {
          predichasPorTerritorio[t] = (predichasPorTerritorio[t] ?? 0) + 1;
        }
      }
      final territoriosCompletos = <String>{
        for (final e in totalPorTerritorio.entries)
          if (e.value > 0 && (predichasPorTerritorio[e.key] ?? 0) >= e.value)
            e.key,
      };
      debugPrint(
        '🗺️ Territorios al 100%: ${territoriosCompletos.length} de ${totalPorTerritorio.length}',
      );

      int reseteadas = 0;
      int preservadas = 0;
      int n = 0;
      WriteBatch b = FirebaseFirestore.instance.batch();
      for (final doc in dirs.docs) {
        final d = doc.data();
        if ((d['estado'] as String?) != 'activa') continue;

        // Sin territorio no hay forma de saber si terminó, y un territorio que
        // no terminó tampoco. En los dos casos el avance queda como está.
        final t = _territorioDe(d, porNorm);
        if (t == null || !territoriosCompletos.contains(t)) {
          preservadas++;
          continue;
        }

        final predicada = d['predicado'] == true;
        b.update(doc.reference, {
          'predicado': false,
          'estado_predicacion': 'pendiente',
          'fecha_predicacion': null,
          'mes_predicacion': null,
          'prioridad_mes_anterior': !predicada,
          if (!predicada) 'mes_pendiente': mesAnterior,

          // Campos del modelo nuevo (Fase 1). Si no se limpian acá, el mes
          // nuevo arranca con resultados y campañas del mes anterior pegados,
          // y la tarjeta muestra direcciones que en realidad nunca se
          // trabajaron este mes.
          //
          // El avance NO se copia de ningún lado: se deriva de estas
          // direcciones, así que volverlas a `pendiente` es lo que deja la
          // tarjeta abierta. No hay contador que resetear.
          'resultado_predicacion': 'sin_marcar',
          'avance_direccion': 'pendiente',
          'campana_estado': 'no_entregada',
          'fecha_confirmacion': null,
          'resultado_por': null,
          'fecha_campana': null,
          'campana_por': null,
          'fecha_actualizacion': null,

          // La que quedó sin trabajar el mes anterior queda marcada como
          // perdonada. No cuenta como fallo y se trabaja con normalidad: es
          // una etiqueta de trazabilidad, no un estado que la bloquee.
          //
          // Si venía predicada, se limpia: un `perdona_mes` de hace tres meses
          // es información vieja y contradice lo que pasó.
          'perdona_mes': predicada ? null : mesAnterior,
        });
        reseteadas++;
        if (++n >= 400) {
          await b.commit();
          b = FirebaseFirestore.instance.batch();
          n = 0;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (n > 0) await b.commit();
      debugPrint(
        '📍 Direcciones: $reseteadas reiniciadas (territorios completos), '
        '$preservadas con su avance intacto',
      );

      // ── PASO 3: Tarjetas ───────────────────────────────────────────────────
      //
      // Misma regla que el paso 2, y por la misma razón. Antes se desasignaba y
      // se bloqueaba (`bloqueado: true`) todas las tarjetas sin excepción, así
      // que un territorio a mitad de camino se quedaba con las direcciones ya
      // cargadas en su ciclo y con la tarjeta cerrada: el trabajo no se perdía,
      // pero nadie podía seguir haciéndolo. Ahora solo se reabren las tarjetas
      // de los territorios que están al 100%, que son los únicos a los que el
      // paso 2 les reinició el avance.
      int territoriesPreserved = 0;
      for (final territorio in territoryDocs) {
        if (const ['removidas', 'estadisticas', 'campanas']
            .contains(territorio.id)) {
          continue;
        }
        if (!territoriosCompletos.contains(territorio.id)) {
          // Ciclo en curso: la tarjeta sigue asignada y abierta, con lo que ya
          // se trabajó. No se toca ningún campo ni se lee la subcolección.
          territoriesPreserved++;
          continue;
        }
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .collection('tarjetas')
            .get();
        n = 0;
        b = FirebaseFirestore.instance.batch();
        for (final tarjeta in tarjetasSnap.docs) {
          final td = tarjeta.data();
          final incompleta = td['completada'] != true &&
              ((td['asignado_a'] as String? ?? '').isNotEmpty ||
                  // También tarjetas nunca enviadas que tenían dirs sin predicar
                  td['prioridad_admin'] == true);
          b.update(tarjeta.reference, {
            'mes_anterior': mesAnterior,
            'asignado_a': null,
            'asignado_en': null,
            'mes_asignacion': null,
            'completada': false,
            'fecha_completada': null,
            'enviado_a': null,
            'enviado_nombre': null,
            'enviado_en': null,
            'enviado_tipo': null,
            'publicador_email': null,
            'publicador_nombre': null,
            'conductor_email': null,
            'devuelta_por': null,
            'devuelta_en': null,
            'estatus_envio': 'disponible',
            'bloqueado': true,
            'disponible_para_publicadores': false,
            'prioridad_admin': incompleta,
            'mes_prioridad': incompleta ? mesAnterior : null,
          });
          if (++n >= 400) {
            await b.commit();
            b = FirebaseFirestore.instance.batch();
            n = 0;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
        if (n > 0) await b.commit();
        await FirebaseFirestore.instance
            .collection('territorios')
            .doc(territorio.id)
            .update({
          'enviado_a': null,
          'enviado_nombre': null,
          'enviado_en': null,
          'conductor_email': null,
          'estatus_envio': 'disponible',
          'disponible_para_publicadores': false,
        });
      }
      debugPrint(
        '🗃️ Territorios con ciclo en curso, tarjetas intactas: '
        '$territoriesPreserved',
      );

      // PASO 4: Limpiar datos basura
      final hace30dias =
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));

      // Notificaciones con más de 30 días
      final notifSnap = await FirebaseFirestore.instance
          .collection('notificaciones')
          .where('created_at', isLessThan: hace30dias)
          .limit(500)
          .get();
      if (notifSnap.docs.isNotEmpty) {
        int n = 0;
        WriteBatch b = FirebaseFirestore.instance.batch();
        for (final d in notifSnap.docs) {
          b.delete(d.reference);
          if (++n >= 400) {
            await b.commit();
            b = FirebaseFirestore.instance.batch();
            n = 0;
          }
        }
        if (n > 0) await b.commit();
        debugPrint(
            '🗑️ ${notifSnap.docs.length} notificaciones antiguas eliminadas');
      }

      // Solicitudes localizador ya procesadas o con más de 30 días
      final solViejasSnap = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('created_at', isLessThan: hace30dias)
          .limit(500)
          .get();
      final solProcSnap = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('estado', whereIn: ['aprobada', 'rechazada', 'agregada'])
          .limit(500)
          .get();
      final solRefs = {
        ...solViejasSnap.docs.map((d) => d.reference),
        ...solProcSnap.docs.map((d) => d.reference),
      };
      if (solRefs.isNotEmpty) {
        int n = 0;
        WriteBatch b = FirebaseFirestore.instance.batch();
        for (final ref in solRefs) {
          b.delete(ref);
          if (++n >= 400) {
            await b.commit();
            b = FirebaseFirestore.instance.batch();
            n = 0;
          }
        }
        if (n > 0) await b.commit();
        debugPrint('🗑️ ${solRefs.length} solicitudes localizador eliminadas');
      }

      // PASO 6: Registrar ejecución — graba el mes EN CURSO (`mesAnterior`) para
      // no volver a correr este mes. Antes grababa el mes siguiente
      // (`nuevoMesStr`), lo que hacía que `debeEjecutarse` diera false el mes
      // próximo y el reinicio se saltara uno sí y otro no.
      await FirebaseFirestore.instance
          .collection('sistema')
          .doc('restauracion_mensual')
          .set({
        'ultimo_mes': mesAnterior,
        'ejecutado_en': FieldValue.serverTimestamp(),
        'predicadas_mes_anterior': predicadas,
        'no_predicadas_mes_anterior': noPredicadas,
      });

      // Marcar como completado
      await FirebaseFirestore.instance
          .collection('sistema')
          .doc('restauracion_mensual')
          .update({
        'estado': 'completado',
        'completado_en': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Reinicio completado: $mesAnterior » $nuevoMesStr');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '🗓️ Nuevo mes $nuevoMesStr iniciado. $noPredicadas dir. como prioridad.'),
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      debugPrint('❌ Error reinicio mensual: $e');
    }
  }
}
