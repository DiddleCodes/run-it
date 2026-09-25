import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../ordering/domain/order_decline.dart';
import '../../ordering/presentation/widgets/ordering_components.dart' show naira;
import '../application/restaurant_orders_controller.dart';
import '../domain/vendor_dashboard_models.dart';

/// Task 12's Orders tab — the live kitchen queue, each card carrying
/// everything kitchen staff actually need at a glance: items + quantities,
/// the student's own Notes (easy to build a card that forgets this — it's
/// the one field that matters most to whoever's cooking), and a
/// status-appropriate forward action. No optimistic UI: an action button
/// shows its own loading state and the card only reflects the new status
/// once `RestaurantOrdersController.advanceStatus` confirms it against the
/// real backend and refetches.
class RestaurantOrdersScreen extends ConsumerWidget {
  const RestaurantOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(restaurantOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(title: const Text('Orders'), backgroundColor: AppColors.backgroundCream, elevation: 0),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.accentForest,
          onRefresh: () => ref.read(restaurantOrdersProvider.notifier).refresh(),
          child: ordersAsync.when(
            loading: () => ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
              children: const [SkeletonList(count: 4)],
            ),
            error: (error, stack) => _ErrorState(
              onRetry: () => ref.read(restaurantOrdersProvider.notifier).refresh(),
            ),
            data: (page) => page.items.isEmpty
                ? const _EmptyOrders()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) => _OrderCard(order: page.items[index]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order});
  final RestaurantOrder order;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _advancing = false;

  Future<void> _advance(RestaurantOrderStatus next) async {
    setState(() => _advancing = true);
    try {
      await ref.read(restaurantOrdersProvider.notifier).advanceStatus(widget.order.id, next);
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(
            e is ApiException ? e.message : "Couldn't reach the server. Check your connection and try again.",
          );
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  /// Task 61: offered only alongside the accept action on a `placed`
  /// order. The sheet returns the chosen reason; nothing is sent until the
  /// restaurant confirms it there.
  Future<void> _decline() async {
    final choice = await showModalBottomSheet<_DeclineChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const _DeclineSheet(),
    );
    if (choice == null || !mounted) return;

    setState(() => _advancing = true);
    try {
      await ref
          .read(restaurantOrdersProvider.notifier)
          .declineOrder(widget.order.id, choice.reason, note: choice.note);
      if (!mounted) return;
      ref.read(appNotificationProvider.notifier).success('Order declined. The student has been notified.');
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(
            e is ApiException ? e.message : "Couldn't reach the server. Check your connection and try again.",
          );
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final nextAction = order.status.nextVendorAction;
    final canDecline = order.status == RestaurantOrderStatus.placed;
    final declinedBecause = declineReasonText(order.declineReason, order.declineReasonNote);
    final showPickupCode =
        order.status == RestaurantOrderStatus.readyForPickup || order.status == RestaurantOrderStatus.pickedUp;

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
          Row(
            children: [
              Flexible(
                child: Text(
                  '#${order.id.substring(0, order.id.length.clamp(0, 8))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.mutedText, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              _StatusPill(status: order.status),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.quantity}×',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.accentForest, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          // Task 45: one note for the whole order, replacing the old
          // per-item notes — the field a kitchen card most needs to not
          // forget.
          if (order.note != null && order.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '"${order.note!.trim()}"',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.gold, fontStyle: FontStyle.italic),
              ),
            ),
          const Divider(height: AppSpacing.lg, color: AppColors.borderSubtle),
          Row(
            children: [
              Text(
                naira(order.totalKobo ~/ 100),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppColors.inkText, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (showPickupCode) _PickupCodeBadge(code: order.pickupCode),
            ],
          ),
          if (declinedBecause != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Declined: $declinedBecause',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.mutedText),
              ),
            ),
          if (nextAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (canDecline) ...[
                  Expanded(
                    child: PrimaryButton(
                      label: 'Decline',
                      style: PrimaryButtonStyle.outlined,
                      onPressed: _advancing ? null : _decline,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: canDecline ? 2 : 1,
                  child: PrimaryButton(
                    label: order.status.nextActionLabel,
                    loading: _advancing,
                    onPressed: _advancing ? null : () => _advance(nextAction),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PickupCodeBadge extends StatelessWidget {
  const _PickupCodeBadge({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentForest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_rounded, size: 14, color: AppColors.accentForest),
          const SizedBox(width: 5),
          Text(
            'Pickup: $code',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.accentForestDeep, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final RestaurantOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      RestaurantOrderStatus.placed => (AppColors.goldTint, AppColors.gold),
      RestaurantOrderStatus.preparing => (AppColors.accentForest.withValues(alpha: 0.12), AppColors.accentForest),
      RestaurantOrderStatus.readyForPickup => (AppColors.successBackground, AppColors.success),
      RestaurantOrderStatus.pickedUp => (AppColors.borderSubtle, AppColors.mutedText),
      RestaurantOrderStatus.delivered => (AppColors.borderSubtle, AppColors.mutedText),
      RestaurantOrderStatus.cancelled => (AppColors.accentRose, AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inbox_outlined, size: 48, color: AppColors.mutedText),
                  const SizedBox(height: 12),
                  Text(
                    'No orders right now',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.inkText, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "New orders will show up here as soon as they come in.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    "Couldn't load your orders.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeclineChoice {
  const _DeclineChoice(this.reason, this.note);
  final OrderDeclineReason reason;
  final String? note;
}

/// Task 61: pick exactly one reason; "Other" requires free text before
/// Decline enables. Pops a [_DeclineChoice], or nothing if dismissed.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet();

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  OrderDeclineReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _valid =>
      _reason != null && (_reason != OrderDeclineReason.other || _note.text.trim().isNotEmpty);

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
            'Decline this order?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 6),
          Text(
            "The student is refunded in full and sees the reason you pick.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 8),
          RadioGroup<OrderDeclineReason>(
            groupValue: _reason,
            onChanged: (value) => setState(() => _reason = value),
            child: Column(
              children: [
                for (final reason in OrderDeclineReason.values)
                  RadioListTile<OrderDeclineReason>(
                    value: reason,
                    title: Text(reason.label),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.accentForest,
                  ),
              ],
            ),
          ),
          if (_reason == OrderDeclineReason.other)
            TextField(
              controller: _note,
              autofocus: true,
              maxLength: 280,
              decoration: const InputDecoration(hintText: 'Tell the student why'),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Decline order',
              onPressed: _valid
                  ? () => Navigator.pop(
                      context,
                      _DeclineChoice(_reason!, _reason == OrderDeclineReason.other ? _note.text.trim() : null),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
