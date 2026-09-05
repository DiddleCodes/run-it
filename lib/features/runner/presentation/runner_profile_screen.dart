import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/campus_repository.dart';
import '../../../core/network/ratings_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/settings_row.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/set_passcode_screen.dart';
import '../../ordering/presentation/widgets/ordering_components.dart';
import '../application/runner_controller.dart';

String _vehicleLabel(VehicleType type) => switch (type) {
  VehicleType.bicycle => 'Bicycle',
  VehicleType.motorbike => 'Motorbike',
  VehicleType.keke => 'Keke',
};

/// Task 14 Part D: the real aggregate behind Runner Profile's Rating stat —
/// `GET /runners/:id/rating-summary`, replacing the old client-side
/// `_demoRating` fake derived from `userId.hashCode`. `autoDispose` since
/// this only matters while Profile is actually mounted.
final runnerRatingSummaryProvider =
    FutureProvider.autoDispose<RunnerRatingSummary?>((ref) async {
      final userId = ref.watch(authControllerProvider)?.user.id;
      if (userId == null) return null;
      return ref
          .watch(ratingsRepositoryProvider)
          .fetchRunnerRatingSummary(userId);
    });

class RunnerProfileScreen extends ConsumerWidget {
  const RunnerProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider)?.user;
    if (user == null) return const SizedBox.shrink();
    final session = ref.watch(runnerControllerProvider);

    final totalEarnings = session.earnings.fold(0, (sum, e) => sum + e.amount);
    // A genuine acceptance rate — offers the dashboard's 20s-countdown
    // flow actually showed this runner vs. how many they accepted (see
    // RunnerController.offersReceived/offersAccepted) — not a fabricated
    // percentage. Dashes until there's at least one offer to measure.
    final acceptanceRateLabel = session.offersReceived == 0
        ? '—'
        : '${(session.offersAccepted / session.offersReceived * 100).round()}%';
    final verified = user.kycStatus == KycStatus.verified;
    // The real aggregate (Task 14) — a dash while it's loading/unreachable
    // or genuinely has no ratings yet, never a fabricated number.
    final ratingSummary = ref.watch(runnerRatingSummaryProvider).valueOrNull;
    final ratingLabel =
        (ratingSummary == null || ratingSummary.ratingCount == 0)
        ? '—'
        : ratingSummary.averageRating.toStringAsFixed(1);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, AppSpacing.lg, 32),
          children: [
            _ProfileHeader(
              onSettingsTap: () => ref
                  .read(appNotificationProvider.notifier)
                  .info('Settings shortcuts are below.'),
            ),
            const SizedBox(height: 14),
            _ProfileHero(
              user: user,
              ratingLabel: ratingLabel,
              onTap: () => _showPersonalInfo(context, user),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.checklist_rounded,
                    label: 'Completed Deliveries',
                    value: session.earnings.length.toString(),
                  ),
                ),
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.verified_rounded,
                    label: 'Acceptance Rate',
                    value: acceptanceRateLabel,
                  ),
                ),
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.star_rounded,
                    label: 'Rating',
                    value: ratingLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Task 48: honest framing — matching/dispatch priority doesn't
            // actually weigh rating yet (informational only for now), so
            // this reads as encouragement toward a real future benefit,
            // not a claim about how jobs are assigned today.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Keep your rating high — it may unlock more job opportunities and bonuses down the line.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
              ),
            ),
            const SizedBox(height: 16),
            _WalletBalanceCard(
              total: totalEarnings,
              onTap: () => context.push(AppRoutes.earnings),
            ),
            if (!verified) ...[
              const SizedBox(height: 16),
              _PendingReviewCard(user: user),
            ],
            const SizedBox(height: 28),
            // TASK 4g §4 deliberate deviation: the reference mockup groups
            // everything into one flat list (Personal Info, Payout Info,
            // Documents, Help & Support, Log Out). Kept as 3 separate
            // grouped cards instead — Earnings/Payouts/Performance,
            // Personal/Verification/Vehicle, Security — since that groups
            // rows by what they're actually about rather than mixing
            // unrelated categories in one long scroll, matching how
            // Uber Driver/DoorDash Dasher organize the same information.
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Earnings',
                  onTap: () => context.push(AppRoutes.earnings),
                ),
                // Task 33: delivery earnings now land in an in-app wallet
                // balance (see OrderEscrowService.release()'s runner leg)
                // — this is where a runner actually sees that balance and
                // withdraws it, distinct from Earnings' own delivery-count
                // history above.
                SettingsRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallet',
                  onTap: () => context.push(AppRoutes.runnerWallet),
                ),
                const PayoutsRow(),
                SettingsRow(
                  icon: Icons.bar_chart_rounded,
                  title: 'Performance',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Performance insights are coming soon.'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Personal Info',
                  onTap: () => _showPersonalInfo(context, user),
                ),
                _VerificationRow(user: user),
                if (user.runnerType == RunnerType.independentRider)
                  _VehicleRow(user: user),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change passcode',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const SetPasscodeScreen(isChangingExisting: true),
                    ),
                  ),
                ),
                _BiometricRow(user: user),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Reach us at support@run-it.app.'),
                ),
                SettingsRow(
                  icon: Icons.info_outline_rounded,
                  title: 'About',
                  onTap: () => _showAbout(context),
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
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonalInfo(BuildContext context, UserProfile user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _PersonalInfoSheet(user: user),
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 24, AppSpacing.lg, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RUN-It',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Log out?'),
        content: const Text("You'll need your passcode to sign back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
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
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onSettingsTap});
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 42),
        Expanded(
          child: Center(
            child: Text(
              'Profile',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.inkText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        InkWell(
          onTap: onSettingsTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.maroonShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.gear,
              color: AppColors.inkText,
              size: 19,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.ratingLabel,
    required this.onTap,
  });
  final UserProfile user;
  final String ratingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final verified = user.kycStatus == KycStatus.verified;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.ml),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: AppElevation.card(false),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // A photo-style placeholder (initial on a gradient disc,
                // same language `_ThreadRow` already uses for contacts
                // without a photo) rather than a generic person-silhouette
                // icon — there's no real avatar upload yet, but this reads
                // as "this runner's avatar", not "no avatar set".
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accentRoseDeep, AppColors.accentRose],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    user.name.trim().isEmpty
                        ? '?'
                        : user.name.trim()[0].toUpperCase(),
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppColors.primaryMaroon,
                      fontSize: 26,
                    ),
                  ),
                ),
                if (verified)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surfaceCard,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.checkmark_alt,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(color: AppColors.inkText, fontSize: 19),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Runner',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        ratingLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.inkText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(width: 10),
                      // TASK 4g §4 deliberate deviation: the reference
                      // mockup doesn't show a role-type pill here. Kept
                      // anyway — Student Runner vs. Independent Rider
                      // drives real behavior in this app (geofencing,
                      // vehicle info, KYC steps), so surfacing which one a
                      // runner is at a glance is worth the extra pill.
                      if (user.runnerType != null)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryMaroon.withValues(
                                alpha: .1,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              user.runnerType == RunnerType.independentRider
                                  ? 'Independent Rider'
                                  : 'Student Runner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.primaryMaroon,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: AppColors.mutedText,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.accentRose,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryMaroon),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }
}

/// Reuses real runner earnings data ([RunnerSession.earnings]) rather than
/// the student-side [walletBalanceProvider] (a different, unrelated
/// concept) or a new persisted balance — this is simply the runner's
/// lifetime earnings total, displayed as their payable balance.
class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({required this.total, required this.onTap});
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.ml),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryMaroon, AppColors.primaryMaroonDeep],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryMaroon.withValues(alpha: .3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wallet balance',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.onMaroon.withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    naira(total),
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(color: AppColors.onMaroon, fontSize: 26),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.onMaroon.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.onMaroon,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on Profile whenever KYC hasn't cleared yet — "account exists,
/// earning doesn't, until cleared" per TASK 4g §1, not a blocked screen.
/// Tapping it goes to the real KYC status screen rather than duplicating
/// its copy here.
class _PendingReviewCard extends StatelessWidget {
  const _PendingReviewCard({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final rejected = user.kycStatus == KycStatus.rejected;
    return InkWell(
      onTap: () => context.push(AppRoutes.kycStatus),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: rejected ? AppColors.accentRose : AppColors.goldTint,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(
              rejected
                  ? Icons.error_outline_rounded
                  : Icons.hourglass_top_rounded,
              color: rejected ? AppColors.error : AppColors.gold,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rejected
                        ? 'Verification needs another look'
                        : 'Verification pending review',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.inkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rejected ? 'Tap to see what needs fixing.' : "You can browse jobs, but can't go online until verified.",
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: AppColors.mutedText,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// A green "Verified" pill tied to the real [UserProfile.kycStatus] —
/// links into the existing `kyc_status_screen.dart` rather than
/// duplicating any part of the KYC flow here.
class _VerificationRow extends StatelessWidget {
  const _VerificationRow({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (user.kycStatus) {
      KycStatus.verified => (
        'Verified',
        AppColors.successBackground,
        AppColors.success,
      ),
      KycStatus.pending => ('Pending', AppColors.goldTint, AppColors.gold),
      KycStatus.rejected => (
        'Action needed',
        AppColors.accentRose,
        AppColors.error,
      ),
      KycStatus.none => (
        'Not started',
        AppColors.borderSubtle,
        AppColors.mutedText,
      ),
    };
    return SettingsRow(
      icon: Icons.verified_user_outlined,
      title: 'Verification',
      onTap: () => context.push(AppRoutes.kycStatus),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            CupertinoIcons.chevron_right,
            color: AppColors.mutedText,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _PersonalInfoSheet extends ConsumerWidget {
  const _PersonalInfoSheet({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <(String, String)>[
      ('Name', user.name),
      // Task 28: a runner's `contact` is their email now (the real OTP
      // channel) — phone is a separate field, shown as its own row when
      // present rather than folded into a generic "Contact" label.
      ('Email', user.contact),
      if (user.phone != null && user.phone!.isNotEmpty)
        ('Phone', user.phone!),
      ('Campus', ref.watch(campusNameProvider(user.campusId)) ?? '—'),
      if (user.classOrGrade != null && user.classOrGrade!.isNotEmpty)
        ('Class / Grade', user.classOrGrade!),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Info',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 16),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: AppColors.inkText),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BiometricRow extends ConsumerStatefulWidget {
  const _BiometricRow({required this.user});
  final UserProfile user;

  @override
  ConsumerState<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends ConsumerState<_BiometricRow> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final auth = ref.read(authControllerProvider.notifier);
    if (value) {
      final ok = await auth.enableBiometric();
      if (!ok && mounted) {
        ref
            .read(appNotificationProvider.notifier)
            .warning('Could not enable biometric login.');
      }
    } else {
      await auth.disableBiometric();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: Icons.fingerprint_rounded,
      title: 'Biometric login',
      trailing: _busy
          ? const AppSpinner(size: 20, strokeWidth: 2.2)
          : Switch.adaptive(
              value: widget.user.biometricEnabled,
              activeThumbColor: AppColors.primaryMaroon,
              onChanged: _toggle,
            ),
    );
  }
}

class _VehicleRow extends ConsumerWidget {
  const _VehicleRow({required this.user});
  final UserProfile user;

  void _edit(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _EditVehicleSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = user.vehicleType;
    final subtitle = type == null
        ? 'Not set'
        : [
            _vehicleLabel(type),
            if (user.vehiclePlate != null && user.vehiclePlate!.isNotEmpty)
              user.vehiclePlate!,
          ].join(' · ');
    return SettingsRow(
      icon: Icons.two_wheeler_rounded,
      title: 'Vehicle / Mode',
      trailingLabel: subtitle,
      onTap: () => _edit(context, ref),
    );
  }
}

class _EditVehicleSheet extends ConsumerStatefulWidget {
  const _EditVehicleSheet({required this.user});
  final UserProfile user;

  @override
  ConsumerState<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends ConsumerState<_EditVehicleSheet> {
  late VehicleType? _type = widget.user.vehicleType;
  late final _plateController = TextEditingController(
    text: widget.user.vehiclePlate ?? '',
  );
  bool _showPlateError = false;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  bool get _plateRequired => _type != null && _type != VehicleType.bicycle;

  Future<void> _save() async {
    final type = _type;
    if (type == null) return;
    final plate = _plateController.text.trim();
    if (_plateRequired && !isPlausiblePlateNumber(plate)) {
      setState(() => _showPlateError = true);
      return;
    }
    await ref
        .read(authControllerProvider.notifier)
        .updateVehicle(
          vehicleType: type,
          vehiclePlate: plate.isEmpty ? null : plate,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        20,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final type in VehicleType.values) ...[
                if (type != VehicleType.values.first) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _type = type;
                      _showPlateError = false;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _type == type
                            ? AppColors.primaryMaroon.withValues(alpha: .1)
                            : AppColors.backgroundCream,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: _type == type
                              ? AppColors.primaryMaroon
                              : AppColors.borderSubtle,
                          width: _type == type ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(switch (type) {
                            VehicleType.bicycle => Icons.pedal_bike_rounded,
                            VehicleType.motorbike => Icons.two_wheeler_rounded,
                            VehicleType.keke => Icons.electric_rickshaw_rounded,
                          }, color: AppColors.primaryMaroon),
                          const SizedBox(height: 4),
                          Text(
                            _vehicleLabel(type),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.inkText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _plateRequired
                ? 'Plate / registration number'
                : 'Plate / registration number (optional)',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _plateController,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) {
              if (_showPlateError) setState(() => _showPlateError = false);
            },
            decoration: InputDecoration(
              hintText: 'e.g. ABC-123-XY',
              errorText: _showPlateError
                  ? 'Enter a valid plate/registration number.'
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: 'Save', onPressed: _type == null ? null : _save),
          ),
        ],
      ),
    );
  }
}
