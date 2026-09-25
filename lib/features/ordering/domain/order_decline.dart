/// Task 61: the fixed set a restaurant picks from when declining a
/// `placed` order — mirrors the backend's `OrderDeclineReason` enum.
/// Shared by the restaurant's Decline sheet and every student-facing view
/// of a declined order, so both sides always word a reason identically.
enum OrderDeclineReason { outOfStock, kitchenClosed, tooBusy, other }

extension OrderDeclineReasonJson on OrderDeclineReason {
  /// `null` for anything unrecognised (e.g. a newer backend value) — a
  /// declined order still renders, just without a specific reason label.
  static OrderDeclineReason? tryParse(String? value) => switch (value) {
    'out_of_stock' => OrderDeclineReason.outOfStock,
    'kitchen_closed' => OrderDeclineReason.kitchenClosed,
    'too_busy' => OrderDeclineReason.tooBusy,
    'other' => OrderDeclineReason.other,
    _ => null,
  };

  String get toJson => switch (this) {
    OrderDeclineReason.outOfStock => 'out_of_stock',
    OrderDeclineReason.kitchenClosed => 'kitchen_closed',
    OrderDeclineReason.tooBusy => 'too_busy',
    OrderDeclineReason.other => 'other',
  };

  String get label => switch (this) {
    OrderDeclineReason.outOfStock => 'Out of stock',
    OrderDeclineReason.kitchenClosed => 'Kitchen closed',
    OrderDeclineReason.tooBusy => 'Too busy',
    OrderDeclineReason.other => 'Other',
  };
}

/// The one line shown for a declined order: the restaurant's own free text
/// for [OrderDeclineReason.other], the fixed label otherwise.
String? declineReasonText(OrderDeclineReason? reason, String? note) {
  if (reason == null) return null;
  if (reason == OrderDeclineReason.other) {
    final trimmed = note?.trim();
    return (trimmed == null || trimmed.isEmpty) ? reason.label : trimmed;
  }
  return reason.label;
}
