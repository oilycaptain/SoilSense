import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: SoilSenseAppBarLeading(showBackButton: true),
        title: Text('Terms & Privacy'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoSection(
            icon: Icons.eco_outlined,
            title: 'Purpose of SoilSense',
            body:
                'SoilSense is an agricultural decision-support application for soil monitoring and crop-management guidance. Sensor accuracy depends on the physical probe, calibration, soil conditions, power, and network availability.',
          ),
          _InfoSection(
            icon: Icons.person_outline,
            title: 'Account and ownership privacy',
            body:
                'Only one account is assigned as the current SoilSense device owner at a time. New scans are saved to that account. When ownership changes, each account keeps access to its own previously saved readings; another user does not inherit that history.',
          ),
          _InfoSection(
            icon: Icons.cloud_outlined,
            title: 'Cloud data',
            body:
                'Account profiles, private soil readings, reports, alerts, device status, and ownership settings are stored using Firebase services. Firestore security rules restrict private records to the signed-in account that owns them, while administrator actions are separately protected.',
          ),
          _InfoSection(
            icon: Icons.auto_awesome_outlined,
            title: 'AI features',
            body:
                'AI is used as additional guidance for crop suitability and smart crop planning. Soil health assessment and report generation remain deterministic and explainable so core results do not depend on AI availability or quota.',
          ),
          _InfoSection(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            body:
                'SoilSense may create account notifications for new sensor readings, abnormal soil conditions, device connectivity, and ownership changes. Android notification permission can be controlled in the phone settings.',
          ),
          _InfoSection(
            icon: Icons.gavel_outlined,
            title: 'Responsible use',
            body:
                'Recommendations are decision-support guidance and should be combined with local agricultural practices, crop requirements, professional advice, and properly calibrated soil testing when making important farm decisions.',
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryGreen),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 6),
                  Text(body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
