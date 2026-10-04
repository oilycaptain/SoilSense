import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/soil_data.dart';
import 'app_settings_service.dart';
import 'decision_support_service.dart';
import 'device_status_service.dart';
import 'firestore_service.dart';
import 'gemini_ai_service.dart';

/// Coordinates SoilSense AI automatically after a soil scan finishes.
///
/// A Firestore soil-reading document is treated as the completed scan output.
/// If the same document is updated several times while a scan is finishing,
/// processing is debounced so Gemini runs only after the values stop changing.
/// The resulting AI advice is cached by GeminiAiService and reused by Home,
/// Crops, Smart Crop Planning, and the report-generation workflow.
class AutomaticAiService extends ChangeNotifier {
  AutomaticAiService({
    required FirestoreService firestoreService,
    required DeviceStatusService deviceStatusService,
    required AppSettingsService appSettingsService,
  })  : _firestoreService = firestoreService,
        _deviceStatusService = deviceStatusService,
        _appSettingsService = appSettingsService {
    _lastLanguageCode = _appSettingsService.languageCode;
    _deviceStatusService.addListener(_handleEligibilityChanged);
    _appSettingsService.addListener(_handleLanguageChanged);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
      onError: (Object error) =>
          debugPrint('Automatic AI auth listener failed: $error'),
    );
    _handleAuthChanged(FirebaseAuth.instance.currentUser);
  }

  final FirestoreService _firestoreService;
  final DeviceStatusService _deviceStatusService;
  final AppSettingsService _appSettingsService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<SoilData?>? _readingSubscription;
  StreamSubscription<bool>? _ownerSubscription;
  Timer? _readingDebounce;
  Timer? _quotaRetryTimer;

  SoilData? _reading;
  GeminiAiResult? _result;
  GeminiAiResult? _lastReadyResult;
  Map<String, dynamic>? _analysis;
  Map<String, dynamic>? _recommendations;
  Map<String, dynamic>? _plan;
  String? _selectedCrop;
  String? _pendingSignature;
  String? _lastProcessedSignature;
  bool _isProcessing = false;
  bool _isCurrentOwner = false;
  bool _deviceOnline = false;
  int _transientRetryCount = 0;
  String _lastLanguageCode = 'en';

  static const Duration _freshReadingWindow = Duration(minutes: 10);

  SoilData? get reading => _reading;
  GeminiAiResult? get result => _result;
  GeminiAiResult? get lastReadyResult => _lastReadyResult;
  Map<String, dynamic>? get analysis => _analysis;
  Map<String, dynamic>? get recommendations => _recommendations;
  Map<String, dynamic>? get plan => _plan;
  String? get selectedCrop => _selectedCrop;
  bool get isProcessing => _isProcessing;
  bool get isCurrentOwner => _isCurrentOwner;
  bool get isDeviceOnline => _deviceOnline;

  bool get hasFreshReading {
    final reading = _reading;
    if (reading == null) return false;
    final age = DateTime.now().difference(reading.timestamp);
    return age <= _freshReadingWindow;
  }

  bool get canRunAi =>
      FirebaseAuth.instance.currentUser != null && _reading != null;

  bool get isUsingSavedReading =>
      _reading != null && (!_isCurrentOwner || !_deviceOnline || !hasFreshReading);

  String get aiReadingContext {
    if (_reading == null) {
      return 'Complete a soil scan first so AI has soil data to analyze.';
    }
    if (!_isCurrentOwner) {
      return "AI is using this account's latest saved private soil reading. New device scans belong only to the current owner.";
    }
    if (!_deviceOnline) {
      return 'AI is using your latest saved private soil reading while the SoilSense device is offline.';
    }
    if (!hasFreshReading) {
      return 'AI is using your latest saved private soil reading.';
    }
    return 'AI is using your latest completed private soil reading.';
  }

  String get pausedReason {
    if (FirebaseAuth.instance.currentUser == null) {
      return 'Sign in to use AI decision support.';
    }
    if (_reading == null) {
      return 'Complete a soil scan first so AI has soil data to analyze.';
    }
    return '';
  }

  bool get hasAiAdvice => _result?.isSuccess == true;

  Map<String, dynamic>? get advice => hasAiAdvice ? _result!.advice : null;

  /// The most recent successful AI response. The UI may show this only while
  /// a newer Gemini request is loading, so users do not see completed advice
  /// disappear and reappear on every scan. It is cleared on sign-out/reset.
  Map<String, dynamic>? get lastReadyAdvice => _lastReadyResult?.advice;

  void _handleAuthChanged(User? user) {
    _readingDebounce?.cancel();
    _quotaRetryTimer?.cancel();
    _readingSubscription?.cancel();
    _ownerSubscription?.cancel();
    _readingSubscription = null;
    _ownerSubscription = null;
    _isCurrentOwner = false;
    _deviceOnline = _deviceStatusService.isDeviceOnline;

    if (user == null) {
      _reset();
      return;
    }

    _ownerSubscription = _firestoreService.watchOwnerAccess().listen(
      (isOwner) {
        _isCurrentOwner = isOwner;
        _handleEligibilityChanged();
      },
      onError: (Object error) {
        debugPrint('Automatic AI owner listener failed: $error');
        _isCurrentOwner = false;
        _handleEligibilityChanged();
      },
    );

    _readingSubscription = _firestoreService.watchLatestSoilReading().listen(
      _handleReading,
      onError: (Object error) {
        debugPrint('Automatic AI reading listener failed: $error');
      },
    );
  }

  void _handleLanguageChanged() {
    final code = _appSettingsService.languageCode;
    if (code == _lastLanguageCode) return;
    _lastLanguageCode = code;
    GeminiAiService.clearCache();
    _lastProcessedSignature = null;

    final reading = _reading;
    if (reading != null && canRunAi) {
      _pendingSignature = _signature(reading);
      _readingDebounce?.cancel();
      _readingDebounce = Timer(const Duration(milliseconds: 250), () {
        final current = _reading;
        if (current != null && canRunAi) {
          unawaited(_processCompletedReading(current));
        }
      });
    }
    notifyListeners();
  }

  void _handleEligibilityChanged() {
    _deviceOnline = _deviceStatusService.isDeviceOnline;

    // Device heartbeat/online-state updates are frequent and are only UI
    // context for AI. They must never restart Gemini for an already-attempted
    // soil reading. New readings, language changes, and the controlled retry
    // timers below are the only events allowed to start AI processing.
    if (!canRunAi) {
      _readingDebounce?.cancel();
      _quotaRetryTimer?.cancel();
      if (_result?.status == GeminiAiStatus.loading) {
        _result = GeminiAiResult(
          status: GeminiAiStatus.idle,
          message: pausedReason,
        );
      }
    }
    notifyListeners();
  }

  void _handleReading(SoilData? reading) {
    if (reading == null) {
      _readingDebounce?.cancel();
      _reading = null;
      _pendingSignature = null;
      _isProcessing = false;
      _lastReadyResult = null;
      if (_result?.status == GeminiAiStatus.loading) {
        _result = null;
      }
      notifyListeners();
      return;
    }

    final previousPendingSignature = _pendingSignature;
    _reading = reading;
    final signature = _signature(reading);
    final samePendingReading = previousPendingSignature == signature;
    if (_pendingSignature != null && _pendingSignature != signature) {
      _transientRetryCount = 0;
    }
    _pendingSignature = signature;

    // Firestore can re-emit the same latest-reading snapshot (for example
    // because of metadata/cache synchronization). Treat those emissions as
    // the same completed scan instead of flipping AI back to loading.
    if (samePendingReading &&
        (_isProcessing ||
            (_readingDebounce?.isActive ?? false) ||
            _lastProcessedSignature == signature)) {
      notifyListeners();
      return;
    }

    if (_lastProcessedSignature == signature) {
      notifyListeners();
      return;
    }

    _readingDebounce?.cancel();

    if (!canRunAi) {
      if (_result?.status == GeminiAiStatus.loading) {
        _result = GeminiAiResult(
          status: GeminiAiStatus.idle,
          message: pausedReason,
        );
      }
      notifyListeners();
      return;
    }

    // Clear any AI text from the previous soil sample immediately so the UI
    // never shows stale crop/fertilizer guidance during the debounce window.
    _result = const GeminiAiResult(
      status: GeminiAiStatus.loading,
      message: 'AI is preparing guidance for the new completed soil reading.',
    );
    notifyListeners();

    _readingDebounce = Timer(const Duration(milliseconds: 900), () {
      final latest = _reading;
      if (latest == null || !canRunAi) return;
      if (_pendingSignature != _signature(latest)) return;
      unawaited(_processCompletedReading(latest));
    });

    notifyListeners();
  }

  Future<void> _processCompletedReading(SoilData reading) async {
    final signature = _signature(reading);
    if (_isProcessing) return;
    if (!canRunAi) return;
    if (_pendingSignature != signature) return;
    if (_lastProcessedSignature == signature && _result?.isSuccess == true) {
      return;
    }

    final isBackgroundRetry =
        _lastProcessedSignature == signature &&
        _result != null &&
        _result?.status != GeminiAiStatus.loading;

    _isProcessing = true;
    if (!isBackgroundRetry) {
      _result = const GeminiAiResult(
        status: GeminiAiStatus.loading,
        message: 'AI is analyzing the completed soil reading.',
      );
    }
    notifyListeners();

    try {
      final soil = _soilMap(reading);
      final analysis = await DecisionSupportService.analyzeSoil(soil);
      final recommendations =
          await DecisionSupportService.getCropRecommendations(soil);
      final best = _asMap(recommendations['best_crop']);
      final crop = best.isEmpty ? null : (best['name'] ?? '').toString().trim();
      final plan = crop == null || crop.isEmpty
          ? null
          : await DecisionSupportService.getSmartPlanning(
              soilData: soil,
              crop: crop,
            );

      // AI may explain fertilizer/soil-management actions, but crop names are
      // constrained to crops that SoilSense already classified as suitable.
      // Not Recommended crops are never promoted by AI.
      final topCrops = <String>[];
      for (final item in <Map<String, dynamic>>[
        ..._asList(recommendations['highly_suitable']),
        ..._asList(recommendations['moderately_suitable']),
      ]) {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isNotEmpty && !topCrops.contains(name)) topCrops.add(name);
        if (topCrops.length >= 5) break;
      }

      GeminiAiResult result;
      final existingReport = await _firestoreService.getReportForReading(
        reading.id,
        readingFingerprint: signature,
      );
      final existingAi = _asMap(existingReport?['ai']);
      final hasCurrentAiShape =
          (existingAi['fertilizerAdvice'] ?? '').toString().trim().isNotEmpty &&
          (existingAi['soilManagement'] ?? '').toString().trim().isNotEmpty &&
          (existingAi['reportSummary'] ?? '').toString().trim().isNotEmpty;
      if (_appSettingsService.languageCode == 'en' &&
          existingReport != null &&
          existingAi.isNotEmpty &&
          hasCurrentAiShape) {
        result = GeminiAiResult(
          status: GeminiAiStatus.ready,
          message: 'AI guidance restored from the saved report for this reading.',
          advice: GeminiAiService.normalizeRecommendationAdvice(
            existingAi,
            deterministicTopCrops: topCrops,
          ),
          model: (existingReport['aiModel'] ?? '').toString(),
          fromCache: true,
        );
      } else {
        result = await GeminiAiService.generateAdvice(
          soilData: soil,
          readingId: reading.id,
          fieldId: reading.fieldId,
          source: reading.source,
          deterministicTopCrops: topCrops,
          languageCode: _appSettingsService.languageCode,
        );
      }

      // A newer reading or sign-out while Gemini was working must not replace
      // the state for a different private reading/session. Device ownership
      // and device online/offline state do not block AI from using saved data.
      if (_reading == null ||
          _signature(_reading!) != signature ||
          !canRunAi) {
        return;
      }

      _analysis = analysis;
      _recommendations = recommendations;
      _plan = plan;
      _selectedCrop = crop;
      if (result.isSuccess) {
        _lastReadyResult = result;
      }
      _result = result;
      _lastProcessedSignature = signature;

      if (result.status == GeminiAiStatus.quotaLimited) {
        _scheduleQuotaRetry(reading, result.retryAfterSeconds ?? 60);
      } else if (result.status == GeminiAiStatus.unavailable) {
        _scheduleTransientRetry(reading);
      } else if (result.isSuccess) {
        _transientRetryCount = 0;
      }

      // AI processing is automatic, but saving a report is intentionally a
      // user action from the Reports screen. This avoids silently filling the
      // saved-report list and keeps the Generate Report button meaningful.
    } catch (error) {
      debugPrint('Automatic SoilSense AI processing failed: $error');
      _result = const GeminiAiResult(
        status: GeminiAiStatus.unavailable,
        message:
            'AI is temporarily unavailable. SoilSense will retry automatically.',
      );
      _lastProcessedSignature = signature;
      _scheduleTransientRetry(reading);
    } finally {
      _isProcessing = false;
      notifyListeners();

      // If a newer scan arrived while the previous AI request was running,
      // process the newest stable reading next instead of leaving it pending.
      final latest = _reading;
      if (latest != null &&
          canRunAi &&
          _signature(latest) != _lastProcessedSignature) {
        _readingDebounce?.cancel();
        _readingDebounce = Timer(const Duration(milliseconds: 500), () {
          final current = _reading;
          if (current != null) {
            unawaited(_processCompletedReading(current));
          }
        });
      }
    }
  }

  void _scheduleTransientRetry(SoilData reading) {
    if (_transientRetryCount >= 3) return;
    _quotaRetryTimer?.cancel();
    _transientRetryCount += 1;
    final delays = <int>[8, 20, 45];
    final seconds = delays[_transientRetryCount - 1];
    final signature = _signature(reading);
    _quotaRetryTimer = Timer(Duration(seconds: seconds), () {
      final current = _reading;
      if (current == null ||
          !canRunAi ||
          _signature(current) != signature) {
        return;
      }
      unawaited(_processCompletedReading(current));
    });
  }

  void _scheduleQuotaRetry(SoilData reading, int seconds) {
    _quotaRetryTimer?.cancel();
    final safeSeconds = seconds < 15 ? 15 : seconds;
    final signature = _signature(reading);
    _quotaRetryTimer = Timer(Duration(seconds: safeSeconds + 1), () {
      final current = _reading;
      if (current == null ||
          !canRunAi ||
          _signature(current) != signature) {
        return;
      }
      unawaited(_processCompletedReading(current));
    });
  }

  /// Returns AI advice for another crop selected in the planning UI.
  /// This happens automatically when the user changes the crop selector.
  Future<GeminiAiResult> generateForCrop(String crop) async {
    final reading = _reading;
    if (reading == null) {
      return const GeminiAiResult(
        status: GeminiAiStatus.unavailable,
        message: 'No soil reading is available for crop planning.',
      );
    }
    if (!canRunAi) {
      return GeminiAiResult(
        status: GeminiAiStatus.idle,
        message: pausedReason,
      );
    }

    final recommendations = _recommendations ??
        await DecisionSupportService.getCropRecommendations(_soilMap(reading));
    final topCrops = <String>[];
    for (final item in <Map<String, dynamic>>[
      ..._asList(recommendations['highly_suitable']),
      ..._asList(recommendations['moderately_suitable']),
    ]) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isNotEmpty && !topCrops.contains(name)) topCrops.add(name);
      if (topCrops.length >= 5) break;
    }

    final cropAllowed = topCrops.any(
      (name) => name.toLowerCase() == crop.trim().toLowerCase(),
    );
    if (!cropAllowed) {
      return const GeminiAiResult(
        status: GeminiAiStatus.idle,
        message:
            'This crop is currently Not Recommended, so SoilSense will not generate an AI crop plan for it.',
      );
    }

    return GeminiAiService.generateAdvice(
      soilData: _soilMap(reading),
      readingId: reading.id,
      fieldId: reading.fieldId,
      source: reading.source,
      deterministicTopCrops: topCrops,
      focusCrop: crop,
      languageCode: _appSettingsService.languageCode,
    );
  }


  void _reset() {
    _quotaRetryTimer?.cancel();
    _reading = null;
    _result = null;
    _lastReadyResult = null;
    _analysis = null;
    _recommendations = null;
    _plan = null;
    _selectedCrop = null;
    _pendingSignature = null;
    _lastProcessedSignature = null;
    _transientRetryCount = 0;
    _isProcessing = false;
    notifyListeners();
  }

  static Map<String, dynamic> _soilMap(SoilData reading) => {
        'nitrogen': reading.nitrogen,
        'phosphorus': reading.phosphorus,
        'potassium': reading.potassium,
        'ph': reading.ph,
        'moisture': reading.moisture,
        'timestamp': reading.timestamp,
        'source': 'IoT sensor',
      };

  static String _signature(SoilData reading) => <Object?>[
        reading.id,
        reading.timestamp.millisecondsSinceEpoch,
        reading.nitrogen,
        reading.phosphorus,
        reading.potassium,
        reading.ph,
        reading.moisture,
      ].join('|');

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map(_asMap).where((item) => item.isNotEmpty).toList();
  }

  @override
  void dispose() {
    _deviceStatusService.removeListener(_handleEligibilityChanged);
    _appSettingsService.removeListener(_handleLanguageChanged);
    _readingDebounce?.cancel();
    _quotaRetryTimer?.cancel();
    _readingSubscription?.cancel();
    _ownerSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
