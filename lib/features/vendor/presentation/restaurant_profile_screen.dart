import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/settings_row.dart';
import '../../auth/application/auth_controller.dart';
import '../application/my_vendor_profile_controller.dart';
import 'widgets/vendor_profile_form.dart';

/// Task 12's Profile tab — business info (reusing the exact same
/// [VendorProfileForm] the first-run completion screen uses, per the
/// task's own "reuses the same form" constraint), the Payouts row already
/// built in Task 8c, and Log Out.
class RestaurantProfileScreen extends ConsumerStatefulWidget {
  const RestaurantProfileScreen({super.key});

  @override
  ConsumerState<RestaurantProfileScreen> createState() => _RestaurantProfileScreenState();
}

class _RestaurantProfileScreenState extends ConsumerState<RestaurantProfileScreen> {
  bool _editing = false;

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Log out?'),
        content: const Text("You'll need your passcode to sign back in."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(authControllerProvider.notifier).logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendorAsync = ref.watch(myVendorProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(title: const Text('Profile'), backgroundColor: AppColors.backgroundCream, elevation: 0),
      body: SafeArea(
        top: false,
        child: vendorAsync.when(
          loading: () => const Center(child: AppSpinner()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    "Couldn't load your business profile.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.read(myVendorProfileProvider.notifier).refresh(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (vendor) => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 32),
            children: [
              if (_editing)
                VendorProfileForm(
                  initialBusinessName: vendor.businessName,
                  initialCategory: vendor.category,
                  initialDescription: vendor.description,
                  initialLogoUrl: vendor.logoUrl,
                  submitLabel: 'Save Changes',
                  onSaved: (_) {
                    setState(() => _editing = false);
                    ref.read(appNotificationProvider.notifier).success('Business profile updated.');
                  },
                )
              else
                _BusinessInfoCard(
                  businessName: vendor.businessName,
                  category: vendor.category,
                  description: vendor.description,
                  logoUrl: vendor.logoUrl,
                  averageRating: vendor.averageRating,
                  ratingCount: vendor.ratingCount,
                  onEdit: () => setState(() => _editing = true),
                ),
              const SizedBox(height: AppSpacing.lg),
              SettingsGroup(
                children: [
                  const PayoutsRow(accentColor: AppColors.accentForest),
                  _PayAtDeliveryRow(enabled: vendor.payAtDeliveryEnabled),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    accentColor: AppColors.accentForest,
                    onTap: () => ref
                        .read(appNotificationProvider.notifier)
                        .info('Reach us at support@run-it.app.'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.logout_rounded,
                    title: 'Log out',
                    destructive: true,
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessInfoCard extends StatelessWidget {
  const _BusinessInfoCard({
    required this.businessName,
    required this.category,
    required this.description,
    required this.logoUrl,
    required this.averageRating,
    required this.ratingCount,
    required this.onEdit,
  });
  final String businessName;
  final String category;
  final String? description;
  final String? logoUrl;

  // Task 48: the restaurant's own real rating — null/0 until it's ever
  // been rated, never a fabricated starting number.
  final double? averageRating;
  final int ratingCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.card(false),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: logoUrl == null || logoUrl!.isEmpty
                ? Container(
                    width: 64,
                    height: 64,
                    color: AppColors.accentForest.withValues(alpha: 0.1),
                    alignment: Alignment.center,
                    child: const Icon(Icons.storefront_rounded, color: AppColors.accentForest),
                  )
                : CachedNetworkImage(imageUrl: logoUrl!, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(category, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.accentForest)),
                if (averageRating != null && ratingCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: AppColors.gold),
                      const SizedBox(width: 3),
                      Text(
                        '${averageRating!.toStringAsFixed(1)} ($ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'})',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.accentForest, size: 20),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// Task 47: the restaurant's own opt-in for Pay on Delivery — off by
/// default (see Vendor.payAtDeliveryEnabled's schema doc comment). Flipping
/// it calls the real backend immediately; the switch only reflects the
/// confirmed value, reverting on a failed save rather than showing an
/// optimistic state the backend never actually accepted.
class _PayAtDeliveryRow extends ConsumerStatefulWidget {
  const _PayAtDeliveryRow({required this.enabled});
  final bool enabled;

  @override
  ConsumerState<_PayAtDeliveryRow> createState() => _PayAtDeliveryRowState();
}

class _PayAtDeliveryRowState extends ConsumerState<_PayAtDeliveryRow> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(myVendorProfileProvider.notifier).setPayAtDeliveryEnabled(value);
    } catch (_) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error("Couldn't update this setting. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: Icons.payments_outlined,
      title: 'Accept Pay on Delivery',
      accentColor: AppColors.accentForest,
      trailing: _saving
          ? const SizedBox(width: 20, height: 20, child: AppSpinner(size: 20, strokeWidth: 2))
          : Switch.adaptive(
              value: widget.enabled,
              activeTrackColor: AppColors.accentForest,
              onChanged: _toggle,
            ),
    );
  }
}
