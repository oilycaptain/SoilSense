import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/notifications_screen.dart';
import '../models/alert.dart';
import '../services/firestore_service.dart';
import 'motion.dart';

/// Notification bell with a small unread-count badge.
///
/// The badge is intentionally placed at the upper-left of the bell to match
/// the SoilSense UI. The number updates in real time from
/// Firestore as alerts are marked read/unread.
class UnreadAlertsButton extends StatelessWidget {
  const UnreadAlertsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Alert>>(
      stream: context.read<FirestoreService>().getAlertsStream(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data
                ?.where((alert) => !alert.read)
                .length ??
            0;
        final displayCount = unreadCount > 99 ? '99+' : '$unreadCount';

        return IconButton(
          tooltip: unreadCount > 0
              ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
              : 'Notifications',
          onPressed: () => pushSoilSenseSecondaryPage(
            context,
            const NotificationsScreen(),
          ),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              if (unreadCount > 0)
                Positioned(
                  left: -11,
                  top: -9,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.4),
                    ),
                    child: Text(
                      displayCount,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
