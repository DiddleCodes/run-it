import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/orders_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/order_history_models.dart';
import 'widgets/ordering_components.dart';

/// Task 46: the real order-history detail view — fetched fresh from
/// `GET /orders/:orderId` (not reused from whatever the list already had
/// cached), so it always reflects the order's current, real state.
final _orderDetailProvider = FutureProvider.autoDispose
    .family<OrderHistoryEntry, String>((ref, orderId) async {
      final session = ref.watch(authControllerProvider);
      if (session == null) throw StateError('Not signed in');
      return ref
          .watch(ordersRepositoryProvider)
          .fetchOrderDetail(orderId: orderId, token: session.accessToken);
    });

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(_orderDetailProvider(orderId));
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: const Text('Order details'),
        backgroundColor: AppColors.backgroundCream,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
            child: SkeletonList(count: 4),
          ),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Couldn't load this order",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(_orderDetailProvider(orderId)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (order) => _OrderDetailBody(order: order),
        ),
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({required this.order});
  final OrderHistoryEntry order;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 32),
      children: [
        Text(
          order.vendorName,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.inkText),
        ),
        const SizedBox(height: 4),
        Text(
          order.itemsSummary,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.ml),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: order.status == 'cancelled'
              ? _CancelledSummary(order: order)
              : _LifecycleStepper(order: order),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(AppSpacing.ml),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.inkText),
              ),
              const SizedBox(height: 10),
              for (final line in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        '${line.quantity}×',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line.name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                        ),
                      ),
                      Text(
                        naira(line.priceKobo * line.quantity ~/ 100),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                      ),
                    ],
                  ),
                ),
              const Divider(height: AppSpacing.lg, color: AppColors.borderSubtle),
              Row(
                children: [
                  Text(
                    'Total',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.inkText, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    naira(order.totalKobo ~/ 100),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.inkText, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (order.deliveryLocationLabel != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Delivery location',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: 2),
                Text(
                  order.deliveryLocationLabel!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                ),
              ],
              if (order.note != null && order.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Note',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: 2),
                Text(
                  order.note!.trim(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.inkText, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The real timestamped lifecycle — reuses [StatusStepper] (same widget
/// OrderTrackingScreen's live view uses) rather than a new visual language,
/// with each reached stage's real time folded into its label.
class _LifecycleStepper extends StatelessWidget {
  const _LifecycleStepper({required this.order});
  final OrderHistoryEntry order;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, h:mm a');
    String label(String name, DateTime? at) =>
        at == null ? name : '$name\n${formatter.format(at)}';

    final timestamps = [order.createdAt, order.acceptedAt, order.pickedUpAt, order.deliveredAt];
    // The last consecutively-reached stage — every real transition sets
    // its own timestamp only once its predecessor already happened, so a
    // gap never occurs, but stopping at the first null is still the
    // correct, honest read of "how far did this order actually get."
    var reached = 0;
    while (reached < timestamps.length && timestamps[reached] != null) {
      reached++;
    }

    return StatusStepper(
      steps: [
        label('Placed', order.createdAt),
        label('Accepted', order.acceptedAt),
        label('Picked Up', order.pickedUpAt),
        label('Delivered', order.deliveredAt),
      ],
      activeIndex: reached,
      nodeColumnWidth: 80,
    );
  }
}

class _CancelledSummary extends StatelessWidget {
  const _CancelledSummary({required this.order});
  final OrderHistoryEntry order;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, h:mm a');
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.accentRose, shape: BoxShape.circle),
          child: const Icon(Icons.cancel_outlined, color: AppColors.primaryMaroon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order cancelled',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
              ),
              if (order.cancelledAt != null)
                Text(
                  formatter.format(order.cancelledAt!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.successBackground,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${naira(order.totalKobo ~/ 100)} refunded',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
