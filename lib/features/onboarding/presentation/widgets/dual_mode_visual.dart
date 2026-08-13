import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/runner_mark.dart';

/// Visualizes the requester/runner mode switch — the app's actual point
/// of difference — as two nodes joined by a traveling dash, rather than
/// burying it in copy the way the source flow currently does.
class DualModeVisual extends StatefulWidget {
  const DualModeVisual({super.key});

  @override
  State<DualModeVisual> createState() => _DualModeVisualState();
}

class _DualModeVisualState extends State<DualModeVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return SizedBox(
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Node(
                  icon: Icons.shopping_bag_rounded,
                  label: 'Request',
                  tileColor: isDark
                      ? AppColors.darkSurfaceHigh
                      : AppColors.lightSurface,
                ),
                _Node(
                  icon: Icons.bolt_rounded,
                  label: 'Earn',
                  tileColor: isDark
                      ? AppColors.darkSurfaceHigh
                      : AppColors.lightSurface,
                ),
              ],
            ),
          ),
          Positioned(
            child: SizedBox(
              width: 200,
              height: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: trackColor)),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final dx = (t < 0.5 ? t * 2 : (1 - t) * 2) * 200 - 100;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: child,
              );
            },
            child: const RunnerMark(size: 44, animate: false),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.label, required this.tileColor});

  final IconData icon;
  final String label;
  final Color tileColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: tileColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: AppColors.amber, size: 30),
        ),
        const SizedBox(height: 12),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}
