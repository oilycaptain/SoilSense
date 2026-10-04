import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'internet_probe_stub.dart'
    if (dart.library.io) 'internet_probe_io.dart';

class NetworkStatusService extends ChangeNotifier with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  bool _isOnline = true;
  bool _initialized = false;
  int _checkGeneration = 0;

  bool get isOnline => _isOnline;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_subscription != null) return;

    WidgetsBinding.instance.addObserver(this);
    try {
      await _updateStatus(await _connectivity.checkConnectivity());
    } catch (error) {
      debugPrint('Network status check failed: $error');
      _setStatus(false);
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      (result) => unawaited(_updateStatus(result)),
      onError: (Object error) {
        debugPrint('Network status stream failed: $error');
        _setStatus(false);
      },
    );
  }

  Future<void> refresh() async {
    try {
      await _updateStatus(await _connectivity.checkConnectivity());
    } catch (error) {
      debugPrint('Network refresh failed: $error');
      _setStatus(false);
    }
  }

  Future<void> _updateStatus(ConnectivityResult result) async {
    final generation = ++_checkGeneration;
    var nextValue = false;
    if (result != ConnectivityResult.none) {
      nextValue = await hasInternetAccess();
    }
    if (generation != _checkGeneration) return;
    _setStatus(nextValue);
  }

  void _setStatus(bool nextValue) {
    final changed = nextValue != _isOnline || !_initialized;
    _isOnline = nextValue;
    _initialized = true;
    if (changed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
