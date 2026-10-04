class AppConfig {
  static const String appName = 'SoilSense';
  static const String appVersion = '4.3.5-gemini-generatecontent-fix';
  static const String environment = 'live';

  // This key is compiled into the Android app and can be extracted from the APK.
  // Replace it with a backend-protected key before any public/production release.
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AQ.Ab8RN6IlLX8NKFx3MutoHWKX2xalEv1SL23QsNdBvA-Ge9yd8Q',
  );
  static const String geminiModel = 'gemini-3.5-flash';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String soilReadingsCollection = 'soil_readings';
  static const String soilAnalysesCollection = 'soil_analyses';
  static const String alertsCollection = 'alerts';
  static const String reportsCollection = 'reports';
  static const String fieldsCollection = 'fields';

  // Nutrient thresholds
  static const Map<String, Map<String, double>> nutrientThresholds = {
    'nitrogen': {'low': 40, 'optimal': 70, 'high': 100},
    'phosphorus': {'low': 50, 'optimal': 80, 'high': 120},
    'potassium': {'low': 100, 'optimal': 200, 'high': 300},
    'ph': {'low': 5.5, 'optimal': 7.0, 'high': 7.5},
    'moisture': {'low': 40, 'optimal': 70, 'high': 90},
  };
}
