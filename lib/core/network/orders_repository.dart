import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_exception.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => const OrdersRepository(),
);

/// Mirrors `EscrowRepository.release`'s outcome split: `verify-delivery` is
/// a single backend call that both checks the PIN and (on match) triggers
/// escrow release, so a correct PIN with a stuck payout leg (a 502) is a
/// genuinely different case from a wrong PIN or a rate-limit (both of which
/// throw [ApiException] and must not advance anything) — callers need to
/// tell them apart.
enum DeliveryVerificationResult { delivered, payoutProcessing }

/// Real backend calls against Task 11's `/orders/:orderId` routes — the
/// runner's own scan/entry of the vendor-shown pickup code and the
/// student-shown delivery PIN, plus the photo-proof fallback and the
/// student's own delivery-PIN lookup.
class OrdersRepository {
  const OrdersRepository({this.client = const ApiClient()});

  final ApiClient client;

  /// Throws [ApiException] on a mismatched code (400) or after too many
  /// wrong attempts on this order (429) — callers show `e.message` directly
  /// and must not advance any local state (no optimistic UI). Task 30:
  /// [handoffPhotoUrl] is required — the backend rejects a request with
  /// none (400) before the code is even checked, same hard-block decision
  /// as `Order.handoffPhotoUrl`'s own doc comment explains.
  Future<void> verifyPickup({
    required String orderId,
    required String code,
    required String handoffPhotoUrl,
    required String token,
  }) async {
    await client.post(
      '/orders/$orderId/verify-pickup',
      token: token,
      body: {'code': code, 'handoffPhotoUrl': handoffPhotoUrl},
    );
  }

  /// See [DeliveryVerificationResult] — an [ApiException] (400/429) means
  /// the PIN itself was rejected and callers must not advance anything.
  Future<DeliveryVerificationResult> verifyDelivery({
    required String orderId,
    required String code,
    required String token,
  }) async {
    try {
      await client.post(
        '/orders/$orderId/verify-delivery',
        token: token,
        body: {'code': code},
      );
      return DeliveryVerificationResult.delivered;
    } on ApiException catch (e) {
      if (e.statusCode == 502) return DeliveryVerificationResult.payoutProcessing;
      rethrow;
    }
  }

  /// Fallback when PIN verification isn't possible — flags the order for
  /// manual review rather than marking it delivered.
  Future<void> submitDeliveryProof({
    required String orderId,
    required String photoUrl,
    required String token,
  }) async {
    await client.post(
      '/orders/$orderId/delivery-proof',
      token: token,
      body: {'photoUrl': photoUrl},
    );
  }

  /// The student's own delivery PIN, to show them once their order is en
  /// route. [token] must belong to the ordering student (or be
  /// internal/admin) — see `OrdersService.getOrderForViewer` backend-side,
  /// which is also why this returns `null` rather than the pickup code for
  /// any other caller.
  Future<String?> fetchDeliveryPin({
    required String orderId,
    required String token,
  }) async {
    final result = await client.get('/orders/$orderId', token: token) as Map<String, dynamic>;
    return result['deliveryPin'] as String?;
  }

  /// Task 30: the real student-facing "report a problem" call — creates a
  /// real backend Dispute (reusing the existing admin dispute-review
  /// model/flow, not a new one) scoped to [token]'s own order. Throws
  /// [ApiException] (409) if a dispute already exists for this order —
  /// same one-per-order limit the admin-manual open() path already has.
  Future<void> reportProblem({
    required String orderId,
    required String reason,
    String? photoUrl,
    required String token,
  }) async {
    await client.post(
      '/orders/$orderId/report',
      token: token,
      body: {'reason': reason, 'photoUrl': ?photoUrl},
    );
  }
}
