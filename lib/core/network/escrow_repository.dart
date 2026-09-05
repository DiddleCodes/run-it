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

/// Outcome of a claim attempt — [alreadyClaimed] is the backend's
/// `409 ORDER_ALREADY_CLAIMED`, an expected, normal outcome of the
/// broadcast model (another runner won the race), never a generic error.
enum ClaimResult { claimed, alreadyClaimed }

/// Mirrors the backend's `OrderItemInputDto` (Task 9/14) — one basket line
/// as sent at hold time. Task 45: no longer carries a per-item note (that
/// moved to `EscrowRepository.hold`'s single order-level `note` param).
class EscrowOrderItem {
  const EscrowOrderItem({
    this.menuItemId,
    required this.name,
    required this.priceKobo,
    required this.quantity,
  });
  final String? menuItemId;
  final String name;
  final int priceKobo;
  final int quantity;

  Map<String, dynamic> toJson() => {
    'menuItemId': ?menuItemId,
    'name': name,
    'priceKobo': priceKobo,
    'quantity': quantity,
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
    // Task 21a/21b: nullable — a real order now starts with no runner
    // attached and is broadcast to the runner pool once the restaurant
    // accepts it (see OrderEscrowService.claim's own doc comment
    // backend-side). Null is the normal case for every real checkout now;
    // a caller only ever passes one for something pre-assigned outside the
    // broadcast model.
    String? runnerUserId,
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
    // its own configured default. Task 45: now a single flat fee (no more
    // zone tiers) — every real checkout sends it explicitly.
    int? deliveryFeeKobo,
    // Task 45: also a separate line item from grossAmountKobo, same
    // reasoning as deliveryFeeKobo above — never commissionable, flows
    // entirely to platform revenue.
    int? serviceFeeKobo,
    // Task 21b: forwarded to `Order.deliveryLocationLabel` — was collected
    // at checkout but never actually sent, so every real order's dropoff
    // was silently null. Optional so an old caller that omits it still
    // works exactly as before.
    String? deliveryLocationLabel,
    // Task 45: replaces the old per-item notes — one note for the whole
    // order.
    String? note,
  }) async {
    await client.post(
      '/orders/$orderId/escrow/hold',
      token: token,
      body: {
        'studentUserId': studentUserId,
        'restaurantUserId': restaurantUserId,
        'runnerUserId': ?runnerUserId,
        'grossAmountKobo': grossAmountKobo,
        'vendorId': ?vendorId,
        'items': ?items?.map((item) => item.toJson()).toList(),
        'deliveryFeeKobo': ?deliveryFeeKobo,
        'serviceFeeKobo': ?serviceFeeKobo,
        'deliveryLocationLabel': ?deliveryLocationLabel,
        'note': ?note,
      },
    );
  }

  /// Task 21a/21b: first-to-claim-wins against a broadcast job — [token]
  /// belongs to whichever runner is attempting the claim, no prior
  /// assignment required (that's exactly what a successful claim creates).
  /// [ClaimResult.alreadyClaimed] is the backend's `409
  /// ORDER_ALREADY_CLAIMED` specifically — every other non-2xx status
  /// rethrows as [ApiException], same as every other call here.
  Future<ClaimResult> claim({required String orderId, required String token}) async {
    try {
      await client.post('/orders/$orderId/escrow/claim', token: token);
      return ClaimResult.claimed;
    } on ApiException catch (e) {
      if (e.statusCode == 409) return ClaimResult.alreadyClaimed;
      rethrow;
    }
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
