import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton.dart';
import '../../ordering/presentation/widgets/ordering_components.dart' show naira;
import '../application/restaurant_metrics_controller.dart';
import '../domain/vendor_dashboard_models.dart';

enum _RangePreset { last7, last30, last90 }

extension on _RangePreset {
  String get label => switch (this) {
    _RangePreset.last7 => '7 days',
    _RangePreset.last30 => '30 days',
    _RangePreset.last90 => '90 days',
  };
  int get days => switch (this) {
    _RangePreset.last7 => 7,
    _RangePreset.last30 => 30,
    _RangePreset.last90 => 90,
  };
}

/// Task 12's Metrics tab — real numbers from `GET /vendors/me/metrics`
/// only, never computed client-side from the Orders list, presented as a
/// ranked revenue-bar visualization rather than a bare table (a plain list
/// of numbers doesn't help a restaurant owner see "what's actually
/// selling" at a glance the way a proportional bar does).
class RestaurantMetricsScreen extends ConsumerStatefulWidget {
  const RestaurantMetricsScreen({super.key});

  @override
  ConsumerState<RestaurantMetricsScreen> createState() => _RestaurantMetricsScreenState();
}

class _RestaurantMetricsScreenState extends ConsumerState<RestaurantMetricsScreen> {
  _RangePreset _preset = _RangePreset.last30;

  Future<void> _selectPreset(_RangePreset preset) async {
    setState(() => _preset = preset);
    final now = DateTime.now();
    await ref
        .read(restaurantMetricsProvider.notifier)
        .setRange(MetricsDateRange(from: now.subtract(Duration(days: preset.days)), to: now));
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(restaurantMetricsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(title: const Text('Metrics'), backgroundColor: AppColors.backgroundCream, elevation: 0),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.accentForest,
          onRefresh: () => ref.read(restaurantMetricsProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _RangePreset.values)
                    _RangeChip(
                      label: 'Last ${preset.label}',
                      selected: _preset == preset,
                      onTap: () => _selectPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              metricsAsync.when(
                loading: () => const Column(
                  children: [
                    SkeletonList(count: 1),
                    SizedBox(height: 20),
                    SkeletonList(count: 4),
                  ],
                ),
                error: (error, stack) => _ErrorState(
                  onRetry: () => ref.read(restaurantMetricsProvider.notifier).refresh(),
                ),
                data: (metrics) => _MetricsBody(metrics: metrics),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsBody extends StatelessWidget {
  const _MetricsBody({required this.metrics});
  final VendorMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final maxCount = metrics.mostOrderedItems.fold(0, (max, item) => item.count > max ? item.count : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_long_rounded,
                label: 'Orders',
                value: '${metrics.totalOrders}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.payments_rounded,
                label: 'Revenue',
                value: naira(metrics.totalRevenueKobo ~/ 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Most ordered',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        if (metrics.mostOrderedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No orders in this range yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
            ),
          )
        else
          for (final item in metrics.mostOrderedItems.take(10))
            _RankedItemBar(item: item, maxCount: maxCount == 0 ? 1 : maxCount),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accentForest, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: AppColors.inkText, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.mutedText)),
        ],
      ),
    );
  }
}

/// A ranked-list-with-revenue-bars visualization: the bar's fill width is
/// proportional to this item's order count against the top seller, so
/// "what's actually selling" reads at a glance rather than requiring the
/// owner to compare raw numbers themselves.
class _RankedItemBar extends StatelessWidget {
  const _RankedItemBar({required this.item, required this.maxCount});
  final VendorMetricsItem item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final fraction = (item.count / maxCount).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.count} sold',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(width: 10),
              Text(
                naira(item.revenueKobo ~/ 100),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.accentForestDeep, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(
                  height: 8,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  height: 8,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.accentForest, AppColors.accentForestDeep]),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
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

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentForest : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.accentForest : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? Colors.white : AppColors.inkText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your metrics.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
