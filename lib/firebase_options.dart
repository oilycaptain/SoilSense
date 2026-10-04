import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase configuration for the SoilSense Flutter mobile application.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'The SoilSense Flutter client is configured for Android only.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase options are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBITS4jOOq6W40N_8NiqrEtUCWnDzv6rKQ',
    appId: '1:166789957038:android:4cbb947bcb35dee970b43f',
    messagingSenderId: '166789957038',
    projectId: 'soilsense-db59e',
    storageBucket: 'soilsense-db59e.firebasestorage.app',
  );
}
