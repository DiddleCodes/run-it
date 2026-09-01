import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Generic step-progress indicator shared across the delivery lifecycle
/// (runner active-delivery, student order tracking) and the KYC capture
/// wizard — one widget instead of duplicating the same stepper three
/// times. Expresses the app's "route line" motif as discrete nodes: mint
/// for ground already covered, signature for "you are here", a quiet
/// hairline for what's ahead.
///
/// Task 10: node/segment state changes now animate (color, checkmark
/// scale+fade) instead of snapping instantly, for every call site. The
/// travel-icon overlay is opt-in via [showTravelIndicator], since not every
/// caller wants a moving delivery icon riding the line.
class StatusStepper extends StatelessWidget {
  const StatusStepper({
    super.key,
    required this.steps,
    required this.activeIndex,
    this.showTravelIndicator = false,
    this.travelIcon = Icons.moped_rounded,
    this.nodeColumnWidth = 72,
  });

  final List<String> steps;
  final int activeIndex;
  final bool showTravelIndicator;
  final IconData travelIcon;

  /// Fixed width per node+label column. Defaults to the original 72dp for
  /// existing 3–4 step callers (KYC wizard, runner active-delivery); a
  /// 5-step caller with short labels (OrderTrackingScreen) passes a
  /// smaller value so the row still fits this codebase's baseline 390dp
  /// phone width without overflowing — see that screen's own comment.
  final double nodeColumnWidth;

  static const _nodeSize = 26.0;

  @override
  Widget build(BuildContext context) {
    final row = _StepRow(
      steps: steps,
      activeIndex: activeIndex,
      nodeColumnWidth: nodeColumnWidth,
    );
    if (!showTravelIndicator || steps.length < 2) return row;

    // RepaintBoundary: this is the one part of the stepper that repaints
    // continuously mid-transition (Task 10 performance audit) — isolating
    // it means the (mostly static) node/label row beneath it doesn't get
    // swept into the same repaint.
    //
    // LayoutBuilder wraps the Stack rather than sitting inside it: it
    // inserts its own RenderObject to intercept constraints, which breaks
    // Positioned's ParentData handoff to RenderStack if placed between
    // Stack and Positioned. TweenAnimationBuilder below has no RenderObject
    // of its own, so it's transparent to that handoff and safe to nest.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              row,
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: activeIndex.toDouble()),
                duration: AppMotion.slower,
                curve: AppMotion.emphasized,
                builder: (context, value, _) {
                  final clamped = value.clamp(0, (steps.length - 1).toDouble()).toDouble();
                  final centerX = _nodeCenterX(constraints.maxWidth, steps.length, clamped);
                  return Positioned(
                    left: centerX - _nodeSize / 2,
                    top: 0,
                    child: _TravelBadge(icon: travelIcon),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  double _nodeCenterX(double totalWidth, int stepCount, double fractionalIndex) {
    final segmentCount = stepCount - 1;
    final segmentWidth = (totalWidth - nodeColumnWidth * stepCount) / segmentCount;
    double centerFor(int i) => nodeColumnWidth * i + segmentWidth * i + nodeColumnWidth / 2;

    final lower = fractionalIndex.floor().clamp(0, stepCount - 1);
    final upper = fractionalIndex.ceil().clamp(0, stepCount - 1);
    final t = fractionalIndex - lower;
    return centerFor(lower) + (centerFor(upper) - centerFor(lower)) * t;
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.steps,
    required this.activeIndex,
    required this.nodeColumnWidth,
  });

  final List<String> steps;
  final int activeIndex;
  final double nodeColumnWidth;

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
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.emphasized,
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
          width: nodeColumnWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.emphasized,
                width: StatusStepper._nodeSize,
                height: StatusStepper._nodeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done || current ? nodeColor : border,
                    width: current ? 2 : 1,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.base,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey('done'),
                          size: 15,
                          color: AppColors.onMaroon,
                        )
                      : current
                      ? Container(
                          key: const ValueKey('current'),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.onMaroon,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('upcoming')),
                ),
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

class _TravelBadge extends StatelessWidget {
  const _TravelBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: StatusStepper._nodeSize,
      height: StatusStepper._nodeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryMaroon.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 14, color: AppColors.onMaroon),
    );
  }
}
