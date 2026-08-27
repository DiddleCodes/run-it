import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/status_stepper.dart';
import '../application/order_tracking_controller.dart';
import '../domain/ordering_models.dart';
import 'widgets/ordering_components.dart';

/// A row in the Past-orders list. Local/demo data only — there's no
/// order-history backend yet, same spirit as the runner side's
/// `EarningsRecord`/`SystemNotice` and this feature's own `ChatThread`.
class OrderHistoryEntry {
  const OrderHistoryEntry({
    required this.id,
    required this.eateryName,
    required this.itemsSummary,
    required this.total,
    required this.deliveredAt,
  });
  final String id;
  final String eateryName;
  final String itemsSummary;
  final int total;
  final DateTime deliveredAt;
}

final orderHistoryProvider = Provider<List<OrderHistoryEntry>>((ref) {
  final now = DateTime.now();
  return [
    OrderHistoryEntry(
      id: 'hist-1',
      eateryName: 'Tantalizers',
      itemsSummary: 'Fried Rice + Chicken',
      total: 2300,
      deliveredAt: now.subtract(const Duration(days: 1)),
    ),
    OrderHistoryEntry(
      id: 'hist-2',
      eateryName: 'FoodCo',
      itemsSummary: 'Burger + Coke',
      total: 2800,
      deliveredAt: now.subtract(const Duration(days: 2)),
    ),
    OrderHistoryEntry(
      id: 'hist-3',
      eateryName: 'UI Snacks',
      itemsSummary: 'Meat Pie + Zobo',
      total: 1500,
      deliveredAt: now.subtract(const Duration(days: 5)),
    ),
  ];
});

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
        session.isActive && session.stage != OrderStage.delivered;
    final history = ref.watch(orderHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
              child: Row(
                children: [
                  Expanded(
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
                  InkWell(
                    onTap: () => ref
                        .read(appNotificationProvider.notifier)
                        .info('Full order history is coming soon.'),
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
                        CupertinoIcons.clock,
                        color: AppColors.inkText,
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
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
                _OrdersTab.past => history.isEmpty
                    ? const _EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No past orders yet',
                        subtitle: 'Orders you complete will show up here.',
                      )
                    : _PastOrdersTab(history: history),
                _OrdersTab.cancelled => const _EmptyState(
                    icon: Icons.cancel_outlined,
                    title: 'No cancelled orders',
                    subtitle: 'Anything you cancel will be listed here.',
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
  OrderStage.placed => (0, 'Order confirmed', Icons.check_circle_outline_rounded),
  OrderStage.runnerAssigned => (1, 'Preparing your order', Icons.restaurant_rounded),
  OrderStage.pickedUp => (2, 'On the way to you', Icons.two_wheeler_rounded),
  OrderStage.delivered => (3, 'Arrived', Icons.home_rounded),
};

const _etaByStage = {
  OrderStage.placed: '15–20 min',
  OrderStage.runnerAssigned: '10–15 min',
  OrderStage.pickedUp: '5–10 min',
  OrderStage.delivered: 'Arrived',
};

class _ActiveOrderTab extends ConsumerWidget {
  const _ActiveOrderTab({required this.session});
  final OrderTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = session.stage!;
    final (stepIndex, statusLabel, statusIcon) = _activeStepInfo(stage);
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
                const SizedBox(height: 18),
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

class _PastOrdersTab extends ConsumerWidget {
  const _PastOrdersTab({required this.history});
  final List<OrderHistoryEntry> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = DateFormat('MMM d');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = history[index];
        final isYesterday =
            DateTime.now().difference(entry.deliveredAt).inDays == 1;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              MenuImagePlaceholder(seed: entry.eateryName, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.eateryName,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: AppColors.inkText),
                    ),
                    Text(
                      entry.itemsSummary,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Delivered ${isYesterday ? 'Yesterday' : formatter.format(entry.deliveredAt)}',
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
                    naira(entry.total),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryMaroon,
                      side: const BorderSide(color: AppColors.primaryMaroon),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    onPressed: () => ref
                        .read(appNotificationProvider.notifier)
                        .info('Reordering is coming soon.'),
                    child: const Text('Reorder'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
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
