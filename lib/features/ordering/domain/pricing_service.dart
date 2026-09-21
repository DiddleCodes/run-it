import 'ordering_models.dart';

class PriceBreakdown {
  const PriceBreakdown({
    required this.subtotal,
    required this.packagingTotal,
    required this.deliveryFee,
    required this.serviceFee,
  });

  final int subtotal;
  final int packagingTotal;
  final int deliveryFee;
  final int serviceFee;
  int get total => subtotal + packagingTotal + deliveryFee + serviceFee;
}

class PricingService {
  const PricingService._();

  /// Task 45: a single flat delivery fee — no more campus-zone tiers.
  static const int flatDeliveryFee = 500;

  /// Task 47: Pay on Delivery is unavailable above this order value
  /// (naira), regardless of the restaurant's own opt-in — mirrors the
  /// backend's own hard `PAY_ON_DELIVERY_MAX_TOTAL_KOBO` business rule.
  static const int payOnDeliveryMaxTotal = 10000;

  /// Task 66: Group Ordering — mirrors the backend's own hard
  /// STANDARD_MAIN_MEAL_CAP/GROUP_MAIN_MEAL_CAP/GROUP_ORDER_SURCHARGE_KOBO
  /// constants (order-escrow.service.ts). This client-side copy is honest
  /// UX only — hold() re-derives and re-enforces all three from the
  /// database regardless of what's sent.
  static const int standardMainMealCap = 2;
  static const int groupMainMealCap = 4;
  static const int groupOrderSurcharge = 150;

  /// How many main-meal units (by quantity, real `MenuItem.isMainMeal`
  /// only) are currently in the basket — what the cap above is checked
  /// against.
  static int mainMealCount({
    required Basket basket,
    required Iterable<MenuItem> menuItems,
  }) {
    final byId = {for (final item in menuItems) item.id: item};
    var count = 0;
    for (final line in basket.items) {
      final item = byId[line.menuItemId];
      if (item != null && item.isMainMeal) count += line.quantity;
    }
    return count;
  }

  /// One source of truth for all money shown in basket and checkout.
  static PriceBreakdown calculate({
    required Basket basket,
    required Iterable<MenuItem> menuItems,
    // Task 66: raises the delivery fee by [groupOrderSurcharge] — never a
    // replacement for the flat fee above, purely additive.
    bool isGroupOrder = false,
  }) {
    final byId = {for (final item in menuItems) item.id: item};
    var subtotal = 0;
    var packaging = 0;
    for (final line in basket.items) {
      final item = byId[line.menuItemId];
      if (item == null) continue;
      subtotal += item.price * line.quantity;
      packaging += item.packagingCost * line.quantity;
    }
    // Service remains deliberately small and transparent, charged only once.
    final service = subtotal == 0 ? 0 : 150;
    final delivery = basket.isEmpty
        ? 0
        : flatDeliveryFee + (isGroupOrder ? groupOrderSurcharge : 0);
    return PriceBreakdown(
      subtotal: subtotal,
      packagingTotal: packaging,
      deliveryFee: delivery,
      serviceFee: service,
    );
  }
}
