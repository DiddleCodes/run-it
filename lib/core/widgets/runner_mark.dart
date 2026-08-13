import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';

/// The brand mark, built as native vector rather than a flattened image so
/// it can actually move: a continuous forward lean plus trailing speed
/// lines. Reused anywhere the product wants to say "someone is en route" —
/// splash, loading states, match-found moments — instead of a generic
/// spinner.
class RunnerMark extends StatelessWidget {
  const RunnerMark({super.key, this.size = 96, this.animate = true});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0A09),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (animate)
            Positioned(
              left: size * 0.16,
              top: size * 0.4,
              child: _SpeedLines(size: size),
            ),
          Icon(
            Icons.directions_run_rounded,
            size: size * 0.56,
            color: AppColors.amber,
          ),
        ],
      ),
    );

    if (!animate) return badge;

    return badge
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveX(
          begin: -2,
          end: 2,
          duration: 900.ms,
          curve: Curves.easeInOutSine,
        );
  }
}

class _SpeedLines extends StatelessWidget {
  const _SpeedLines({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(size * 0.16, 0),
        SizedBox(height: size * 0.045),
        _line(size * 0.10, 220),
        SizedBox(height: size * 0.045),
        _line(size * 0.06, 420),
      ],
    );
  }

  Widget _line(double width, int delayMs) {
    return Container(
          height: 2,
          width: width,
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .fadeIn(delay: delayMs.ms, duration: 300.ms)
        .then()
        .fadeOut(delay: 300.ms, duration: 400.ms);
  }
}
