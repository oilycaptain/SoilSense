import 'package:flutter/material.dart';

class AiSkeletonLoader extends StatefulWidget {
  const AiSkeletonLoader({
    super.key,
    this.cards = 1,
    this.compact = false,
  });

  final int cards;
  final bool compact;

  @override
  State<AiSkeletonLoader> createState() => _AiSkeletonLoaderState();
}

class _AiSkeletonLoaderState extends State<AiSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: .35, end: .72).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Column(
        children: List.generate(
          widget.cards,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == widget.cards - 1 ? 0 : 12),
            child: _SkeletonCard(compact: widget.compact),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade300;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 36 : 44,
                  height: compact ? 36 : 44,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(base, .52, 14),
                      const SizedBox(height: 9),
                      _line(base, .84, 10),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _line(base, 1, 11),
            const SizedBox(height: 9),
            _line(base, .78, 11),
            if (!compact) ...[
              const SizedBox(height: 9),
              _line(base, .62, 11),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(Color color, double widthFactor, double height) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
