import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import 'motion.dart';
import 'unread_alerts_button.dart';

List<Widget> soilSenseUserActions(BuildContext context) {
  return [
    const UnreadAlertsButton(),
    IconButton(
      tooltip: 'User profile',
      icon: const Icon(Icons.person_outline),
      onPressed: () => pushSoilSenseSecondaryPage(
        context,
        const ProfileScreen(),
      ),
    ),
  ];
}
