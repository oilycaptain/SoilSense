import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../models/soil_data.dart';
import 'device_status_service.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class NotificationService {
  NotificationService({
    required GlobalKey<NavigatorState> navigatorKey,
    required FirestoreService firestoreService,
    required DeviceStatusService deviceStatusService,
  })  : _navigatorKey = navigatorKey,
        _firestoreService = firestoreService,
        _deviceStatusService = deviceStatusService;

  static const String _channelId = 'soilsense_live_updates';
  static const String _channelName = 'SoilSense Live Updates';
  static const String _channelDescription =
      'Sensor readings, device status, and important SoilSense updates.';

  final GlobalKey<NavigatorState> _navigatorKey;
  final FirestoreService _firestoreService;
  final DeviceStatusService _deviceStatusService;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<SoilData?>? _readingSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _assignmentSubscription;

  String? _registeredUserId;
  String? _registeredToken;
  String? _monitoredUserId;
  String? _lastReadingKey;
  bool _readingBaselineReady = false;
  bool? _lastOwnerState;
  bool? _lastDeviceOnline;
  bool _currentUserIsOwner = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _initializeLocalNotifications();
    } catch (error) {
      debugPrint('Local notification setup failed: $error');
    }

    try {
      await _messaging.setAutoInitEnabled(true);
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (error) {
      debugPrint('Notification permission setup failed: $error');
    }

    _deviceStatusService.addListener(_handleDeviceStatusChanged);

    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen(
      (user) {
        unawaited(_handleAuthChanged(user));
      },
    );
    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
      onError: (Object error) {
        debugPrint('Notification token refresh failed: $error');
      },
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_showRemoteMessage(message)),
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => _openNotificationsScreen(),
    );

    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _openNotificationsScreen();
      }
    } catch (error) {
      debugPrint('Initial notification lookup failed: $error');
    }

  }

  Future<void> _initializeLocalNotifications() async {
    final initializationSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (_) => _openNotificationsScreen(),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
      await android?.requestNotificationsPermission();
    }
  }

  Future<void> _handleAuthChanged(User? user) async {
    await _readingSubscription?.cancel();
    await _assignmentSubscription?.cancel();
    _readingSubscription = null;
    _assignmentSubscription = null;
    _monitoredUserId = user?.uid;
    _lastReadingKey = null;
    _readingBaselineReady = false;
    _lastOwnerState = null;
    _lastDeviceOnline = null;
    _currentUserIsOwner = false;

    if (user == null || !user.emailVerified) {
      await _removePreviousRegistration();
      return;
    }

    await syncToken();
    _startAssignmentMonitor(user.uid);
    _startReadingMonitor(user.uid);
  }

  void _startAssignmentMonitor(String userId) {
    _assignmentSubscription = _firestore
        .collection('system')
        .doc('device_assignment')
        .snapshots()
        .listen(
      (snapshot) {
        if (_monitoredUserId != userId) return;
        final isOwner = snapshot.data()?['currentOwnerUid'] == userId;
        final previous = _lastOwnerState;
        _lastOwnerState = isOwner;
        _currentUserIsOwner = isOwner;

        if (previous == null) return;

        if (!previous && isOwner) {
          _lastReadingKey = null;
          _readingBaselineReady = false;
          unawaited(_emitAlert(
            userId: userId,
            title: 'SoilSense device assigned',
            message: 'This account is now the current SoilSense device owner.',
            type: 'ownership_assigned',
            severity: 'low',
            category: 'Access',
            eventKey: 'owner_assigned_${_assignmentEventKey(snapshot)}',
          ));
        } else if (previous && !isOwner) {
          _lastReadingKey = null;
          _readingBaselineReady = false;
          unawaited(_emitAlert(
            userId: userId,
            title: 'SoilSense access changed',
            message: 'The SoilSense device is no longer assigned to this account.',
            type: 'ownership_removed',
            severity: 'low',
            category: 'Access',
            eventKey: 'owner_removed_${_assignmentEventKey(snapshot)}',
          ));
        }
      },
      onError: (Object error) {
        debugPrint('Notification ownership monitor failed: $error');
      },
    );
  }

  void _startReadingMonitor(String userId) {
    _readingSubscription = _firestoreService.watchLatestSoilReading().listen(
      (reading) {
        if (_monitoredUserId != userId || reading == null) return;
        final key = '${reading.id}|${reading.timestamp.millisecondsSinceEpoch}';

        if (!_readingBaselineReady) {
          _readingBaselineReady = true;
          _lastReadingKey = key;
          return;
        }
        if (_lastReadingKey == key) return;
        _lastReadingKey = key;

        unawaited(_notifyForReading(userId, reading));
      },
      onError: (Object error) {
        debugPrint('Notification reading monitor failed: $error');
      },
    );
  }

  Future<void> _notifyForReading(String userId, SoilData reading) async {
    final issues = <String>[];
    if (reading.nitrogen < 40 || reading.nitrogen > 100) {
      issues.add('nitrogen');
    }
    if (reading.phosphorus < 50 || reading.phosphorus > 120) {
      issues.add('phosphorus');
    }
    if (reading.potassium < 100 || reading.potassium > 300) {
      issues.add('potassium');
    }
    if (reading.ph < 5.5 || reading.ph > 7.5) {
      issues.add('pH');
    }
    if (reading.moisture < 40 || reading.moisture > 90) {
      issues.add('moisture');
    }

    if (issues.isEmpty) {
      await _emitAlert(
        userId: userId,
        title: 'New soil reading received',
        message: 'The latest SoilSense scan was uploaded successfully.',
        type: 'sensor_update',
        severity: 'low',
        category: 'Soil Reading',
        eventKey: 'reading_${reading.id}',
      );
      return;
    }

    final issueText = _naturalList(issues);
    await _emitAlert(
      userId: userId,
      title: 'Soil reading needs attention',
      message: 'New scan uploaded. Check $issueText in SoilSense.',
      type: 'soil_attention',
      severity: 'medium',
      category: 'Soil Reading',
      eventKey: 'reading_${reading.id}',
    );
  }

  void _handleDeviceStatusChanged() {
    final userId = _monitoredUserId;
    if (userId == null || !_currentUserIsOwner) {
      _lastDeviceOnline = null;
      return;
    }

    if (!_deviceStatusService.isInternetOnline ||
        _deviceStatusService.isSetupMode) {
      return;
    }

    final online = _deviceStatusService.isDeviceOnline;
    final previous = _lastDeviceOnline;
    _lastDeviceOnline = online;
    if (previous == null || previous == online) return;

    if (online) {
      unawaited(_emitAlert(
        userId: userId,
        title: 'SoilSense device online',
        message: 'The IoT device reconnected and is ready for a new scan.',
        type: 'device_online',
        severity: 'low',
        category: 'Device',
        eventKey: 'device_online_${_deviceStatusService.deviceLastSeen?.millisecondsSinceEpoch ?? 0}',
      ));
    } else {
      unawaited(_emitAlert(
        userId: userId,
        title: 'SoilSense device offline',
        message: 'The device heartbeat stopped. Check its power or Wi-Fi connection.',
        type: 'device_offline',
        severity: 'medium',
        category: 'Device',
        eventKey: 'device_offline_${_deviceStatusService.deviceLastSeen?.millisecondsSinceEpoch ?? 0}',
      ));
    }
  }

  Future<void> _emitAlert({
    required String userId,
    required String title,
    required String message,
    required String type,
    required String severity,
    required String category,
    String? eventKey,
  }) async {
    if (_monitoredUserId != userId || FirebaseAuth.instance.currentUser?.uid != userId) {
      return;
    }

    final rawKey = eventKey ?? '${type}_${DateTime.now().millisecondsSinceEpoch}';
    final safeKey = rawKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final alertId = '${userId}_${safeKey.length > 180 ? safeKey.substring(0, 180) : safeKey}';

    try {
      await _firestore.collection('alerts').doc(alertId).set({
        'title': title,
        'type': type,
        'severity': severity,
        'category': category,
        'message': message,
        'currentValue': 0.0,
        'optimalRange': '',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': userId,
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Could not save SoilSense notification: $error');
    }

    // Keep notifications in the Android/iOS notification area and the
    // in-app Notifications screen. Do not show a second floating SnackBar.
    await _showSystemNotification(title, message);
  }

  String _assignmentEventKey(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final updatedAt = snapshot.data()?['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.millisecondsSinceEpoch.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> _showSystemNotification(String title, String body) async {
    if (kIsWeb) return;
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'notifications',
      );
    } catch (error) {
      debugPrint('Could not show local notification: $error');
    }
  }

  Future<void> _showRemoteMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'SoilSense';
    final body = message.notification?.body ??
        message.data['message']?.toString() ??
        'A new SoilSense update is available.';
    await _showSystemNotification(title, body);
  }

  String _naturalList(List<String> values) {
    if (values.isEmpty) return 'the soil values';
    if (values.length == 1) return values.first;
    if (values.length == 2) return '${values[0]} and ${values[1]}';
    return '${values.sublist(0, values.length - 1).join(', ')}, and ${values.last}';
  }

  Future<void> unregisterCurrentToken() async {
    await _removePreviousRegistration();
  }

  Future<void> syncToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) {
      await _removePreviousRegistration();
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (error) {
      debugPrint('Could not obtain notification token: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return;

    if (_registeredUserId == user.uid && _registeredToken == token) return;
    await _removePreviousRegistration();

    try {
      final tokenId = token.replaceAll('/', '_');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('push_tokens')
          .doc(tokenId)
          .set({
        'token': token,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _registeredUserId = user.uid;
      _registeredToken = token;
    } catch (error) {
      debugPrint('Could not save notification token: $error');
    }
  }

  Future<void> _removePreviousRegistration() async {
    final userId = _registeredUserId;
    final token = _registeredToken;
    _registeredUserId = null;
    _registeredToken = null;

    if (userId == null || token == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('push_tokens')
          .doc(token.replaceAll('/', '_'))
          .delete();
    } catch (error) {
      debugPrint('Could not remove old notification token: $error');
    }
  }

  void _openNotificationsScreen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushNamed('/notifications');
    });
  }

  void dispose() {
    _deviceStatusService.removeListener(_handleDeviceStatusChanged);
    _authSubscription?.cancel();
    _tokenSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    _readingSubscription?.cancel();
    _assignmentSubscription?.cancel();
  }
}
