import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/route_line.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../ordering/presentation/widgets/ordering_components.dart';
import '../application/runner_controller.dart';
import '../domain/runner_models.dart';

export '../../../core/widgets/app_nav_shell.dart' show RunnerShell;

class RunnerHomeScreen extends ConsumerStatefulWidget {
  const RunnerHomeScreen({super.key});
  @override
  ConsumerState<RunnerHomeScreen> createState() => _RunnerHomeScreenState();
}

class _RunnerHomeScreenState extends ConsumerState<RunnerHomeScreen> {
  // Shown inline on the hero card rather than a SnackBar, so a blocked
  // "go online" attempt reads as part of this screen's own state rather
  // than a generic system toast — auto-clears itself so it doesn't linger.
  String? _blockedMessage;
  Timer? _messageTimer;

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleToggle() async {
    final result = await ref
        .read(runnerControllerProvider.notifier)
        .toggleAvailability();
    if (!mounted) return;
    final message = switch (result) {
      GoOnlineResult.success => null,
      GoOnlineResult.hasActiveDelivery =>
        'Finish your active delivery before going offline.',
      GoOnlineResult.notVerified =>
        'Verify your ID before you can go online.',
      GoOnlineResult.outsideCampusBoundary =>
        'You need to be on campus to go online.',
      GoOnlineResult.locationUnavailable => "We couldn't check your location. Enable location access and try again.",
    };
    _messageTimer?.cancel();
    setState(() => _blockedMessage = message);
    if (message != null) {
      _messageTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _blockedMessage = null);
      });
    }
  }

  void _menuTapped() {
    ref.read(appNotificationProvider.notifier).info('Menu coming soon.');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RunnerSession>(runnerControllerProvider, (previous, next) {
      if (previous?.offer == null && next.offer != null && context.mounted) {
        context.push(AppRoutes.runnerOffer);
      }
    });
    final session = ref.watch(runnerControllerProvider);
    final online = session.status.availability == RunnerAvailability.online;
    final total = session.earnings.fold(0, (sum, item) => sum + item.amount);

    var stagger = 0;
    Widget staggered(Widget child) {
      final delay = Duration(milliseconds: 70 * stagger++);
      return child
          .animate()
          .fadeIn(delay: delay, duration: 260.ms)
          .moveY(begin: 12, end: 0);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardHeader(onMenuTap: _menuTapped),
              const SizedBox(height: 22),
              staggered(
                _OnlineHeroCard(
                  online: online,
                  locked: session.activeDelivery != null,
                  blockedMessage: _blockedMessage,
                  onTap: _handleToggle,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: staggered(
                      _StatCard(
                        icon: Icons.checklist_rounded,
                        iconColor: AppColors.primaryMaroon,
                        tint: AppColors.accentRose,
                        label: 'JOBS TODAY',
                        value: session.earnings.length.toString(),
                        isEmpty: session.earnings.isEmpty,
                        emptyLabel: 'No active jobs yet',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: staggered(
                      _StatCard(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AppColors.gold,
                        tint: AppColors.goldTint,
                        label: 'EARNED TODAY',
                        value: naira(total),
                        isEmpty: total == 0,
                        emptyLabel: 'Your earnings will appear here',
                        emphasize: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (session.activeDelivery != null)
                _ActiveCard(active: session.activeDelivery!)
              else if (online && session.noJobsInZone)
                const _NoJobsInZoneState()
              else if (online)
                const _WaitingState()
              else
                const _HelperRow(
                  icon: Icons.schedule_rounded,
                  text: 'Switch on when you have a little space in your route.',
                ),
              const SizedBox(height: 28),
              _RecentActivitySection(earnings: session.earnings),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Runner Mode" header — circular menu button, centered title, tappable
/// Earnings pill, and the same route/pin decorative motif used on the
/// role-select screen's header, scaled down for this shorter header.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onMenuTap});
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Same route_decoration.png + native pin composite as the
        // role-select header — the earlier pre-composited PNG here had an
        // opaque baked-in background that showed as a faint box against
        // the cream page; this transparent asset + a real Icon don't.
        Positioned(
          top: 44,
          right: 4,
          child: IgnorePointer(
            child: SizedBox(
              width: 66,
              height: 82,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/route_decoration.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Positioned(
                    right: 2,
                    top: 34,
                    child: Icon(
                      Icons.location_on,
                      color: AppColors.primaryMaroon,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CircleIconButton(icon: Icons.menu_rounded, onTap: onMenuTap),
                Expanded(
                  child: Center(
                    child: Text(
                      'Runner Mode',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.inkText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _EarningsChip(onTap: () => context.push(AppRoutes.earnings)),
              ],
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.only(right: 66),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Make a little\nof your '),
                    TextSpan(
                      text: 'walk.',
                      style: TextStyle(color: AppColors.primaryMaroon),
                    ),
                  ],
                ),
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(color: AppColors.inkText),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 66),
              child: Text(
                'Accept deliveries that already fit your route around campus.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
        child: Icon(icon, color: AppColors.inkText, size: 20),
      ),
    );
  }
}

class JobOfferScreen extends ConsumerWidget {
  const JobOfferScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(runnerControllerProvider);
    final job = session.offer;
    if (job == null) return const RunnerHomeScreen();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      ref
                          .read(runnerControllerProvider.notifier)
                          .declineOffer();
                      context.go(AppRoutes.runnerHome);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  Text(
                    '${session.offerSecondsRemaining}s',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: OrderingColors.text(context)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: session.offerSecondsRemaining / 20,
                  minHeight: 4,
                  color: AppColors.primaryMaroon,
                  backgroundColor: OrderingColors.border(context),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                'A delivery on your route.',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              const SizedBox(height: 12),
              Text(
                'Review the details, then decide. This offer will simply pass on if you do nothing.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: OrderingColors.muted(context)),
              ),
              const SizedBox(height: 28),
              JobCard(job: job),
              const Spacer(),
              PrimaryButton(
                onPressed: () async {
                  final result = await ref
                      .read(runnerControllerProvider.notifier)
                      .acceptOffer();
                  if (!context.mounted) return;
                  if (result == AcceptOfferResult.accepted) {
                    context.go(AppRoutes.runnerDelivery);
                    return;
                  }
                  final message = switch (result) {
                    AcceptOfferResult.notVerified =>
                      'Verify your ID before you can accept deliveries.',
                    AcceptOfferResult.outsideCampusBoundary =>
                      'You need to be on campus to accept this delivery.',
                    AcceptOfferResult.locationUnavailable => "We couldn't check your location. Enable location access and try again.",
                    AcceptOfferResult.accepted ||
                    AcceptOfferResult.blocked => null,
                  };
                  if (message != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(message)));
                  }
                },
                label: 'Accept delivery · ${naira(job.payoutAmount)}',
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  ref.read(runnerControllerProvider.notifier).declineOffer();
                  context.go(AppRoutes.runnerHome);
                },
                child: const Text('Decline'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveDeliveryScreen extends ConsumerWidget {
  const ActiveDeliveryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Task 10 performance audit: same rationale as EarningsScreen above —
    // this screen only cares about activeDelivery, not e.g. the per-second
    // offer countdown.
    final active = ref.watch(runnerControllerProvider.select((s) => s.activeDelivery));
    if (active == null) return const RunnerHomeScreen();
    if (active.status == DeliveryStage.delivered) {
      return _DeliveryComplete(active: active);
    }
    final pickup = active.status == DeliveryStage.accepted;
    return Scaffold(
      appBar: AppBar(title: Text(pickup ? 'Pickup' : 'Drop-off')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeliveryStatusStepper(stage: active.status),
            const SizedBox(height: 30),
            Text(
              pickup ? 'Head to the eatery.' : 'Bring it to the student.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            const SizedBox(height: 10),
            Text(
              pickup ? active.job.eateryLocation : active.job.dropoffLocation,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: OrderingColors.muted(context)),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: OrderingColors.surface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OrderingColors.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ORDER ${active.orderNumber}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1,
                      color: OrderingColors.muted(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...active.orderItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: OrderingColors.text(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            PrimaryButton(
              label: pickup ? 'Mark as picked up' : 'Mark as delivered',
              onPressed: () => _confirm(context, ref, pickup),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm(BuildContext context, WidgetRef ref, bool pickup) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(pickup ? 'Confirm collection' : 'Confirm drop-off'),
        content: Text(
          pickup ? 'Confirm you have the complete order before continuing.' : 'Confirm you have handed the order to the student. Photo proof will be added later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () {
              pickup
                  ? ref.read(runnerControllerProvider.notifier).confirmPickup()
                  : ref
                        .read(runnerControllerProvider.notifier)
                        .confirmDropoff();
              Navigator.pop(dialogContext);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Task 10 performance audit: .select() so this screen doesn't rebuild
    // on unrelated session churn — most notably offerSecondsRemaining,
    // which ticks every second while an offer is pending.
    final earnings = ref.watch(runnerControllerProvider.select((s) => s.earnings));
    final total = earnings.fold(0, (sum, item) => sum + item.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primaryMaroonDeep,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TODAY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    color: AppColors.onMaroon.withValues(alpha: .7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  naira(total),
                  style: Theme.of(context).textTheme.displayLarge
                      ?.copyWith(color: AppColors.onMaroon),
                ),
                const SizedBox(height: 10),
                Text(
                  '${earnings.length} completed deliveries',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.onMaroon.withValues(alpha: .72)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'This week',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: OrderingColors.text(context)),
          ),
          const SizedBox(height: 12),
          const _WeeklyBars(),
          const SizedBox(height: 28),
          Text(
            'Completed deliveries',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: OrderingColors.text(context)),
          ),
          const SizedBox(height: 10),
          if (earnings.isEmpty)
            Text(
              'Your completed deliveries will show up here.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: OrderingColors.muted(context)),
            ),
          ...earnings.map(
            (record) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryMaroon.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.primaryMaroon,
                ),
              ),
              title: Text(
                'Delivery completed',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              subtitle: Text(
                'Today',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: OrderingColors.muted(context)),
              ),
              trailing: Text(
                naira(record.amount),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job});
  final DeliveryJob job;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JobPoint(
          label: 'PICK UP',
          title: job.eateryName,
          subtitle: job.eateryLocation,
          icon: Icons.storefront_outlined,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Container(
            width: 1,
            height: 25,
            color: OrderingColors.border(context),
          ),
        ),
        _JobPoint(
          label: 'DROP OFF',
          title: job.dropoffZone,
          subtitle: job.dropoffLocation,
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 20),
        Divider(color: OrderingColors.border(context)),
        const SizedBox(height: 12),
        Row(
          children: [
            _Metric(label: 'PAYOUT', value: naira(job.payoutAmount)),
            const SizedBox(width: 32),
            _Metric(
              label: 'DISTANCE',
              value:
                  '${(job.estimatedDistanceMeters / 1000).toStringAsFixed(1)} km',
            ),
          ],
        ),
      ],
    ),
  );
}

class DeliveryStatusStepper extends StatelessWidget {
  const DeliveryStatusStepper({super.key, required this.stage});
  final DeliveryStage stage;
  @override
  Widget build(BuildContext context) {
    final activeIndex = stage == DeliveryStage.accepted
        ? 0
        : stage == DeliveryStage.pickedUp
        ? 1
        : 2;
    return StatusStepper(
      steps: const ['Accepted', 'Picked up', 'Delivered'],
      activeIndex: activeIndex,
    );
  }
}

/// The single most important control on the dashboard. Stays a rich,
/// dark maroon gradient card regardless of online/offline state (a
/// deliberate visual anchor, not a themed surface) — only the icon badge,
/// title/subtext, and pill switch change with state. An inline (not
/// SnackBar) banner explains a blocked "go online" attempt so it reads as
/// part of this card's own state.
class _OnlineHeroCard extends StatelessWidget {
  const _OnlineHeroCard({
    required this.online,
    required this.locked,
    required this.blockedMessage,
    required this.onTap,
  });
  final bool online;
  final bool locked;
  final String? blockedMessage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryMaroon, AppColors.primaryMaroonDeep],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryMaroon.withValues(alpha: .35),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.onMaroon,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: AppColors.primaryMaroon,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        online ? 'You’re online' : 'Go online',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: AppColors.onMaroon),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        locked
                            ? 'Finish your delivery before going offline.'
                            : online
                            ? 'Ready for a delivery that fits your route.'
                            : 'Be ready when a nearby job appears.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(
                              color: AppColors.onMaroon.withValues(alpha: .78),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _PillSwitch(value: online),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: blockedMessage == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.onMaroon.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: AppColors.onMaroon,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                blockedMessage!,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.onMaroon,
                                      height: 1.3,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom pill switch — soft shadow, animated thumb, gold/maroon-deep
/// gradient fill when active — matching the craft level of the passcode
/// keypad and OTP cells rather than the default system switch. Purely
/// presentational: the whole [_OnlineHeroCard] is the tap target, so this
/// has no `onChanged` of its own.
class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 54,
      height: 32,
      padding: const EdgeInsets.all(3),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        gradient: value
            ? const LinearGradient(
                colors: [AppColors.gold, AppColors.primaryMaroonDeep],
              )
            : null,
        color: value ? null : AppColors.primaryMaroonDeep,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningsChip extends StatelessWidget {
  const _EarningsChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 15,
              color: AppColors.primaryMaroon,
            ),
            const SizedBox(width: 6),
            Text(
              'Earnings',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primaryMaroon,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jobs Today (soft rose tint) vs Earned Today (soft gold tint, larger
/// serif headline in the gold accent) — deliberately different visual
/// weight since the earned amount is the number runners care most about.
/// A zero value fades toward the muted tone and shows a short reassurance
/// line, reading as "nothing yet" rather than looking broken.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.label,
    required this.value,
    required this.isEmpty,
    required this.emptyLabel,
    this.emphasize = false,
  });
  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String label;
  final String value;
  final bool isEmpty;
  final String emptyLabel;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final valueColor = isEmpty
        ? AppColors.mutedText
        : (emphasize ? AppColors.gold : AppColors.inkText);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.mutedText,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style:
                (emphasize
                        ? Theme.of(context).textTheme.headlineMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(
                      color: valueColor,
                      fontSize: emphasize ? 24 : null,
                    ),
          ),
          if (isEmpty) ...[
            const SizedBox(height: 3),
            Text(
              emptyLabel,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}

/// Slim helper card — clock icon + a short line of guidance. Fills the
/// space below the stats row when there's nothing else to show (offline,
/// no active delivery), instead of ending in a blank void.
class _HelperRow extends StatelessWidget {
  const _HelperRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.accentRose,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: AppColors.primaryMaroon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkText, height: 1.3),
          ),
        ),
      ],
    ),
  );
}

/// Fills the dead space below the status area with a short list of
/// completed deliveries, or the sparkle-accented empty-state illustration
/// when there aren't any yet. Always data-driven — never hardcoded to
/// only the empty case.
class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.earnings});
  final List<EarningsRecord> earnings;

  @override
  Widget build(BuildContext context) {
    final recent = earnings.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.inkText,
                fontWeight: FontWeight.w700,
              ),
            ),
            InkWell(
              onTap: () => context.push(AppRoutes.earnings),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View all',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primaryMaroon,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          const _RecentActivityEmptyState()
        else
          ...recent.map((record) => _RecentActivityRow(record: record)),
      ],
    );
  }
}

class _RecentActivityEmptyState extends StatelessWidget {
  const _RecentActivityEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 130,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  left: 8,
                  top: 4,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppColors.borderSubtle,
                  ),
                ),
                const Positioned(
                  right: 4,
                  bottom: 2,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 10,
                    color: AppColors.borderSubtle,
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.accentRose,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.primaryMaroon,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No deliveries yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
          ),
          const SizedBox(height: 6),
          Text(
            'Your completed deliveries will show up here.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.record});
  final EarningsRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryMaroon.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.primaryMaroon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery completed',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: OrderingColors.text(context)),
                ),
                Text(
                  'Today',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: OrderingColors.muted(context)),
                ),
              ],
            ),
          ),
          Text(
            naira(record.amount),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: OrderingColors.text(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: OrderingColors.muted(context), letterSpacing: .8),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: OrderingColors.text(context)),
      ),
    ],
  );
}

class _JobPoint extends StatelessWidget {
  const _JobPoint({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22, color: AppColors.primaryMaroon),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: OrderingColors.muted(context),
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: OrderingColors.muted(context)),
            ),
          ],
        ),
      ),
    ],
  );
}

class _WaitingState extends StatelessWidget {
  const _WaitingState();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const SizedBox(height: 28),
        Icon(Icons.radar_rounded, size: 38, color: AppColors.primaryMaroon),
        const SizedBox(height: 14),
        Text(
          'Waiting nearby.',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: OrderingColors.text(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'We’ll bring you a delivery when one fits.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: OrderingColors.muted(context)),
        ),
      ],
    ),
  );
}

// Zero active vendors in the runner's own campus/zone — distinct from
// "online and waiting", since no job is ever coming until a vendor is
// onboarded there.
class _NoJobsInZoneState extends StatelessWidget {
  const _NoJobsInZoneState();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const SizedBox(height: 12),
        const RouteLineEmptyIllustration(width: 200, height: 110),
        const SizedBox(height: 14),
        Text(
          'No jobs in your zone yet.',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: OrderingColors.text(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'There are no active vendors in your campus right now — check back soon.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: OrderingColors.muted(context)),
        ),
      ],
    ),
  );
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.active});
  final ActiveDelivery active;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push(AppRoutes.runnerDelivery),
    child: JobCard(job: active.job),
  );
}

class _DeliveryComplete extends ConsumerWidget {
  const _DeliveryComplete({required this.active});
  final ActiveDelivery active;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primaryMaroon,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.onMaroon,
                size: 36,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Delivery complete.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            const SizedBox(height: 8),
            Text(
              '${naira(active.job.payoutAmount)} added to today’s earnings.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: OrderingColors.muted(context)),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'View earnings',
              onPressed: () {
                ref
                    .read(runnerControllerProvider.notifier)
                    .finishDeliveredDelivery();
                context.go(AppRoutes.earnings);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 82,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        7,
        (index) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              height: index == 6 ? 60 : 14.0 + index * 4,
              decoration: BoxDecoration(
                color: index == 6
                    ? AppColors.primaryMaroon
                    : OrderingColors.border(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
