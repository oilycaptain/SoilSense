import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/help_support_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/terms_privacy_screen.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/motion.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;
  Map<String, int> _stats = const {
    'readings': 0,
    'reports': 0,
    'notifications': 0,
  };
  bool _isLoading = true;
  bool _isCurrentOwner = false;
  Object? _loadError;
  StreamSubscription<bool>? _ownerSubscription;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _ownerSubscription = context.read<FirestoreService>().watchOwnerAccess().listen(
      (isOwner) {
        if (mounted) setState(() => _isCurrentOwner = isOwner);
      },
      onError: (Object error) {
        debugPrint('Profile owner listener failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _ownerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        context.read<AuthService>().getUserProfile(),
        context.read<FirestoreService>().getProfileStats(),
        context.read<FirestoreService>().isCurrentUserOwner(),
      ]);
      if (!mounted) return;
      setState(() {
        _userProfile = results[0] as Map<String, dynamic>?;
        _stats = results[1] as Map<String, int>;
        _isCurrentOwner = results[2] as bool;
      });
    } catch (error) {
      debugPrint('Could not load profile: $error');
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;
    final settings = context.watch<AppSettingsService>();
    final canPop = Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 96 : 56,
        leading: SoilSenseAppBarLeading(showBackButton: canPop),
        title: Text(settings.text('Profile', 'Profile')),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildLoadError(settings)
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      SoilSenseReveal(
                        child: _buildProfileHeader(user, settings),
                      ),
                      SizedBox(height: 16),
                      SoilSenseReveal(
                        delay: const Duration(milliseconds: 60),
                        child: _buildStats(settings),
                      ),
                      SizedBox(height: 16),
                      SoilSenseReveal(
                        delay: const Duration(milliseconds: 120),
                        child: _buildProfileActions(settings),
                      ),
                      SizedBox(height: 18),
                      SoilSenseReveal(
                        delay: const Duration(milliseconds: 180),
                        child: _buildLogoutButton(settings),
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 0),
    );
  }

  Widget _buildLoadError(AppSettingsService settings) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 42, color: colors.error),
            SizedBox(height: 10),
            Text(
              settings.text('Could not load profile.', 'Hindi ma-load ang profile.'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              settings.text('Pull down or tap Retry.', 'Mag-pull down o pindutin ang Retry.'),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              icon: Icon(Icons.refresh),
              label: Text(settings.text('Retry', 'Subukan Muli')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(User? user, AppSettingsService settings) {
    final name = (_userProfile?['name'] ?? user?.displayName ?? 'SoilSense User')
        .toString()
        .trim();
    final safeName = name.isEmpty ? 'SoilSense User' : name;
    final initial = safeName[0].toUpperCase();
    final rawRole = (_userProfile?['role'] ?? 'farmer').toString().trim().toLowerCase();
    final role = rawRole.isEmpty ? 'farmer' : rawRole;
    final roleLabel = role == 'technician'
        ? settings.text('Agricultural Technician', 'Agricultural Technician')
        : role[0].toUpperCase() + role.substring(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 45,
            backgroundColor: Colors.white,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 36,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 12),
          Text(
            safeName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(roleLabel, style: TextStyle(color: Colors.white.withOpacity(.9))),
          SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: TextStyle(color: Colors.white.withOpacity(.8), fontSize: 13),
          ),
          SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isCurrentOwner
                  ? settings.text(
                      'SoilSense Device: Current Owner',
                      'SoilSense Device: Kasalukuyang Owner',
                    )
                  : settings.text(
                      'SoilSense Device: Not Assigned',
                      'SoilSense Device: Hindi Naka-assign',
                    ),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(AppSettingsService settings) {
    return Row(
      children: [
        _stat(
          '${_stats['readings'] ?? 0}',
          settings.text('Readings', 'Readings'),
          Icons.sensors_outlined,
        ),
        _stat(
          '${_stats['reports'] ?? 0}',
          settings.text('Reports', 'Reports'),
          Icons.description_outlined,
        ),
        _stat(
          '${_stats['notifications'] ?? 0}',
          settings.text('Alerts', 'Alerts'),
          Icons.notifications_outlined,
        ),
      ],
    );
  }

  Widget _stat(String value, String label, IconData icon) => Expanded(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            child: Column(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildProfileActions(AppSettingsService settings) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(settings.text('Settings', 'Mga Setting')),
            subtitle: Text(settings.text(
              'Account, device, scan duration, dark mode, and language',
              'Account, device, tagal ng scan, dark mode, at wika',
            )),
            trailing: Icon(Icons.chevron_right),
            onTap: () => pushSoilSenseSecondaryPage(
              context,
              const SettingsScreen(),
            ),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.policy_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(settings.text('Terms & Privacy Policy', 'Terms & Privacy Policy')),
            subtitle: Text(settings.text(
              'How SoilSense handles accounts, sensor data, and AI features',
              'Paano pinangangasiwaan ng SoilSense ang account, sensor data, at AI features',
            )),
            trailing: Icon(Icons.chevron_right),
            onTap: () => pushSoilSenseSecondaryPage(
              context,
              const TermsPrivacyScreen(),
            ),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.help_outline_rounded, color: Theme.of(context).colorScheme.primary),
            title: Text(settings.text('Help, Support & FAQ', 'Tulong, Support & FAQ')),
            subtitle: Text(settings.text(
              'Setup, scanning, ownership, Wi-Fi, and troubleshooting',
              'Setup, scanning, ownership, Wi-Fi, at troubleshooting',
            )),
            trailing: Icon(Icons.chevron_right),
            onTap: () => pushSoilSenseSecondaryPage(
              context,
              const HelpSupportScreen(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(AppSettingsService settings) => SizedBox(
        width: double.infinity,
        height: 54,
        child: OutlinedButton.icon(
          icon: Icon(Icons.logout, color: AppTheme.warningRed),
          label: Text(
            settings.text('Logout', 'Mag-logout'),
            style: TextStyle(color: AppTheme.warningRed),
          ),
          onPressed: () => _confirmLogout(settings),
        ),
      );

  Future<void> _confirmLogout(AppSettingsService settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(settings.text('Log out of SoilSense?', 'Mag-logout sa SoilSense?')),
        content: Text(settings.text(
          'Are you sure you want to log out? Your saved soil readings will remain private in your account, but you will need to sign in again to access them.',
          'Sigurado ka bang gusto mong mag-logout? Mananatiling pribado sa account mo ang mga naka-save na soil reading, pero kailangan mong mag-sign in muli para ma-access ang mga ito.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(settings.text('Cancel', 'Kanselahin')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            icon: Icon(Icons.logout),
            label: Text(settings.text('Log Out', 'Mag-logout')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<NotificationService>().unregisterCurrentToken();
    if (!mounted) return;
    await context.read<AuthService>().signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }
}
