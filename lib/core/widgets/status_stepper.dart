import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Generic step-progress indicator shared across the delivery lifecycle
/// (runner active-delivery, student order tracking) and the KYC capture
/// wizard — one widget instead of duplicating the same stepper three
/// times. Expresses the app's "route line" motif as discrete nodes: mint
/// for ground already covered, signature for "you are here", a quiet
/// hairline for what's ahead.
class StatusStepper extends StatelessWidget {
  const StatusStepper({
    super.key,
    required this.steps,
    required this.activeIndex,
  });

  final List<String> steps;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    const border = AppColors.borderSubtle;
    const surface = AppColors.surfaceCard;
    const text = AppColors.inkText;
    const muted = AppColors.mutedText;
    const traveled = AppColors.accentRoseDeep;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final segment = index ~/ 2;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: segment < activeIndex ? traveled : border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final item = index ~/ 2;
        final done = item < activeIndex;
        final current = item == activeIndex;
        final nodeColor = done ? traveled : (current ? AppColors.primaryMaroon : surface);
        return SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done || current ? nodeColor : border,
                    width: current ? 2 : 1,
                  ),
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: AppColors.onMaroon,
                      )
                    : current
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.onMaroon,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 7),
              Text(
                steps[item],
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: done || current ? text : muted,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
