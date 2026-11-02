import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_network_status_stub.dart'
    if (dart.library.js_interop) 'web_network_status_web.dart' as web_network;

/// Estado visible del modo sin conexión y de la cola nativa de Firestore.
///
/// La persistencia de Firestore es la cola durable: esta clase solo presenta el
/// estado y espera a que Firestore confirme la cola al recuperar conexión.
class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _firestoreProbeSubscription;
  StreamSubscription<bool>? _webConnectivitySubscription;
  Timer? _webConnectivityPoll;

  bool _started = false;
  bool _networkAvailable = true;
  bool? _serverAvailable;
  bool _syncing = false;
  int _syncRun = 0;

  bool get isOffline => !_networkAvailable || _serverAvailable == false;
  bool get isSyncing => _syncing && !isOffline;

  void start() {
    if (_started) return;
    _started = true;
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    if (kIsWeb) {
      _webConnectivitySubscription = web_network.onlineChanges.listen(
        (online) => _onConnectivityChanged([
          online ? ConnectivityResult.wifi : ConnectivityResult.none,
        ]),
      );
    }
    unawaited(_checkConnectivity());
    // Algunos navegadores no emiten `online`/`offline` de manera consistente.
    // navigator.onLine se consulta periódicamente como respaldo para web.
    if (kIsWeb) {
      _webConnectivityPoll = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_checkConnectivity()),
      );
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      if (kIsWeb) {
        _onConnectivityChanged([
          web_network.isOnline
              ? ConnectivityResult.wifi
              : ConnectivityResult.none,
        ]);
        return;
      }
      final results = await _connectivity.checkConnectivity();
      _onConnectivityChanged(results);
    } catch (error) {
      debugPrint('No se pudo comprobar la conectividad: $error');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final available =
        results.any((result) => result != ConnectivityResult.none);
    if (available == _networkAvailable) return;
    final wasOffline = isOffline;
    _networkAvailable = available;
    if (!available) {
      _setSyncing(false);
    } else if (wasOffline) {
      _waitForPendingWrites();
    }
    notifyListeners();
  }

  /// El listener de un documento de configuración permite distinguir
  /// "hay Wi-Fi/datos" de "Firestore realmente está sincronizado".
  void observeFirestore() {
    _firestoreProbeSubscription?.cancel();
    _firestoreProbeSubscription = FirebaseFirestore.instance
        .collection('configuracion')
        .doc('progreso_mensual')
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        final available = !snapshot.metadata.isFromCache;
        final wasOffline = isOffline;
        _serverAvailable = available;
        if (available && wasOffline) _waitForPendingWrites();
        notifyListeners();
      },
      onError: (Object error) {
        // Puede fallar antes del login. Connectivity sigue proporcionando el
        // estado de red; un error de permisos no se presenta como offline.
        debugPrint('Sonda de sincronización Firestore: $error');
      },
    );
  }

  void stopObservingFirestore() {
    _firestoreProbeSubscription?.cancel();
    _firestoreProbeSubscription = null;
    _serverAvailable = null;
    notifyListeners();
  }

  void _waitForPendingWrites() {
    final run = ++_syncRun;
    _setSyncing(true);
    unawaited(() async {
      try {
        await FirebaseFirestore.instance
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 45));
      } catch (error) {
        debugPrint('La cola Firestore sigue pendiente: $error');
      } finally {
        if (run == _syncRun) _setSyncing(false);
      }
    }());
  }

  void _setSyncing(bool value) {
    if (_syncing == value) return;
    _syncing = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _webConnectivityPoll?.cancel();
    _webConnectivitySubscription?.cancel();
    _connectivitySubscription?.cancel();
    _firestoreProbeSubscription?.cancel();
    super.dispose();
  }
}

class OfflineStatusBanner extends StatelessWidget {
  const OfflineStatusBanner({
    required this.offline,
    required this.syncing,
    super.key,
  });

  final bool offline;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    if (!offline && !syncing) return const SizedBox.shrink();

    final color = offline ? const Color(0xFF8D3B00) : const Color(0xFF1B5E20);
    final message = offline
        ? 'Sin conexión. Los cambios se guardan en este dispositivo y se sincronizarán al reconectar.'
        : 'Conexión recuperada. Sincronizando cambios pendientes…';

    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.sync,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              if (syncing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
