import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Shared pagination-dot indicator for any horizontally-swiped [PageView] —
/// originally the onboarding sequence's own progress track, generalized
/// (Task 54) for the Home screen's promo-banner carousel too, since both
/// are the same "which page am I on" affordance. Left-aligned, fixed-width
/// segments (not full-bleed) so it sits as a compact mark rather than
/// spanning the available width. [page] is a fractional page value (e.g.
/// straight from `PageController.page`) so the active dot animates
/// smoothly mid-swipe rather than snapping between pages.
class CarouselDots extends StatelessWidget {
  const CarouselDots({
    super.key,
    required this.pageCount,
    required this.page,
    this.activeColor = AppColors.accentRose,
    // AppColors.onMaroon at ~28% alpha — matches the original onboarding
    // track exactly (0xFF FBF4E9 @ 0.28 alpha ~= 0x47), spelled out as a
    // literal since a `const` default can't call `.withValues(...)`.
    this.inactiveColor = const Color(0x47FBF4E9),
  });

  final int pageCount;
  final double page;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(pageCount, (i) {
        final distance = (page - i).clamp(-1.0, 1.0).abs();
        final active = 1 - distance;

        return Padding(
          padding: EdgeInsets.only(right: i == pageCount - 1 ? 0 : 8),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.emphasized,
            height: 4,
            width: active > 0.5 ? 22 : 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Color.lerp(inactiveColor, activeColor, active),
            ),
          ),
        );
      }),
    );
  }
}
