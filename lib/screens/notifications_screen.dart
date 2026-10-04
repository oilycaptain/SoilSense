import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firestore_service.dart';
import '../services/device_status_service.dart';
import '../models/alert.dart';
import '../widgets/navigation_bar.dart';
import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/motion.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Alert> _alerts = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<Alert>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    _subscription = context.read<FirestoreService>().getAlertsStream().listen(
      (alerts) {
        if (!mounted) return;
        setState(() {
          _alerts = alerts;
          _isLoading = false;
          _errorMessage = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load alerts. Check your connection and try again.';
        });
      },
    );
  }

  Future<void> _refreshAll() async {
    final deviceStatus = context.read<DeviceStatusService>();
    await deviceStatus.refresh();
    if (!mounted) return;
    _subscribe();
    await Future<void>.delayed(Duration(milliseconds: 350));
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<FirestoreService>().markAllAlertsRead();
    } catch (error) {
      _showMessage('Could not mark all alerts as read.', error: true);
    }
  }

  Future<void> _markRead(Alert alert) async {
    if (!context.read<DeviceStatusService>().isInternetOnline) {
      _showMessage('Connect to the internet to update this alert.', error: true);
      return;
    }
    try {
      await context.read<FirestoreService>().markAlertRead(alert.id);
    } catch (error) {
      _showMessage('Could not update this alert.', error: true);
    }
  }

  Future<void> _deleteAlert(Alert alert) async {
    if (!context.read<DeviceStatusService>().isInternetOnline) {
      _showMessage('Connect to the internet to delete this notification.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete notification?'),
        content: Text(
          'This notification will be permanently removed from your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<FirestoreService>().deleteAlert(alert.id);
      _showMessage('Notification deleted.');
    } catch (error) {
      _showMessage('Could not delete this notification.', error: true);
    }
  }

  Future<void> _clearAllAlerts() async {
    if (!context.read<DeviceStatusService>().isInternetOnline) {
      _showMessage('Connect to the internet to clear notifications.', error: true);
      return;
    }

    final count = _alerts.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clear all notifications?'),
        content: Text(
          count == 1
              ? 'This notification will be permanently removed from your account.'
              : 'All $count notifications will be permanently removed from your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            child: Text('Clear all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<FirestoreService>().deleteAllAlerts();
      _showMessage('Notifications cleared.');
    } catch (error) {
      _showMessage('Could not clear notifications.', error: true);
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
    final deviceStatus = context.watch<DeviceStatusService>();
    final visibleAlerts = _alerts;
    final canPop = Navigator.canPop(context);

    Widget content;
    if ((deviceStatus.isLoading || _isLoading) && _alerts.isEmpty) {
      content = Center(child: CircularProgressIndicator());
    } else {
      content = RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, color: AppTheme.warningRed),
                      SizedBox(width: 10),
                      Expanded(child: Text(_errorMessage!)),
                    ],
                  ),
                ),
              ),
            if (_errorMessage != null) SizedBox(height: 12),
            if (visibleAlerts.isEmpty)
              SoilSenseReveal(
                child: Padding(
                  padding: const EdgeInsets.only(top: 70),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Sensor updates, device status changes, and important soil alerts will appear here automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...visibleAlerts.asMap().entries.map((entry) {
                final delayMs = entry.key > 6 ? 210 : entry.key * 35;
                return SoilSenseReveal(
                  key: ValueKey('notification-${entry.value.id}'),
                  delay: Duration(milliseconds: delayMs),
                  child: _buildNotificationCard(entry.value),
                );
              }),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 96 : 56,
        leading: SoilSenseAppBarLeading(showBackButton: canPop),
        title: Text('Notifications'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: Icon(Icons.check_circle_outline),
            onPressed: deviceStatus.isInternetOnline &&
                    visibleAlerts.any((alert) => !alert.read)
                ? _markAllRead
                : null,
          ),
          IconButton(
            tooltip: 'Clear all notifications',
            icon: Icon(Icons.delete_sweep_outlined),
            onPressed: deviceStatus.isInternetOnline && visibleAlerts.isNotEmpty
                ? _clearAllAlerts
                : null,
          ),
        ],
      ),
      body: content,
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 0),
    );
  }

  Widget _buildNotificationCard(Alert alert) {
    return Card(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: alert.severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getAlertIcon(alert),
                color: alert.severityColor,
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: TextStyle(
                            fontWeight: alert.read ? FontWeight.w600 : FontWeight.w700,
                                    fontSize: 14,
                          ),
                        ),
                      ),
                      if (!alert.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    alert.message,
                    style: TextStyle(
                      color: alert.read
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '${alert.category} • ${_getTimeAgo(alert.timestamp)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  if (!{'device', 'access', 'system', 'soil reading'}
                      .contains(alert.category.toLowerCase()))
                    Text(
                      'Value: ${alert.currentValue.toStringAsFixed(1)} (Optimal: ${alert.optimalRange})',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Notification options',
              onSelected: (value) {
                if (value == 'read') {
                  _markRead(alert);
                } else if (value == 'delete') {
                  _deleteAlert(alert);
                }
              },
              itemBuilder: (context) => [
                if (!alert.read)
                  const PopupMenuItem<String>(
                    value: 'read',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppTheme.primaryGreen),
                        SizedBox(width: 12),
                        Text('Mark as read'),
                      ],
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppTheme.warningRed),
                      SizedBox(width: 12),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAlertIcon(Alert alert) {
    switch (alert.category.toLowerCase()) {
      case 'moisture':
        return Icons.water_drop;
      case 'ph':
        return Icons.science;
      case 'nitrogen':
      case 'phosphorus':
      case 'potassium':
        return Icons.warning_amber_rounded;
      case 'soil reading':
        return Icons.sensors_rounded;
      case 'device':
        return Icons.router_outlined;
      case 'access':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.notifications;
    }
  }

  String _getTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
