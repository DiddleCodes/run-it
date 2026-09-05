import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/orders_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../auth/application/auth_controller.dart';
import '../application/order_tracking_controller.dart';
import '../domain/order_history_models.dart';
import '../domain/ordering_models.dart';
import 'widgets/ordering_components.dart';

/// Task 46: the student's real order history — every order they've ever
/// placed, fetched once from `GET /orders` and bucketed client-side by
/// status into the Past (delivered) and Cancelled tabs below. Replaces the
/// old hardcoded-fake `OrderHistoryEntry` list and the separate
/// in-memory-only `CancelledOrdersController` — both were standing in for
/// exactly this one real fetch.
class OrderHistoryController extends AsyncNotifier<List<OrderHistoryEntry>> {
  @override
  Future<List<OrderHistoryEntry>> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null) return const [];
    final page = await ref
        .watch(ordersRepositoryProvider)
        .fetchOrderHistory(token: session.accessToken);
    return page.items;
  }

  /// Re-fetches from the backend — called after a successful cancellation
  /// so the just-cancelled order shows up in the Cancelled tab without
  /// waiting for some unrelated rebuild to happen to trigger it.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryController, List<OrderHistoryEntry>>(
      OrderHistoryController.new,
    );

/// Deterministic per-runner demo rating — mirrors the runner side's own
/// `_demoRating`; there's no ratings backend for either direction yet.
double _demoRunnerRating(String name) => 4.5 + (name.hashCode.abs() % 5) / 10;

enum _OrdersTab { active, past, cancelled }

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  _OrdersTab _tab = _OrdersTab.active;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(orderTrackingProvider);
    // An order that has fully arrived no longer counts as "active" on this
    // screen — there's no persistence yet to move it into Past, so once
    // delivered it simply stops counting here (a known, honestly-scoped
    // limitation rather than fabricated history).
    final hasActiveOrder =
        session.isActive &&
        session.stage != OrderStage.delivered &&
        session.stage != OrderStage.confirmed;
    final history = ref.watch(orderHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, AppSpacing.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Orders',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(color: AppColors.inkText, fontSize: 28),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track, repeat or review your meals.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _SegmentedTabs(
                value: _tab,
                activeCount: hasActiveOrder ? 1 : 0,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            Expanded(
              child: switch (_tab) {
                _OrdersTab.active => hasActiveOrder
                    ? _ActiveOrderTab(session: session)
                    : const _EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No active order',
                        subtitle: 'Place an order and track it here in real time.',
                      ),
                _OrdersTab.past => history.when(
                  loading: () => const _HistoryLoading(),
                  error: (_, _) => _HistoryError(
                    onRetry: () => ref.read(orderHistoryProvider.notifier).refresh(),
                  ),
                  data: (orders) {
                    final past = orders.where((o) => o.status == 'delivered').toList();
                    return past.isEmpty
                        ? const _EmptyState(
                            icon: Icons.history_rounded,
                            title: 'No past orders yet',
                            subtitle: 'Orders you complete will show up here.',
                          )
                        : _PastOrdersTab(history: past);
                  },
                ),
                _OrdersTab.cancelled => history.when(
                  loading: () => const _HistoryLoading(),
                  error: (_, _) => _HistoryError(
                    onRetry: () => ref.read(orderHistoryProvider.notifier).refresh(),
                  ),
                  data: (orders) {
                    final cancelled = orders.where((o) => o.status == 'cancelled').toList();
                    return cancelled.isEmpty
                        ? const _EmptyState(
                            icon: Icons.cancel_outlined,
                            title: 'No cancelled orders',
                            subtitle: 'Anything you cancel will be listed here.',
                          )
                        : _CancelledOrdersTab(cancelled: cancelled);
                  },
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.value,
    required this.activeCount,
    required this.onChanged,
  });
  final _OrdersTab value;
  final int activeCount;
  final ValueChanged<_OrdersTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _OrdersTab.active: 'Active ($activeCount)',
      _OrdersTab.past: 'Past',
      _OrdersTab.cancelled: 'Cancelled',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.borderSubtle.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final tab in _OrdersTab.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == tab ? AppColors.primaryMaroon : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: value == tab ? AppColors.onMaroon : AppColors.inkText,
                        fontWeight: value == tab ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: Text(labels[tab]!),
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

const _stepLabels = ['Confirmed', 'Preparing', 'On the way', 'Arrived'];

(int, String, IconData) _activeStepInfo(OrderStage stage) => switch (stage) {
  OrderStage.placed => (0, 'Order received', Icons.check_circle_outline_rounded),
  OrderStage.runnerAssigned => (1, 'Preparing your order', Icons.restaurant_rounded),
  OrderStage.pickedUp => (2, 'On the way to you', Icons.two_wheeler_rounded),
  // Neither of these ever actually renders here — hasActiveOrder excludes
  // both stages above — but the switch must stay exhaustive.
  OrderStage.delivered => (3, 'Arrived', Icons.home_rounded),
  OrderStage.confirmed => (4, 'Confirmed', Icons.celebration_rounded),
};

const _etaByStage = {
  OrderStage.placed: '15–20 min',
  OrderStage.runnerAssigned: '10–15 min',
  OrderStage.pickedUp: '5–10 min',
  OrderStage.delivered: 'Arrived',
  OrderStage.confirmed: 'Arrived',
};

class _ActiveOrderTab extends ConsumerWidget {
  const _ActiveOrderTab({required this.session});
  final OrderTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = session.stage!;
    final (stepIndex, statusLabel, statusIcon) = _activeStepInfo(stage);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.ml),
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
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.accentRose,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, size: 17, color: AppColors.primaryMaroon),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const MenuImagePlaceholder(seed: 'order', size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.eateryName,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppColors.inkText),
                        ),
                        Text(
                          session.orderItems.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.mutedText),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    naira(session.total),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              StatusStepper(steps: _stepLabels, activeIndex: stepIndex),
              if (session.runnerName != null) ...[
                const SizedBox(height: AppSpacing.ml),
                _RunnerInfoRow(name: session.runnerName!),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated arrival',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                        ),
                        Text(
                          _etaByStage[stage]!,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: AppColors.inkText),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => context.push(AppRoutes.orderTracking),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View on map',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: AppColors.primaryMaroon,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunnerInfoRow extends ConsumerWidget {
  const _RunnerInfoRow({required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundCream,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
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
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.primaryMaroon),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: AppColors.inkText),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
                    const SizedBox(width: 2),
                    Text(
                      _demoRunnerRating(name).toStringAsFixed(1),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.successBackground,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'On campus',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          _RunnerActionButton(
            icon: CupertinoIcons.phone_fill,
            onTap: () => ref
                .read(appNotificationProvider.notifier)
                .info('Calling your runner is coming soon.'),
          ),
          const SizedBox(width: 8),
          _RunnerActionButton(
            icon: CupertinoIcons.chat_bubble_fill,
            onTap: () => ref
                .read(appNotificationProvider.notifier)
                .info('Messaging your runner is coming soon.'),
          ),
        ],
      ),
    );
  }
}

class _RunnerActionButton extends StatelessWidget {
  const _RunnerActionButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.surfaceCard, shape: BoxShape.circle),
        child: Icon(icon, size: 15, color: AppColors.primaryMaroon),
      ),
    );
  }
}

class _PastOrdersTab extends StatelessWidget {
  const _PastOrdersTab({required this.history});
  final List<OrderHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = history[index];
        final deliveredAt = entry.deliveredAt!;
        final isYesterday = DateTime.now().difference(deliveredAt).inDays == 1;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => context.push(AppRoutes.orderDetail, extra: entry.id),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                MenuImagePlaceholder(seed: entry.vendorName, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.vendorName,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: AppColors.inkText),
                      ),
                      Text(
                        entry.itemsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Delivered ${isYesterday ? 'Yesterday' : formatter.format(deliveredAt)}',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      naira(entry.totalKobo ~/ 100),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: AppColors.mutedText,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CancelledOrdersTab extends StatelessWidget {
  const _CancelledOrdersTab({required this.cancelled});
  final List<OrderHistoryEntry> cancelled;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
      itemCount: cancelled.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = cancelled[index];
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => context.push(AppRoutes.orderDetail, extra: entry.id),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                MenuImagePlaceholder(seed: entry.vendorName, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.vendorName,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: AppColors.inkText),
                      ),
                      Text(
                        entry.itemsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Cancelled ${formatter.format(entry.cancelledAt!)}',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${naira(entry.totalKobo ~/ 100)}',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.successBackground,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'Refunded',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
    child: SkeletonList(count: 4),
  );
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Couldn't load your orders",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

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
              decoration: const BoxDecoration(color: AppColors.accentRose, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryMaroon, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}
