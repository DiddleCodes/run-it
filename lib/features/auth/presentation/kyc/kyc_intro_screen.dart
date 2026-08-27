import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/icon_badge_row.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_models.dart';

/// Consent/context screen shown once, right before the KYC capture wizard
/// — sets expectations (what's checked, why) before the camera opens.
class KycIntroScreen extends ConsumerWidget {
  const KycIntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunner =
        ref.watch(authControllerProvider)?.user.accountType ==
        AccountType.runner;

    final screen = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.accentRose,
                          AppColors.accentRoseDeep,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: AppElevation.raised(false),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.primaryMaroon,
                      size: 42,
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .scale(begin: const Offset(.85, .85)),
              const SizedBox(height: AppSpacing.xl),
              Builder(
                builder: (context) => Text(
                  'Keep our campus\nsafe & secure',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(color: AppColors.inkText),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Builder(
                builder: (context) => Text(
                  "A quick verification keeps every order and delivery on ${isRunner ? 'your route' : 'your campus'} trustworthy.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.mutedText),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Builder(
                builder: (context) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.borderSubtle),
                      boxShadow: AppElevation.card(false),
                    ),
                    child: Column(
                      children: [
                        const IconBadgeRow(
                          icon: Icons.badge_outlined,
                          label: 'Confirm your identity',
                          subtitle:
                              'A quick photo of your student or campus ID.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const IconBadgeRow(
                          icon: Icons.shield_outlined,
                          label: 'Protect the community',
                          subtitle: 'Verified accounts keep deliveries safe for everyone.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        IconBadgeRow(
                          icon: Icons.storefront_outlined,
                          label: 'Unlock checkout',
                          subtitle: isRunner
                              ? 'Get cleared to accept delivery jobs.'
                              : 'Get cleared to order from campus vendors.',
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Start Verification',
                onPressed: () => context.go(AppRoutes.kycCapture),
              ),
              const SizedBox(height: AppSpacing.sm),
              Builder(
                builder: (context) => Text(
                  'It only takes a few minutes',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return screen;
  }
}
