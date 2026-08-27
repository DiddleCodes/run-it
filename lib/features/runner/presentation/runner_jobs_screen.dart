import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../ordering/presentation/widgets/ordering_components.dart';
import '../application/runner_controller.dart';
import '../domain/runner_models.dart';

enum _JobsTab { available, active, completed }

/// A small fixed rotation of vendor-badge tints/glyphs/category labels,
/// picked deterministically per eatery name — so the Available list reads
/// as a row of distinct vendors rather than identical rose tiles, without
/// needing any new per-vendor data.
const _vendorBadges = [
  (AppColors.accentRose, AppColors.primaryMaroon, Icons.restaurant_rounded, 'Food & Drinks'),
  (AppColors.goldTint, AppColors.gold, Icons.local_cafe_rounded, 'Bakery & Pastries'),
  (AppColors.successBackground, AppColors.success, Icons.eco_rounded, 'Healthy & Organic'),
  (Color(0xFFE4E9F7), Color(0xFF3B5BA8), Icons.icecream_rounded, 'Desserts & Treats'),
];

(Color, Color, IconData, String) _vendorBadgeFor(String eateryName) =>
    _vendorBadges[eateryName.hashCode.abs() % _vendorBadges.length];

/// Deterministic per-eatery "New" flag — there's no listing timestamp to
/// key off (every preview job's `offeredAt` is simply "now"), so this
/// picks a stable ~half of vendors to badge as new rather than either
/// always/never showing the tag.
bool _isNewJob(String eateryName) => eateryName.hashCode.isEven;

class RunnerJobsScreen extends ConsumerStatefulWidget {
  const RunnerJobsScreen({super.key});
  @override
  ConsumerState<RunnerJobsScreen> createState() => _RunnerJobsScreenState();
}

class _RunnerJobsScreenState extends ConsumerState<RunnerJobsScreen> {
  _JobsTab _tab = _JobsTab.available;

  Future<void> _accept(DeliveryJob job) async {
    final result = await ref.read(runnerControllerProvider.notifier).acceptJob(job);
    if (!mounted) return;
    final notifier = ref.read(appNotificationProvider.notifier);
    switch (result) {
      case AcceptOfferResult.accepted:
        setState(() => _tab = _JobsTab.active);
        notifier.success('Job accepted — head to ${job.eateryName}.');
      case AcceptOfferResult.notVerified:
        notifier.warning('Verify your ID before you can accept deliveries.');
      case AcceptOfferResult.outsideCampusBoundary:
        notifier.warning('You need to be on campus to accept this delivery.');
      case AcceptOfferResult.locationUnavailable:
        notifier.warning(
          "We couldn't check your location. Enable location access and try again.",
        );
      case AcceptOfferResult.blocked:
        notifier.warning('Finish your active delivery before accepting another.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(runnerControllerProvider);
    final user = ref.watch(authControllerProvider)?.user;
    // Pending/rejected/no-KYC runners keep read-only access to Jobs — they
    // can browse what's out there, just can't accept anything — rather
    // than being kicked out of the screen entirely. See TASK 4g §1.
    final verified = user?.kycStatus == KycStatus.verified;
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: _JobsHeader(
                onFilterTap: () => ref
                    .read(appNotificationProvider.notifier)
                    .info('Filters are coming soon.'),
                onMapTap: () => ref
                    .read(appNotificationProvider.notifier)
                    .info('Map view is coming soon.'),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _SegmentedTabs(
                value: _tab,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            if (!verified)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                child: _PendingReviewBanner(user: user),
              ),
            Expanded(
              child: switch (_tab) {
                _JobsTab.available =>
                  _AvailableTab(onAccept: _accept, readOnly: !verified),
                _JobsTab.active => _ActiveTab(session: session),
                _JobsTab.completed => _CompletedTab(earnings: session.earnings),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on the Jobs screen (and reused on Profile) while a runner's KYC
/// hasn't cleared yet — "account exists, earning doesn't, until cleared",
/// not a blocked screen. [KycStatus.none] and [KycStatus.pending] both
/// read as "under review" here; [KycStatus.rejected] gets its own
/// actionable copy since there's something the runner needs to do.
class _PendingReviewBanner extends StatelessWidget {
  const _PendingReviewBanner({required this.user});
  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final rejected = user?.kycStatus == KycStatus.rejected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: rejected ? AppColors.accentRose : AppColors.goldTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            rejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
            size: 18,
            color: rejected ? AppColors.error : AppColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rejected
                  ? 'Your verification needs another look — check Profile for details.'
                  : "You're browsing read-only while your ID is under review. You'll be able to accept jobs once verified.",
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.inkText,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobsHeader extends StatelessWidget {
  const _JobsHeader({required this.onFilterTap, required this.onMapTap});
  final VoidCallback onFilterTap;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderIconButton(icon: CupertinoIcons.slider_horizontal_3, onTap: onFilterTap),
        Expanded(
          child: Center(
            child: Text(
              'Jobs',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.inkText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        _HeaderIconButton(icon: CupertinoIcons.map, onTap: onMapTap),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
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
        child: Icon(icon, color: AppColors.inkText, size: 19),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.value, required this.onChanged});
  final _JobsTab value;
  final ValueChanged<_JobsTab> onChanged;

  static const _labels = {
    _JobsTab.available: 'Available',
    _JobsTab.active: 'Accepted',
    _JobsTab.completed: 'Completed',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.borderSubtle.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final tab in _JobsTab.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == tab ? AppColors.surfaceCard : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: value == tab
                        ? [
                            BoxShadow(
                              color: AppColors.maroonShadow,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: value == tab
                            ? AppColors.primaryMaroon
                            : AppColors.mutedText,
                        fontWeight: value == tab ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: Text(_labels[tab]!),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvailableTab extends ConsumerWidget {
  const _AvailableTab({required this.onAccept, required this.readOnly});
  final ValueChanged<DeliveryJob> onAccept;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(availableJobsProvider);
    return jobs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const _EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Couldn’t load jobs',
        subtitle: 'Something went wrong. Pull to refresh in a moment.',
      ),
      data: (jobs) {
        if (jobs.isEmpty) {
          return const _EmptyState(
            icon: Icons.explore_off_rounded,
            title: 'No jobs nearby',
            subtitle: 'When a vendor near you has a delivery, it’ll show up here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          itemCount: jobs.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _AvailableJobsBar(
                count: jobs.length,
                onSortTap: () => ref
                    .read(appNotificationProvider.notifier)
                    .info('Sorting options are coming soon.'),
              );
            }
            final job = jobs[index - 1];
            return _AvailableJobCard(
                  job: job,
                  readOnly: readOnly,
                  onAccept: () => onAccept(job),
                )
                .animate(delay: (60 * (index - 1)).ms)
                .fadeIn(duration: 260.ms)
                .moveY(begin: 10, end: 0);
          },
        );
      },
    );
  }
}

class _AvailableJobsBar extends StatelessWidget {
  const _AvailableJobsBar({required this.count, required this.onSortTap});
  final int count;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          'Available jobs · $count',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.inkText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onSortTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.arrow_up_arrow_down,
                  size: 13,
                  color: AppColors.inkText,
                ),
                const SizedBox(width: 5),
                Text(
                  'Sort',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AvailableJobCard extends StatelessWidget {
  const _AvailableJobCard({
    required this.job,
    required this.onAccept,
    this.readOnly = false,
  });
  final DeliveryJob job;
  final VoidCallback onAccept;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final etaMinutes = (job.estimatedDistanceMeters / 80).ceil();
    final (badgeBg, badgeFg, badgeIcon, category) = _vendorBadgeFor(job.eateryName);
    final isNew = _isNewJob(job.eateryName);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.card(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(badgeIcon, size: 20, color: badgeFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.eateryName,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: AppColors.inkText),
                    ),
                    Text(
                      category,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.location_solid,
                          size: 12,
                          color: AppColors.mutedText,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            job.eateryLocation,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.mutedText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isNew)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successBackground,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'New',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundCream,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _JobStat(label: 'Earnings', value: naira(job.payoutAmount)),
                ),
                _JobStatDivider(),
                Expanded(
                  child: _JobStat(label: 'Est. time', value: '~$etaMinutes min'),
                ),
                _JobStatDivider(),
                Expanded(
                  child: _JobStat(
                    label: 'Distance',
                    value: '${(job.estimatedDistanceMeters / 1000).toStringAsFixed(1)} km',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: readOnly
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundCream,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Text(
                      'Pending verification',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: AppColors.mutedText, fontWeight: FontWeight.w600),
                    ),
                  )
                : _PressableButton(
                    onPressed: onAccept,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Accept Job'),
                        const SizedBox(width: 6),
                        const Icon(CupertinoIcons.arrow_right, size: 16),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _JobStat extends StatelessWidget {
  const _JobStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }
}

class _JobStatDivider extends StatelessWidget {
  const _JobStatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: AppColors.borderSubtle);
}

/// A [FilledButton] that also scales down ~0.97 on press — the motion
/// spec's "buttons scale to ~0.97 on press" applied without pulling in a
/// third-party button package.
class _PressableButton extends StatefulWidget {
  const _PressableButton({required this.onPressed, required this.child});
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryMaroon,
            foregroundColor: AppColors.onMaroon,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          onPressed: widget.onPressed,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.session});
  final RunnerSession session;

  @override
  Widget build(BuildContext context) {
    final active = session.activeDelivery;
    if (active == null) {
      return const _EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No active job',
        subtitle: 'Accept a job from the Available tab to get started.',
      );
    }
    final pickup = active.status == DeliveryStage.accepted;
    final statusLabel = pickup ? 'Heading to pickup' : 'Delivering';
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: AppElevation.card(false),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pickup ? Icons.storefront_rounded : Icons.two_wheeler_rounded,
                          size: 13,
                          color: AppColors.primaryMaroon,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    naira(active.job.payoutAmount),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: AppColors.inkText),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                active.job.eateryName,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: AppColors.inkText, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                pickup ? active.job.eateryLocation : active.job.dropoffLocation,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _PressableButton(
                  onPressed: () => context.push(AppRoutes.runnerScan),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.viewfinder, size: 18),
                      const SizedBox(width: 8),
                      Text(pickup ? 'Scan pickup code' : 'Scan delivery code'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletedTab extends StatelessWidget {
  const _CompletedTab({required this.earnings});
  final List<EarningsRecord> earnings;

  @override
  Widget build(BuildContext context) {
    if (earnings.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No completed deliveries yet',
        subtitle: 'Deliveries you finish will show up here with a full receipt.',
      );
    }
    final formatter = DateFormat('MMM d · h:mm a');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      itemCount: earnings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = earnings[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
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
                child: const Icon(Icons.check_rounded, color: AppColors.primaryMaroon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.eateryName,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: AppColors.inkText),
                    ),
                    Text(
                      '${record.dropoffZone} · ${formatter.format(record.completedAt)}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                  ],
                ),
              ),
              Text(
                naira(record.amount),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.inkText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Same icon-in-circle + headline + muted-subtext language as the
/// dashboard's Recent Activity empty state — used across all 3 tabs so an
/// empty Jobs screen never reads as broken.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accentRose,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryMaroon, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}
