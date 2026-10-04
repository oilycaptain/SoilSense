import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthService>().signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      await context.read<NotificationService>().syncToken();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'email-not-verified') {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/verify-email',
            (_) => false,
          );
        }
      } else {
        _showSnackBar(AuthService.friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    var editedEmail = _emailController.text.trim();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset Password'),
        content: TextFormField(
          initialValue: editedEmail,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Account email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onChanged: (value) => editedEmail = value,
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(editedEmail.trim()),
            child: Text('Send Link'),
          ),
        ],
      ),
    );
    if (!mounted || email == null || email.trim().isEmpty) return;
    try {
      await context.read<AuthService>().resetPassword(email.trim());
      _showSnackBar('Password reset link sent. Check your email.');
    } catch (e) {
      _showSnackBar(AuthService.friendlyError(e), error: true);
    }
  }

  void _showSnackBar(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? AppTheme.warningRed : AppTheme.primaryGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF101712), Color(0xFF142219)]
                : const [Colors.white, Color(0xFFE8F5E9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: SoilSenseReveal(
                offsetY: 14,
                duration: const Duration(milliseconds: 320),
                child: Form(
                  key: _formKey,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [AppTheme.primaryGreen, AppTheme.primaryLight]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.eco, size: 40, color: Colors.white),
                      ),
                    ),
                    SizedBox(height: 32),
                    Text('Welcome Back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.onSurface)),
                    SizedBox(height: 8),
                    Text('Sign in to monitor your soil and crop plan.', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined), hintText: 'farmer@example.com'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Enter a valid email address.';
                        return null;
                      },
                    ),
                    SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _isLoading ? null : _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) => (value ?? '').isEmpty ? 'Enter your password.' : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: _resetPassword, child: Text('Forgot Password?')),
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Sign In', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account? "),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/signup'), child: Text('Sign Up')),
                      ],
                    ),
                    Center(
                      child: Text('Your soil readings stay private to your account.', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
