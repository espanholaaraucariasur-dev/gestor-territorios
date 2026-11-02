import 'dart:async';

import 'package:web/web.dart' as web;

bool get isOnline => web.window.navigator.onLine;

Stream<bool> get onlineChanges {
  final controller = StreamController<bool>();
  final online = const web.EventStreamProvider<web.Event>('online')
      .forTarget(web.window)
      .listen((_) => controller.add(true));
  final offline = const web.EventStreamProvider<web.Event>('offline')
      .forTarget(web.window)
      .listen((_) => controller.add(false));
  controller.onCancel = () {
    online.cancel();
    offline.cancel();
  };
  return controller.stream;
}
