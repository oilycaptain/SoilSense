import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  bool _isChecking = false;
  bool _isResending = false;
  bool _hasNavigated = false;
  int _resendCooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Users normally leave the app to open the verification link. Recheck as
    // soon as they return so dashboard access can be granted without guessing.
    if (state == AppLifecycleState.resumed && !_hasNavigated) {
      _checkVerification(showUnverifiedMessage: false);
    }
  }

  Future<void> _checkVerification({bool showUnverifiedMessage = true}) async {
    if (_isChecking || _hasNavigated) return;
    setState(() => _isChecking = true);

    try {
      final auth = context.read<AuthService>();
      final verified = await auth.refreshEmailVerificationStatus();
      if (!verified) {
        if (showUnverifiedMessage) {
          _showMessage(
            'Your email is still not verified. Open the verification link, then return to SoilSense.',
            error: true,
          );
        }
        return;
      }

      await auth.ensureMobileAccess();
      await context.read<NotificationService>().syncToken();
      if (mounted && !_hasNavigated) {
        _hasNavigated = true;
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (error) {
      if (showUnverifiedMessage) {
        _showMessage(AuthService.friendlyError(error), error: true);
      }
    } finally {
      if (mounted && !_hasNavigated) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_isResending || _resendCooldownSeconds > 0) return;
    setState(() => _isResending = true);

    try {
      await context.read<AuthService>().sendVerificationEmail();
      _startResendCooldown();
      _showMessage('Verification email sent. Check your inbox and spam folder.');
    } catch (error) {
      _showMessage(AuthService.friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendCooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds--);
      }
    });
  }

  Future<void> _useAnotherAccount() async {
    await context.read<AuthService>().signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.warningRed : AppTheme.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthService>().currentUser?.email ?? 'your email';
    final resendLabel = _isResending
        ? 'Sending...'
        : _resendCooldownSeconds > 0
            ? 'Resend in ${_resendCooldownSeconds}s'
            : 'Resend Verification Email';

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFE8F5E9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 28),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(.12),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.mark_email_unread_outlined,
                      size: 46,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                  SizedBox(height: 28),
                  Text(
                    'Verify Your Email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'We sent a verification link to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 8),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Open the email and tap the verification link. SoilSense will check again automatically when you return to the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isChecking ? null : () => _checkVerification(),
                      icon: _isChecking
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.verified_outlined),
                      label: Text(
                        _isChecking ? 'Checking...' : 'I Have Verified My Email',
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isResending || _resendCooldownSeconds > 0
                          ? null
                          : _resendVerification,
                      icon: _isResending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send_outlined),
                      label: Text(resendLabel),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: _useAnotherAccount,
                    child: Text('Use a different account'),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Check Spam or Junk if the message is missing. Repeated resend requests are temporarily limited to protect your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
