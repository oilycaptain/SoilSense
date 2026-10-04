import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/crop_recommendation_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/home_screen.dart';
import 'screens/help_support_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/smart_crop_planning_screen.dart';
import 'screens/terms_privacy_screen.dart';
import 'screens/wifi_setup_screen.dart';
import 'screens/soil_analysis_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/app_settings_service.dart';
import 'services/automatic_ai_service.dart';
import 'services/firestore_service.dart';
import 'services/network_status_service.dart';
import 'services/device_status_service.dart';
import 'services/notification_service.dart';
import 'services/wifi_provisioning_service.dart';
import 'theme/app_theme.dart';
import 'widgets/internet_status_banner.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw a Flutter frame immediately. Previously, runApp() was called only
  // after Firebase initialization, which could leave Android's native splash
  // screen visible forever when Firebase stalled.
  runApp(const SoilSenseBootstrap());
}

class SoilSenseBootstrap extends StatefulWidget {
  const SoilSenseBootstrap({super.key});

  @override
  State<SoilSenseBootstrap> createState() => _SoilSenseBootstrapState();
}

class _SoilSenseBootstrapState extends State<SoilSenseBootstrap> {
  late Future<FirebaseApp> _firebaseInitialization;
  bool _backgroundHandlerRegistered = false;

  @override
  void initState() {
    super.initState();
    _firebaseInitialization = _initializeFirebase();
  }

  Future<FirebaseApp> _initializeFirebase() async {
    try {
      debugPrint('SoilSense: initializing Firebase...');

      final FirebaseApp app;
      if (Firebase.apps.isNotEmpty) {
        debugPrint('SoilSense: Firebase was already initialized.');
        app = Firebase.app();
      } else {
        app = await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 20));
        debugPrint('SoilSense: Firebase initialized successfully.');
      }

      if (!_backgroundHandlerRegistered) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        _backgroundHandlerRegistered = true;
      }
      return app;
    } on TimeoutException {
      throw StateError(
        'Firebase initialization timed out after 20 seconds. Check the '
        'device or emulator internet connection and Firebase project configuration.',
      );
    }
  }

  void _retry() {
    setState(() {
      _firebaseInitialization = _initializeFirebase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _firebaseInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return StartupErrorApp(
              error: snapshot.error.toString(),
              onRetry: _retry,
            );
          }
          return const SoilSenseApp();
        }

        return const StartupLoadingApp();
      },
    );
  }
}

class StartupLoadingApp extends StatelessWidget {
  const StartupLoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withOpacity(.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.eco, size: 58, color: Colors.white),
                ),
                const SizedBox(height: 22),
                Text(
                  'SoilSense',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connecting securely...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const StartupErrorApp({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 80),
                const Icon(Icons.error_outline, size: 52, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'SoilSense could not connect',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Check that the device or emulator has internet access, then press Retry. '
                  'The technical message below identifies the exact startup problem.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(.25)),
                  ),
                  child: SelectableText(error),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SoilSenseApp extends StatefulWidget {
  const SoilSenseApp({super.key});

  @override
  State<SoilSenseApp> createState() => _SoilSenseAppState();
}

class _SoilSenseAppState extends State<SoilSenseApp> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  late final WifiProvisioningService _wifiProvisioningService;
  late final NetworkStatusService _networkStatusService;
  late final DeviceStatusService _deviceStatusService;
  late final NotificationService _notificationService;
  late final AppSettingsService _appSettingsService;
  late final AutomaticAiService _automaticAiService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _firestoreService = FirestoreService();
    _wifiProvisioningService = WifiProvisioningService();
    _networkStatusService = NetworkStatusService();
    _deviceStatusService = DeviceStatusService(
      firestoreService: _firestoreService,
      networkStatusService: _networkStatusService,
    );
    _appSettingsService = AppSettingsService();
    _notificationService = NotificationService(
      navigatorKey: rootNavigatorKey,
      firestoreService: _firestoreService,
      deviceStatusService: _deviceStatusService,
    );
    _automaticAiService = AutomaticAiService(
      firestoreService: _firestoreService,
      deviceStatusService: _deviceStatusService,
      appSettingsService: _appSettingsService,
    );

    unawaited(_networkStatusService.initialize());
    unawaited(_notificationService.initialize());
  }

  @override
  void dispose() {
    _automaticAiService.dispose();
    _appSettingsService.dispose();
    _wifiProvisioningService.dispose();
    _notificationService.dispose();
    _deviceStatusService.dispose();
    _networkStatusService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: _authService),
        Provider<FirestoreService>.value(value: _firestoreService),
        ChangeNotifierProvider<WifiProvisioningService>.value(
          value: _wifiProvisioningService,
        ),
        ChangeNotifierProvider<NetworkStatusService>.value(
          value: _networkStatusService,
        ),
        ChangeNotifierProvider<DeviceStatusService>.value(
          value: _deviceStatusService,
        ),
        Provider<NotificationService>.value(value: _notificationService),
        ChangeNotifierProvider<AppSettingsService>.value(
          value: _appSettingsService,
        ),
        ChangeNotifierProvider<AutomaticAiService>.value(
          value: _automaticAiService,
        ),
      ],
      child: const _SoilSenseMaterialApp(),
    );
  }
}

class _SoilSenseMaterialApp extends StatelessWidget {
  const _SoilSenseMaterialApp();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final isDark = settings.themeMode == ThemeMode.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        title: 'SoilSense',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: settings.themeMode,
        locale: settings.locale,
        supportedLocales: const [Locale('en'), Locale('fil')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        initialRoute: '/splash',
        builder: (context, child) => InternetStatusBanner(
          child: child ?? const SizedBox.shrink(),
        ),
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignupScreen(),
          '/verify-email': (context) => const EmailVerificationScreen(),
          '/home': (context) => const HomeScreen(),
          '/soil-analysis': (context) => const SoilAnalysisScreen(),
          '/crop-recommendation': (context) =>
              const CropRecommendationScreen(),
          '/smart-crop-planning': (context) =>
              const SmartCropPlanningScreen(),
          '/reports': (context) => const ReportsScreen(),
          '/notifications': (context) => const NotificationsScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/wifi-setup': (context) => const WifiSetupScreen(),
          '/terms-privacy': (context) => const TermsPrivacyScreen(),
          '/help-support': (context) => const HelpSupportScreen(),
        },
      );
  }
}
