import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A circular tinted icon badge + bold label + muted subtext, laid out as
/// a row. Used wherever the identity system wants "icon-led" explanation
/// (KYC intro, onboarding) instead of an illustration.
class IconBadgeRow extends StatelessWidget {
  const IconBadgeRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.badgeSize = 48,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const badgeBg = AppColors.accentRose;
    const iconColor = AppColors.primaryMaroon;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: badgeSize,
          height: badgeSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: badgeSize * 0.46),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: onBg, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
