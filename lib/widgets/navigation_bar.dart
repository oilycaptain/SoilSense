import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

class SoilSenseNavBar extends StatefulWidget {
  final int currentIndex;

  const SoilSenseNavBar({super.key, required this.currentIndex});

  @override
  State<SoilSenseNavBar> createState() => _SoilSenseNavBarState();
}

class _SoilSenseNavBarState extends State<SoilSenseNavBar> {
  int? _pressedIndex;
  bool _navigating = false;

  Widget _icon(int index, IconData icon) {
    return AnimatedScale(
      scale: _pressedIndex == index ? .88 : 1,
      duration: const Duration(milliseconds: 85),
      curve: Curves.easeOut,
      child: Icon(icon),
    );
  }

  Future<void> _open(int index) async {
    if (index == widget.currentIndex || _navigating) return;
    _navigating = true;
    setState(() => _pressedIndex = index);
    await Future<void>.delayed(const Duration(milliseconds: 75));
    if (!mounted) return;
    setState(() => _pressedIndex = null);

    final route = switch (index) {
      0 => '/home',
      1 => '/soil-analysis',
      2 => '/crop-recommendation',
      3 => '/reports',
      _ => '/home',
    };
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unselected = dark ? colors.onSurfaceVariant : AppTheme.textLight;

    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: dark ? AppTheme.accentGreen : AppTheme.primaryGreen,
      unselectedItemColor: unselected,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      items: [
        BottomNavigationBarItem(
          icon: _icon(0, Icons.home_outlined),
          activeIcon: _icon(0, Icons.home),
          label: settings.text('Home', 'Home'),
        ),
        BottomNavigationBarItem(
          icon: _icon(1, Icons.science_outlined),
          activeIcon: _icon(1, Icons.science),
          label: settings.text('Analysis', 'Pagsusuri'),
        ),
        BottomNavigationBarItem(
          icon: _icon(2, Icons.agriculture_outlined),
          activeIcon: _icon(2, Icons.agriculture),
          label: settings.text('Crops', 'Pananim'),
        ),
        BottomNavigationBarItem(
          icon: _icon(3, Icons.description_outlined),
          activeIcon: _icon(3, Icons.description),
          label: settings.text('Reports', 'Ulat'),
        ),
      ],
      onTap: _open,
    );
  }
}
