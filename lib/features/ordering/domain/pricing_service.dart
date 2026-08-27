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

  /// One source of truth for all money shown in basket and checkout.
  static PriceBreakdown calculate({
    required Basket basket,
    required Iterable<MenuItem> menuItems,
    required DeliveryFeeZone zone,
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
    return PriceBreakdown(
      subtotal: subtotal,
      packagingTotal: packaging,
      deliveryFee: basket.isEmpty ? 0 : zone.fee,
      serviceFee: service,
    );
  }
}
