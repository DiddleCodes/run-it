import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';

/// Replaces the generic dot-indicator carousel with a single track whose
/// active segment slides and stretches — reads as one continuous piece of
/// UI rather than a row of static dots.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = (constraints.maxWidth - (pageCount - 1) * 8) /
            pageCount;

        return Row(
          children: List.generate(pageCount, (i) {
            final distance = (page - i).clamp(-1.0, 1.0).abs();
            final active = 1 - distance;

            return Padding(
              padding: EdgeInsets.only(right: i == pageCount - 1 ? 0 : 8),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.emphasized,
                height: 4,
                width: segmentWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Color.lerp(trackColor, AppColors.amber, active),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
