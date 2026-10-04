import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeUser();
  }

  Future<void> _routeUser() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    final auth = context.read<AuthService>();
    final settings = context.read<AppSettingsService>();
    final cachedUser = await auth.waitForRestoredUser();
    if (!mounted) return;

    if (cachedUser == null && !await settings.hasCompletedOnboarding()) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
      return;
    }

    var route = '/login';
    if (cachedUser != null) {
      if (!cachedUser.emailVerified) {
        route = '/verify-email';
      } else {
        route = '/home';
        try {
          await auth.ensureMobileAccess();
        } on FirebaseAuthException catch (error) {
          if (error.code == 'email-not-verified') {
            route = '/verify-email';
          } else if (error.code == 'account-disabled' ||
              error.code == 'role-not-authorized') {
            route = '/login';
          } else {
            debugPrint(
              'Startup access refresh failed; keeping the cached Firebase session: $error',
            );
          }
        } catch (error) {
          debugPrint(
            'Startup refresh failed; keeping the cached Firebase session: $error',
          );
        }
      }
    }

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SoilSenseReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .88, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withOpacity(.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.eco, size: 60, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SoilSense',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI-Powered Soil Intelligence',
                style: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
