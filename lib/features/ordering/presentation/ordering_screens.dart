import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/demo_identity_service.dart';
import '../../../core/network/escrow_repository.dart';
import '../../../core/network/orders_repository.dart';
import '../../../core/network/ratings_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/route_line.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../auth/application/auth_controller.dart';
import '../../wallet/application/wallet_controller.dart';
import '../application/order_tracking_controller.dart';
import '../application/ordering_providers.dart';
import '../domain/ordering_models.dart';
import '../domain/pricing_service.dart';
import 'my_orders_screen.dart';
import 'widgets/ordering_components.dart';

class EateryMenuScreen extends ConsumerStatefulWidget {
  // [vendorId] is the real vendor tapped on Home (Task 14) — `null` (e.g.
  // the post-delivery closing screen's "Order again") means "keep browsing
  // whichever vendor is already selected" rather than clearing it.
  const EateryMenuScreen({super.key, this.vendorId});
  final String? vendorId;
  @override
  ConsumerState<EateryMenuScreen> createState() => _EateryMenuScreenState();
}

class _EateryMenuScreenState extends ConsumerState<EateryMenuScreen> {
  String _category = 'All';
  // Visual-only toggle — there's no favorites/backend concept yet (same
  // "coming soon" scope as Profile's own Favorites row).
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    if (widget.vendorId != null) {
      // Deferred a frame — writing to a provider synchronously from
      // initState can fire while this very widget tree is still being
      // built (e.g. when this screen is the very first thing built inside
      // its ProviderScope), which Riverpod rejects outright.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(selectedVendorIdProvider.notifier).state = widget.vendorId;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eatery = ref.watch(selectedEateryProvider);
    final menu = ref.watch(menuProvider);
    final basket = ref.watch(basketProvider);
    return Scaffold(
      body: eatery.when(
        loading: () => const _MenuScreenSkeleton(),
        error: (_, _) =>
            const Center(child: Text('Unable to load this eatery.')),
        data: (place) => place == null
            ? const _NoVendorsEmptyState()
            : menu.when(
                loading: () => const _MenuScreenSkeleton(),
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
                            final note = matching.isEmpty
                                ? null
                                : matching.first.note;
                            return _MenuItemCard(
                              item: item,
                              isEateryOpen: place.isOpen,
                              quantity: quantity,
                              onAdd: () => _add(item),
                              onRemove: () => ref
                                  .read(basketProvider.notifier)
                                  .setQuantity(item.id, quantity - 1),
                              onTap: item.isAvailable && place.isOpen
                                  ? () =>
                                        _openOptionsSheet(item, quantity, note)
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

  void _openOptionsSheet(
    MenuItem item,
    int currentQuantity,
    String? currentNote,
  ) {
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
        initialNote: currentNote,
        onConfirm: (quantity, note) {
          final result = ref
              .read(basketProvider.notifier)
              .setLine(item, quantity: quantity, note: note);
          if (result == AddToBasketResult.needsReplacement) {
            Navigator.pop(context);
            _confirmReplace(item);
            return;
          }
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

  /// Reopens Task 6's Item Options sheet (the same one used from the Menu
  /// screen) prefilled with this line's current quantity/note — an edit
  /// affordance, not a second note-entry UI.
  void _editNote(
    BuildContext context,
    WidgetRef ref,
    BasketItem line,
    MenuItem item,
  ) {
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
        initialQuantity: line.quantity,
        initialNote: line.note,
        onConfirm: (quantity, note) {
          ref
              .read(basketProvider.notifier)
              .setLine(item, quantity: quantity, note: note);
          Navigator.pop(context);
        },
      ),
    );
  }

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
                note: entry.$1.note,
                onAdd: () => ref
                    .read(basketProvider.notifier)
                    .setQuantity(entry.$1.menuItemId, entry.$1.quantity + 1),
                onRemove: () => ref
                    .read(basketProvider.notifier)
                    .setQuantity(entry.$1.menuItemId, entry.$1.quantity - 1),
                onEditNote: () => _editNote(context, ref, entry.$1, entry.$2),
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

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _placingOrder = false;

  Future<void> _placeOrder({
    required List<String> orderItems,
    required List<EscrowOrderItem> escrowItems,
    required PriceBreakdown pricing,
    required String eateryName,
    required String deliveryLocationLabel,
  }) async {
    final session = ref.read(authControllerProvider);
    if (session == null) return;
    setState(() => _placingOrder = true);

    final orderId = 'order-${DateTime.now().microsecondsSinceEpoch}';
    try {
      // Task 14: the real vendor a student actually browsed and ordered
      // from, when one is known — falling back to the fixed demo
      // restaurant identity only if it somehow isn't (there's still no
      // real runner-matching backend, so the runner leg always stays
      // DemoIdentityService's stand-in — see its own doc comment).
      final vendor = await ref.read(selectedVendorProfileProvider.future);
      final restaurantUserId =
          vendor?.userId ??
          await ref.read(demoIdentityServiceProvider).ensureRestaurantUserId();
      final runnerUserId = await ref
          .read(demoIdentityServiceProvider)
          .ensureRunnerUserId();

      await ref
          .read(escrowRepositoryProvider)
          .hold(
            orderId: orderId,
            studentUserId: session.user.id,
            restaurantUserId: restaurantUserId,
            runnerUserId: runnerUserId,
            // Task 15: the backend now splits delivery fee out from the food
            // subtotal (and gives the runner a real cut of it) rather than
            // treating the whole order as one commissionable amount — so
            // grossAmountKobo carries everything except delivery, and the
            // real zone-based delivery fee (already shown in the checkout
            // breakdown below) travels separately. This keeps the total
            // charged identical to what the student was shown; only how the
            // backend splits it internally changes.
            grossAmountKobo:
                (pricing.subtotal + pricing.packagingTotal + pricing.serviceFee) *
                100,
            deliveryFeeKobo: pricing.deliveryFee * 100,
            token: session.accessToken,
            vendorId: vendor?.id,
            items: escrowItems,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _placingOrder = false);
      // 402 Payment Required from the backend means the balance check that
      // gated this button already went stale (e.g. spent elsewhere in
      // another tab) — anything else is a genuine backend rejection. Either
      // way, surface the backend's own message rather than a generic one,
      // and never proceed to OrderTrackingScreen on a failed hold.
      ref.read(appNotificationProvider.notifier).error(e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _placingOrder = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            "Couldn't reach the server. Check your connection and try again.",
          );
      return;
    }

    // Task 11: fetched once, right after the hold that generated it —
    // non-fatal on failure (a connectivity blip here shouldn't undo an
    // order that already placed successfully). OrderTrackingScreen falls
    // back to a "check your connection" notice if this comes back null.
    String? deliveryPin;
    try {
      deliveryPin = await ref
          .read(ordersRepositoryProvider)
          .fetchDeliveryPin(orderId: orderId, token: session.accessToken);
    } catch (_) {
      deliveryPin = null;
    }

    if (!mounted) return;
    ref
        .read(orderTrackingProvider.notifier)
        .placeOrder(
          orderId: orderId,
          orderItems: orderItems,
          total: pricing.total,
          eateryName: eateryName,
          deliveryLocationLabel: deliveryLocationLabel,
          deliveryPin: deliveryPin,
        );
    ref.read(basketProvider.notifier).clear();
    ref.read(walletBalanceProvider.notifier).refresh();
    setState(() => _placingOrder = false);
    context.go(AppRoutes.orderTracking);
  }

  List<EscrowOrderItem> _buildEscrowItems(
    Basket basket,
    List<MenuItem> menu,
  ) => [
    for (final line in basket.items)
      EscrowOrderItem(
        menuItemId: line.menuItemId,
        name: menu.firstWhere((item) => item.id == line.menuItemId).name,
        priceKobo:
            menu.firstWhere((item) => item.id == line.menuItemId).price * 100,
        quantity: line.quantity,
        notes: line.note,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final basket = ref.watch(basketProvider);
    final menu = ref.watch(menuProvider).valueOrNull ?? const <MenuItem>[];
    final eateryName =
        ref.watch(selectedEateryProvider).valueOrNull?.name ?? 'Vendor';
    final form = ref.watch(checkoutFormProvider);
    final wallet = ref.watch(walletBalanceProvider).valueOrNull ?? 0;
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
            loading: _placingOrder,
            onPressed: (insufficient || _placingOrder)
                ? null
                : () => _placeOrder(
                    orderItems: [
                      for (final line in basket.items)
                        '${line.quantity} × ${menu.firstWhere((item) => item.id == line.menuItemId).name}',
                    ],
                    // Task 14: the same lines, shaped for the escrow hold's
                    // real `items` payload — notes included, so a
                    // student's per-item request actually reaches
                    // `OrderItem.notes` instead of being computed as a
                    // display string and discarded.
                    escrowItems: _buildEscrowItems(basket, menu),
                    pricing: pricing,
                    eateryName: eateryName,
                    deliveryLocationLabel: form.location.label,
                  ),
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

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  static const _steps = [
    'Order Received',
    'Preparing',
    'En Route',
    'Delivered',
    'Confirmed',
  ];

  bool _cancelling = false;

  Future<void> _cancelOrder(OrderTrackingSession orderSession) async {
    final orderId = orderSession.orderId;
    final authSession = ref.read(authControllerProvider);
    if (orderId == null || authSession == null) return;
    setState(() => _cancelling = true);
    try {
      await ref
          .read(escrowRepositoryProvider)
          .refund(orderId: orderId, token: authSession.accessToken);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            e is ApiException ? e.message : "Couldn't reach the server. Check your connection and try again.",
          );
      return;
    }
    if (!mounted) return;
    ref
        .read(cancelledOrdersProvider.notifier)
        .recordCancellation(
          CancelledOrder(
            id: orderId,
            eateryName: orderSession.eateryName,
            itemsSummary: orderSession.orderItems.join(', '),
            refundedAmount: orderSession.total,
            cancelledAt: DateTime.now(),
          ),
        );
    ref.read(orderTrackingProvider.notifier).resetOrder();
    ref.read(walletBalanceProvider.notifier).refresh();
    setState(() => _cancelling = false);
    ref
        .read(appNotificationProvider.notifier)
        .success('Order cancelled and refunded to your wallet.');
    context.go(AppRoutes.studentOrders);
  }

  void _confirmCancel(OrderTrackingSession session) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text("You'll get a full refund to your RUN-It Wallet."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _cancelOrder(session);
            },
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
  }

  void _confirmDelivery() {
    ref.read(orderTrackingProvider.notifier).confirmDelivery();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(orderTrackingProvider);
    final stage = session.stage;
    if (stage == null) return const _NoActiveOrder();

    final delivered = stage == OrderStage.delivered;
    final confirmed = stage == OrderStage.confirmed;
    // Once the order is en route, this is what the student hands off to
    // the runner in person at drop-off (Task 11) — hidden before pickup so
    // there's nothing to show prematurely, and dropped once confirmed
    // since there's nothing left to verify.
    final showDeliveryPin =
        !confirmed && stage.index >= OrderStage.pickedUp.index;
    // Once a runner has picked the order up, cancelling would mean
    // reversing food that's already physically in transit — the
    // cancellation window closes there.
    final cancellable =
        stage == OrderStage.placed || stage == OrderStage.runnerAssigned;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track your order'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          children: [
            StatusStepper(
              steps: _steps,
              activeIndex: stage.index,
              showTravelIndicator: true,
              // 5 short-label steps at the default 72dp/node would overflow
              // this codebase's baseline 390dp phone width once this
              // screen's own 22dp horizontal padding is subtracted.
              nodeColumnWidth: 54,
            ),
            const SizedBox(height: 26),
            // "Confirmed" replaces the live-tracking status line with the
            // closing moment entirely — there's nothing left to track.
            if (confirmed)
              _ConfirmedClosingMessage(
                key: ValueKey('confirmed-${session.orderId}'),
                orderId: session.orderId,
              )
            else
              Text(
                _statusLine(session),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
            if (showDeliveryPin) ...[
              const SizedBox(height: 16),
              _DeliveryPinCard(pin: session.deliveryPin),
            ],
            const SizedBox(height: 22),
            if (!confirmed) ...[
              _MapPlaceholder(delivered: delivered),
              if (session.runnerName != null) ...[
                const SizedBox(height: 18),
                _RunnerCard(name: session.runnerName!),
              ],
              const SizedBox(height: 18),
            ],
            _OrderSummaryCard(items: session.orderItems, total: session.total),
            if (confirmed) ...[
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Back to menu',
                onPressed: () {
                  ref.read(orderTrackingProvider.notifier).resetOrder();
                  context.go(AppRoutes.menu);
                },
              ),
            ] else if (delivered) ...[
              const SizedBox(height: 28),
              // A student action, not automatic — this tap is the trigger
              // point the (future) rider-rating prompt will hang off of, so
              // it has to reflect a real acknowledgement rather than a timer.
              PrimaryButton(
                label: "I've received my order",
                onPressed: _confirmDelivery,
              ),
            ] else if (cancellable) ...[
              const SizedBox(height: 28),
              TextButton(
                onPressed: _cancelling ? null : () => _confirmCancel(session),
                child: _cancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cancel order'),
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
        return 'Delivered to ${session.deliveryLocationLabel}. Tap below once you have it.';
      case OrderStage.confirmed:
      case null:
        return '';
    }
  }
}

/// Task 11: large and hard to miss, since this is the code the student
/// hands off to the runner in person at drop-off — the other half of the
/// pickup-code handoff at the vendor. `pin == null` only ever means the
/// fetch right after checkout failed (a connectivity blip), never that
/// none was issued — this app never shows a fabricated code.
class _DeliveryPinCard extends StatelessWidget {
  const _DeliveryPinCard({required this.pin});
  final String? pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppElevation.raised(false),
      ),
      child: Column(
        children: [
          Text(
            'Show this code to your runner',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppColors.onMaroon.withValues(alpha: .85)),
          ),
          const SizedBox(height: 8),
          if (pin == null)
            Text(
              "Couldn't load your code — check your connection.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.onMaroon),
            )
          else
            Text(
              pin!.split('').join('  '),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppColors.onMaroon,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
        ],
      ),
    );
  }
}

/// Task 10's one hero moment on this screen: a brief, subtle celebratory
/// beat (never garish) settling into a warm closing message once the
/// student has confirmed receipt. Reuses [RouteLineReveal] — the same
/// "journey complete" motif already used for the KYC-approved moment —
/// rather than inventing a second checkmark animation for the same idea.
enum _ClosingPhase { rating, thanks, message }

/// The post-delivery closing flow (Task 10's "Enjoy your meal!" moment,
/// extended by Task 14 Part D): a star-rating prompt with a clear Skip
/// option comes first, then — only on a real submission, never
/// optimistically — a brief "Thanks for your feedback" confirmation,
/// before settling into the original celebratory message. An
/// already-rated (409) rejection is treated the same as a successful
/// submission: from the student's own perspective nothing went wrong, so
/// there's nothing to alarm them with.
class _ConfirmedClosingMessage extends ConsumerStatefulWidget {
  const _ConfirmedClosingMessage({super.key, required this.orderId});
  final String? orderId;

  @override
  ConsumerState<_ConfirmedClosingMessage> createState() =>
      _ConfirmedClosingMessageState();
}

class _ConfirmedClosingMessageState
    extends ConsumerState<_ConfirmedClosingMessage> {
  _ClosingPhase _phase = _ClosingPhase.rating;
  int _stars = 0;
  bool _submitting = false;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _skip() => setState(() => _phase = _ClosingPhase.message);

  Future<void> _showThanksThenMessage() async {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _phase = _ClosingPhase.thanks;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _phase = _ClosingPhase.message);
  }

  Future<void> _submit() async {
    final orderId = widget.orderId;
    final session = ref.read(authControllerProvider);
    if (orderId == null || _stars == 0 || session == null) return;
    setState(() => _submitting = true);

    try {
      await ref
          .read(ratingsRepositoryProvider)
          .rate(
            orderId: orderId,
            stars: _stars,
            comment: _commentController.text,
            token: session.accessToken,
          );
    } on ApiException catch (e) {
      // "This order has already been rated" is an expected, non-alarming
      // outcome here (e.g. a double-tap) — not a real failure to surface.
      if (e.statusCode == 409) {
        await _showThanksThenMessage();
        return;
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      ref.read(appNotificationProvider.notifier).error(e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ref
          .read(appNotificationProvider.notifier)
          .error(
            "Couldn't reach the server. Check your connection and try again.",
          );
      return;
    }
    await _showThanksThenMessage();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _ClosingPhase.rating:
        return _RatingPrompt(
          stars: _stars,
          onStarsChanged: (value) => setState(() => _stars = value),
          commentController: _commentController,
          submitting: _submitting,
          onSkip: _skip,
          onSubmit: _submit,
        );
      case _ClosingPhase.thanks:
        return const _ThanksForFeedback();
      case _ClosingPhase.message:
        return const _EnjoyYourMealMessage();
    }
  }
}

/// "How was your delivery?" — 1-5 stars, an optional short comment, and a
/// clear Skip so this never blocks the closing screen a student just wants
/// to leave.
class _RatingPrompt extends StatelessWidget {
  const _RatingPrompt({
    required this.stars,
    required this.onStarsChanged,
    required this.commentController,
    required this.submitting,
    required this.onSkip,
    required this.onSubmit,
  });
  final int stars;
  final ValueChanged<int> onStarsChanged;
  final TextEditingController commentController;
  final bool submitting;
  final VoidCallback onSkip;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: OrderingColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: OrderingColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How was your delivery?',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: OrderingColors.text(context)),
              ),
              const SizedBox(height: 4),
              Text(
                'Rate your runner — it only takes a second.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    InkWell(
                      onTap: () => onStarsChanged(i),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          i <= stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 34,
                          color: i <= stars
                              ? AppColors.gold
                              : AppColors.mutedText,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: commentController,
                hintText: 'Add a comment (optional)',
                maxLength: 500,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Submit',
                loading: submitting,
                onPressed: (stars == 0 || submitting) ? null : onSubmit,
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: submitting ? null : onSkip,
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: AppMotion.base)
        .moveY(
          begin: 10,
          end: 0,
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
        );
  }
}

class _ThanksForFeedback extends StatelessWidget {
  const _ThanksForFeedback();
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('thanks-for-feedback'),
    children: [
      const Icon(
        Icons.check_circle_rounded,
        size: 56,
        color: AppColors.success,
      ),
      const SizedBox(height: 14),
      Text(
        'Thanks for your feedback!',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(color: OrderingColors.text(context)),
      ),
    ],
  ).animate().fadeIn(duration: AppMotion.base);
}

class _EnjoyYourMealMessage extends StatelessWidget {
  const _EnjoyYourMealMessage();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('enjoy-your-meal'),
      children: [
        const RouteLineReveal(size: 96),
        const SizedBox(height: 18),
        Text(
              'Enjoy your meal!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(color: OrderingColors.text(context)),
            )
            .animate()
            .fadeIn(duration: AppMotion.slow, curve: AppMotion.emphasized)
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              duration: AppMotion.slow,
              curve: AppMotion.bouncy,
            ),
        const SizedBox(height: 6),
        Text(
          'We look forward to your next order.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.mutedText),
        ).animate(delay: 150.ms).fadeIn(duration: AppMotion.slow),
      ],
    );
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
    // No fixed height — a Column + Spacer forcing content into a hardcoded
    // box is exactly the overflow anti-pattern audited out elsewhere this
    // task (Campus Pick card, vendor cards): at larger Dynamic Type scale
    // the name/rating text needs more room than a fixed height allows.
    // Sizing to content (min height, generous padding) instead means
    // there's nothing to overflow against.
    constraints: const BoxConstraints(minHeight: 184),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.primaryMaroonDeep,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: 28),
        Text(
          eatery.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Colors.white),
        ),
        // No vendor-level rating/prep-time estimate exists on the backend
        // yet (Eatery.rating/prepTimeMinutes are null for every real
        // vendor) — this row simply doesn't render rather than showing a
        // fabricated number. Falls back to the vendor's own blurb
        // (description or category) so the hero isn't left empty here.
        if (eatery.rating != null || eatery.prepTimeMinutes != null)
          Row(
            children: [
              if (eatery.rating != null) ...[
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
              ],
              if (eatery.prepTimeMinutes != null)
                Flexible(
                  child: Text(
                    '${eatery.prepTimeMinutes} min prep',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: Colors.white.withValues(alpha: .72)),
                  ),
                ),
            ],
          )
        else if (eatery.blurb != null)
          Text(
            eatery.blurb!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: Colors.white.withValues(alpha: .72)),
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
            MenuImagePlaceholder(seed: item.name, imageUrl: item.imageUrl),
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
                      Flexible(
                        child: item.isAvailable && isEateryOpen
                            ? QuantityStepper(
                                quantity: quantity,
                                onAdd: onAdd,
                                onRemove: onRemove,
                                compact: true,
                              )
                            : Text(
                                isEateryOpen ? 'Unavailable' : 'Closed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
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
const _kNoteMaxLength = 280;

class _ItemOptionsSheet extends StatefulWidget {
  const _ItemOptionsSheet({
    required this.item,
    required this.initialQuantity,
    this.initialNote,
    required this.onConfirm,
  });
  final MenuItem item;
  final int initialQuantity;
  final String? initialNote;
  final void Function(int quantity, String? note) onConfirm;

  @override
  State<_ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<_ItemOptionsSheet> {
  late int _quantity = widget.initialQuantity;
  late final _noteController = TextEditingController(
    text: widget.initialNote ?? '',
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

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
          // The notes field (Task 14) pushed this sheet's content past a
          // phone's available height at larger Dynamic Type scales — a
          // fixed, non-scrolling Column had nowhere for the overflow to
          // go. SingleChildScrollView lets the sheet's own max-height
          // constraint (from showModalBottomSheet) scroll its content
          // instead of overflowing it.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MenuImagePlaceholder(
                      seed: widget.item.name,
                      size: 68,
                      imageUrl: widget.item.imageUrl,
                    ),
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
                                ?.copyWith(
                                  color: OrderingColors.muted(context),
                                ),
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
                Text(
                  'Add a note',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: OrderingColors.text(context)),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _noteController,
                  hintText: 'e.g. no onions, extra spicy',
                  maxLength: _kNoteMaxLength,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  switchInCurve: AppMotion.emphasized,
                  switchOutCurve: AppMotion.emphasized,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: PrimaryButton(
                    key: ValueKey(total),
                    label: 'Add to Basket — ${naira(total)}',
                    onPressed: () {
                      final note = _noteController.text.trim();
                      widget.onConfirm(_quantity, note.isEmpty ? null : note);
                    },
                  ),
                ),
              ],
            ),
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
    this.note,
    required this.onAdd,
    required this.onRemove,
    required this.onEditNote,
  });
  final MenuItem item;
  final int quantity;
  final String? note;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onEditNote;
  @override
  Widget build(BuildContext context) {
    final hasNote = note != null && note!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: OrderingColors.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OrderingColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MenuImagePlaceholder(
                seed: item.name,
                size: 62,
                imageUrl: item.imageUrl,
              ),
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
          const SizedBox(height: 8),
          InkWell(
            onTap: onEditNote,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    hasNote
                        ? Icons.edit_note_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: hasNote
                        ? AppColors.gold
                        : OrderingColors.muted(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasNote ? '"${note!.trim()}"' : 'Add a note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: hasNote
                            ? AppColors.gold
                            : OrderingColors.muted(context),
                        fontStyle: hasNote
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

/// Task 10 performance audit: shape-matched skeleton for the menu screen's
/// two loading states (eatery details, then its menu) — a hero-image-sized
/// block and a few item-row placeholders read as "this is loading" far
/// better than a bare center-screen spinner.
class _MenuScreenSkeleton extends StatelessWidget {
  const _MenuScreenSkeleton();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 160, borderRadius: 20),
          const SizedBox(height: 16),
          const SkeletonBox(width: 180, height: 20),
          const SizedBox(height: 10),
          const SkeletonBox(width: 120, height: 14),
          const SizedBox(height: 24),
          const SkeletonList(count: 5),
        ],
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
