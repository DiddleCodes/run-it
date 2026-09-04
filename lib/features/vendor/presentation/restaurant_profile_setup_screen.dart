import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../application/my_vendor_profile_controller.dart';
import '../application/vendor_application_controller.dart';
import 'widgets/vendor_profile_form.dart';

/// Task 12: the bridge between Task 7's still-local application wizard and
/// a real backend vendor row. Reached once, right after wizard submission
/// (auto-approved — see `VendorsService.upsertMyVendor`'s doc comment) —
/// but also self-heals a returning session (see `postAuthDestination`'s
/// doc comment): it checks `GET /vendors/me` itself first, and skips
/// straight to the shell if a real profile already exists rather than
/// asking the restaurant to redo this step.
class RestaurantProfileSetupScreen extends ConsumerWidget {
  const RestaurantProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existing = ref.watch(myVendorProfileProvider);

    return existing.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) {
        // A 404 genuinely means "no real vendor row yet" — first-run,
        // show the confirm form. Anything else (a connectivity blip, a
        // real backend error) is a real error state to surface honestly
        // rather than silently treating it as "first run".
        if (error is ApiException && error.statusCode == 404) return const _SetupForm();
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 12),
                  const Text("Couldn't check your business profile."),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.read(myVendorProfileProvider.notifier).refresh(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      data: (vendor) {
        // Already real — nothing left to confirm. Scheduled for next frame
        // since navigating away mid-build isn't safe.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(AppRoutes.restaurantOrders);
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class _SetupForm extends ConsumerWidget {
  const _SetupForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(vendorApplicationProvider);
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're approved!",
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: onBg, fontSize: 25),
                ).animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
                const SizedBox(height: 6),
                Text(
                  "Confirm your business details below — we've carried over what you already gave us.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                VendorProfileForm(
                  initialBusinessName: application.businessName,
                  initialCategory: application.category,
                  initialDescription: application.description,
                  initialLogoBytes: application.storefrontPhoto,
                  requestedCampusId: application.campus?.id,
                  submitLabel: 'Get Started',
                  onSaved: (_) {
                    ref
                        .read(appNotificationProvider.notifier)
                        .success('Your dashboard is ready.');
                    context.go(AppRoutes.restaurantOrders);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
