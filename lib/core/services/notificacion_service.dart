import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoNotificacion {
  motivacional,
  avisoDevolucion,
  solicitudDireccion,
  nuevaDireccionEnviada,
  alertaPredicacion,
  solicitudAcceso,
  tarjetaTomada,
  devolucionTarjeta,
  devolucionAutomatica,
  anuncio,
  sugerencia,
}

/// Perfil de un usuario para leer sus notificaciones.
/// La notificación se dirige por NOMBRE (con el que se registró) y por ROL.
class PerfilNotificacion {
  final String nombre;
  final Set<String> roles;

  PerfilNotificacion({required this.nombre, required this.roles});
}

/// Sistema de notificaciones.
///
/// IMPORTANTE: las notificaciones se dirigen utilizando el NOMBRE de usuario
/// (el nombre con el que la persona se registró), nunca por correo electrónico.
///
/// Reglas de destinatarios:
///  - Roles: `es_admin`, `es_admin_territorios`, `es_conductor`, `es_publicador`.
///  - Modo Territorio (es_admin_territorios) recibe TODOS los movimientos de
///    territorios y tarjetas.
///  - Modo Conductor recibe cuando le envían/asignan una tarjeta/territorio.
///  - Modo Publicador es individual: solo recibe lo que le corresponde a él.
///
/// Cada documento de `notificaciones` lleva:
///  - `destinatarios`: List<String> con los NOMBRES de los usuarios concretos.
///  - `destinatarios_roles`: List<String> con las claves de rol a las que va (Ej: 'es_admin').
///  - `titulo`, `cuerpo`, `tipo`, `leida`, `created_at`, `extra`.
///  - `destinatario_email` (resuelto) sólo para el push FCM (Cloud Function).
class NotificacionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _tipoToString(TipoNotificacion tipo) {
    switch (tipo) {
      case TipoNotificacion.motivacional:
        return 'motivacional';
      case TipoNotificacion.avisoDevolucion:
        return 'aviso_devolucion';
      case TipoNotificacion.solicitudDireccion:
        return 'solicitud_direccion';
      case TipoNotificacion.nuevaDireccionEnviada:
        return 'nueva_direccion_enviada';
      case TipoNotificacion.alertaPredicacion:
        return 'alerta_predicacion';
      case TipoNotificacion.solicitudAcceso:
        return 'solicitud_acceso';
      case TipoNotificacion.tarjetaTomada:
        return 'tarjeta_tomada';
      case TipoNotificacion.devolucionTarjeta:
        return 'devolucion_tarjeta';
      case TipoNotificacion.devolucionAutomatica:
        return 'devolucion_automatica';
      case TipoNotificacion.anuncio:
        return 'anuncio';
      case TipoNotificacion.sugerencia:
        return 'sugerencia';
    }
  }

  // ─────────────────────────── ESCRITURA ───────────────────────────

  /// Validación interna de campos consistentes según el tipo de target.
  /// Retorna el email resuelto para FCM push notification.
  static Future<Map<String, dynamic>> _construirDatosNotificacion({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    List<String>? usuarios,
    List<String>? roles,
    Map<String, dynamic>? extra,
    String? emailResuelto, // Inyectado desde el llamador
  }) async {
    final destUsuarios = (usuarios ?? const <String>[])
        .where((u) => u.trim().isNotEmpty)
        .toSet()
        .toList();
    final destRoles = (roles ?? const <String>[])
        .where((r) => r.trim().isNotEmpty)
        .toSet()
        .toList();

    if (destUsuarios.isEmpty && destRoles.isEmpty) {
      throw ArgumentError('Se deben especificar usuarios o roles para la notificación');
    }

    // Construir estructura consistente
    final Map<String, dynamic> data = {
      'titulo': titulo,
      'cuerpo': cuerpo,
      'tipo': _tipoToString(tipo),
      'leida': false,
      'created_at': FieldValue.serverTimestamp(),
      'destinatarios': destUsuarios,
      'destinatarios_roles': destRoles,
      'destinatario_nombre':
          destUsuarios.isNotEmpty ? destUsuarios.first : null,
    };

    // Añadir email solo si hay usuarios individuales (para FCM push)
    if (destUsuarios.isNotEmpty && emailResuelto != null) {
      data['destinatario_email'] = emailResuelto;
      data['destinatario'] = emailResuelto;
    }

    if (extra != null) data['extra'] = extra;

    return data;
  }

  static Future<void> _crear({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    List<String>? usuarios,
    List<String>? roles,
    Map<String, dynamic>? extra,
    String? emailResuelto, // Inyectado para FCM push a usuarios individuales
  }) async {
    final datos = await _construirDatosNotificacion(
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
      usuarios: usuarios,
      roles: roles,
      extra: extra,
      emailResuelto: emailResuelto,
    );

    await _db.collection('notificaciones').add(datos);
  }

  /// Envía a un rol o varios (broadcast). Ej.: roles: ['es_admin'].
  static Future<void> enviarARoles({
    required List<String> roles,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        roles: roles,
        extra: extra,
        emailResuelto: null, // No aplica email para envío por rol
      );

  /// Envía a un USUARIO concreto por su NOMBRE (individual).
  static Future<void> enviarAPublicador({
    required String nombre,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        usuarios: [nombre],
        extra: extra,
        emailResuelto: null, // Email resuelto internamente si es necesario
      );

  /// Envía a un CONDUCTOR concreto por su NOMBRE (individual).
  static Future<void> enviarAConductor({
    required String nombre,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        usuarios: [nombre],
        extra: extra,
        emailResuelto: null,
      );

  /// Envía a un usuario concreto por su NOMBRE (equivalente individual).
  static Future<void> enviarAUser({
    required String destinatarioNombre,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        usuarios: [destinatarioNombre],
        extra: extra,
        emailResuelto: null,
      );

  /// Broadcast a Administradores.
  static Future<void> enviarAAdmins({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        roles: ['es_admin'],
        extra: extra,
        emailResuelto: null,
      );

  /// Broadcast a Administradores de Territorios (recibe todos los movimientos
  /// de territorios y tarjetas) + admins.
  static Future<void> enviarAAdminTerritorios({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        roles: ['es_admin', 'es_admin_territorios'],
        extra: extra,
        emailResuelto: null,
      );

  /// Broadcast a auditores/admins/territorios.
  static Future<void> enviarAAuditores({
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) =>
      _crear(
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        roles: ['es_admin', 'es_admin_territorios', 'es_auditor'],
        extra: extra,
        emailResuelto: null,
      );

  // ─────────────────────────── PERFIL DE USUARIO ───────────────────────────
  /// Construye el perfil (nombre + roles) de un usuario a partir de su
  /// [usuarioData] para leer sus notificaciones por NOMBRE y ROL.
  static PerfilNotificacion perfilDesdeUsuario(Map<String, dynamic> usuarioData) {
    final roles = <String>{};
    if (usuarioData['es_admin'] == true) roles.add('es_admin');
    if (usuarioData['es_auditor'] == true) roles.add('es_auditor');
    if (usuarioData['es_admin_territorios'] == true) roles.add('es_admin_territorios');
    if (usuarioData['es_conductor'] == true) roles.add('es_conductor');
    if (usuarioData['es_publicador'] == true) roles.add('es_publicador');
    final rolStr = usuarioData['rol'];
    if (rolStr is String) {
      final r = rolStr.toLowerCase();
      if (r == 'admin' || r == 'administrador' || r == 'superadmin') roles.add('es_admin');
      if (r == 'auditor') roles.add('es_auditor');
      if (r == 'territorios' || r == 'admin_territorios') roles.add('es_admin_territorios');
      if (r == 'conductor') roles.add('es_conductor');
      if (r == 'publicador') roles.add('es_publicador');
    }
    return PerfilNotificacion(
      nombre: (usuarioData['nombre'] as String?)?.trim() ?? '',
      roles: roles,
    );
  }

  // ─────────────────────────── LECTURA ───────────────────────────
  // NOTA: se lee la colección completa y se filtra/ordena EN MEMORIA para NO
  // depender de índices compuestos de Firestore. Así la campanilla y el
  // listado nunca salen en blanco, pase lo que pase.

  static Stream<QuerySnapshot> _snapGlobal() {
    // Cada llamada crea una suscripción NUEVA e independiente. No se cachea el
    // stream: `snapshots()` es de suscripción única y reutilizarlo entre el
    // badge y el listado rompería al segundo StreamBuilder (el stream ya fue
    // escuchado). La ordenación por un solo campo usa índice automático.
    return _db
        .collection('notificaciones')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  static bool _aplica(PerfilNotificacion perfil, Map<String, dynamic> data) {
    if (perfil.nombre.isNotEmpty) {
      final dest = data['destinatarios'];
      if (dest is List &&
          dest.any((d) => d is String && d.trim() == perfil.nombre)) {
        return true;
      }
      // Documentos viejos que guardaban el destinatario uno a uno.
      final individual = data['destinatario_nombre'];
      if (individual is String && individual.trim() == perfil.nombre) {
        return true;
      }
    }
    // Se aceptan los dos nombres de campo porque en la base conviven los dos
    // (`para_roles` lo escribían pantallas antiguas) y con uno solo había
    // notificaciones invisibles para todos.
    for (final clave in const ['destinatarios_roles', 'para_roles']) {
      final roles = data[clave];
      if (roles is List) {
        for (final r in roles) {
          if (r is String && perfil.roles.contains(r.trim())) return true;
        }
      }
    }
    return false;
  }

  static Stream<int> streamConteo(PerfilNotificacion perfil) {
    return _snapGlobal().map((snap) {
      var count = 0;
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
        if (data['leida'] == true) continue;
        if (_aplica(perfil, data)) count++;
      }
      return count;
    });
  }

  static Stream<List<QueryDocumentSnapshot>> streamNotificaciones(
      PerfilNotificacion perfil) {
    return _snapGlobal().map((snap) {
      final out = <QueryDocumentSnapshot>[];
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
        if (_aplica(perfil, data)) out.add(d);
      }
      return out.take(50).toList();
    });
  }

  static Future<void> marcarLeidas(PerfilNotificacion perfil) async {
    final docs = await _obtenerDocs(perfil);
    final batch = _db.batch();
    var ops = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
      if (data['leida'] == true) continue;
      batch.update(doc.reference, {'leida': true});
      ops++;
      if (ops >= 380) {
        await batch.commit();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  static Future<void> limpiar(PerfilNotificacion perfil) async {
    final docs = await _obtenerDocs(perfil);
    final batch = _db.batch();
    var ops = 0;
    for (final doc in docs) {
      batch.delete(doc.reference);
      ops++;
      if (ops >= 380) {
        await batch.commit();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  static Future<List<QueryDocumentSnapshot>> _obtenerDocs(
      PerfilNotificacion perfil) async {
    final snap = await _snapGlobal().first;
    final out = <QueryDocumentSnapshot>[];
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
      if (_aplica(perfil, data)) out.add(d);
    }
    return out.take(200).toList();
  }

  // ─────────────────────────── MÉTODOS EXPLÍCITOS MEJORADOS ───────────────────────────

  /// Envía notificación a usuario individual por NOMBRE (validado).
  /// Lanza ArgumentError si el nombre no existe o está vacío.
  /// Resuelve automáticamente el email para FCM push notification.
  static Future<void> enviarNotificacionIndividual({
    required String nombre,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) async {
    if (nombre.trim().isEmpty) {
      throw ArgumentError('El nombre del destinatario no puede estar vacío');
    }

    final snap = await _db
        .collection('usuarios')
        .where('nombre', isEqualTo: nombre.trim())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw ArgumentError('No existe un usuario registrado con el nombre: "$nombre"');
    }

    final emailResuelto = snap.docs.first['email'] as String?;
    await _crear(
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
      usuarios: [nombre.trim()],
      extra: extra,
      emailResuelto: emailResuelto,
    );
  }

  /// Envía notificación a uno o varios roles especificados.
  /// Lanza ArgumentError si la lista de roles está vacía o solo contiene strings vacíos.
  static Future<void> enviarNotificacionPorRol({
    required List<String> roles,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) async {
    final rolesValidos = roles.where((r) => r.isNotEmpty).toList();
    if (rolesValidos.isEmpty) {
      throw ArgumentError('Se deben especificar uno o más roles válidos para la notificación');
    }

    await _crear(
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
      roles: rolesValidos,
      extra: extra,
    );
  }

  /// Envía notificación con combinación de usuarios y/o roles.
  /// - Si solo hay usuarios: envío individual (por nombre)
  /// - Si solo hay roles: envío por rol (broadcast)
  /// - Si ambos tienen elementos: mezcla (aunque en Firestore se guardan por separado)
  /// Lanza ArgumentError si ambos están vacíos.
  static Future<void> enviarNotificacionMixta({
    required List<String>? usuarios,
    required List<String>? roles,
    required String titulo,
    required String cuerpo,
    required TipoNotificacion tipo,
    Map<String, dynamic>? extra,
  }) async {
    final tieneUsuarios = usuarios?.isNotEmpty == true;
    final tieneRoles = roles?.isNotEmpty == true;

    if (!tieneUsuarios && !tieneRoles) {
      throw ArgumentError('Se deben especificar usuarios o roles (al menos uno)');
    }

    // Filtrar strings vacíos
    final usuariosFiltrados = usuarios?.where((u) => u.isNotEmpty).toList();
    final rolesFiltrados = roles?.where((r) => r.isNotEmpty).toList();

    await _crear(
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
      usuarios: usuariosFiltrados,
      roles: rolesFiltrados,
      extra: extra,
    );
  }
}
