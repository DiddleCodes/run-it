enum PaymentMethod { wallet, card }

/// The student-side delivery lifecycle. Kept separate from the runner's
/// `DeliveryStage` since the student sees one extra stage before a runner
/// has even been matched.
enum OrderStage { placed, runnerAssigned, pickedUp, delivered }

enum DeliveryFeeZone {
  north('North Campus', 450),
  central('Central Campus', 350),
  south('South Campus', 500);

  const DeliveryFeeZone(this.label, this.fee);
  final String label;
  final int fee;
}

class Eatery {
  const Eatery({
    required this.id,
    required this.name,
    required this.bannerUrl,
    required this.rating,
    required this.prepTimeMinutes,
    required this.isOpen,
    required this.campusId,
  });

  final String id;
  final String name;
  final String bannerUrl;
  final double rating;
  final int prepTimeMinutes;
  final bool isOpen;
  final String campusId;
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.eateryId,
    required this.name,
    required this.description,
    required this.price,
    required this.packagingCost,
    required this.category,
    required this.imageUrl,
    required this.isAvailable,
  });

  final String id;
  final String eateryId;
  final String name;
  final String description;
  final int price;
  final int packagingCost;
  final String category;
  final String imageUrl;
  final bool isAvailable;
}

class BasketItem {
  const BasketItem({
    required this.menuItemId,
    required this.quantity,
    this.note,
  });
  final String menuItemId;
  final int quantity;
  final String? note;

  BasketItem copyWith({int? quantity, String? note}) => BasketItem(
    menuItemId: menuItemId,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
  );
}

class Basket {
  const Basket({this.items = const [], this.eateryId});
  final List<BasketItem> items;
  final String? eateryId;
  bool get isEmpty => items.isEmpty;

  Basket copyWith({
    List<BasketItem>? items,
    String? eateryId,
    bool clearEatery = false,
  }) => Basket(
    items: items ?? this.items,
    eateryId: clearEatery ? null : eateryId ?? this.eateryId,
  );
}

class DeliveryLocation {
  const DeliveryLocation({required this.label, required this.zone});
  final String label;
  final DeliveryFeeZone zone;
}

class Order {
  const Order({
    required this.id,
    required this.basketSnapshot,
    required this.deliveryLocation,
    required this.paymentMethod,
    required this.subtotal,
    required this.packagingTotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.total,
    required this.status,
  });

  final String id;
  final Basket basketSnapshot;
  final DeliveryLocation deliveryLocation;
  final PaymentMethod paymentMethod;
  final int subtotal;
  final int packagingTotal;
  final int deliveryFee;
  final int serviceFee;
  final int total;
  final String status;
}
