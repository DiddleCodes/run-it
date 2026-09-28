import 'package:run_it/features/ordering/domain/order_history_models.dart';

/// Task 73: a real-shaped `GET /orders/:orderId` snapshot — what
/// OrderTrackingController.applyServerOrder consumes — so tests move the
/// student tracker exactly the way the real backend does, instead of
/// through a timer or a test-only shortcut.
///
/// Status strings are the backend's own OrderStatus values; [runnerName]
/// set means a real runner has claimed the order.
OrderHistoryEntry serverOrder(
  String orderId,
  String status, {
  String? runnerName,
  String vendorName = 'Tantalizers',
  int totalKobo = 300000,
}) => OrderHistoryEntry(
  id: orderId,
  status: status,
  vendorName: vendorName,
  totalKobo: totalKobo,
  note: null,
  deliveryLocationLabel: 'Hostel B',
  items: const [OrderHistoryItemLine(name: 'Jollof Rice', quantity: 1, priceKobo: 300000)],
  createdAt: DateTime(2026, 9, 28, 12),
  paymentMethod: 'wallet',
  runnerName: runnerName,
);
