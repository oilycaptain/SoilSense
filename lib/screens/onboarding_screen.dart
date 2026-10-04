import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.sensors_rounded,
      title: 'Understand Your Soil',
      filipinoTitle: 'Unawain ang Iyong Lupa',
      description:
          'Measure N, P, K, pH, moisture, temperature, and electrical conductivity with the SoilSense device.',
      filipinoDescription:
          'Sukatin ang N, P, K, pH, moisture, temperature, at electrical conductivity gamit ang SoilSense device.',
    ),
    _OnboardingPage(
      icon: Icons.agriculture_rounded,
      title: 'Make Better Crop Decisions',
      filipinoTitle: 'Mas Maayos na Desisyon sa Pananim',
      description:
          'Review soil condition, crop suitability, practical soil guidance, and a smart crop plan from each completed scan.',
      filipinoDescription:
          'Tingnan ang kondisyon ng lupa, crop suitability, praktikal na gabay, at smart crop plan mula sa bawat kumpletong scan.',
    ),
    _OnboardingPage(
      icon: Icons.wifi_tethering_rounded,
      title: 'Scan, Save, and Track',
      filipinoTitle: 'Mag-scan, Mag-save, at Subaybayan',
      description:
          'Connect the portable device, keep private reading history, receive alerts, and download soil reports directly to your phone.',
      filipinoDescription:
          'Ikonekta ang portable device, panatilihin ang pribadong history, tumanggap ng alerts, at direktang mag-download ng soil reports sa phone.',
    ),
  ];

  Future<void> _finish() async {
    await context.read<AppSettingsService>().completeOnboarding();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _next() async {
    if (_page == _pages.length - 1) {
      await _finish();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
              child: Row(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.eco_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'SoilSense',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: Text(settings.text('Skip', 'Laktawan')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final item = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: SoilSenseReveal(
                      key: ValueKey('onboarding-$index-${settings.languageCode}'),
                      offsetY: 14,
                      duration: const Duration(milliseconds: 320),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: .92, end: 1),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) => Transform.scale(
                              scale: scale,
                              child: child,
                            ),
                            child: Container(
                              width: 152,
                              height: 152,
                              decoration: BoxDecoration(
                                color: dark
                                    ? colors.primary.withOpacity(.13)
                                    : AppTheme.primaryGreen.withOpacity(.09),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.primary.withOpacity(.22),
                                ),
                              ),
                              child: Icon(item.icon, size: 72, color: colors.primary),
                            ),
                          ),
                          const SizedBox(height: 38),
                          Text(
                            settings.text(item.title, item.filipinoTitle),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 29,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            settings.text(item.description, item.filipinoDescription),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15.5,
                              height: 1.55,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (index) {
                      final selected = index == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: selected ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant.withOpacity(.28),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _next,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _page == _pages.length - 1
                              ? settings.text('Get Started', 'Magsimula')
                              : settings.text('Next', 'Susunod'),
                          key: ValueKey(_page == _pages.length - 1),
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String filipinoTitle;
  final String description;
  final String filipinoDescription;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.filipinoTitle,
    required this.description,
    required this.filipinoDescription,
  });
}
