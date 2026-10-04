import 'package:flutter/material.dart';

/// Small, calm entrance motion used for content cards and data sections.
/// Main bottom-navigation routes intentionally remain transition-free.
class SoilSenseReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  const SoilSenseReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 260),
    this.offsetY = 10,
  });

  @override
  State<SoilSenseReveal> createState() => _SoilSenseRevealState();
}

class _SoilSenseRevealState extends State<SoilSenseReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(curved);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}


/// Calm transition for secondary destinations such as Profile, Notifications,
/// Settings, Help and Privacy. Main bottom-navigation routes deliberately do
/// not use this helper so the bottom tabs remain visually static.
Future<T?> pushSoilSenseSecondaryPage<T>(
  BuildContext context,
  Widget page,
) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 230),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}
