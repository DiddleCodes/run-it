/// One line item on a real, backend-persisted order — shared by both the
/// history list and the detail fetch (Task 46), same convention as the
/// vendor side's `RestaurantOrderItem`.
class OrderHistoryItemLine {
  const OrderHistoryItemLine({
    required this.name,
    required this.quantity,
    required this.priceKobo,
  });
  final String name;
  final int quantity;
  final int priceKobo;

  factory OrderHistoryItemLine.fromJson(Map<String, dynamic> json) =>
      OrderHistoryItemLine(
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        priceKobo: json['priceKobo'] as int,
      );
}

/// A real, backend-persisted order — Task 46 replaces the old hardcoded
/// "Past" fake entries and the in-memory-only Cancelled tab with this,
/// fetched from `GET /orders` (list) and `GET /orders/:orderId` (detail).
/// One shape serves both endpoints; each just populates the fields it has.
class OrderHistoryEntry {
  const OrderHistoryEntry({
    required this.id,
    required this.status,
    required this.vendorName,
    required this.totalKobo,
    required this.note,
    required this.deliveryLocationLabel,
    required this.items,
    required this.createdAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.cancelledAt,
  });

  final String id;
  // Raw backend OrderStatus string — 'placed' | 'preparing' |
  // 'ready_for_pickup' | 'picked_up' | 'delivered' | 'cancelled'. My
  // Orders only ever buckets 'delivered' into Past and 'cancelled' into
  // Cancelled; any other value simply won't match either tab (the Active
  // tab covers in-flight orders through its own separate live session).
  final String status;
  final String vendorName;
  final int totalKobo;
  final String? note;
  final String? deliveryLocationLabel;
  final List<OrderHistoryItemLine> items;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;

  String get itemsSummary =>
      items.map((line) => '${line.quantity}× ${line.name}').join(', ');

  static DateTime? _parseNullable(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  factory OrderHistoryEntry.fromJson(Map<String, dynamic> json) =>
      OrderHistoryEntry(
        id: json['id'] as String,
        status: json['status'] as String,
        vendorName: json['vendorName'] as String,
        totalKobo: json['totalAmount'] as int,
        note: json['note'] as String?,
        deliveryLocationLabel: json['deliveryLocationLabel'] as String?,
        items: (json['items'] as List)
            .map((e) => OrderHistoryItemLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        acceptedAt: _parseNullable(json['acceptedAt']),
        pickedUpAt: _parseNullable(json['pickedUpAt']),
        deliveredAt: _parseNullable(json['deliveredAt']),
        cancelledAt: _parseNullable(json['cancelledAt']),
      );
}

class OrderHistoryPage {
  const OrderHistoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
  final List<OrderHistoryEntry> items;
  final int total;
  final int page;
  final int limit;

  factory OrderHistoryPage.fromJson(Map<String, dynamic> json) =>
      OrderHistoryPage(
        items: (json['items'] as List)
            .map((e) => OrderHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        limit: json['limit'] as int,
      );
}
