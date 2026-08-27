import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A row of rounded segments — one per step — used for linear step-through
/// flows (KYC capture, onboarding pagination) instead of a node-based
/// stepper. `currentIndex` segments (0-based, inclusive) render filled;
/// the rest render as a quiet resting track.
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    super.key,
    required this.stepCount,
    required this.currentIndex,
    this.filledColor,
    this.trackColor,
    this.height = 4,
    this.gap = 6,
  });

  final int stepCount;
  final int currentIndex;
  final Color? filledColor;
  final Color? trackColor;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final filled = filledColor ?? AppColors.primaryMaroon;
    final track = trackColor ?? AppColors.borderSubtle;

    return Row(
      children: List.generate(stepCount, (index) {
        final isFilled = index <= currentIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == stepCount - 1 ? 0 : gap),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: height,
              decoration: BoxDecoration(
                color: isFilled ? filled : track,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      }),
    );
  }
}
