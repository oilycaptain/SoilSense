import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/device_status_service.dart';
import '../theme/app_theme.dart';

class SoilSenseInfoButton extends StatelessWidget {
  SoilSenseInfoButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About SoilSense',
      icon: Icon(Icons.info_outline_rounded),
      onPressed: () => _showInformation(context),
    );
  }

  Future<void> _showInformation(BuildContext context) async {
    final deviceStatus = context.read<DeviceStatusService>();
    final status = deviceStatus.isDeviceOnline
        ? 'IoT device online'
        : deviceStatus.isSetupMode
            ? 'Wi-Fi setup mode'
            : deviceStatus.isInternetOnline
                ? 'IoT device offline'
                : 'Phone offline';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          minChildSize: .45,
          maxChildSize: .92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.eco_rounded, color: AppTheme.primaryGreen),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About SoilSense',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${AppConfig.appVersion} • $status',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              const _AboutItem(
                icon: Icons.sensors_outlined,
                title: 'What the app monitors',
                body:
                    'SoilSense receives nitrogen, phosphorus, potassium, pH, moisture, temperature, and electrical-conductivity readings from the ESP32 soil probe.',
              ),
              const _MeasurementCriteriaCard(),
              const _AboutItem(
                icon: Icons.history_rounded,
                title: 'Saved data remains available',
                body:
                    'When the IoT device is offline, your last saved private reading, history, soil assessment, crop guidance, and reports remain available. The Online/Offline badge tells you whether a new live scan can currently arrive.',
              ),
              const _AboutItem(
                icon: Icons.person_pin_circle_outlined,
                title: 'Private ownership model',
                body:
                    'Only the currently assigned owner receives new scans. If ownership changes, previous owners keep their own historical readings privately instead of losing them or sharing them with the new owner.',
              ),
              const _AboutItem(
                icon: Icons.auto_awesome_outlined,
                title: 'Where AI is used',
                body:
                    'AI is used as additional guidance for Crop Suitability Ranking and Smart Crop Plan. Soil Condition Assessment and report generation remain deterministic so core results are explainable and still work when AI is unavailable.',
              ),
              const _AboutItem(
                icon: Icons.security_outlined,
                title: 'Secure cloud connection',
                body:
                    'Firebase Authentication protects account sign-in, Firestore Security Rules restrict private user records, and HTTPS/TLS is used for cloud communication. Device ownership is controlled separately by the administrator.',
              ),
              const _AboutItem(
                icon: Icons.landscape_outlined,
                title: 'Generalized farm use',
                body:
                    'The app no longer requires users to manage Field IDs. A reading belongs to the signed-in account that owned the SoilSense device when the scan was uploaded, so it can be used across different farms without creating field records first.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeasurementCriteriaCard extends StatelessWidget {
  const _MeasurementCriteriaCard();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_rounded, color: AppTheme.primaryGreen, size: 21),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reading criteria & color guide',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'SoilSense project reference bands:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text('Nitrogen: 40–100 mg/kg'),
            Text('Phosphorus: 50–120 mg/kg'),
            Text('Potassium: 100–300 mg/kg'),
            Text('pH: 5.5–7.5'),
            Text('Moisture: 40–90%'),
            SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: const [
                _LegendChip(color: AppTheme.primaryGreen, label: 'Normal'),
                _LegendChip(color: Colors.red, label: 'Low'),
                _LegendChip(color: Colors.orange, label: 'High'),
                _LegendChip(color: Colors.grey, label: 'No data'),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'NPK is shown as mg/kg, a soil mass-concentration unit that is numerically equivalent to ppm. Temperature and EC are supplemental readings and are not currently classified as Low/Normal/High in the balance score. These are SoilSense decision-support reference bands, not universal laboratory standards for every crop or soil type.',
              style: TextStyle(color: muted, height: 1.4, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AboutItem extends StatelessWidget {
  const _AboutItem({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryGreen, size: 21),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text(body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SoilSenseAppBarLeading extends StatelessWidget {
  SoilSenseAppBarLeading({
    super.key,
    required this.showBackButton,
  });

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBackButton) BackButton(),
        SoilSenseInfoButton(),
      ],
    );
  }
}
