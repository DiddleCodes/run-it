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
                  onEdit: () => setState(() => _editing = true),
                ),
              const SizedBox(height: AppSpacing.lg),
              SettingsGroup(
                children: [
                  const PayoutsRow(accentColor: AppColors.accentForest),
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
    required this.onEdit,
  });
  final String businessName;
  final String category;
  final String? description;
  final String? logoUrl;
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
