import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/route_line.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../wallet/application/wallet_controller.dart';
import '../application/order_tracking_controller.dart';
import '../application/ordering_providers.dart';
import '../domain/ordering_models.dart';
import '../domain/pricing_service.dart';
import 'widgets/ordering_components.dart';

class EateryMenuScreen extends ConsumerStatefulWidget {
  const EateryMenuScreen({super.key});
  @override
  ConsumerState<EateryMenuScreen> createState() => _EateryMenuScreenState();
}

class _EateryMenuScreenState extends ConsumerState<EateryMenuScreen> {
  String _category = 'All';
  // Visual-only toggle — there's no favorites/backend concept yet (same
  // "coming soon" scope as Profile's own Favorites row).
  bool _isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final eatery = ref.watch(selectedEateryProvider);
    final menu = ref.watch(menuProvider);
    final basket = ref.watch(basketProvider);
    return Scaffold(
      body: eatery.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Unable to load this eatery.')),
        data: (place) => place == null
            ? const _NoVendorsEmptyState()
            : menu.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text('Unable to load this menu.')),
                data: (items) {
                  final categories = [
                    'All',
                    ...{for (final item in items) item.category},
                  ];
                  final visible = _category == 'All'
                      ? items
                      : items
                            .where((item) => item.category == _category)
                            .toList();
                  return CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        backgroundColor: Theme.of(context)
                            .scaffoldBackgroundColor,
                        surfaceTintColor: Colors.transparent,
                        leading: IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        actions: [
                          IconButton(
                            onPressed: () =>
                                setState(() => _isFavorite = !_isFavorite),
                            icon: Icon(
                              _isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: _isFavorite ? AppColors.error : null,
                            ),
                          ),
                          _BasketAction(
                            count: basket.items.fold(
                              0,
                              (sum, item) => sum + item.quantity,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                        sliver: SliverToBoxAdapter(
                          child: _EateryHero(eatery: place),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 72,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) => CategoryChip(
                              label: categories[index],
                              selected: _category == categories[index],
                              onTap: () =>
                                  setState(() => _category = categories[index]),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
                        sliver: SliverList.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final item = visible[index];
                            final matching = basket.items.where(
                              (line) => line.menuItemId == item.id,
                            );
                            final quantity = matching.isEmpty
                                ? 0
                                : matching.first.quantity;
                            return _MenuItemCard(
                              item: item,
                              isEateryOpen: place.isOpen,
                              quantity: quantity,
                              onAdd: () => _add(item),
                              onRemove: () => ref
                                  .read(basketProvider.notifier)
                                  .setQuantity(item.id, quantity - 1),
                              onTap: item.isAvailable && place.isOpen
                                  ? () => _openOptionsSheet(item, quantity)
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _FloatingBasketBar(
          visible: !basket.isEmpty,
          label: () {
            final count = basket.items.fold(
              0,
              (sum, item) => sum + item.quantity,
            );
            final items = menu.valueOrNull ?? const <MenuItem>[];
            final subtotal = PricingService.calculate(
              basket: basket,
              menuItems: items,
              zone: DeliveryFeeZone.central,
            ).subtotal;
            return 'View Basket · $count item${count == 1 ? '' : 's'} · ${naira(subtotal)}';
          }(),
          onTap: () => context.push(AppRoutes.basket),
        ),
      ),
    );
  }

  void _openOptionsSheet(MenuItem item, int currentQuantity) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _ItemOptionsSheet(
        item: item,
        initialQuantity: currentQuantity == 0 ? 1 : currentQuantity,
        onConfirm: (quantity) {
          final result = ref.read(basketProvider.notifier).add(item);
          if (result == AddToBasketResult.needsReplacement) {
            Navigator.pop(context);
            _confirmReplace(item);
            return;
          }
          ref.read(basketProvider.notifier).setQuantity(item.id, quantity);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _add(MenuItem item) {
    final result = ref.read(basketProvider.notifier).add(item);
    if (result != AddToBasketResult.needsReplacement) return;
    _confirmReplace(item);
  }

  void _confirmReplace(MenuItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new basket?'),
        content: const Text(
          'Your basket can only contain items from one eatery. Replacing it will remove your current items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep basket'),
          ),
          TextButton(
            onPressed: () {
              ref.read(basketProvider.notifier).replaceWith(item);
              Navigator.pop(dialogContext);
            },
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }
}

/// The persistent "View Basket" affordance — its own elevated tray (same
/// rounded-top-corner + soft-shadow treatment as [AppNavShell]'s nav bar)
/// so it reads as floating above the screen content rather than a bare
/// button glued to the bottom edge. Stays mounted even when [visible] is
/// false so hiding/showing (and the label changing as items are added)
/// animates instead of popping in and out.
class _FloatingBasketBar extends StatelessWidget {
  const _FloatingBasketBar({
    required this.visible,
    required this.label,
    required this.onTap,
  });
  final bool visible;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: AppMotion.base,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            margin: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppElevation.raised(false),
            ),
            child: AnimatedSwitcher(
              duration: AppMotion.fast,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.emphasized,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(label),
                child: PrimaryButton(label: label, onPressed: onTap),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BasketScreen extends ConsumerWidget {
  const BasketScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = ref.watch(basketProvider);
    final menu = ref.watch(menuProvider).valueOrNull ?? const <MenuItem>[];
    final eateryName =
        ref.watch(selectedEateryProvider).valueOrNull?.name ?? '';
    final form = ref.watch(checkoutFormProvider);
    final pricing = PricingService.calculate(
      basket: basket,
      menuItems: menu,
      zone: form.location.zone,
    );
    if (basket.isEmpty) return const _EmptyBasket();
    final lines = <(BasketItem, MenuItem)>[];
    for (final line in basket.items) {
      final match = menu.where((item) => item.id == line.menuItemId);
      if (match.isNotEmpty) lines.add((line, match.first));
    }
    final hasUnavailable = lines.any((entry) => !entry.$2.isAvailable);
    return Scaffold(
      appBar: AppBar(title: const Text('Your basket')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        children: [
          Text(
            eateryName,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: OrderingColors.muted(context)),
          ),
          const SizedBox(height: 14),
          ...lines.map(
            (entry) => Dismissible(
              key: ValueKey(entry.$1.menuItemId),
              direction: DismissDirection.endToStart,
              onDismissed: (_) =>
                  ref.read(basketProvider.notifier).remove(entry.$1.menuItemId),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              ),
              child: _BasketLine(
                item: entry.$2,
                quantity: entry.$1.quantity,
                onAdd: () => ref
                    .read(basketProvider.notifier)
                    .setQuantity(entry.$1.menuItemId, entry.$1.quantity + 1),
                onRemove: () => ref
                    .read(basketProvider.notifier)
                    .setQuantity(entry.$1.menuItemId, entry.$1.quantity - 1),
              ),
            ),
          ),
          if (hasUnavailable)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'One or more items are no longer available. Remove them to continue.',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'A note for your runner',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: OrderingColors.text(context)),
          ),
          const SizedBox(height: 8),
          const AppTextField(hintText: 'Gate, landmark, or anything helpful'),
          const SizedBox(height: 24),
          _Breakdown(pricing: pricing),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: PrimaryButton(
            label: hasUnavailable
                ? 'Remove unavailable items to continue'
                : 'Proceed to checkout · ${naira(pricing.total)}',
            onPressed: hasUnavailable
                ? null
                : () => context.push(AppRoutes.checkout),
          ),
        ),
      ),
    );
  }
}

class CheckoutScreen extends ConsumerWidget {
  const CheckoutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = ref.watch(basketProvider);
    final menu = ref.watch(menuProvider).valueOrNull ?? const <MenuItem>[];
    final eateryName =
        ref.watch(selectedEateryProvider).valueOrNull?.name ?? 'Vendor';
    final form = ref.watch(checkoutFormProvider);
    final wallet = ref.watch(walletBalanceProvider);
    final pricing = PricingService.calculate(
      basket: basket,
      menuItems: menu,
      zone: form.location.zone,
    );
    final insufficient = wallet < pricing.total;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        children: [
          const _SectionLabel(label: 'DELIVERY'),
          _LocationCard(
            location: form.location,
            onEdit: () => _pickLocation(context, ref),
          ),
          const SizedBox(height: 26),
          const _SectionLabel(label: 'PAYMENT'),
          _PaymentOption(
            icon: Icons.account_balance_wallet_outlined,
            title: 'RUN IT Wallet',
            subtitle:
                'Balance ${naira(wallet)}${insufficient ? ' · Not enough for this order' : ''}',
            selected: form.paymentMethod == PaymentMethod.wallet,
            warning: insufficient,
            onTap: () => ref
                .read(checkoutFormProvider.notifier)
                .setPayment(PaymentMethod.wallet),
          ),
          if (insufficient)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child:
                  InkWell(
                        onTap: () => context.push(AppRoutes.studentWallet),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentRose,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your wallet balance is too low for this order.',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: AppColors.inkText,
                                        height: 1.3,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Add funds to your wallet',
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.primaryMaroon,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: AppColors.primaryMaroon,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: AppMotion.base)
                      .scaleXY(
                        begin: 0.97,
                        end: 1,
                        duration: AppMotion.base,
                        curve: AppMotion.emphasized,
                      ),
            ),
          const SizedBox(height: 10),
          // STUB: card/bank has no gateway wired up yet — same convention
          // as Wallet's own mock Add Funds/Withdraw. Tapping it never
          // actually selects it as a usable payment method; it just tells
          // the shopper it's on the way, per the Wallet-flow precedent.
          _PaymentOption(
            icon: Icons.credit_card_rounded,
            title: 'Card / Bank',
            subtitle: 'Coming soon',
            selected: false,
            onTap: () => ref
                .read(appNotificationProvider.notifier)
                .info(
                  'Card payments are coming soon — pay with your Wallet for now.',
                ),
          ),
          const SizedBox(height: 26),
          const _SectionLabel(label: 'PROMO CODE'),
          const SizedBox(height: 8),
          const AppTextField(hintText: 'Add a code (optional)'),
          const SizedBox(height: 26),
          _Breakdown(pricing: pricing),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: PrimaryButton(
            label: insufficient
                ? 'Wallet balance is insufficient'
                : 'Place order · ${naira(pricing.total)}',
            onPressed: insufficient
                ? null
                : () {
                    final lines = [
                      for (final line in basket.items)
                        '${line.quantity} × ${menu.firstWhere((item) => item.id == line.menuItemId).name}',
                    ];
                    // STUB: deducts local wallet state only — no real
                    // payment-gateway call, same convention as
                    // WalletBalanceController.mockAddFunds/mockWithdraw.
                    final charged = ref
                        .read(walletBalanceProvider.notifier)
                        .mockWithdraw(pricing.total);
                    if (!charged) return;
                    ref
                        .read(walletTransactionsProvider.notifier)
                        .recordOrderPayment(
                          eateryName: eateryName,
                          amount: pricing.total,
                        );
                    ref
                        .read(orderTrackingProvider.notifier)
                        .placeOrder(
                          orderItems: lines,
                          total: pricing.total,
                          eateryName: eateryName,
                          deliveryLocationLabel: form.location.label,
                        );
                    ref.read(basketProvider.notifier).clear();
                    context.go(AppRoutes.orderTracking);
                  },
          ),
        ),
      ),
    );
  }

  void _pickLocation(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose delivery point',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...DeliveryFeeZone.values.map(
              (zone) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(zone.label),
                subtitle: Text('Delivery from ${naira(zone.fee)}'),
                onTap: () {
                  final currentLabel = ref
                      .read(checkoutFormProvider)
                      .location
                      .label;
                  ref
                      .read(checkoutFormProvider.notifier)
                      .setLocation(
                        DeliveryLocation(label: currentLabel, zone: zone),
                      );
                  Navigator.pop(sheetContext);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({super.key});

  static const _steps = [
    'Order placed',
    'Runner assigned',
    'Picked up',
    'Delivered',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(orderTrackingProvider);
    final stage = session.stage;
    if (stage == null) return const _NoActiveOrder();

    final delivered = stage == OrderStage.delivered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track your order'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          children: [
            StatusStepper(steps: _steps, activeIndex: stage.index),
            const SizedBox(height: 26),
            Text(
              _statusLine(session),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            const SizedBox(height: 22),
            _MapPlaceholder(delivered: delivered),
            if (session.runnerName != null) ...[
              const SizedBox(height: 18),
              _RunnerCard(name: session.runnerName!),
            ],
            const SizedBox(height: 18),
            _OrderSummaryCard(items: session.orderItems, total: session.total),
            if (delivered) ...[
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Back to menu',
                onPressed: () {
                  ref.read(orderTrackingProvider.notifier).resetOrder();
                  context.go(AppRoutes.menu);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLine(OrderTrackingSession session) {
    switch (session.stage) {
      case OrderStage.placed:
        return 'Looking for a runner nearby.';
      case OrderStage.runnerAssigned:
        return '${session.runnerName} is heading to ${session.eateryName}.';
      case OrderStage.pickedUp:
        return '${session.runnerName} has picked up your order.';
      case OrderStage.delivered:
        return 'Delivered to ${session.deliveryLocationLabel}.';
      case null:
        return '';
    }
  }
}

class _NoActiveOrder extends StatelessWidget {
  const _NoActiveOrder();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Track your order')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: OrderingColors.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No active order.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go(AppRoutes.menu),
              child: const Text('Browse the menu'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.delivered});
  final bool delivered;
  @override
  Widget build(BuildContext context) => Container(
    height: 170,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delivered ? Icons.location_on_rounded : Icons.map_outlined,
          size: 30,
          color: AppColors.primaryMaroon,
        ),
        const SizedBox(height: 8),
        Text(
          delivered ? 'Delivered' : 'Live map coming soon',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: OrderingColors.muted(context)),
        ),
      ],
    ),
  );
}

class _RunnerCard extends StatelessWidget {
  const _RunnerCard({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
          child: Text(
            name[0],
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppColors.primaryMaroon),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              Text(
                'Your runner',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: OrderingColors.muted(context)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: null,
          icon: const Icon(Icons.call_outlined),
          color: OrderingColors.muted(context),
        ),
        IconButton(
          onPressed: null,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          color: OrderingColors.muted(context),
        ),
      ],
    ),
  );
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.items, required this.total});
  final List<String> items;
  final int total;
  @override
  Widget build(BuildContext context) => Container(
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
          'ORDER SUMMARY',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1,
            color: OrderingColors.muted(context),
          ),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              item,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Divider(color: OrderingColors.border(context)),
        ),
        PriceRow(label: 'Total', amount: total, emphasized: true),
      ],
    ),
  );
}

class _EateryHero extends StatelessWidget {
  const _EateryHero({required this.eatery});
  final Eatery eatery;
  @override
  Widget build(BuildContext context) => Container(
    height: 184,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.primaryMaroonDeep,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            eatery.isOpen ? 'OPEN NOW' : 'CLOSED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.onMaroon,
            ),
          ),
        ),
        const Spacer(),
        Text(
          eatery.name,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.star_rounded,
              size: 17,
              color: AppColors.primaryMaroon,
            ),
            const SizedBox(width: 4),
            Text(
              '${eatery.rating}',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              '· ${eatery.prepTimeMinutes} min prep',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Colors.white.withValues(alpha: .72)),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BasketAction extends StatelessWidget {
  const _BasketAction({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: () => context.push(AppRoutes.basket),
    icon: Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.shopping_bag_outlined),
    ),
  );
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.item,
    required this.isEateryOpen,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.onTap,
  });
  final MenuItem item;
  final bool isEateryOpen;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: item.isAvailable && isEateryOpen ? 1 : .48,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: OrderingColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OrderingColors.border(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MenuImagePlaceholder(seed: item.name),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 16,
                      color: OrderingColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      height: 1.35,
                      color: OrderingColors.muted(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        naira(item.price),
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: OrderingColors.text(context)),
                      ),
                      const Spacer(),
                      item.isAvailable && isEateryOpen
                          ? QuantityStepper(
                              quantity: quantity,
                              onAdd: onAdd,
                              onRemove: onRemove,
                              compact: true,
                            )
                          : Text(isEateryOpen ? 'Unavailable' : 'Closed'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Quantity (+ any future add-ons — the menu has no options model yet, so
/// this is quantity-only for now) bottom sheet opened by tapping a menu
/// item's row. The inline "+"/stepper on the card itself stays for a quick
/// one-tap add; this sheet is for a deliberate, reviewed add.
class _ItemOptionsSheet extends StatefulWidget {
  const _ItemOptionsSheet({
    required this.item,
    required this.initialQuantity,
    required this.onConfirm,
  });
  final MenuItem item;
  final int initialQuantity;
  final ValueChanged<int> onConfirm;

  @override
  State<_ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<_ItemOptionsSheet> {
  late int _quantity = widget.initialQuantity;

  @override
  Widget build(BuildContext context) {
    final total = widget.item.price * _quantity;
    return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            8,
            22,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MenuImagePlaceholder(seed: widget.item.name, size: 68),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: OrderingColors.text(context)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: OrderingColors.muted(context)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          naira(widget.item.price),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: OrderingColors.text(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Quantity',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: OrderingColors.text(context)),
                  ),
                  const Spacer(),
                  QuantityStepper(
                    quantity: _quantity,
                    onAdd: () => setState(() => _quantity += 1),
                    onRemove: () => setState(
                      () => _quantity = _quantity <= 1 ? 1 : _quantity - 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                switchInCurve: AppMotion.emphasized,
                switchOutCurve: AppMotion.emphasized,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: PrimaryButton(
                  key: ValueKey(total),
                  label: 'Add to Basket — ${naira(total)}',
                  onPressed: () => widget.onConfirm(_quantity),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: AppMotion.base)
        .moveY(
          begin: 14,
          end: 0,
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
        );
  }
}

class _BasketLine extends StatelessWidget {
  const _BasketLine({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Row(
      children: [
        MenuImagePlaceholder(seed: item.name, size: 62),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              const SizedBox(height: 4),
              Text(
                '${naira(item.price)} each',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: OrderingColors.muted(context)),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              naira(item.price * quantity),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: OrderingColors.text(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            QuantityStepper(
              quantity: quantity,
              onAdd: onAdd,
              onRemove: onRemove,
              compact: true,
            ),
          ],
        ),
      ],
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.pricing});
  final PriceBreakdown pricing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Column(
      children: [
        PriceRow(label: 'Items', amount: pricing.subtotal),
        PriceRow(label: 'Packaging', amount: pricing.packagingTotal),
        PriceRow(label: 'Delivery', amount: pricing.deliveryFee),
        PriceRow(label: 'Service fee', amount: pricing.serviceFee),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Divider(color: OrderingColors.border(context)),
        ),
        PriceRow(label: 'Total', amount: pricing.total, emphasized: true),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
      color: OrderingColors.muted(context),
    ),
  );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.onEdit});
  final DeliveryLocation location;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: OrderingColors.surface(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: OrderingColors.border(context)),
    ),
    child: Row(
      children: [
        const Icon(Icons.location_on_outlined, color: AppColors.primaryMaroon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              const SizedBox(height: 3),
              Text(
                location.zone.label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: OrderingColors.muted(context)),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onEdit, child: const Text('Edit')),
      ],
    ),
  );
}

/// A selectable payment card — same fill/border/shadow selection language
/// as [_RoleCard] on Account Type (tinted fill + maroon border + a lifted
/// shadow once chosen), not a plain radio row.
class _PaymentOption extends StatefulWidget {
  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.warning = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool warning;
  final VoidCallback onTap;

  @override
  State<_PaymentOption> createState() => _PaymentOptionState();
}

class _PaymentOptionState extends State<_PaymentOption> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.title,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: AppMotion.fast,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.emphasized,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.accentRose.withValues(alpha: .32)
                  : OrderingColors.surface(context),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: widget.selected
                    ? AppColors.primaryMaroon
                    : Colors.transparent,
                width: 1.6,
              ),
              boxShadow: widget.selected
                  ? AppElevation.raised(false)
                  : AppElevation.card(false),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: widget.selected
                      ? AppColors.primaryMaroon
                      : OrderingColors.muted(context),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: OrderingColors.text(context)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.warning
                              ? Theme.of(context).colorScheme.error
                              : OrderingColors.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.emphasized,
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? AppColors.primaryMaroon
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.selected
                          ? AppColors.primaryMaroon
                          : OrderingColors.border(context),
                      width: 1.6,
                    ),
                  ),
                  child: widget.selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your basket')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 44,
              color: OrderingColors.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Your basket is waiting.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: OrderingColors.text(context)),
            ),
            const SizedBox(height: 8),
            Text(
              'Add something you’ll look forward to.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: OrderingColors.muted(context)),
            ),
            const SizedBox(height: 22),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Browse the menu'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shown when the signed-in user's campus has no active vendors yet — the
/// repository legitimately returned an empty list, not an error. Content
/// only for now; this gets the full design-system treatment in the
/// dedicated retrofit pass.
class _NoVendorsEmptyState extends StatelessWidget {
  const _NoVendorsEmptyState();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RouteLineEmptyIllustration(),
                  const SizedBox(height: 16),
                  Text(
                    'No vendors here yet.',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(color: OrderingColors.text(context)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We're still onboarding vendors for your campus — check back soon.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: OrderingColors.muted(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
