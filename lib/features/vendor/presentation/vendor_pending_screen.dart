import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/icon_badge_row.dart';
import '../../../core/widgets/radar_pulse.dart';
import '../../auth/application/auth_controller.dart';
import '../application/vendor_application_controller.dart';

/// The end of the mobile road for a restaurant account — reached after
/// Review & Submit, and again on every later app open (see
/// `postAuthDestination`). There is deliberately nothing to tap into
/// beyond this screen: menu editing, order management, and anything else
/// vendor-facing is web-dashboard scope, unlocked by the approval email
/// this screen promises, not by more mobile screens.
class VendorPendingScreen extends ConsumerWidget {
  const VendorPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const forest = AppColors.accentForest;

    final application = ref.watch(vendorApplicationProvider);
    final businessName = application.businessName.trim().isEmpty
        ? 'your business'
        : application.businessName.trim();

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadarPulse(
                      color: forest,
                      maxExtent: 190,
                      child: Container(
                        width: 88,
                        height: 88,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.accentForest,
                              AppColors.accentForestDeep,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: AppElevation.raised(false),
                        ),
                        child: const Icon(
                          Icons.mark_email_read_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .scale(begin: const Offset(.85, .85)),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Application submitted',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(color: onBg),
                ).animate().fadeIn(delay: 150.ms, duration: 280.ms),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "We're reviewing $businessName. This usually takes 1–2 business days.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: secondary),
                ).animate().fadeIn(delay: 200.ms, duration: 280.ms),
                const SizedBox(height: AppSpacing.xxl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppElevation.card(false),
                  ),
                  child: const Column(
                    children: [
                      IconBadgeRow(
                        icon: Icons.fact_check_outlined,
                        label: "We'll review your details",
                        subtitle: 'A quick check against your business info.',
                      ),
                      SizedBox(height: AppSpacing.lg),
                      IconBadgeRow(
                        icon: Icons.mark_email_unread_outlined,
                        label: "You'll get an email",
                        subtitle:
                            'Sent to the phone/contact on file, once approved.',
                      ),
                      SizedBox(height: AppSpacing.lg),
                      IconBadgeRow(
                        icon: Icons.dashboard_outlined,
                        label: 'Follow the link to your dashboard',
                        subtitle: 'Manage your menu and orders from the RUN-It web dashboard.',
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 260.ms, duration: 300.ms),
                const SizedBox(height: AppSpacing.xl),
                TextButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  style: TextButton.styleFrom(foregroundColor: secondary),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
