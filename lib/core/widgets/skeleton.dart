import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';

/// Task 10 performance audit: a shared skeleton/shimmer placeholder,
/// replacing bare spinners and "…" text on data-heavy screens (Home, Jobs,
/// Menu, Wallet) — a shape close to the real content reads as "this is
/// loading" far better than a blank center-screen spinner, and avoids a
/// jarring pop-in once data arrives. Built on flutter_animate's built-in
/// `.shimmer()` effect rather than a bespoke AnimationController, matching
/// this codebase's existing motion conventions.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
    this.baseColor = AppColors.borderSubtle,
    this.shimmerColor,
  });

  final double? width;
  final double height;
  final double borderRadius;

  /// Defaults suit a light card surface. Pass lighter values (e.g.
  /// `Colors.white` alpha-blended) when placing a skeleton over a dark/
  /// colored background, such as the Wallet balance card.
  final Color baseColor;
  final Color? shimmerColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1200.ms,
            color: shimmerColor ?? AppColors.surfaceCard.withValues(alpha: 0.6),
          ),
    );
  }
}

/// A single skeleton row shaped like a list item with a leading thumbnail —
/// covers the transaction/order/job-card shape without a bespoke skeleton
/// per screen.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key, this.padding = const EdgeInsets.symmetric(vertical: 10)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const SkeletonBox(width: 42, height: 42, borderRadius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 140, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 48, height: 13),
        ],
      ),
    );
  }
}

/// A vertical run of [count] skeleton tiles — the common case of "a list is
/// loading," so callers don't have to hand-roll the Column each time.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const SkeletonListTile()),
    );
  }
}
