import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'notificacion_lectura_store.dart';

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
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    final destRoles = (roles ?? const <String>[])
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
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

  /// ¿La notificación corresponde al perfil?
  ///
  /// Acepta el esquema actual (`destinatarios` / `destinatarios_roles`) y el
  /// antiguo (`destinatario_nombre` / `para_roles`), porque hay documentos
  /// escritos antes de unificar los nombres de campo.
  static bool aplica(PerfilNotificacion perfil, Map<String, dynamic> data) {
    return _destinatario(perfil, data);
  }

  static bool _destinatario(
      PerfilNotificacion perfil, Map<String, dynamic> data) {
    if (perfil.nombre.isNotEmpty) {
      final dest = data['destinatarios'];
      if (dest is List &&
          dest.any((d) => d is String && d.trim() == perfil.nombre)) {
        return true;
      }
      final individual = data['destinatario_nombre'];
      if (individual is String && individual.trim() == perfil.nombre) {
        return true;
      }
    }
    final roles = <Object?>[
      ...?(data['destinatarios_roles'] as List?),
      ...?(data['para_roles'] as List?),
    ];
    for (final r in roles) {
      if (r is String && perfil.roles.contains(r.trim())) return true;
    }
    return false;
  }

  static DateTime? _fecha(Map<String, dynamic> data) {
    for (final clave in const ['created_at', 'enviado_en']) {
      final valor = data[clave];
      if (valor is Timestamp) return valor.toDate();
      if (valor is DateTime) return valor;
      if (valor is String) {
        final parseada = DateTime.tryParse(valor);
        if (parseada != null) return parseada;
      }
    }
    return null;
  }

  /// Más recientes primero. Los documentos sin fecha quedan al final para no
  /// desplazar las notificaciones nuevas.
  static int _compararRecientes(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final fa = _fecha(a.data());
    final fb = _fecha(b.data());
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fb.compareTo(fa);
  }

  /// Notificaciones visibles para el perfil, más recientes primero.
  ///
  /// Con [lectura] se descartan las que el usuario limpió de su bandeja. El
  /// documento compartido no se modifica: el estado de lectura es por usuario.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrarNotificaciones(
    PerfilNotificacion perfil,
    QuerySnapshot<Map<String, dynamic>> snap, [
    NotificacionLecturaStore? lectura,
  ]) {
    final out = snap.docs.where((d) {
      if (!aplica(perfil, d.data())) return false;
      return lectura == null || !lectura.estaOculta(d.id, d.data());
    }).toList()
      ..sort(_compararRecientes);
    return out;
  }

  static int contarNoLeidas(
    PerfilNotificacion perfil,
    QuerySnapshot<Map<String, dynamic>> snap, [
    NotificacionLecturaStore? lectura,
  ]) {
    var count = 0;
    for (final d in snap.docs) {
      final data = d.data();
      if (!aplica(perfil, data)) continue;
      if (lectura != null) {
        if (lectura.estaOculta(d.id, data)) continue;
        if (lectura.estaLeida(d.id, data)) continue;
        count++;
        continue;
      }
      if (data['leida'] == true) continue;
      count++;
    }
    return count;
  }

  static Future<void> marcarLeidas(PerfilNotificacion perfil) async {
    final docs = await _obtenerDocs(perfil);
    WriteBatch batch = _db.batch();
    var ops = 0;
    for (final doc in docs) {
      if (doc.data()['leida'] == true) continue;
      batch.update(doc.reference, {'leida': true});
      if (++ops >= 380) {
        await batch.commit();
        // Un WriteBatch no se puede reutilizar después de commit().
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  static Future<void> limpiar(PerfilNotificacion perfil) async {
    final docs = await _obtenerDocs(perfil);
    WriteBatch batch = _db.batch();
    var ops = 0;
    for (final doc in docs) {
      batch.delete(doc.reference);
      if (++ops >= 380) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _obtenerDocs(
      PerfilNotificacion perfil) async {
    // Sin `orderBy` ni `take`: se lee una vez y se filtra en memoria para no
    // depender de índices y no dejar notificaciones antiguas sin marcar/borrar.
    final snap = await _db.collection('notificaciones').get();
    return filtrarNotificaciones(perfil, snap);
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
