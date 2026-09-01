import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_exception.dart';

final escrowRepositoryProvider = Provider<EscrowRepository>(
  (ref) => const EscrowRepository(),
);

/// How a release actually went — the backend's `/release` either fully
/// succeeds (both transfer legs initiated) or throws a 502 the instant
/// either leg's Paystack call fails to *initiate* (see
/// `OrderEscrowService.release`'s doc comment backend-side); there is no
/// partial-success 2xx response shape to parse; the distinction the caller
/// cares about is "succeeded outright" vs. "at least one leg needs a retry."
enum EscrowReleaseOutcome { released, partiallyFailed }

/// Mirrors the backend's `OrderItemInputDto` (Task 9/14) — one basket line
/// as sent at hold time, [notes] included so a student's per-item
/// customization request actually lands on `OrderItem.notes` for the
/// restaurant to see, instead of being computed client-side and thrown away.
class EscrowOrderItem {
  const EscrowOrderItem({
    this.menuItemId,
    required this.name,
    required this.priceKobo,
    required this.quantity,
    this.notes,
  });
  final String? menuItemId;
  final String name;
  final int priceKobo;
  final int quantity;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'menuItemId': ?menuItemId,
    'name': name,
    'priceKobo': priceKobo,
    'quantity': quantity,
    'notes': ?notes,
  };
}

/// Real backend calls against Task 8b's `/orders/:orderId/escrow` routes —
/// shared by the ordering feature (hold at checkout, refund on cancel) and
/// the runner feature (release on delivery-scan), since escrow itself isn't
/// specific to either side of an order.
class EscrowRepository {
  const EscrowRepository({this.client = const ApiClient()});

  final ApiClient client;

  /// Amounts are already in kobo — callers hold the naira/kobo boundary
  /// (mirrors `WalletRepository`), since this repository's shape mirrors
  /// the backend's `HoldEscrowDto` directly.
  Future<void> hold({
    required String orderId,
    required String studentUserId,
    required String restaurantUserId,
    required String runnerUserId,
    required int grossAmountKobo,
    required String token,
    // Task 14: the real vendor row a student actually ordered from
    // (`MyVendorProfile.id`), and the basket's own line items — both
    // optional so any already-shipped caller that omits them keeps working
    // exactly as before (see `HoldEscrowDto.vendorId`'s own doc comment
    // backend-side for the same fallback).
    String? vendorId,
    List<EscrowOrderItem>? items,
    // Task 15: a separate line item from grossAmountKobo (now the food
    // subtotal only), never subject to restaurant commission. Optional so
    // an old caller that omits it still works — the backend falls back to
    // its own configured default — but every real checkout should send the
    // zone-based fee it already displays, so the app is never charged more
    // than what the checkout screen showed.
    int? deliveryFeeKobo,
  }) async {
    await client.post(
      '/orders/$orderId/escrow/hold',
      token: token,
      body: {
        'studentUserId': studentUserId,
        'restaurantUserId': restaurantUserId,
        'runnerUserId': runnerUserId,
        'grossAmountKobo': grossAmountKobo,
        'vendorId': ?vendorId,
        'items': ?items?.map((item) => item.toJson()).toList(),
        'deliveryFeeKobo': ?deliveryFeeKobo,
      },
    );
  }

  /// [token] must belong to the runner assigned to this order's escrow (or
  /// be an internal/admin token) — see `EscrowPartyGuard` backend-side.
  Future<EscrowReleaseOutcome> release({
    required String orderId,
    required String token,
  }) async {
    try {
      await client.post('/orders/$orderId/escrow/release', token: token);
      return EscrowReleaseOutcome.released;
    } on ApiException catch (e) {
      // BadGatewayException from the backend — one or more transfer legs
      // failed to *initiate*. The order was still genuinely delivered; this
      // is a payout-processing state, not a delivery failure, so callers
      // should say so honestly rather than implying both sides were
      // instantly paid.
      if (e.statusCode == 502) return EscrowReleaseOutcome.partiallyFailed;
      rethrow;
    }
  }

  /// [token] must belong to the student who placed this order (or be an
  /// internal/admin token) — see `EscrowPartyGuard` backend-side.
  Future<void> refund({required String orderId, required String token}) async {
    await client.post('/orders/$orderId/escrow/refund', token: token);
  }
}
