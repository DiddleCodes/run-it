import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's existing abstract accent mark — a pair of [Icons
/// .auto_awesome_rounded] glyphs at different sizes, first used as a
/// decorative flourish around the receipt icon in the runner home
/// screen's empty recent-activity state (see
/// `RunnerScreens._RecentActivityEmptyState`). Task 56 reuses the same
/// glyph as a visible accent on hero icon badges (Welcome Back, Create
/// Account) rather than inventing a new decorative shape.
class SparkleAccent extends StatelessWidget {
  const SparkleAccent({
    super.key,
    required this.child,
    this.color = AppColors.gold,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          top: -6,
          right: -8,
          child: Icon(Icons.auto_awesome_rounded, size: 18, color: color),
        ),
        Positioned(
          bottom: -2,
          left: -10,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: color.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}
