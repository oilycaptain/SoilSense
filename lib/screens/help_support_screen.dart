import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: SoilSenseAppBarLeading(showBackButton: true),
        title: Text('Help & FAQ'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HelpHeader(),
          SizedBox(height: 12),
          _Faq(
            question: 'How do I scan the soil?',
            answer:
                'Insert the probe correctly, keep it still, choose a scan duration in Profile, then press the physical START button. A completed scan uploads the averaged reading. Press STOP anytime to cancel; partial samples are discarded and are not uploaded.',
          ),
          _Faq(
            question: 'Does every new user need to set up Wi-Fi?',
            answer:
                'No. Wi-Fi belongs to the physical ESP32, not to a user account. If the device already remembers a working 2.4 GHz network, new users do not need to configure it again.',
          ),
          _Faq(
            question: 'When do I hold the button for 3 seconds?',
            answer:
                'Only when the ESP32 needs a new Wi-Fi network or password. Hold the physical button for about 3 seconds, then send the target 2.4 GHz Wi-Fi credentials from SoilSense Wi-Fi Setup.',
          ),
          _Faq(
            question: 'What happens when the device is borrowed?',
            answer:
                'The administrator assigns the device to the new current owner. Future scans go to that account. The previous owner keeps their own historical readings privately and can continue reviewing them.',
          ),
          _Faq(
            question: 'Can I view data while the IoT device is offline?',
            answer:
                'Yes. SoilSense keeps your last saved reading, history, analysis, and recommendations visible for reference. The Online/Offline badge tells you whether the displayed data is currently live.',
          ),
          _Faq(
            question: 'What do the LED indicators mean?',
            answer:
                'Red means the IoT device is powered; red blinking indicates an error. Blue means Wi-Fi setup is active. Yellow blinks during the scan. Green confirms a successful upload and also lights briefly when a scan is manually stopped.',
          ),
          _Faq(
            question: 'Why did I not receive an Android notification?',
            answer:
                'Check that Android notification permission is enabled for SoilSense. Local live-event notifications require the app process to still be available in the foreground or background; fully force-stopping the app prevents it from observing Firestore until it is opened again.',
          ),
          _Faq(
            question: 'Where can I get support?',
            answer:
                'For account assignment, device ownership, or project-specific troubleshooting, contact the SoilSense administrator or project team. For hardware issues, check power, wiring, the 2.4 GHz Wi-Fi connection, and the Serial Monitor output.',
          ),
        ],
      ),
    );
  }
}

class _HelpHeader extends StatelessWidget {
  const _HelpHeader();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.support_agent_rounded, color: AppTheme.primaryGreen),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SoilSense Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  SizedBox(height: 4),
                  Text('Quick answers for account, device, Wi-Fi, scanning, and notification questions.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(Icons.help_outline_rounded, color: AppTheme.primaryGreen),
        title: Text(question, style: TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(answer, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
