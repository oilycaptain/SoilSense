import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance, language, and first-run preferences for SoilSense.
///
/// Theme/language are cached locally so the login, sign-up, onboarding and
/// splash/auth screens can keep the user's selected appearance even while no
/// Firebase account is signed in. When an account is signed in, its Firestore
/// preference document remains the cross-device source of truth.
class AppSettingsService extends ChangeNotifier {
  static const String _darkModeKey = 'soilsense.darkMode';
  static const String _languageKey = 'soilsense.languageCode';
  static const String _onboardingKey = 'soilsense.onboardingComplete.v1';

  AppSettingsService() {
    unawaited(_initialize());
  }

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _settingsSubscription;

  bool _darkMode = false;
  String _languageCode = 'en';
  bool _isLoading = false;
  bool _saving = false;
  bool _localReady = false;

  bool get darkMode => _darkMode;
  String get languageCode => _languageCode;
  bool get isFilipino => _languageCode == 'fil';
  bool get isLoading => _isLoading;
  bool get saving => _saving;
  bool get localReady => _localReady;
  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;
  Locale get locale => Locale(_languageCode);

  String text(String english, String filipino) =>
      isFilipino ? filipino : english;

  String get languageLabel => isFilipino ? 'Filipino' : 'English';

  Future<void> _initialize() async {
    await _loadLocalPreferences();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
      onError: (Object error) {
        debugPrint('App settings auth listener failed: $error');
      },
    );
    _handleAuthChanged(FirebaseAuth.instance.currentUser);
  }

  Future<void> _loadLocalPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _darkMode = prefs.getBool(_darkModeKey) ?? false;
      final code = prefs.getString(_languageKey) ?? 'en';
      _languageCode = code == 'fil' ? 'fil' : 'en';
    } catch (error) {
      debugPrint('Could not load local app preferences: $error');
    } finally {
      _localReady = true;
      notifyListeners();
    }
  }

  Future<void> _saveLocalPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, _darkMode);
      await prefs.setString(_languageKey, _languageCode);
    } catch (error) {
      debugPrint('Could not save local app preferences: $error');
    }
  }

  Future<bool> hasCompletedOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingKey) ?? false;
    } catch (error) {
      debugPrint('Could not read onboarding preference: $error');
      return false;
    }
  }

  Future<void> completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingKey, true);
    } catch (error) {
      debugPrint('Could not save onboarding preference: $error');
    }
  }

  DocumentReference<Map<String, dynamic>>? get _settingsRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('preferences')
        .doc('app');
  }

  void _handleAuthChanged(User? user) {
    _settingsSubscription?.cancel();
    _settingsSubscription = null;

    // Keep the local appearance/language when signed out so auth screens use
    // the same theme the user selected inside SoilSense.
    if (user == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _settingsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('preferences')
        .doc('app')
        .snapshots()
        .listen(
      (snapshot) async {
        final data = snapshot.data();
        if (snapshot.exists && data != null) {
          final code = (data['languageCode'] ?? _languageCode).toString();
          _darkMode = data['darkMode'] is bool
              ? data['darkMode'] == true
              : _darkMode;
          _languageCode = code == 'fil' ? 'fil' : 'en';
          await _saveLocalPreferences();
        } else {
          // New/legacy account: seed Firestore with the device-local choice.
          try {
            await snapshot.reference.set(
              <String, dynamic>{
                'darkMode': _darkMode,
                'languageCode': _languageCode,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (error) {
            debugPrint('Could not seed account preferences: $error');
          }
        }
        _isLoading = false;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('App settings listener failed: $error');
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_darkMode == enabled && !_saving) return;
    _darkMode = enabled;
    _saving = true;
    notifyListeners();
    await _saveLocalPreferences();

    try {
      final ref = _settingsRef;
      if (ref != null) {
        await ref.set(
          <String, dynamic>{
            'darkMode': enabled,
            'languageCode': _languageCode,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (error) {
      // Keep the local preference so the selected appearance still works when
      // Firestore is temporarily unavailable.
      debugPrint('Could not sync dark mode preference: $error');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> setLanguageCode(String code) async {
    final normalized = code == 'fil' ? 'fil' : 'en';
    if (_languageCode == normalized && !_saving) return;
    _languageCode = normalized;
    _saving = true;
    notifyListeners();
    await _saveLocalPreferences();

    try {
      final ref = _settingsRef;
      if (ref != null) {
        await ref.set(
          <String, dynamic>{
            'darkMode': _darkMode,
            'languageCode': normalized,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (error) {
      debugPrint('Could not sync language preference: $error');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
