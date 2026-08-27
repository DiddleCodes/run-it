import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A single row in a checklist card — a filled check icon (or a plain
/// outline icon for a non-completion row, e.g. a reassurance line) plus a
/// label. Used on the "Almost there" KYC summary.
class ChecklistRow extends StatelessWidget {
  const ChecklistRow({
    super.key,
    required this.label,
    this.complete = true,
    this.icon,
  });

  final String label;
  final bool complete;

  /// Overrides the leading icon (e.g. a lock icon for a reassurance row
  /// that isn't really a "done" state) — defaults to a filled/empty check.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    final iconBg = complete ? AppColors.accentRose : AppColors.borderSubtle;
    final iconColor = complete ? AppColors.primaryMaroon : secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(
              icon ?? (complete ? Icons.check_rounded : Icons.circle_outlined),
              size: 17,
              color: iconColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: onBg, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
