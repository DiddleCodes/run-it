import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Icon-led composition (not a literal storefront illustration) used for
/// the "every campus spot" onboarding page — a loose grid of tilted rose
/// icon badges over a soft glow, styled to sit on the full-bleed maroon
/// onboarding background. Badges are joined by thin connector lines (each
/// node linked to its two nearest neighbours) so the cluster reads as one
/// connected network of spots rather than icons scattered at random.
class CampusCollageVisual extends StatelessWidget {
  const CampusCollageVisual({super.key});

  static const _tiles = <(IconData, double, Alignment)>[
    (Icons.local_cafe_rounded, -8, Alignment(-0.7, -0.55)),
    (Icons.storefront_rounded, 6, Alignment(0.55, -0.65)),
    (Icons.fastfood_rounded, -5, Alignment(-0.15, -0.05)),
    (Icons.icecream_rounded, 9, Alignment(0.75, 0.15)),
    (Icons.local_pizza_rounded, -10, Alignment(-0.65, 0.55)),
    (Icons.shopping_bag_rounded, 7, Alignment(0.35, 0.7)),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
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
                  AppColors.accentRose.withValues(alpha: 0.22),
                  AppColors.accentRose.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _NetworkLinesPainter(_tiles.map((t) => t.$3).toList()),
            ),
          ),
          for (final tile in _tiles)
            Align(
              alignment: tile.$3,
              child: Transform.rotate(
                angle: tile.$2 * 3.14159 / 180,
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentRose,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryMaroonDeep.withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    tile.$1,
                    color: AppColors.primaryMaroon,
                    size: 26,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws a thin line from each node to its two nearest neighbours — a
/// simple constellation/network layout rather than a hub-and-spoke one,
/// so the connections feel organic instead of radiating from a center.
class _NetworkLinesPainter extends CustomPainter {
  _NetworkLinesPainter(this.nodes);
  final List<Alignment> nodes;

  Offset _centerOf(Alignment a, Size size) =>
      Offset((a.x + 1) / 2 * size.width, (a.y + 1) / 2 * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final points = nodes.map((a) => _centerOf(a, size)).toList();

    final linePaint = Paint()
      ..color = AppColors.accentRose.withValues(alpha: 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = AppColors.accentRose.withValues(alpha: 0.55);

    final drawn = <(int, int)>{};
    for (var i = 0; i < points.length; i++) {
      final byDistance =
          [
            for (var j = 0; j < points.length; j++)
              if (j != i) j,
          ]..sort(
            (a, b) => (points[i] - points[a]).distanceSquared.compareTo(
              (points[i] - points[b]).distanceSquared,
            ),
          );
      for (final j in byDistance.take(2)) {
        final key = i < j ? (i, j) : (j, i);
        if (drawn.add(key)) {
          canvas.drawLine(points[i], points[j], linePaint);
        }
      }
    }
    for (final p in points) {
      canvas.drawCircle(p, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkLinesPainter oldDelegate) => false;
}
