import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Abstract composition (not a literal storefront illustration) used for
/// the "every campus spot" page — a loose grid of tilted icon tiles over
/// a soft amber glow, in the same warm palette as the peer-handoff art so
/// the carousel still reads as one system.
class CampusCollageVisual extends StatelessWidget {
  const CampusCollageVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurface;

    final tiles = <(IconData, double, Alignment)>[
      (Icons.local_cafe_rounded, -8, Alignment(-0.7, -0.55)),
      (Icons.storefront_rounded, 6, Alignment(0.55, -0.65)),
      (Icons.fastfood_rounded, -5, Alignment(-0.15, -0.05)),
      (Icons.icecream_rounded, 9, Alignment(0.75, 0.15)),
      (Icons.local_pizza_rounded, -10, Alignment(-0.65, 0.55)),
      (Icons.shopping_bag_rounded, 7, Alignment(0.35, 0.7)),
    ];

    return SizedBox(
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.amber.withValues(alpha: isDark ? 0.22 : 0.28),
                  AppColors.amber.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          for (final tile in tiles)
            Align(
              alignment: tile.$3,
              child: Transform.rotate(
                angle: tile.$2 * 3.14159 / 180,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: tileColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.amber.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(tile.$1, color: AppColors.amber, size: 26),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
