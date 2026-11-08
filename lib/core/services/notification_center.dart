import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Suscripción única a la colección `notificaciones`, compartida por la
/// campanilla, el panel y el cajón del menú.
///
/// Antes cada `StreamBuilder` abría su propia suscripción (y se recreaba en
/// cada `build`), lo que multiplicaba lecturas y hacía parpadear el contador.
class NotificationCenter {
  NotificationCenter._();

  static final NotificationCenter instance = NotificationCenter._();

  final _db = FirebaseFirestore.instance;
  final _controller =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  QuerySnapshot<Map<String, dynamic>>? _ultimo;
  Object? _ultimoError;

  void _asegurar() {
    if (_sub != null) return;
    _sub = _db.collection('notificaciones').snapshots().listen(
      (snap) {
        _ultimo = snap;
        _ultimoError = null;
        if (!_controller.isClosed) _controller.add(snap);
      },
      onError: (Object error, StackTrace stack) {
        // Se guarda el error para que quien se suscriba después también lo vea
        // y se descarta la suscripción para poder reintentar en la próxima.
        _ultimoError = error;
        debugPrint('NotificationCenter: $error\n$stack');
        if (!_controller.isClosed) _controller.addError(error, stack);
        _descartarSuscripcion();
      },
      onDone: _descartarSuscripcion,
    );
  }

  void _descartarSuscripcion() {
    final sub = _sub;
    if (sub == null) return;
    _sub = null;
    sub.cancel();
  }

  /// Emite el último snapshot conocido al suscribirse y luego comparte las
  /// actualizaciones en tiempo real.
  Stream<QuerySnapshot<Map<String, dynamic>>> get snapshots async* {
    _asegurar();
    if (_ultimo != null) yield _ultimo!;
    if (_ultimoError != null && _ultimo == null) {
      yield* Stream<QuerySnapshot<Map<String, dynamic>>>.error(_ultimoError!);
      return;
    }
    yield* _controller.stream;
  }

  /// Descarta la suscripción actual (p. ej. al cerrar sesión). La próxima
  /// lectura vuelve a abrirla con las credenciales nuevas.
  Future<void> reiniciar() async {
    final sub = _sub;
    _sub = null;
    _ultimo = null;
    _ultimoError = null;
    await sub?.cancel();
  }
}
