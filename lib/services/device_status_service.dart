import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/soil_data.dart';
import 'firestore_service.dart';
import 'network_status_service.dart';

class DeviceStatusService extends ChangeNotifier {
  DeviceStatusService({
    required FirestoreService firestoreService,
    required NetworkStatusService networkStatusService,
  })  : _firestoreService = firestoreService,
        _networkStatusService = networkStatusService {
    _networkStatusService.addListener(_handleNetworkChange);
    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen(
      _handleAuthChange,
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  static const Duration offlineAfter = Duration(seconds: 60);

  final FirestoreService _firestoreService;
  final NetworkStatusService _networkStatusService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<SoilData?>? _readingSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  Timer? _clockTimer;

  SoilData? _latestReading;
  bool _isLoading = true;
  Object? _error;

  bool _reportedOnline = false;
  bool _setupMode = false;
  DateTime? _deviceLastSeen;
  int? _rssi;
  String? _hardwareFingerprint;
  bool _isScanning = false;
  int _scanDurationSeconds = FirestoreService.defaultScanDurationSeconds;

  SoilData? get latestReading => _latestReading;
  SoilData? get activeReading => isDeviceOnline ? _latestReading : null;
  bool get hasDisplayReading => _latestReading != null;
  bool get hasLiveReading => isDeviceOnline && _latestReading != null;
  SoilData? get displayReading => _latestReading;
  bool get isLoading => _networkStatusService.isOnline && _isLoading;
  Object? get error => _error;
  bool get isInternetOnline => _networkStatusService.isOnline;
  bool get hasLastKnownData => _latestReading != null;
  bool get hasActiveReading => activeReading != null;
  DateTime? get lastReadingAt => _latestReading?.timestamp;
  DateTime? get deviceLastSeen => _deviceLastSeen;
  bool get isSetupMode => _setupMode;
  int? get rssi => _rssi;
  String? get hardwareFingerprint => _hardwareFingerprint;
  bool get isScanning => _isScanning && isDeviceOnline;
  int get scanDurationSeconds => _scanDurationSeconds;

  bool get isDeviceStale => _deviceLastSeen != null && !isDeviceOnline;

  bool get isDeviceOnline {
    if (!_networkStatusService.isOnline || !_reportedOnline || _setupMode) {
      return false;
    }

    final lastSeen = _deviceLastSeen;
    if (lastSeen == null) return false;

    final age = DateTime.now().difference(lastSeen);
    return age <= offlineAfter;
  }

  String get unavailableMessage {
    if (!_networkStatusService.isOnline) {
      return _latestReading == null ? 'No internet connection. No saved soil reading is available yet.' : 'No internet connection. Showing your last saved soil reading; it is not a live value.';
    }
    if (_setupMode) {
      return _latestReading == null ? 'The SoilSense device is in Wi-Fi Setup Mode. No saved soil reading is available yet.' : 'The SoilSense device is in Wi-Fi Setup Mode. Showing your last saved soil reading.';
    }
    if (_deviceLastSeen == null) {
      return _latestReading == null ? 'The SoilSense device is unavailable and no saved soil reading is available yet.' : 'The SoilSense device is unavailable. Showing your last saved soil reading.';
    }
    return _latestReading == null ? 'The SoilSense device is offline and no saved soil reading is available yet.' : 'The SoilSense device is offline. Your last saved soil reading remains available for reference.';
  }

  void _handleAuthChange(User? user) {
    _readingSubscription?.cancel();
    _statusSubscription?.cancel();
    _readingSubscription = null;
    _statusSubscription = null;
    _latestReading = null;
    _reportedOnline = false;
    _setupMode = false;
    _deviceLastSeen = null;
    _rssi = null;
    _hardwareFingerprint = null;
    _isScanning = false;
    _scanDurationSeconds = FirestoreService.defaultScanDurationSeconds;
    _error = null;

    if (user == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _statusSubscription = FirebaseFirestore.instance
        .collection('system')
        .doc('device_status')
        .snapshots()
        .listen(
      (snapshot) {
        final data = snapshot.data();
        final timestamp = data?['lastSeen'];

        _reportedOnline = data?['online'] == true;
        _setupMode = data?['setupMode'] == true;
        _deviceLastSeen = timestamp is Timestamp ? timestamp.toDate() : null;
        final rssiValue = data?['rssi'];
        _rssi = rssiValue is int ? rssiValue : null;
        final fingerprintValue = data?['hardwareFingerprint'];
        _hardwareFingerprint = fingerprintValue is String ? fingerprintValue : null;
        _isScanning = data?['scanning'] == true;
        final scanDurationValue = data?['scanDurationSeconds'];
        _scanDurationSeconds = scanDurationValue is num
            ? scanDurationValue.toInt().clamp(
                FirestoreService.minScanDurationSeconds,
                FirestoreService.maxScanDurationSeconds,
              ).toInt()
            : FirestoreService.defaultScanDurationSeconds;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Device heartbeat stream failed: $error');
        _reportedOnline = false;
        _setupMode = false;
        _deviceLastSeen = null;
        _isScanning = false;
        _isLoading = false;
        _error = error;
        notifyListeners();
      },
    );

    _readingSubscription = _firestoreService.watchLatestSoilReading().listen(
      (reading) {
        _latestReading = reading;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Device reading stream failed: $error');
        _isLoading = false;
        _error = error;
        notifyListeners();
      },
    );
  }

  void _handleNetworkChange() {
    notifyListeners();
    if (_networkStatusService.isOnline && FirebaseAuth.instance.currentUser != null) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (FirebaseAuth.instance.currentUser == null) return;

    await _networkStatusService.refresh();
    if (!_networkStatusService.isOnline) {
      notifyListeners();
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.getSoilReadings(limit: 1, includeClearedHistory: true),
        FirebaseFirestore.instance.collection('system').doc('device_status').get(),
      ]);

      final readings = results[0] as List<SoilData>;
      final statusSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final status = statusSnapshot.data();
      final timestamp = status?['lastSeen'];

      _latestReading = readings.isEmpty ? null : readings.first;
      _reportedOnline = status?['online'] == true;
      _setupMode = status?['setupMode'] == true;
      _deviceLastSeen = timestamp is Timestamp ? timestamp.toDate() : null;
      final rssiValue = status?['rssi'];
      _rssi = rssiValue is int ? rssiValue : null;
      final fingerprintValue = status?['hardwareFingerprint'];
      _hardwareFingerprint = fingerprintValue is String ? fingerprintValue : null;
      _isScanning = status?['scanning'] == true;
      final scanDurationValue = status?['scanDurationSeconds'];
      _scanDurationSeconds = scanDurationValue is num
          ? scanDurationValue.toInt().clamp(
              FirestoreService.minScanDurationSeconds,
              FirestoreService.maxScanDurationSeconds,
            ).toInt()
          : FirestoreService.defaultScanDurationSeconds;
      _error = null;
    } catch (error) {
      _error = error;
      debugPrint('Device status refresh failed: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _networkStatusService.removeListener(_handleNetworkChange);
    _authSubscription?.cancel();
    _readingSubscription?.cancel();
    _statusSubscription?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }
}
