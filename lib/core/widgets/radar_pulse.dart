import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Concentric rings expanding outward from the brand mark — a recurring
/// motif meant to read as "proximity" / "someone nearby", carried from
/// splash through onboarding and later the live match/tracking screens
/// rather than used once and discarded.
class RadarPulse extends StatefulWidget {
  const RadarPulse({
    super.key,
    required this.child,
    this.color = AppColors.primaryMaroon,
    this.maxExtent = 340,
    this.ringCount = 3,
  });

  final Widget child;
  final Color color;
  final double maxExtent;
  final int ringCount;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.maxExtent,
      height: widget.maxExtent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size.square(widget.maxExtent),
                painter: _RadarPainter(
                  progress: _controller.value,
                  color: widget.color,
                  ringCount: widget.ringCount,
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  final double progress;
  final Color color;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    for (var i = 0; i < ringCount; i++) {
      final t = (progress + i / ringCount) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1 - t) * 0.35;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
