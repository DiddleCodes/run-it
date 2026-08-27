import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/radar_pulse.dart';

/// Product-photo hero for the "Campus meals" onboarding page: the branded
/// delivery bag render on a radar-pulse glow, matching the splash's
/// "proximity" motif — real product weight instead of a flat vector card.
class DeliveryHeroVisual extends StatelessWidget {
  const DeliveryHeroVisual({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RadarPulse(
            color: AppColors.accentRose.withValues(alpha: 0.5),
            maxExtent: 280,
            ringCount: 4,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accentRose.withValues(alpha: 0.30),
                    AppColors.accentRose.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            child: Container(
              width: 190,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryMaroonDeep.withValues(alpha: 0.55),
                    AppColors.primaryMaroonDeep.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryMaroonDeep.withValues(alpha: 0.55),
                  blurRadius: 32,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/01_delivery_bag.png',
              height: 210,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
