import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_status_service.dart';
import '../services/wifi_provisioning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';

class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  static const Duration _offlineAfter = Duration(seconds: 60);

  final _wifiNameController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  bool _hidePassword = true;
  bool _setupMode = false;
  bool _reportedOnline = false;
  bool _firstTimeSetupOverride = false;
  DateTime? _lastSeen;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _statusSubscription = FirebaseFirestore.instance
        .collection('system')
        .doc('device_status')
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        final data = snapshot.data();
        final timestamp = data?['lastSeen'];
        setState(() {
          _setupMode = data?['setupMode'] == true;
          _reportedOnline = data?['online'] == true;
          _lastSeen = timestamp is Timestamp ? timestamp.toDate() : null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _setupMode = false;
          _reportedOnline = false;
          _lastSeen = null;
        });
      },
    );
    _freshnessTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _freshnessTimer?.cancel();
    _wifiNameController.dispose();
    _wifiPasswordController.dispose();
    super.dispose();
  }

  bool get _isFresh {
    final lastSeen = _lastSeen;
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen) <= _offlineAfter;
  }

  bool get _deviceOnline => _reportedOnline && _isFresh && !_setupMode;

  // Wi-Fi fields must follow the ESP32's real setup mode. Being offline by
  // itself is not permission to change credentials. The only exception is an
  // explicit first-time setup override for a brand-new device whose blue LED
  // is already on but cannot publish setupMode before it has Wi-Fi.
  bool get _wifiSetupEnabled => _setupMode || _firstTimeSetupOverride;

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WifiProvisioningService>();
    final wifiSetupLocked = !_wifiSetupEnabled;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: SoilSenseAppBarLeading(showBackButton: true),
        title: Text('SoilSense Wi-Fi Setup'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _connectionBanner(),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: AppTheme.primaryGreen, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Direct Wi-Fi Setup',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'No Bluetooth. No device-account pairing. The ESP32 only receives the 2.4 GHz Wi-Fi settings.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  _instruction(1, 'Keep this phone connected to the 2.4 GHz Wi-Fi or hotspot that the ESP32 should use.'),
                  _instruction(2, 'If SoilSense is already online, Wi-Fi setup stays locked. Hold the physical device button for 3 seconds to change Wi-Fi.'),
                  _instruction(3, 'When the ESP32 enters Wi-Fi Setup Mode, these fields unlock automatically. Enter the new Wi-Fi name/password and send them.'),
                  if (!_deviceOnline && !_setupMode && !wifi.isWorking) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _firstTimeSetupOverride = !_firstTimeSetupOverride;
                          });
                        },
                        icon: Icon(
                          _firstTimeSetupOverride
                              ? Icons.lock_outline
                              : Icons.add_circle_outline,
                        ),
                        label: Text(
                          _firstTimeSetupOverride
                              ? 'Cancel first-time setup'
                              : 'First-time device setup',
                        ),
                      ),
                    ),
                    if (_firstTimeSetupOverride)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Use this only for a brand-new or reset ESP32 when its blue setup LED is already ON.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                  SizedBox(height: 8),
                  TextField(
                    controller: _wifiNameController,
                    enabled: !wifi.isWorking && !wifiSetupLocked,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '2.4 GHz Wi-Fi or hotspot name',
                      prefixIcon: Icon(Icons.wifi),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _wifiPasswordController,
                    enabled: !wifi.isWorking && !wifiSetupLocked,
                    obscureText: _hidePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Wi-Fi password',
                      helperText: 'Leave blank only for an open Wi-Fi network.',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: wifi.isWorking || wifiSetupLocked
                            ? null
                            : () => setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: wifi.isWorking || wifiSetupLocked ? null : _connect,
                      icon: wifi.isWorking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.wifi),
                      label: Text(
                        wifi.isWorking
                            ? 'Sending...'
                            : wifiSetupLocked
                                ? 'Wi-Fi Already Connected'
                                : 'Send Wi-Fi Settings',
                      ),
                    ),
                  ),
                  if (wifi.stage != WifiProvisioningStage.idle) ...[
                    SizedBox(height: 12),
                    _statusCard(wifi),
                  ],
                  if (wifi.detectedDevice != null) ...[
                    SizedBox(height: 8),
                    Text(
                      'Detected: ${wifi.detectedDevice}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.withOpacity(.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.groups_outlined, color: Colors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wi-Fi setup belongs to the physical SoilSense device, not to a user account. If the saved network disappears, the ESP32 keeps retrying it automatically and the fields stay locked. Hold START for 3 seconds only when you intentionally want to change Wi-Fi.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionBanner() {
    Color color;
    IconData icon;
    String title;
    String message;

    if (_setupMode) {
      color = Colors.blue;
      icon = Icons.settings_input_antenna;
      title = 'Wi-Fi Setup Mode Active';
      message = 'The ESP32 detected the 3-second hold. Wi-Fi name and password fields are enabled automatically.';
    } else if (_deviceOnline) {
      color = AppTheme.primaryGreen;
      icon = Icons.wifi;
      title = 'SoilSense is connected to Wi-Fi';
      message = 'Wi-Fi setup is locked to prevent accidental changes. New app accounts do not need to configure the device again.';
    } else {
      color = Colors.orange;
      icon = Icons.wifi_off;
      title = 'SoilSense Wi-Fi is unavailable';
      message = 'The device is offline, but Wi-Fi settings stay locked. Hold START for 3 seconds to change networks. For a brand-new device whose blue LED is already on, use First-time setup below.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _instruction(int number, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(height: 1.35))),
          ],
        ),
      );

  Widget _statusCard(WifiProvisioningService wifi) {
    final failed = wifi.stage == WifiProvisioningStage.failed;
    final completed = wifi.stage == WifiProvisioningStage.completed;
    final color = failed
        ? AppTheme.warningRed
        : completed
            ? AppTheme.primaryGreen
            : Colors.blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wifi.isWorking)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              failed ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
            ),
          SizedBox(width: 10),
          Expanded(child: Text(wifi.statusMessage, style: TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final wifi = context.read<WifiProvisioningService>();
    final deviceStatus = context.read<DeviceStatusService>();
    final nameError = WifiProvisioningService.validateWifiName(_wifiNameController.text);
    final passwordError = WifiProvisioningService.validateWifiPassword(_wifiPasswordController.text);
    final error = nameError ?? passwordError;
    if (error != null) {
      _message(error, AppTheme.warningRed);
      return;
    }

    // Require a heartbeat newer than this setup attempt. This prevents an old
    // cached device_status document from being mistaken for a successful setup.
    final attemptStartedAt = DateTime.now().subtract(const Duration(seconds: 2));

    try {
      await wifi.provision(
        wifiName: _wifiNameController.text.trim(),
        wifiPassword: _wifiPasswordController.text,
      );
      if (!mounted) return;

      final confirmed = await _waitForFreshOnlineHeartbeat(attemptStartedAt);
      if (!mounted) return;

      if (confirmed) {
        wifi.confirmConnected();
        _wifiPasswordController.clear();
        setState(() {
          _firstTimeSetupOverride = false;
          _setupMode = false;
          _reportedOnline = true;
        });

        // Refresh the shared device service before the user goes back so Home
        // does not briefly keep showing the pre-setup offline state.
        await deviceStatus.refresh();
        if (!mounted) return;
        _message(
          'Wi-Fi connected. SoilSense is online and Wi-Fi setup is now locked.',
          AppTheme.primaryGreen,
        );
      } else {
        wifi.confirmationTimedOut();
        _message(
          'Settings were sent, but SoilSense has not confirmed a fresh online heartbeat yet.',
          Colors.orange,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _message(wifi.errorMessage ?? error.toString(), AppTheme.warningRed);
    }
  }

  Future<bool> _waitForFreshOnlineHeartbeat(DateTime notBefore) async {
    final reference = FirebaseFirestore.instance
        .collection('system')
        .doc('device_status');

    bool isConfirmed(DocumentSnapshot<Map<String, dynamic>> snapshot) {
      final data = snapshot.data();
      final timestamp = data?['lastSeen'];
      final lastSeen = timestamp is Timestamp ? timestamp.toDate() : null;
      return data?['online'] == true &&
          data?['setupMode'] != true &&
          lastSeen != null &&
          !lastSeen.isBefore(notBefore);
    }

    try {
      final immediate = await reference.get();
      if (isConfirmed(immediate)) return true;
    } catch (_) {
      // Continue with the live stream; it may recover while the ESP32 reconnects.
    }

    try {
      await reference
          .snapshots(includeMetadataChanges: true)
          .firstWhere(isConfirmed)
          .timeout(const Duration(seconds: 35));
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _message(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
      ),
    );
  }
}
