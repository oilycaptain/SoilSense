import 'dart:async';
import 'dart:convert';

import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WifiProvisioningStage {
  idle,
  preparing,
  broadcasting,
  confirming,
  completed,
  failed,
}

/// Simple SoilSense Wi-Fi provisioning with Espressif ESPTouch / SmartConfig.
///
/// This service does NOT pair an ESP32 to a Firebase user account. It only
/// sends the target 2.4 GHz Wi-Fi credentials to a SoilSense ESP32 that is in
/// SmartConfig mode. Device ownership and soil-reading visibility remain
/// controlled separately by Firestore and the SoilSense admin assignment.
class WifiProvisioningService extends ChangeNotifier {
  static const Duration setupWindow = Duration(seconds: 35);
  static const MethodChannel _wifiChannel = MethodChannel(
    'soilsense/wifi_multicast',
  );

  WifiProvisioningStage _stage = WifiProvisioningStage.idle;
  String _statusMessage =
      'Keep this phone connected to the 2.4 GHz Wi-Fi that SoilSense should use.';
  String? _errorMessage;
  String? _detectedDevice;
  bool _cancelRequested = false;

  WifiProvisioningStage get stage => _stage;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  String? get detectedDevice => _detectedDevice;
  bool get isWorking =>
      _stage == WifiProvisioningStage.preparing ||
      _stage == WifiProvisioningStage.broadcasting ||
      _stage == WifiProvisioningStage.confirming;

  static String? validateWifiName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter the 2.4 GHz Wi-Fi or hotspot name.';
    if (utf8.encode(name).length > 32) {
      return 'The Wi-Fi name must be 32 bytes or fewer.';
    }
    return null;
  }

  static String? validateWifiPassword(String value) {
    final byteLength = utf8.encode(value).length;
    if (byteLength > 63) {
      return 'The Wi-Fi password must be 63 bytes or fewer.';
    }
    if (value.isNotEmpty && byteLength < 8) {
      return 'The Wi-Fi password must contain at least 8 characters.';
    }
    return null;
  }

  Future<void> provision({
    required String wifiName,
    required String wifiPassword,
  }) async {
    final nameError = validateWifiName(wifiName);
    if (nameError != null) throw FormatException(nameError);
    final passwordError = validateWifiPassword(wifiPassword);
    if (passwordError != null) throw FormatException(passwordError);
    if (isWorking) return;

    _cancelRequested = false;
    _errorMessage = null;
    _detectedDevice = null;
    final provisioner = Provisioner.espTouch();
    StreamSubscription<ProvisioningResponse>? responseSubscription;
    final responseCompleter = Completer<void>();

    try {
      _setStage(
        WifiProvisioningStage.preparing,
        'Preparing Wi-Fi setup...',
      );
      await _setMulticastLock(true);

      responseSubscription = provisioner.listen((response) {
        if (_cancelRequested) return;
        final mac = _normalizeMac((response.bssidText ?? '').toString());
        if (mac.isNotEmpty) {
          _detectedDevice = 'SoilSense-${mac.substring(8)}';
        }
        if (!responseCompleter.isCompleted) responseCompleter.complete();
        notifyListeners();
      });

      _setStage(
        WifiProvisioningStage.broadcasting,
        'Sending Wi-Fi settings to the ESP32. Keep the device powered and in setup mode...',
      );

      await provisioner.start(
        ProvisioningRequest.fromStrings(
          ssid: wifiName.trim(),
          password: wifiPassword,
        ),
      );

      // ESPTouch does not have a built-in timeout. A local acknowledgement is
      // useful when available, but some routers block that reply even though the
      // ESP32 received the credentials. Therefore a missing acknowledgement is
      // treated as "settings sent" rather than a hard account-activation error.
      await Future.any<void>([
        responseCompleter.future,
        Future<void>.delayed(setupWindow),
      ]);

      if (_cancelRequested) {
        throw StateError('Wi-Fi setup was cancelled.');
      }

      if (responseCompleter.isCompleted) {
        _setStage(
          WifiProvisioningStage.confirming,
          'Wi-Fi settings were received by the ESP32. Confirming its fresh online heartbeat...',
        );
      } else {
        _setStage(
          WifiProvisioningStage.confirming,
          'Wi-Fi settings were sent. Waiting for SoilSense to confirm that it is online...',
        );
      }
    } catch (error) {
      final message = _friendlyError(error);
      _errorMessage = message;
      _setStage(WifiProvisioningStage.failed, message);
      throw StateError(message);
    } finally {
      provisioner.stop();
      await responseSubscription?.cancel();
      await _setMulticastLock(false);
    }
  }


  void confirmConnected() {
    _errorMessage = null;
    _setStage(
      WifiProvisioningStage.completed,
      'Wi-Fi connected and SoilSense is online. Wi-Fi setup is now locked.',
    );
  }

  void confirmationTimedOut() {
    _errorMessage =
        'The Wi-Fi settings were sent, but SoilSense has not confirmed a fresh online heartbeat yet.';
    _setStage(
      WifiProvisioningStage.failed,
      'The Wi-Fi settings were sent, but the app could not confirm the device online yet. Keep SoilSense powered and check the device connection.',
    );
  }

  void cancel() {
    _cancelRequested = true;
    _errorMessage = null;
    _setStage(WifiProvisioningStage.idle, 'Wi-Fi setup cancelled.');
  }

  void resetStatus() {
    if (isWorking) return;
    _errorMessage = null;
    _detectedDevice = null;
    _setStage(
      WifiProvisioningStage.idle,
      'Keep this phone connected to the 2.4 GHz Wi-Fi that SoilSense should use.',
    );
  }

  static String _normalizeMac(String value) {
    final normalized = value
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-F]'), '');
    return normalized.length == 12 ? normalized : '';
  }

  Future<void> _setMulticastLock(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _wifiChannel.invokeMethod<void>(
        enabled ? 'acquireMulticastLock' : 'releaseMulticastLock',
      );
    } catch (error) {
      debugPrint('SoilSense multicast helper: $error');
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('cancel')) return 'Wi-Fi setup was cancelled.';
    if (lower.contains('socket') || lower.contains('network')) {
      return 'SmartConfig could not use the current network. Keep Wi-Fi enabled and use a 2.4 GHz Wi-Fi connection.';
    }
    if (lower.contains('ssid') || lower.contains('password')) {
      return 'Check the Wi-Fi name and password, then try again.';
    }
    return 'Could not send the Wi-Fi settings. Hold the ESP32 button for 3 seconds, keep the phone on 2.4 GHz Wi-Fi, and try again.';
  }

  void _setStage(WifiProvisioningStage stage, String message) {
    _stage = stage;
    _statusMessage = message;
    notifyListeners();
  }
}
