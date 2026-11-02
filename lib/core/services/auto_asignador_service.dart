import 'package:cloud_firestore/cloud_firestore.dart';
import 'groq_territory_service.dart';
import 'mapbox_service.dart';
import 'notificacion_service.dart' as notif;

/// Motor de auto-asignación territorial. Procesa direcciones nuevas
/// (individuales o en lote) y las ubica inteligentemente en tarjetas
/// existentes o crea nuevas tarjetas/territorios si es necesario.
///
/// Flujo completo:
/// 1. IA decide la mejor tarjeta destino para cada dirección.
/// 2. Si no hay tarjeta con cupo » crea una nueva (y territorio si no existe).
/// 3. Guarda en `direcciones_globales` con `tarjeta_id` vinculada.
/// 4. Actualiza el contador `totalDirecciones` de la tarjeta.
/// 5. Registra en `historial_reorganizaciones`.
/// 6. Emite notificación in-app (NotificacionService).
class AutoAsignadorService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────── ENTRADA PÚBLICA ────────────────────────

  /// Procesa una dirección individual. Respetando complementos: si la
  /// dirección tiene complemento diferente, se guarda como dirección
  /// separada (una casa/familia distinta en el mismo terreno).
  ///
  /// Retorna un mapa con la decisión tomada (para notificaciones UI).
  static Future<Map<String, dynamic>> procesarDireccionNueva({
    required Map<String, dynamic> nuevaDireccion,
    required String usuarioEmail,
  }) async {
    // ─────────────────── VALIDACIÓN DE REALIDAD (Mapbox) ───────────────────
    // Antes de gastar tokens de IA y de guardar, exigimos que Mapbox confirme
    // que la dirección es REAL (nivel dirección/POI, relevancia alta, en zona).
    // Direcciones inventadas (p. ej. "Rua Teste 20") se rechazan y NO se guardan.
    final calleCampo = (nuevaDireccion['calle'] ?? nuevaDireccion['texto_direccion'] ?? '').toString().trim();
    final complemento = (nuevaDireccion['complemento'] ?? '').toString().trim();
    final barrio = (nuevaDireccion['barrio'] ?? '').toString().trim();

    final direccionTextoParaValidar = [calleCampo, complemento, barrio]
        .where((x) => x.isNotEmpty)
        .join(', ');

    final validacion =
        await MapboxService.validarDireccion(direccionTextoParaValidar);
    if (validacion['ok'] != true) {
      final motivo = (validacion['motivo'] as String?) ?? 'Dirección no validada por Mapbox.';
      // No lanzamos: dejamos constancia y no guardamos, devolviendo decisión
      // de rechazo para que el llamador lo registre/notifique.
      return {
        'decision': 'RECHAZADA',
        'directa': false,
        'tarjeta_id_destino': '',
        'tarjeta_nombre': '',
        'explicacion': 'Rechazada por validación de realidad (Mapbox): $motivo',
        'lat': validacion['lat'],
        'lng': validacion['lng'],
        'lugar': validacion['lugar'],
      };
    }

    final lat = validacion['lat'] as double?;
    final lng = validacion['lng'] as double?;
    final lugar = (validacion['lugar'] as String?) ?? '';

    // Normalizar el TEXTO de la dirección (Groq: completa ciudad/estado,
    // corrige abreviaturas) con el mismo motor que usa el resto de la app
    // (admin, asignación manual del auditor). No se vuelve a geocodificar
    // acá — ya se validaron lat/lng arriba con Mapbox — solo se limpia el
    // texto para que se guarde igual de completo que en cualquier otro
    // camino de ingreso.
    String calleNormalizada = calleCampo;
    try {
      final normalizadas = await GroqTerritoryService.normalizarDireccionesParaGeocoding([
        {
          'id': 'temp',
          'calle': calleCampo,
          'numero': nuevaDireccion['numero'] ?? '',
          'complemento': complemento,
          'barrio': barrio,
        }
      ]);
      if (normalizadas.isNotEmpty) {
        final texto = normalizadas.first['direccion_normalizada']?.toString() ?? '';
        if (texto.isNotEmpty) calleNormalizada = texto;
      }
    } catch (_) {
      // Sin conexión/error de Groq: se guarda el texto original, sin
      // bloquear el flujo de auto-asignación por un problema de red puntual.
    }

    // ─────────────────── DEDUPLICACIÓN CONTRA EL BANCO ───────────────────
    // Antes de gastar tokens de IA y de guardar, comprobamos si la dirección
    // YA EXISTE en `direcciones_globales`. Regla de negocio:
    //   - MisMA calle + número + barrio con el MISMO complemento (o sin él)
    //     » es un DUPLICADO: NO se guarda; se avisa y se espera confirmación.
    //   - MisMA calle + número + barrio pero con COMPLEMENTO distinto
    //     » es una dirección VÁLIDA (otra casa/familia en el mismo terreno):
    //     se guarda como dirección separada.
    final numero = (nuevaDireccion['numero'] ?? '').toString().trim();
    final duplicado = await _buscarDuplicado(
      calle: calleCampo,
      numero: numero,
      complemento: complemento,
      barrio: barrio,
    );
    if (duplicado != null) {
      final existeEn = (duplicado['barrio'] ?? duplicado['territorio_destino'] ?? 'desconocido').toString();
      return {
        'decision': 'DUPLICADA',
        'directa': false,
        'tarjeta_id_destino': '',
        'tarjeta_nombre': '',
        'explicacion':
            'Ya existe en el banco de datos ($existeEn) sin complemento '
            'distinto. No se guardó; revisa el registro existente.',
        'duplicado_id': duplicado['id'],
        'duplicado_barrio': existeEn,
        'duplicado_existente': duplicado,
      };
    }

    // Obtener tarjetas actuales para análisis. IMPORTANTE: las tarjetas viven
    // en la subcolección territorios/{id}/tarjetas, no en una colección
    // 'tarjetas' de nivel raíz (esa colección está desconectada del resto
    // del sistema: admin y publicador nunca la leen). collectionGroup trae
    // todas las tarjetas de todos los territorios, conservando su campo
    // 'territorio_id' propio.
    final tarjetasSnap = await _db.collectionGroup('tarjetas').get();
    final tarjetas =
        tarjetasSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    // Consultar a la IA para decisión
    final decisionIA = await GroqTerritoryService.decidirTarjetaParaDireccion(
      direccion: nuevaDireccion,
      tarjetasExistentes: tarjetas,
    );

    final String tarjetaIdTarget =
        (decisionIA['tarjeta_id_destino'] as String?) ?? '';
    final String tarjetaNombre =
        (decisionIA['tarjeta_nombre'] as String?) ?? '';
    final String explicacion = (decisionIA['explicacion'] as String?) ?? '';

    // Resolver la tarjeta destino. Regla: NUNCA se crea un territorio por una
    // dirección suelta. Si la IA sugiere una existente, se usa; si no, se
    // reutiliza una con cupo o se crea una tarjeta dentro de un territorio
    // existente. Si no hay ningún territorio, la dirección queda pendiente.
    final tarjetaExiste = tarjetaIdTarget.isNotEmpty &&
        tarjetas.any((t) => t['id'] == tarjetaIdTarget);

    Map<String, String>? resuelta;
    if (tarjetaExiste) {
      final tarjetaMatch =
          tarjetas.firstWhere((t) => t['id'] == tarjetaIdTarget);
      resuelta = {
        'id': tarjetaIdTarget,
        'nombre': tarjetaNombre,
        'territorio_id': tarjetaMatch['territorio_id']?.toString() ?? '',
      };
    } else {
      resuelta = await _resolverTarjeta(
        direccion: nuevaDireccion,
        nombreSugerido: tarjetaNombre,
        tarjetas: tarjetas,
      );
    }

    // No hay ningún territorio existente para albergar esta dirección.
    // NO se crea territorio: la dirección queda en la bandeja para revisión.
    if (resuelta == null || (resuelta['territorio_id'] ?? '').isEmpty) {
      return {
        'decision': 'SIN_TERRITORIO',
        'directa': false,
        'tarjeta_id_destino': '',
        'tarjeta_nombre': '',
        'explicacion':
            'No hay ningún territorio existente donde ubicar esta dirección. '
            'Revisa/crea un territorio manualmente antes de procesar.',
        'lat': lat,
        'lng': lng,
        'lugar': lugar,
      };
    }

    String tarjetaFinalId = resuelta['id']!;
    String tarjetaFinalNombre = resuelta['nombre']!;
    String tarjetaFinalTerritorioId = resuelta['territorio_id']!;

    // Guardar la dirección vinculada en direcciones_globales.
    final batch = _db.batch();
    final globalRef = _db.collection('direcciones_globales').doc();
    batch.set(globalRef, {
      ...nuevaDireccion,
      'calle': calleNormalizada,
      'direccionNormalizada': calleNormalizada,
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
      'lugar_validado': lugar,
      'tarjeta_id': tarjetaFinalId,
      'territorio_id': tarjetaFinalTerritorioId,
      // `complemento` y `barrio` se escriben SIEMPRE, aunque el llamador los
      // traiga vacíos o no los traiga. Antes solo llegaban si venían en el
      // spread de `nuevaDireccion`, y un documento sin la clave `complemento`
      // hace que `_buscarDuplicado` no pueda verificar nada (ver el `continue`
      // de más abajo). Un documento sin `barrio` además queda fuera de las tres
      // consultas que filtran por ese campo. Van después del spread para ganar.
      'complemento': (nuevaDireccion['complemento'] ?? '').toString().trim(),
      'barrio': _barrioDe(
        (nuevaDireccion['barrio'] ?? '').toString().trim(),
        tarjetaFinalTerritorioId,
      ),
      'estado_predicacion': 'pendiente',
      // 'estado': 'asignada' (no un valor custom) porque el publicador
      // filtra con .where('estado', isNotEqualTo: 'removida') — y además
      // así queda consistente con lo que escribe el admin y el auditor.
      'estado': 'asignada',
      'origen': 'Auto-asignación (IA)',
      'creado_el': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    });

    // Actualizar contador de la tarjeta (subcolección real, no la colección
    // raíz desconectada).
    batch.update(
      _db
          .collection('territorios')
          .doc(tarjetaFinalTerritorioId)
          .collection('tarjetas')
          .doc(tarjetaFinalId),
      {
        'totalDirecciones': FieldValue.increment(1),
        'cantidad_direcciones': FieldValue.increment(1),
      },
    );

    // Registrar en historial.
    final historialRef = _db.collection('historial_reorganizaciones').doc();
    batch.set(historialRef, {
      'tipo_evento': 'AUTO_ASIGNACION_DIRECTA',
      'fecha': FieldValue.serverTimestamp(),
      'direccion_ingresada': calleCampo,
      'complemento': complemento,
      'barrio': barrio,
      'lugar_validado': lugar,
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
      'territorio_destino': barrio,
      'tarjeta_asignada_id': tarjetaFinalId,
      'tarjeta_nombre': tarjetaFinalNombre,
      'accion_tomada': 'Auto-asignada a tarjeta $tarjetaFinalNombre',
      'usuario': usuarioEmail,
      'razonamiento_ia': explicacion,
    });

    await batch.commit();

    // Notificar al auditor que una dirección fue colocada.
    try {
      final calle = (nuevaDireccion['calle'] ?? nuevaDireccion['texto_direccion'] ?? '').toString();
      final comp = (nuevaDireccion['complemento'] ?? '').toString();
      await notif.NotificacionService.enviarAAuditores(
        titulo: 'Dirección auto-asignada',
        cuerpo: '$calle${comp.isNotEmpty ? ' ($comp)' : ''} » $tarjetaFinalNombre',
        tipo: notif.TipoNotificacion.solicitudDireccion,
        extra: {
          'tipo_evento': 'AUTO_ASIGNACION_DIRECTA',
          'tarjeta_id': tarjetaFinalId,
          'tarjeta_nombre': tarjetaFinalNombre,
        },
      );
    } catch (_) {}

    return {
      'direccion_id': globalRef.id,
      'tarjeta_id': tarjetaFinalId,
      'tarjeta_nombre': tarjetaFinalNombre,
      'explicacion_ia': explicacion,
    };
  }

  /// Procesa un lote de direcciones nuevas. Útil para:
  /// - Múltiples casas/condominio enviadas desde EnviarDireccionCard
  /// - Lote de direcciones pegadas desde WhatsApp y procesadas por IA
  /// - Bandeja automática cuando el modo automático está activo
  ///
  /// Cada dirección se procesa independientemente (respetando complemento).
  /// Retorna un resumen de lo procesado (para UI/notificaciones).
  static Future<Map<String, dynamic>> procesarLoteDirecciones({
    required List<Map<String, dynamic>> direcciones,
    required String usuarioEmail,
    Function(int procesados, int total)? onProgress,
  }) async {
    final resultados = <Map<String, dynamic>>[];
    final errores = <String>[];
    final idsProcesados = <String>[];
    int procesadas = 0;

    for (int i = 0; i < direcciones.length; i++) {
      final dir = direcciones[i];
      try {
        final resultado = await procesarDireccionNueva(
          nuevaDireccion: dir,
          usuarioEmail: usuarioEmail,
        );
        // Dirección que no pudo colocarse (no real según Mapbox, o sin ningún
        // territorio existente) NO se considera colocada: va al resumen.
        final decision = (resultado['decision'] as String?) ?? '';
        if (decision.isNotEmpty) {
          final calle =
              (dir['calle'] ?? dir['texto_direccion'] ?? '?').toString();
          final motivo = (resultado['explicacion'] as String?) ?? '';
          errores.add('$calle » $decision: $motivo');
        } else {
          resultados.add(resultado);
          procesadas++;
          final idSug = dir['id_sugerencia'];
          if (idSug is String && idSug.isNotEmpty) {
            idsProcesados.add(idSug);
          }
        }
      } catch (e) {
        final calle = (dir['calle'] ?? dir['texto_direccion'] ?? '?').toString();
        errores.add('$calle: $e');
      }
      onProgress?.call(i + 1, direcciones.length);
    }

    // Notificar resumen del lote.
    try {
      if (procesadas > 0 || errores.isNotEmpty) {
        await notif.NotificacionService.enviarAAuditores(
          titulo:
              errores.isEmpty
                  ? 'Lote procesado: $procesadas/${direcciones.length}'
                  : 'Lote: $procesadas ok, ${errores.length} no válidas',
          cuerpo: errores.isEmpty
              ? 'Todas las direcciones fueron auto-asignadas correctamente.'
              : generarResumenErrores(errores),
          tipo: notif.TipoNotificacion.solicitudDireccion,
          extra: {'procesadas': procesadas, 'errores': errores.length},
        );
      }
    } catch (_) {}

    return {
      'procesadas': procesadas,
      'errores': errores,
      'resultados': resultados,
      'ids_procesados': idsProcesados,
    };
  }

  static String generarResumenErrores(List<String> errores) {
    if (errores.length <= 3) return errores.join('\n');
    return '${errores.take(3).join('\n')}\n… y ${errores.length - 3} más.';
  }

  // ──────────────────── CREACIÓN INTELIGENTE DE TARJETA ────────────────────

  /// Resuelve la mejor tarjeta para una dirección NUEVA.
  ///
  /// Regla de negocio (Punto 1): una dirección suelta NUNCA crea un territorio.
  /// - Si ya existe una tarjeta con cupo » se reutiliza.
  /// - Si hace falta crear una tarjeta » se crea DENTRO de un territorio
  ///   existente (coincide por barrio, o el territorio con más similitud).
  /// - Si no existe ningún territorio » NO se crea: devuelve null y el
  ///   llamador deja la dirección pendiente para revisión manual.
  ///
  /// Retorna {id, nombre} o null si no se puede ubicar sin crear territorio.
  static Future<Map<String, String>?> _resolverTarjeta({
    required Map<String, dynamic> direccion,
    required String nombreSugerido,
    required List<Map<String, dynamic>> tarjetas,
  }) async {
    final barrio = (direccion['barrio'] ?? '').toString().trim();

    // 1) Reutilizar una tarjeta EXISTENTE con el mismo nombre (si la IA la
    //    sugirió y no existe, caemos a creación normal).
    if (nombreSugerido.isNotEmpty) {
      final porNombre = tarjetas
          .where((t) =>
              (t['nombre']?.toString() ?? '').trim().toLowerCase() ==
              nombreSugerido.trim().toLowerCase())
          .toList();
      if (porNombre.isNotEmpty) {
        return {
          'id': porNombre.first['id'].toString(),
          'nombre': nombreSugerido,
          'territorio_id': porNombre.first['territorio_id']?.toString() ?? '',
        };
      }
    }

    // 2) Reutilizar una tarjeta existente con cupo SOLO en el mismo
    //    territorio/barrio (la lógica inteligente analiza y matchea primero,
    //    no asigna a tarjetas de territorios ajenos).
    if (barrio.isNotEmpty) {
      final coincidenBarrio = tarjetas.where((t) {
        final tb = (t['barrio'] ?? '').toString().toLowerCase();
        final tn = (t['nombre']?.toString() ?? '').toLowerCase();
        final tid = (t['territorio_id']?.toString() ?? '').toLowerCase();
        return tb == barrio.toLowerCase() ||
            tn.contains(barrio.toLowerCase()) ||
            tid == barrio.toLowerCase();
      }).toList();
      for (final t in coincidenBarrio) {
        final total = (t['totalDirecciones'] as num?)?.toInt() ?? 0;
        if (total < 8) {
          return {
            'id': t['id'].toString(),
            'nombre': (t['nombre'] ?? '').toString(),
            'territorio_id': t['territorio_id']?.toString() ?? '',
          };
        }
      }
    }

    // 3) Crear tarjeta nueva PERO siempre dentro de un TERRITORIO que
    //    realmente coincida con el barrio de la dirección. Si no hay
    //    coincidencia, NO se asigna a territorios ajenos.
    final territorioId = await _encontrarTerritorioPara(direccion);
    if (territorioId == null) {
      // No hay ningún territorio relacionado » NO creamos ni asignamos.
      return null;
    }

    // Si la IA sugirió un nombre usarlo; sino derivar del barrio/calle.
    String nombreTarjeta = nombreSugerido.isNotEmpty
        ? nombreSugerido
        : barrio.isNotEmpty
            ? 'Tarjeta $barrio'
            : 'Tarjeta ${(direccion['calle'] ?? direccion['texto_direccion'] ?? '').toString().split(' ').take(2).join(' ')}';

    // Asegurar nombre único.
    final existentes = tarjetas.map((t) =>
        (t['nombre']?.toString() ?? '').trim().toLowerCase()).toSet();
    var base = nombreTarjeta;
    int cont = 2;
    while (existentes.contains(base.trim().toLowerCase())) {
      base = '$nombreTarjeta $cont';
      cont++;
    }
    nombreTarjeta = base.trim();

    // Subcolección real (no la colección raíz desconectada). El id del
    // documento ES el nombre de la tarjeta, igual que en el resto del
    // sistema (admin, reorganización del auditor), para que el resto del
    // código que asume esa convención pueda encontrarla sin problemas.
    final tarRef = _db
        .collection('territorios')
        .doc(territorioId)
        .collection('tarjetas')
        .doc(nombreTarjeta);
    await tarRef.set({
      'nombre': nombreTarjeta,
      'territorio_id': territorioId,
      'totalDirecciones': 0,
      'creado_por_ia': true,
      'created_at': FieldValue.serverTimestamp(),
    });
    return {
      'id': tarRef.id,
      'nombre': nombreTarjeta,
      'territorio_id': territorioId,
    };
  }

  /// Encuentra una TERRITORIO existente que pueda albergar la dirección.
  /// Coincide primero por barrio; si no, devuelve el territorio que ya tiene
  /// más direcciones en ese mismo barrio; como último recurso, el primero
  /// existente. NUNCA crea un territorio.
  static Future<String?> _encontrarTerritorioPara(
      Map<String, dynamic> direccion) async {
    final territoriosSnap = await _db.collection('territorios').get();
    if (territoriosSnap.docs.isEmpty) return null;

    final barrio = (direccion['barrio'] ?? '').toString().trim();

    // 1) Territorio cuyo nombre coincide con el barrio.
    if (barrio.isNotEmpty) {
      for (final terDoc in territoriosSnap.docs) {
        final nombreTer = (terDoc.data()['nombre'] as String? ?? '').trim();
        if (nombreTer.toLowerCase() == barrio.toLowerCase() ||
            terDoc.id.toLowerCase() == barrio.toLowerCase()) {
          return terDoc.id;
        }
      }
    }

    // 2) Territorio que ya contenga direcciones del mismo barrio (más cercano).
    if (barrio.isNotEmpty) {
      final direccionesSnap = await _db
          .collection('direcciones_globales')
          .where('barrio', isEqualTo: barrio)
          .limit(200)
          .get();
      final conteoPorTerritorio = <String, int>{};
      for (final doc in direccionesSnap.docs) {
        final tid = doc.data()['territorio_id'];
        if (tid != null) {
          final clave = tid.toString();
          conteoPorTerritorio[clave] = (conteoPorTerritorio[clave] ?? 0) + 1;
        }
      }
      if (conteoPorTerritorio.isNotEmpty) {
        final mejor = conteoPorTerritorio.entries
            .reduce((a, b) => a.value >= b.value ? a : b);
        return mejor.key;
      }
    }

    // Sin barrio o sin coincidencia » NO se asigna a un territorio ajeno.
    // La dirección queda pendiente para revisión manual del auditor.
    return null;
  }

  // ──────────────────── DEDUPLICACIÓN (banco de datos) ────────────────────

  /// `barrio` con la convención que ya usa la base: si no viene del llamador,
  /// se deriva del territorio con los guiones bajos convertidos en espacios.
  ///
  /// Es la misma regla con la que `restaurar-barrio.js` reconstruyó el campo
  /// en los 194 documentos que la migración del 2026-10-04 había borrado
  /// (§9.2 del plan), y la única con la que las consultas por `barrio` devuelven
  /// algo: `CAMPINA_DA_BARRA` se busca como `CAMPINA DA BARRA`.
  static String _barrioDe(String barrio, String territorioId) {
    final b = barrio.trim();
    if (b.isNotEmpty) return b;
    return territorioId.replaceAll('_', ' ').trim();
  }

  /// Normaliza texto para comparar direcciones (minúsculas, sin espacios
  /// dobles, sin tildes).
  static String _norm(String s) {
    const withAccents = 'áéíóúÁÉÍÓÚñÑ';
    const withoutAccents = 'aeiouAEIOUnN';
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      final idx = withAccents.indexOf(c);
      buffer.write(idx >= 0 ? withoutAccents[idx] : c);
    }
    return buffer.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Busca en `direcciones_globales` una dirección que ya exista con la misma
  /// calle + número + barrio y el MISMO complemento. Retorna el registro
  /// existente si es un duplicado real; null si no existe o si el complemento
  /// es distinto (en ese caso es una dirección separada válida).
  static Future<Map<String, dynamic>?> _buscarDuplicado({
    required String calle,
    required String numero,
    required String complemento,
    required String barrio,
  }) async {
    final nCalle = _norm(calle);
    if (nCalle.isEmpty) return null;
    final nNumero = _norm(numero);
    final nComp = _norm(complemento);

    Query<Map<String, dynamic>> q =
        _db.collection('direcciones_globales');
    if (barrio.trim().isNotEmpty) {
      q = q.where('barrio', isEqualTo: barrio.trim());
    }
    final snap = await q.limit(500).get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final eCalle =
          _norm((data['calle'] ?? data['texto_direccion'] ?? '').toString());
      if (eCalle.isEmpty) continue;
      if (eCalle != nCalle) continue;

      final eNumero = _norm((data['numero'] ?? '').toString());
      final mismoNumero = (eNumero.isEmpty && nNumero.isEmpty) ||
          (eNumero.isNotEmpty && eNumero == nNumero);
      if (!mismoNumero) continue;

      final eBarrio = _norm((data['barrio'] ?? '').toString());
      if (barrio.trim().isNotEmpty && eBarrio != _norm(barrio)) continue;

      // Mismo calle+nº+barrio: sólo es duplicado si el complemento coincide.
      //
      // La clave `complemento` tiene que EXISTIR en el documento. Si no existe
      // no se puede verificar nada, así que se sigue buscando en vez de
      // afirmar que es duplicado. Con un `?? ''` el "no lo sé" se convertía en
      // "vacío", y como la dirección nueva sin complemento también normaliza a
      // vacío, salía falso positivo: bloqueaba el alta de una dirección que en
      // realidad era otra unidad (mismo lote, distinto depto).
      //
      // El sesgo es deliberado y va en contra del "no duplicar": ante la duda
      // se inserta el duplicado, que se ve y se puede borrar, en lugar de
      // bloquear el alta en silencio. Los 194 documentos que dejó la migración
      // del 2026-10-04 están sin `complemento` (§9.2 del plan), así que hasta
      // recuperar ese campo no se van a detectar duplicados contra ellos. Las
      // direcciones nuevas sí lo traen, y desde la segunda alta el control
      // vuelve a funcionar.
      if (!data.containsKey('complemento') || data['complemento'] == null) {
        continue;
      }
      final eComp = _norm(data['complemento'].toString());
      if (eComp == nComp) {
        return {'id': doc.id, ...data};
      }
    }
    return null;
  }
}
