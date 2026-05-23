import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio de reinicio automático del primer día de cada mes.
class RestauracionMensual {

  static Future<bool> debeEjecutarse() async {
    final hoy = DateTime.now();
    if (hoy.day != 1) return false;
    final mesActual = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sistema').doc('restauracion_mensual').get();
      if (doc.exists) {
        final ultimoMes = doc.data()?['ultimo_mes'] as String?;
        if (ultimoMes == mesActual) return false;
      }
      return true;
    } catch (_) { return false; }
  }

  static Future<void> ejecutar(BuildContext context) async {
    try {
      debugPrint('🗓️ Reinicio automático de mes...');
      final ahora = DateTime.now();
      final mesAnterior = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
      final nuevoMes = ahora.month == 12
          ? DateTime(ahora.year + 1, 1, 1)
          : DateTime(ahora.year, ahora.month + 1, 1);
      final nuevoMesStr = '${nuevoMes.year}-${nuevoMes.month.toString().padLeft(2, '0')}';

      // PASO 1: Estadísticas
      final dirs = await FirebaseFirestore.instance.collection('direcciones_globales').get();
      final predicadas = dirs.docs.where((d) => d.data()['predicado'] == true).length;
      final noPredicadas = dirs.docs.where((d) =>
          d.data()['predicado'] != true && d.data()['estado'] == 'activa').length;

      await FirebaseFirestore.instance.collection('estadisticas').doc(mesAnterior).set({
        'mes': mesAnterior, 'total_direcciones': dirs.docs.length,
        'predicadas': predicadas, 'no_predicadas': noPredicadas,
        'creado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('configuraciones').doc('mes_actual').set({
        'inicio_mes': Timestamp.fromDate(nuevoMes),
        'mes_str': nuevoMesStr,
        'actualizado_en': FieldValue.serverTimestamp(),
      });

      // PASO 2: Direcciones — marcar prioridades
      int n = 0;
      WriteBatch b = FirebaseFirestore.instance.batch();
      for (final doc in dirs.docs) {
        final d = doc.data();
        if ((d['estado'] as String?) != 'activa') continue;
        final predicada = d['predicado'] == true;
        b.update(doc.reference, {
          'predicado': false,
          'estado_predicacion': 'pendiente',
          'fecha_predicacion': null,
          'mes_predicacion': null,
          'motivo_temporal': null,
          'prioridad_mes_anterior': !predicada,
          if (!predicada) 'mes_pendiente': mesAnterior,
        });
        if (++n >= 400) { await b.commit(); b = FirebaseFirestore.instance.batch(); n = 0; await Future.delayed(const Duration(milliseconds: 100)); }
      }
      if (n > 0) await b.commit();

      // PASO 3: Tarjetas
      final territoriosSnap = await FirebaseFirestore.instance.collection('territorios').get();
      for (final territorio in territoriosSnap.docs) {
        if (['temporales','removidas','estadisticas','campanas'].contains(territorio.id)) continue;
        final tarjetasSnap = await FirebaseFirestore.instance
            .collection('territorios').doc(territorio.id).collection('tarjetas').get();
        n = 0;
        b = FirebaseFirestore.instance.batch();
        for (final tarjeta in tarjetasSnap.docs) {
          final td = tarjeta.data();
          if (td['es_temporal'] == true) continue;
          final incompleta = td['completada'] != true && 
              ((td['asignado_a'] as String? ?? '').isNotEmpty ||
               // También tarjetas nunca enviadas que tenían dirs sin predicar
               td['prioridad_admin'] == true);
          b.update(tarjeta.reference, {
            'mes_anterior': mesAnterior, 'asignado_a': null, 'asignado_en': null,
            'mes_asignacion': null, 'completada': false, 'fecha_completada': null,
            'enviado_a': null, 'enviado_nombre': null, 'enviado_en': null,
            'enviado_tipo': null, 'publicador_email': null, 'publicador_nombre': null,
            'conductor_email': null, 'estatus_envio': 'disponible',
            'bloqueado': true, 'disponible_para_publicadores': false,
            'prioridad_admin': incompleta,
            'mes_prioridad': incompleta ? mesAnterior : null,
          });
          if (++n >= 400) { await b.commit(); b = FirebaseFirestore.instance.batch(); n = 0; await Future.delayed(const Duration(milliseconds: 100)); }
        }
        if (n > 0) await b.commit();
        await FirebaseFirestore.instance.collection('territorios').doc(territorio.id).update({
          'enviado_a': null, 'enviado_nombre': null, 'enviado_en': null,
          'conductor_email': null, 'estatus_envio': 'disponible', 'disponible_para_publicadores': false,
        });
      }

      // PASO 4: Tarjetas temporales → devolver dirs a origen
      final tempTarjetasSnap = await FirebaseFirestore.instance
          .collection('territorios')
          .doc('temporales')
          .collection('tarjetas')
          .get();

      for (final tarjetaTemp in tempTarjetasSnap.docs) {
        final dirsTemp = await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .where('tarjeta_id', isEqualTo: tarjetaTemp.id)
            .get();

        if (dirsTemp.docs.isNotEmpty) {
          int n2 = 0;
          WriteBatch bDir = FirebaseFirestore.instance.batch();
          for (final dir in dirsTemp.docs) {
            final dd = dir.data();
            final tarjetaOrigen = (dd['tarjeta_id_origen'] as String?) ?? '';
            final territorioOrigen = (dd['territorio_id_origen'] as String?) ?? '';
            if (tarjetaOrigen.isNotEmpty && territorioOrigen.isNotEmpty) {
              bDir.update(dir.reference, {
                'tarjeta_id': tarjetaOrigen,
                'territorio_id': territorioOrigen,
                'barrio': territorioOrigen,
                'es_temporal': false,
                'tarjeta_id_origen': FieldValue.delete(),
                'territorio_id_origen': FieldValue.delete(),
                'predicado': false,
                'estado_predicacion': 'pendiente',
                'asignado_a': null,
                'motivo_temporal': null,
                'prioridad_mes_anterior': !((dd['predicado'] as bool?) ?? false),
              });
              if (++n2 >= 400) { await bDir.commit(); bDir = FirebaseFirestore.instance.batch(); n2 = 0; }
            }
          }
          if (n2 > 0) await bDir.commit();
        }
        await tarjetaTemp.reference.delete();
      }
      debugPrint('🧹 ${tempTarjetasSnap.docs.length} tarjetas temporales procesadas al nuevo mes');

      // PASO 5: Limpiar datos basura
      final hace30dias = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));

      // Notificaciones con más de 30 días
      final notifSnap = await FirebaseFirestore.instance
          .collection('notificaciones')
          .where('created_at', isLessThan: hace30dias)
          .limit(500).get();
      if (notifSnap.docs.isNotEmpty) {
        int n = 0; WriteBatch b = FirebaseFirestore.instance.batch();
        for (final d in notifSnap.docs) {
          b.delete(d.reference);
          if (++n >= 400) { await b.commit(); b = FirebaseFirestore.instance.batch(); n = 0; }
        }
        if (n > 0) await b.commit();
        debugPrint('🗑️ ${notifSnap.docs.length} notificaciones antiguas eliminadas');
      }

      // Solicitudes localizador ya procesadas o con más de 30 días
      final solViejasSnap = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('created_at', isLessThan: hace30dias)
          .limit(500).get();
      final solProcSnap = await FirebaseFirestore.instance
          .collection('solicitudes_localizador')
          .where('estado', whereIn: ['aprobada', 'rechazada', 'agregada'])
          .limit(500).get();
      final solRefs = {
        ...solViejasSnap.docs.map((d) => d.reference),
        ...solProcSnap.docs.map((d) => d.reference),
      };
      if (solRefs.isNotEmpty) {
        int n = 0; WriteBatch b = FirebaseFirestore.instance.batch();
        for (final ref in solRefs) {
          b.delete(ref);
          if (++n >= 400) { await b.commit(); b = FirebaseFirestore.instance.batch(); n = 0; }
        }
        if (n > 0) await b.commit();
        debugPrint('🗑️ ${solRefs.length} solicitudes localizador eliminadas');
      }

      // PASO 6: Registrar ejecución — usa nuevoMesStr para no volver a correr este mes
      await FirebaseFirestore.instance.collection('sistema').doc('restauracion_mensual').set({
        'ultimo_mes': nuevoMesStr,
        'ejecutado_en': FieldValue.serverTimestamp(),
        'predicadas_mes_anterior': predicadas,
        'no_predicadas_mes_anterior': noPredicadas,
      });

      debugPrint('✅ Reinicio completado: $mesAnterior → $nuevoMesStr');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🗓️ Nuevo mes $nuevoMesStr iniciado. $noPredicadas dir. como prioridad.'),
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) { debugPrint('❌ Error reinicio mensual: $e'); }
  }
}
