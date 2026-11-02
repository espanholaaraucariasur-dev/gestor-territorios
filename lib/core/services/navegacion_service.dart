import 'dart:async';

import 'package:flutter/foundation.dart';

/// Destinos de navegación que se pueden abrir desde una notificación.
///
/// Cada notificación lleva una clave `screen` (dentro de `extra` en Firestore,
/// aplanada por la Cloud Function al payload FCM). Este archivo es la única
/// fuente de verdad de qué clave lleva a qué pantalla y de qué roles pueden
/// verla, para que el enrutado no quede esparcido en los widgets.
class Pantallas {
  // Admin
  static const String usuariosPendientes = 'usuarios_pendientes';
  static const String solicitudesDirecciones = 'solicitudes_direcciones';
  static const String sugerencias = 'sugerencias';

  // Admin › Auditoría
  static const String auditorDireccionesNuevas = 'auditor_direcciones_nuevas';

  // Publicador
  static const String misTarjetas = 'mis_tarjetas';

  static const Set<String> todas = {
    usuariosPendientes,
    solicitudesDirecciones,
    auditorDireccionesNuevas,
    misTarjetas,
    sugerencias,
  };
}

/// Un destino pendiente de ser ejecutado.
class DestinoNotificacion {
  final String pantalla;
  final Map<String, dynamic> extra;

  const DestinoNotificacion(this.pantalla, [this.extra = const {}]);

  @override
  String toString() => 'DestinoNotificacion($pantalla)';
}

/// Enrutador de notificaciones dentro de la app.
///
/// Por qué existe una cola y no se navega directo: una notificación se puede
/// tocar en momentos donde la app todavía NO tiene navigator listo (por
/// ejemplo mientras se restaura la sesión). En vez de perder el destino, se
/// encola aquí y `home_page` —que es el único que sabe cómo cambiar de
/// modo/tab— lo consume cuando está montado.
class NavegacionService {
  NavegacionService._();

  static final StreamController<DestinoNotificacion> _controller =
      StreamController<DestinoNotificacion>.broadcast();

  /// Destino aún no consumido. Sobrevive a la app en background.
  static DestinoNotificacion? _pendiente;

  static Stream<DestinoNotificacion> get destinos => _controller.stream;

  static DestinoNotificacion? get pendiente => _pendiente;

  /// Encola un destino. Si ya había uno sin consumir, el nuevo manda.
  static void solicitar(String? pantalla, [Map<String, dynamic> extra = const {}]) {
    final id = (pantalla ?? '').trim();
    if (id.isEmpty) return;
    final destino = DestinoNotificacion(id, extra);
    _pendiente = destino;
    if (!_controller.isClosed) _controller.add(destino);
    debugPrint('🧭 Destino encolado: $destino');
  }

  /// Marca el destino pendiente como consumido (get-and-clear).
  static DestinoNotificacion? consumirPendiente() {
    final d = _pendiente;
    _pendiente = null;
    return d;
  }

  /// Resuelve la pantalla a la que debe abrir una notificación.
  ///
  /// Prioridad:
  ///  1. `extra['screen']` si viene explícito (así lo define el emisor).
  ///  2. Mapa por defecto según el `tipo`, sensible al rol del receptor.
  ///
  /// El rol importa en `solicitud_direccion`: la misma notificación significa
  /// cosas distintas según quién la recibe. Al admin le sirve verlas en
  /// Comunicación (la bandeja de solicitudes); al auditor le sirve entrar
  /// directo a la bandeja de Direcciones Nuevas, que es donde tiene que
  /// trabajar.
  static String? resolverPantalla(
    String tipo,
    Map<String, dynamic> data, [
    Map<String, dynamic>? usuarioData,
  ]) {
    final extra = data['extra'];
    if (extra is Map && extra['screen'] is String) {
      final s = (extra['screen'] as String).trim();
      if (s.isNotEmpty) return s;
    }
    final top = (data['screen'] as String?)?.trim();
    if (top != null && top.isNotEmpty) return top;

    final u = usuarioData;
    final esAuditor = u?['es_auditor'] == true;
    final esTerritorios = u?['es_admin_territorios'] == true;

    return switch (tipo) {
      'solicitud_acceso' => Pantallas.usuariosPendientes,
      'solicitud_direccion' => (esAuditor || esTerritorios)
          ? Pantallas.auditorDireccionesNuevas
          : Pantallas.solicitudesDirecciones,
      'nueva_direccion_enviada' => Pantallas.auditorDireccionesNuevas,
      'tarjeta_tomada' => Pantallas.misTarjetas,
      'devolucion_tarjeta' => Pantallas.misTarjetas,
      'aviso_devolucion' => Pantallas.misTarjetas,
      'motivacional' => null, // Se maneja aparte: ventana animada.
      'anuncio' => null, // Se maneja aparte: diálogo informativo.
      'sugerencia' => Pantallas.sugerencias,
      _ => null,
    };
  }

  /// ¿El usuario conectado tiene permiso para ver esa pantalla?
  ///
  /// Se evalúa contra sus roles para que tocar una notificación de una
  /// pantalla que no le corresponde no lo deje en un limbo.
  static bool permitido(String pantalla, Map<String, dynamic> usuarioData) {
    final esAdmin = usuarioData['es_admin'] == true;
    final esTerritorios = usuarioData['es_admin_territorios'] == true;
    final esAuditor = usuarioData['es_auditor'] == true;
    final esPublicador = usuarioData['es_publicador'] == true;
    final esConductor = usuarioData['es_conductor'] == true;

    return switch (pantalla) {
      Pantallas.usuariosPendientes => esAdmin,
      Pantallas.solicitudesDirecciones => esAdmin || esTerritorios,
      Pantallas.auditorDireccionesNuevas => esAdmin || esAuditor || esTerritorios,
      Pantallas.misTarjetas => esPublicador || esConductor,
      Pantallas.sugerencias => esAdmin || esTerritorios,
      _ => true,
    };
  }

  /// Descripción legible de la acción, para el SnackBar de confirmación.
  static String descripcion(String pantalla) => switch (pantalla) {
        Pantallas.usuariosPendientes => 'Revisa los usuarios pendientes de aprobación',
        Pantallas.solicitudesDirecciones => 'Revisa las direcciones enviadas',
        Pantallas.auditorDireccionesNuevas => 'Revisa las direcciones nuevas por auditar',
        Pantallas.misTarjetas => 'Revisa tus tarjetas',
        Pantallas.sugerencias => 'Revisa las sugerencias recibidas',
        _ => 'Abrir',
      };
}
