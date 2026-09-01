import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/payout/application/payout_controller.dart';
import '../routing/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A card grouping several [SettingsRow]s with hairline dividers between
/// them — shared by every Profile screen's settings list (Task 8c built it
/// for Runner Profile; Task 12 lifts it here for the Restaurant Dashboard's
/// own Profile tab).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, color: AppColors.borderSubtle, indent: 54),
          ],
        ],
      ),
    );
  }
}

/// A single settings-list row (icon, title, optional trailing label/chevron)
/// — shared by every Profile screen in the app (Task 8c built it for
/// Runner Profile; Task 12 lifts it here so the Restaurant Dashboard's own
/// Profile tab doesn't duplicate it). [accentColor] lets each role keep its
/// own icon accent (maroon for student/runner, forest for restaurant)
/// without forking the row itself.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.trailingLabel,
    this.destructive = false,
    this.onTap,
    this.trailing,
    this.accentColor = AppColors.primaryMaroon,
  });
  final IconData icon;
  final String title;
  final String? trailingLabel;
  final bool destructive;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.inkText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? AppColors.error : accentColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
              ),
            ),
            if (trailing != null)
              trailing!
            else ...[
              if (trailingLabel != null) ...[
                Text(
                  trailingLabel!,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(width: 6),
              ],
              if (onTap != null)
                const Icon(CupertinoIcons.chevron_right, color: AppColors.mutedText, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// Task 8c Part B: wires the "Payouts" row to the real
/// [PayoutAccountScreen] and reflects the saved account (masked) as the
/// row's trailing label — "Not set" until one exists. Loads once per mount
/// rather than on every parent rebuild. Role-agnostic — [PayoutController]
/// itself is keyed off whichever user is signed in, so this same row (and
/// the same backend record) works unchanged for a runner or a restaurant.
class PayoutsRow extends ConsumerStatefulWidget {
  const PayoutsRow({super.key, this.accentColor = AppColors.primaryMaroon});
  final Color accentColor;

  @override
  ConsumerState<PayoutsRow> createState() => _PayoutsRowState();
}

class _PayoutsRowState extends ConsumerState<PayoutsRow> {
  @override
  void initState() {
    super.initState();
    ref.read(payoutControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(payoutControllerProvider);
    final subtitle = account == null
        ? 'Not set'
        : '${account.maskedAccountNumber} — ${account.bankName}';
    return SettingsRow(
      icon: Icons.account_balance_outlined,
      title: 'Payouts',
      trailingLabel: subtitle,
      accentColor: widget.accentColor,
      onTap: () => context.push(AppRoutes.payoutAccount),
    );
  }
}
