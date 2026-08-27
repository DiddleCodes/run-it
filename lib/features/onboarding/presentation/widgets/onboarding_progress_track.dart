import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';

/// Segmented pagination dots for the onboarding sequence — left-aligned,
/// fixed-width segments (not full-bleed) so they sit as a compact mark in
/// the bottom-left corner rather than spanning the screen.
class OnboardingProgressTrack extends StatelessWidget {
  const OnboardingProgressTrack({
    super.key,
    required this.pageCount,
    required this.page,
  });

  final int pageCount;
  final double page;

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
              color: Color.lerp(
                AppColors.onMaroon.withValues(alpha: 0.28),
                AppColors.accentRose,
                active,
              ),
            ),
          ),
        );
      }),
    );
  }
}
