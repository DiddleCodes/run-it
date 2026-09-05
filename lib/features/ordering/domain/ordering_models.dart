enum PaymentMethod { wallet, card }

/// The student-side delivery lifecycle. Kept separate from the runner's
/// `DeliveryStage` since the student sees one extra stage before a runner
/// has even been matched. `placed -> runnerAssigned` is still simulated
/// locally (no real runner-matching backend exists yet). `pickedUp` and
/// `delivered` (Task 11) are reached only via
/// `OrderTrackingController.markPickedUp`/`markDelivered`, called only
/// after the runner's real `verify-pickup`/`verify-delivery` backend call
/// has actually succeeded — never by a timer. `confirmed` is reached only
/// by an explicit student tap on OrderTrackingScreen (Task 10) — since it's
/// the trigger point for the (future) rider-rating prompt and must reflect
/// a real acknowledgement, not an assumption.
enum OrderStage { placed, runnerAssigned, pickedUp, delivered, confirmed }

class Eatery {
  const Eatery({
    required this.id,
    required this.name,
    this.bannerUrl,
    this.blurb,
    this.rating,
    this.prepTimeMinutes,
    this.isOpen = true,
  });

  final String id;
  final String name;
  // The vendor's logoUrl, if one was uploaded — nullable, unlike the old
  // mock data's always-present (if often empty) string.
  final String? bannerUrl;
  // Real vendor description if given, else its category — shown as the
  // one-line subtitle under the vendor's name. Never a fabricated blurb.
  final String? blurb;
  // No backend concept of a vendor-level star rating exists yet (only
  // per-runner ratings, Task 14 Part D) — null everywhere real data is
  // used; UI hides the rating row rather than showing a fake number.
  final double? rating;
  // Same story: no backend prep-time estimate exists yet.
  final int? prepTimeMinutes;
  // The backend has no open/closed-hours concept for a vendor yet — every
  // vendor `GET /vendors` returns is, by definition, `active`, so this is
  // simply always true for real data. Item-level `isAvailable` (real) is
  // what actually gates ordering, not this.
  final bool isOpen;
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
  const BasketItem({required this.menuItemId, required this.quantity});
  final String menuItemId;
  final int quantity;

  BasketItem copyWith({int? quantity}) =>
      BasketItem(menuItemId: menuItemId, quantity: quantity ?? this.quantity);
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
  const DeliveryLocation({required this.label});
  final String label;
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
