/// Task 12's Restaurant Dashboard order lifecycle — mirrors the backend's
/// `OrderStatus` enum exactly (see `schema.prisma`'s own doc comment there
/// for the full placed → preparing → ready_for_pickup → picked_up →
/// delivered / cancelled shape). `preparing`/`ready_for_pickup` are the
/// only two transitions this app ever pushes forward itself — everything
/// else is runner/escrow-driven (Task 11).
enum RestaurantOrderStatus { placed, preparing, readyForPickup, pickedUp, delivered, cancelled }

extension RestaurantOrderStatusJson on RestaurantOrderStatus {
  static RestaurantOrderStatus fromJson(String value) => switch (value) {
    'placed' => RestaurantOrderStatus.placed,
    'preparing' => RestaurantOrderStatus.preparing,
    'ready_for_pickup' => RestaurantOrderStatus.readyForPickup,
    'picked_up' => RestaurantOrderStatus.pickedUp,
    'delivered' => RestaurantOrderStatus.delivered,
    'cancelled' => RestaurantOrderStatus.cancelled,
    _ => throw ArgumentError('Unknown order status: $value'),
  };

  String get toJson => switch (this) {
    RestaurantOrderStatus.placed => 'placed',
    RestaurantOrderStatus.preparing => 'preparing',
    RestaurantOrderStatus.readyForPickup => 'ready_for_pickup',
    RestaurantOrderStatus.pickedUp => 'picked_up',
    RestaurantOrderStatus.delivered => 'delivered',
    RestaurantOrderStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    RestaurantOrderStatus.placed => 'New',
    RestaurantOrderStatus.preparing => 'Preparing',
    RestaurantOrderStatus.readyForPickup => 'Ready for pickup',
    RestaurantOrderStatus.pickedUp => 'Out for delivery',
    RestaurantOrderStatus.delivered => 'Delivered',
    RestaurantOrderStatus.cancelled => 'Cancelled',
  };

  /// The vendor's own next forward action from this status, if any — `null`
  /// once it's out of the kitchen's hands (picked up onward).
  RestaurantOrderStatus? get nextVendorAction => switch (this) {
    RestaurantOrderStatus.placed => RestaurantOrderStatus.preparing,
    RestaurantOrderStatus.preparing => RestaurantOrderStatus.readyForPickup,
    _ => null,
  };

  String get nextActionLabel => switch (nextVendorAction) {
    RestaurantOrderStatus.preparing => 'Start Preparing',
    RestaurantOrderStatus.readyForPickup => 'Mark Ready for Pickup',
    _ => '',
  };
}

class RestaurantOrderItem {
  const RestaurantOrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.priceKobo,
  });
  final String id;
  final String name;
  final int quantity;
  final int priceKobo;

  factory RestaurantOrderItem.fromJson(Map<String, dynamic> json) => RestaurantOrderItem(
    id: json['id'] as String,
    name: json['nameSnapshot'] as String,
    quantity: json['quantity'] as int,
    priceKobo: json['priceSnapshot'] as int,
  );
}

class RestaurantOrder {
  const RestaurantOrder({
    required this.id,
    required this.status,
    required this.pickupCode,
    required this.totalKobo,
    required this.deliveryLocationLabel,
    this.note,
    required this.createdAt,
    required this.items,
  });
  final String id;
  final RestaurantOrderStatus status;
  final String pickupCode;
  final int totalKobo;
  final String? deliveryLocationLabel;
  // Task 45: replaces the old per-item RestaurantOrderItem.notes — one note
  // for the whole order.
  final String? note;
  final DateTime createdAt;
  final List<RestaurantOrderItem> items;

  factory RestaurantOrder.fromJson(Map<String, dynamic> json) => RestaurantOrder(
    id: json['id'] as String,
    status: RestaurantOrderStatusJson.fromJson(json['status'] as String),
    pickupCode: json['pickupCode'] as String,
    totalKobo: json['totalAmount'] as int,
    deliveryLocationLabel: json['deliveryLocationLabel'] as String?,
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    items: (json['items'] as List)
        .map((e) => RestaurantOrderItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class VendorOrdersPage {
  const VendorOrdersPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
  final List<RestaurantOrder> items;
  final int total;
  final int page;
  final int limit;

  factory VendorOrdersPage.fromJson(Map<String, dynamic> json) => VendorOrdersPage(
    items: (json['items'] as List).map((e) => RestaurantOrder.fromJson(e as Map<String, dynamic>)).toList(),
    total: json['total'] as int,
    page: json['page'] as int,
    limit: json['limit'] as int,
  );
}

/// The vendor's own business profile, as the backend actually has it —
/// distinct from `VendorApplication` (Task 7's still-local wizard state):
/// this is what `GET/POST /vendors/me` reflects, once real. Also doubles as
/// the shape of one entry in the public `GET /vendors` list and the
/// `vendor` half of `GET /vendors/:id/menu` (Task 14) — the same fields,
/// just reused for a student's read-only view instead of the owning
/// vendor's own.
class MyVendorProfile {
  const MyVendorProfile({
    required this.id,
    required this.businessName,
    required this.category,
    this.description,
    this.logoUrl,
    this.userId,
  });
  final String id;
  final String businessName;
  final String category;
  final String? description;
  final String? logoUrl;

  // Only ever populated from `GET /vendors/:id/menu` (whose `vendor` object
  // is an unfiltered Prisma row, `userId` included) — never from the public
  // `GET /vendors` list, which deliberately selects a narrower public shape
  // without it. Task 14's checkout flow needs this to hold the escrow for
  // the REAL vendor the student actually ordered from, rather than the
  // fixed demo restaurant identity `DemoIdentityService` stands in for
  // everywhere a real one isn't known yet.
  final String? userId;

  factory MyVendorProfile.fromJson(Map<String, dynamic> json) => MyVendorProfile(
    id: json['id'] as String,
    businessName: json['businessName'] as String,
    category: json['category'] as String,
    description: json['description'] as String?,
    logoUrl: json['logoUrl'] as String?,
    userId: json['userId'] as String?,
  );
}

/// One entry from the backend's controlled vendor-category vocabulary
/// (`GET /vendors/categories`) — the fix for category chips fragmenting
/// into near-duplicates ("Nigerian Food"/"nigerian food"/"Naija Dishes")
/// as more vendors sign up. [slug] is a stable key for widgets/lists;
/// [label] is what gets shown and what `upsertMyVendor`'s `category`
/// argument expects (the backend always persists/matches on the label).
class VendorCategoryOption {
  const VendorCategoryOption({required this.slug, required this.label});
  final String slug;
  final String label;

  factory VendorCategoryOption.fromJson(Map<String, dynamic> json) =>
      VendorCategoryOption(slug: json['slug'] as String, label: json['label'] as String);
}

class VendorsPage {
  const VendorsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
  final List<MyVendorProfile> items;
  final int total;
  final int page;
  final int limit;

  factory VendorsPage.fromJson(Map<String, dynamic> json) => VendorsPage(
    items: (json['items'] as List).map((e) => MyVendorProfile.fromJson(e as Map<String, dynamic>)).toList(),
    total: json['total'] as int,
    page: json['page'] as int,
    limit: json['limit'] as int,
  );
}

/// The combined response `GET /vendors/:id/menu` actually returns — a
/// vendor row plus its menu, in one call. [VendorsRepository.fetchMenu]
/// serves both the Restaurant Dashboard (which only needed the items) and
/// Task 14's student-side browsing (which also needs the vendor's own
/// name/category for the eatery hero) from this single shape.
class VendorWithMenu {
  const VendorWithMenu({required this.vendor, required this.items});
  final MyVendorProfile vendor;
  final List<VendorMenuItem> items;

  factory VendorWithMenu.fromJson(Map<String, dynamic> json) => VendorWithMenu(
    vendor: MyVendorProfile.fromJson(json['vendor'] as Map<String, dynamic>),
    items: (json['items'] as List).map((e) => VendorMenuItem.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class VendorMenuItem {
  const VendorMenuItem({
    required this.id,
    required this.name,
    this.description,
    required this.priceKobo,
    this.photoUrl,
    required this.category,
    required this.isAvailable,
  });
  final String id;
  final String name;
  final String? description;
  final int priceKobo;
  final String? photoUrl;
  final String category;
  final bool isAvailable;

  factory VendorMenuItem.fromJson(Map<String, dynamic> json) => VendorMenuItem(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    priceKobo: json['price'] as int,
    photoUrl: json['photoUrl'] as String?,
    category: json['category'] as String,
    isAvailable: json['isAvailable'] as bool,
  );
}

class VendorMetricsItem {
  const VendorMetricsItem({required this.name, required this.count, required this.revenueKobo});
  final String name;
  final int count;
  final int revenueKobo;

  factory VendorMetricsItem.fromJson(Map<String, dynamic> json) => VendorMetricsItem(
    name: json['name'] as String,
    count: json['count'] as int,
    revenueKobo: json['revenue'] as int,
  );
}

class VendorMetrics {
  const VendorMetrics({
    required this.from,
    required this.to,
    required this.totalOrders,
    required this.totalRevenueKobo,
    required this.mostOrderedItems,
  });
  final DateTime from;
  final DateTime to;
  final int totalOrders;
  final int totalRevenueKobo;
  final List<VendorMetricsItem> mostOrderedItems;

  factory VendorMetrics.fromJson(Map<String, dynamic> json) => VendorMetrics(
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    totalOrders: json['totalOrders'] as int,
    totalRevenueKobo: json['totalRevenue'] as int,
    mostOrderedItems: (json['mostOrderedItems'] as List)
        .map((e) => VendorMetricsItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
