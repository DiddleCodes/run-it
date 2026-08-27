import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Visualizes the requester/runner mode switch as two rose icon badges
/// joined by a traveling dash — styled to sit on the full-bleed maroon
/// onboarding background.
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
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                _Node(icon: Icons.shopping_bag_rounded, label: 'Request'),
                _Node(icon: Icons.bolt_rounded, label: 'Earn'),
              ],
            ),
          ),
          Positioned(
            child: SizedBox(
              width: 200,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.onMaroon.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final dx = (t < 0.5 ? t * 2 : (1 - t) * 2) * 200 - 100;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: AppColors.accentRose,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentRose,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryMaroonDeep.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.primaryMaroon, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppColors.onMaroon),
        ),
      ],
    );
  }
}
