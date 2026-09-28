import 'ordering_models.dart';

/// Task 70: the backend's live checkout pricing (`GET /pricing`) —
/// OrderEscrowService.hold rejects any fee that doesn't match, so the app
/// prices with the server's own numbers rather than a stale copy. [defaults]
/// mirrors the backend's own defaults, used until (or if) that fetch lands.
class PricingConfig {
  const PricingConfig({this.serviceFeeRate = 0.05, this.deliveryFee = 500});

  factory PricingConfig.fromJson(Map<String, dynamic> json) => PricingConfig(
    serviceFeeRate: (json['serviceFeeRate'] as num).toDouble(),
    deliveryFee: (json['deliveryFeeKobo'] as int) ~/ 100,
  );

  static const defaults = PricingConfig();

  /// 0-1, applied to the food subtotal only.
  final double serviceFeeRate;

  /// Naira — the flat base delivery fee (a group order adds its surcharge).
  final int deliveryFee;
}

class PriceBreakdown {
  const PriceBreakdown({
    required this.subtotal,
    required this.packagingTotal,
    required this.deliveryFee,
    required this.serviceFee,
    this.serviceFeeRate = 0,
  });

  final int subtotal;
  final int packagingTotal;
  final int deliveryFee;
  final int serviceFee;

  /// Task 70: what [serviceFee] is a share of the food subtotal — shown as
  /// "Service fee (5%)".
  final double serviceFeeRate;

  String get serviceFeePercentLabel {
    final percent = serviceFeeRate * 100;
    return percent == percent.roundToDouble() ? '${percent.round()}%' : '${percent.toStringAsFixed(1)}%';
  }

  int get total => subtotal + packagingTotal + deliveryFee + serviceFee;
}

class PricingService {
  const PricingService._();

  /// Task 70: [rate] of the food subtotal (naira), to the nearest whole
  /// naira, half up. Integer maths with the rate as whole basis points —
  /// the exact formula the backend's computeServiceFeeKobo uses, so the fee
  /// shown here always equals the fee charged.
  static int serviceFeeFor(int subtotal, double rate) {
    final basisPoints = (rate * 10000).round();
    return (subtotal * 100 * basisPoints + 500000) ~/ 1000000;
  }

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
    // replacement for the flat fee, purely additive.
    bool isGroupOrder = false,
    PricingConfig config = PricingConfig.defaults,
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
    // Task 70: a percentage of the food subtotal only — never packaging or
    // delivery.
    final service = serviceFeeFor(subtotal, config.serviceFeeRate);
    final delivery = basket.isEmpty
        ? 0
        : config.deliveryFee + (isGroupOrder ? groupOrderSurcharge : 0);
    return PriceBreakdown(
      subtotal: subtotal,
      packagingTotal: packaging,
      deliveryFee: delivery,
      serviceFee: service,
      serviceFeeRate: config.serviceFeeRate,
    );
  }
}
