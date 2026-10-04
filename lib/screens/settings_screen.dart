import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/wifi_setup_screen.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/device_status_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCurrentOwner = false;
  int _scanDurationSeconds = FirestoreService.defaultScanDurationSeconds;
  bool _savingScanDuration = false;
  StreamSubscription<bool>? _ownerSubscription;
  StreamSubscription<int>? _scanDurationSubscription;

  @override
  void initState() {
    super.initState();
    _ownerSubscription = context.read<FirestoreService>().watchOwnerAccess().listen(
      (isOwner) {
        if (mounted) setState(() => _isCurrentOwner = isOwner);
      },
      onError: (Object error) {
        debugPrint('Settings owner listener failed: $error');
      },
    );
    _scanDurationSubscription = context
        .read<FirestoreService>()
        .watchScanDurationSeconds()
        .listen(
      (seconds) {
        if (mounted && !_savingScanDuration) {
          setState(() => _scanDurationSeconds = seconds);
        }
      },
      onError: (Object error) {
        debugPrint('Settings scan duration listener failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _ownerSubscription?.cancel();
    _scanDurationSubscription?.cancel();
    super.dispose();
  }

  String _t(String en, String fil) =>
      context.read<AppSettingsService>().text(en, fil);

  String _formatScanDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes min' : '$minutes min ${remainder}s';
  }

  Future<void> _saveScanDuration(int seconds) async {
    final normalized = seconds.clamp(
      FirestoreService.minScanDurationSeconds,
      FirestoreService.maxScanDurationSeconds,
    ).toInt();
    setState(() {
      _scanDurationSeconds = normalized;
      _savingScanDuration = true;
    });
    try {
      await context.read<FirestoreService>().setScanDurationSeconds(normalized);
      if (!mounted) return;
      _message(_t(
        'Scan duration set to ${_formatScanDuration(normalized)}.',
        'Naitakda ang tagal ng scan sa ${_formatScanDuration(normalized)}.',
      ));
    } catch (error) {
      if (!mounted) return;
      _message(
        _t('Could not update scan duration.', 'Hindi ma-update ang tagal ng scan.'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _savingScanDuration = false);
    }
  }

  Future<void> _showScanDurationSheet() async {
    final deviceStatus = context.read<DeviceStatusService>();
    if (deviceStatus.isScanning) {
      _message(_t(
        'Wait for the current scan to finish or press the physical Stop button first.',
        'Hintaying matapos ang kasalukuyang scan o pindutin muna ang physical Stop button.',
      ));
      return;
    }

    var draftSeconds = _scanDurationSeconds;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final colors = Theme.of(context).colorScheme;
          final settings = context.watch<AppSettingsService>();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 10),
                      Text(
                        settings.text('Scan Duration', 'Tagal ng Scan'),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    settings.text(
                      'Choose how long the physical SoilSense scan should run. You can still cancel anytime with the Stop button.',
                      'Piliin kung gaano katagal tatakbo ang SoilSense scan. Maaari pa rin itong ihinto anumang oras gamit ang Stop button.',
                    ),
                    style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                  SizedBox(height: 20),
                  Center(
                    child: Text(
                      _formatScanDuration(draftSeconds),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Slider(
                    min: FirestoreService.minScanDurationSeconds.toDouble(),
                    max: FirestoreService.maxScanDurationSeconds.toDouble(),
                    divisions: 9,
                    value: draftSeconds.toDouble(),
                    label: _formatScanDuration(draftSeconds),
                    onChanged: (value) {
                      setSheetState(() {
                        draftSeconds = (value / 30).round() * 30;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('30 sec', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                      Text('5 min', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                    ],
                  ),
                  SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(draftSeconds),
                      child: Text(settings.text('Save Duration', 'I-save ang Tagal')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || selected == null) return;
    await _saveScanDuration(selected);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final user = context.read<AuthService>().currentUser;
    final scanning = context.watch<DeviceStatusService>().isScanning;
    final colors = Theme.of(context).colorScheme;
    final scanDisabled = !_isCurrentOwner || scanning || _savingScanDuration;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.text('Settings', 'Mga Setting')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(settings.text('Account', 'Account')),
          SoilSenseReveal(
            child: Card(
              child: Column(
                children: [
                  ListTile(
                  leading: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.primary),
                  title: Text(settings.text('Edit Display Name', 'Palitan ang Display Name')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: _editName,
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lock_reset, color: Theme.of(context).colorScheme.primary),
                  title: Text(settings.text('Send Password Reset Email', 'Magpadala ng Password Reset Email')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: user?.email == null ? null : () => _sendReset(user!.email!),
                ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _sectionTitle(settings.text('Device', 'Device')),
          SoilSenseReveal(
            delay: const Duration(milliseconds: 60),
            child: Card(
              child: Column(
                children: [
                ListTile(
                  leading: Icon(Icons.wifi_tethering, color: Theme.of(context).colorScheme.primary),
                  title: Text('SoilSense Wi-Fi Setup'),
                  subtitle: Text(settings.text(
                    'Change the ESP32 2.4 GHz Wi-Fi connection',
                    'Palitan ang 2.4 GHz Wi-Fi connection ng ESP32',
                  )),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => pushSoilSenseSecondaryPage(
                    context,
                    const WifiSetupScreen(),
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.timer_outlined, color: Theme.of(context).colorScheme.primary),
                  title: Text(settings.text('Scan Duration', 'Tagal ng Scan')),
                  subtitle: Text(
                    !_isCurrentOwner
                        ? settings.text('Available to the current device owner', 'Para lamang sa kasalukuyang device owner')
                        : scanning
                            ? settings.text('Locked while a scan is running', 'Naka-lock habang may scan')
                            : settings.text('Automatic limit: 30 seconds to 5 minutes', 'Automatic limit: 30 segundo hanggang 5 minuto'),
                  ),
                  trailing: _savingScanDuration
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatScanDuration(_scanDurationSeconds),
                              style: TextStyle(
                                color: scanDisabled ? colors.onSurfaceVariant : AppTheme.primaryGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                  onTap: scanDisabled ? null : _showScanDurationSheet,
                ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _sectionTitle(settings.text('Appearance & Language', 'Itsura at Wika')),
          SoilSenseReveal(
            delay: const Duration(milliseconds: 120),
            child: Card(
              child: Column(
                children: [
                SwitchListTile.adaptive(
                  secondary: Icon(Icons.dark_mode_outlined, color: Theme.of(context).colorScheme.primary),
                  title: Text(settings.text('Dark Mode', 'Dark Mode')),
                  subtitle: Text(settings.text(
                    'Use a darker SoilSense interface',
                    'Gumamit ng mas madilim na interface ng SoilSense',
                  )),
                  value: settings.darkMode,
                  onChanged: (value) => _setDarkMode(value),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                  title: Text(settings.text('App & AI Language', 'Wika ng App at AI')),
                  subtitle: Text(settings.text(
                    'Changes key app labels and new AI guidance',
                    'Binabago ang mahahalagang label at bagong AI guidance',
                  )),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        settings.languageLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _chooseLanguage,
                ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              settings.text(
                'Language changes new AI responses. Previously saved AI text is kept as it was generated.',
                'Ang napiling wika ay gagamitin sa mga bagong AI response. Hindi binabago ang dati nang naka-save na AI text.',
              ),
              style: TextStyle(
                fontSize: 11.5,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Future<void> _setDarkMode(bool enabled) async {
    try {
      await context.read<AppSettingsService>().setDarkMode(enabled);
    } catch (_) {
      if (mounted) {
        _message(
          _t('Could not save appearance setting.', 'Hindi ma-save ang appearance setting.'),
          error: true,
        );
      }
    }
  }

  Future<void> _chooseLanguage() async {
    final settings = context.read<AppSettingsService>();
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.language),
              title: Text('English'),
              trailing: settings.languageCode == 'en' ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              leading: Icon(Icons.translate),
              title: Text('Filipino'),
              trailing: settings.languageCode == 'fil' ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () => Navigator.pop(context, 'fil'),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || selected == settings.languageCode) return;
    try {
      await context.read<AppSettingsService>().setLanguageCode(selected);
      if (!mounted) return;
      _message(selected == 'fil'
          ? 'Filipino na ang gagamitin para sa app at mga bagong AI response.'
          : 'English will now be used for the app and new AI responses.');
    } catch (_) {
      if (mounted) {
        _message(
          _t('Could not save language setting.', 'Hindi ma-save ang language setting.'),
          error: true,
        );
      }
    }
  }

  Future<void> _editName() async {
    final user = context.read<AuthService>().currentUser;
    final profile = await context.read<AuthService>().getUserProfile();
    if (!mounted) return;
    var editedName = (profile?['name'] ?? user?.displayName ?? '').toString();
    final settings = context.read<AppSettingsService>();

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(settings.text('Edit Display Name', 'Palitan ang Display Name')),
        content: TextFormField(
          initialValue: editedName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: settings.text('Full name', 'Buong pangalan')),
          onChanged: (value) => editedName = value,
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(settings.text('Cancel', 'Kanselahin')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(editedName.trim()),
            child: Text(settings.text('Save', 'I-save')),
          ),
        ],
      ),
    );

    if (!mounted || value == null || value.trim().isEmpty) return;
    try {
      await context.read<AuthService>().updateProfile(name: value.trim());
      if (mounted) _message(_t('Profile updated.', 'Na-update ang profile.'));
    } catch (error) {
      if (mounted) {
        _message(_t('Could not update profile.', 'Hindi ma-update ang profile.'), error: true);
      }
    }
  }

  Future<void> _sendReset(String email) async {
    try {
      await context.read<AuthService>().resetPassword(email);
      if (mounted) {
        _message(_t('Password reset email sent.', 'Naipadala ang password reset email.'));
      }
    } catch (error) {
      if (mounted) {
        _message(AuthService.friendlyError(error), error: true);
      }
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.warningRed : AppTheme.primaryGreen,
      ),
    );
  }
}
