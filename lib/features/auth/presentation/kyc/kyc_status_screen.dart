import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/radar_pulse.dart';
import '../../application/auth_controller.dart';
import '../../application/kyc_flow_controller.dart';
import '../../domain/auth_models.dart';

/// This is often the screen a user sits on longest — waiting for review —
/// so every state (pending/verified/rejected) gets its own hero icon and
/// color treatment inside one consistent elevated card, rather than plain
/// colored text on a flat background. Reassuring, not clinical.
class KycStatusScreen extends ConsumerWidget {
  const KycStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final user = session?.user;
    if (user == null) return const SizedBox.shrink();

    final screen = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: _StatusCard(
              child: switch (user.kycStatus) {
                KycStatus.pending => const _PendingState(),
                KycStatus.verified => _VerifiedState(user: user),
                KycStatus.rejected => _RejectedState(
                  user: user,
                  reason: user.kycRejectionReason,
                ),
                KycStatus.none => const _PendingState(),
              },
            ),
          ),
        ),
      ),
    );

    return screen;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.raised(false),
      ),
      child: child,
    ).animate().fadeIn(duration: 260.ms).moveY(begin: 12, end: 0);
  }
}

class _PendingState extends StatelessWidget {
  const _PendingState();

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const amber = AppColors.warning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadarPulse(
          color: amber,
          maxExtent: 170,
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.hourglass_top_rounded, size: 40, color: amber),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Verifying your details…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: onBg),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "We're checking your details. This usually takes a few minutes.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 100),
          duration: const Duration(milliseconds: 4000),
          curve: Curves.easeInOut,
          builder: (context, value, _) => Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    value: value / 100,
                    minHeight: 6,
                    color: amber,
                    backgroundColor: AppColors.borderSubtle,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${value.round()}%',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: secondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiedState extends ConsumerStatefulWidget {
  const _VerifiedState({required this.user});
  final UserProfile user;

  @override
  ConsumerState<_VerifiedState> createState() => _VerifiedStateState();
}

class _VerifiedStateState extends ConsumerState<_VerifiedState> {
  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    final isRunner = widget.user.accountType == AccountType.runner;
    final destination = isRunner ? AppRoutes.runnerHome : AppRoutes.home;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _VerifiedBadge(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          "You're Verified!",
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: onBg),
        ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
        const SizedBox(height: AppSpacing.xs),
        Text(
          isRunner
              ? 'You can now see and accept delivery jobs.'
              : 'You can now order from vendors on your campus.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: secondary),
        ).animate().fadeIn(delay: 260.ms, duration: 300.ms),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: isRunner ? 'Start Earning' : 'Explore Menu',
          onPressed: () => context.go(destination),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.go(destination),
          // Uses the same muted `secondary` tone as this screen's body
          // copy rather than the default TextButtonTheme maroon, so it
          // stays legible while still reading as visually secondary to
          // the primary "Start Earning"/"Explore Menu" button above.
          style: TextButton.styleFrom(foregroundColor: secondary),
          child: const Text('Go to Home'),
        ),
      ],
    );
  }
}

/// Centered green check badge with a few scattered "confetti" accents —
/// the celebration moment inside the status card.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    const green = AppColors.success;
    final confetti = <(double, double, double, Color)>[
      (-60, -70, 10, green),
      (58, -60, 7, AppColors.accentRose),
      (-70, 40, 8, AppColors.accentRose),
      (66, 52, 11, green),
      (0, -84, 6, green),
    ];

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final c in confetti)
            Positioned(
              left: 110 + c.$1 - c.$3 / 2,
              top: 110 + c.$2 - c.$3 / 2,
              child:
                  Container(
                        width: c.$3,
                        height: c.$3,
                        decoration: BoxDecoration(
                          color: c.$4,
                          shape: BoxShape.circle,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 150.ms, duration: 300.ms)
                      .scale(begin: const Offset(0, 0)),
            ),
          Container(
                width: 116,
                height: 116,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: green.withValues(alpha: .4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.onMaroon,
                  size: 56,
                ),
              )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(.7, .7)),
        ],
      ),
    );
  }
}

class _RejectedState extends ConsumerWidget {
  const _RejectedState({required this.user, this.reason});
  final UserProfile user;
  final String? reason;

  /// Sends them straight back into just the ID/selfie/vehicle steps — not
  /// the whole onboarding funnel — by re-seeding the (transient, and
  /// already-reset-after-submission) capture wizard with their persisted
  /// [UserProfile.runnerType]. Without this, [kycStepsFor] would see a
  /// null runner type and fall back to the shorter student-runner step
  /// list even for an Independent Rider who still owes a vehicle step.
  void _resubmit(WidgetRef ref, BuildContext context) {
    final runnerType = user.runnerType;
    if (runnerType != null) {
      ref.read(kycFlowProvider.notifier).setRunnerType(runnerType);
    }
    context.go(AppRoutes.kycCapture);
  }

  void _contactSupport(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reach us at support@run-it.app and we’ll help sort this out.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const errorColor = AppColors.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: errorColor.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close_rounded, size: 42, color: errorColor),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Verification failed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: onBg),
        ),
        const SizedBox(height: AppSpacing.xs),
        // The specific reason from review, when the backend provides
        // one — never just a generic "rejected" label.
        Text(
          reason ?? 'We were unable to verify your documents.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Resubmit',
          onPressed: () => _resubmit(ref, context),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => _contactSupport(context),
          style: TextButton.styleFrom(foregroundColor: secondary),
          child: const Text('Contact support'),
        ),
      ],
    );
  }
}
