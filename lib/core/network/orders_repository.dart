import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ordering/domain/order_history_models.dart';
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
  /// Task 47: [amountCollectedKobo] is the runner's "mark as paid"
  /// confirmation for a Pay on Delivery order — the backend rejects this
  /// call with no PIN check at all if the order is Pay on Delivery and
  /// this is omitted (see OrdersService.verifyDelivery's own doc comment).
  /// Meaningless, and ignored, for a wallet order.
  Future<DeliveryVerificationResult> verifyDelivery({
    required String orderId,
    required String code,
    required String token,
    int? amountCollectedKobo,
  }) async {
    try {
      await client.post(
        '/orders/$orderId/verify-delivery',
        token: token,
        body: {'code': code, 'amountCollectedKobo': ?amountCollectedKobo},
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

  /// Task 46: the real order-detail view — the same `GET /orders/:orderId`
  /// endpoint `fetchDeliveryPin` above uses, now also carrying the vendor
  /// name, items, total, note, and the full timestamped lifecycle.
  Future<OrderHistoryEntry> fetchOrderDetail({
    required String orderId,
    required String token,
  }) async {
    final result = await client.get('/orders/$orderId', token: token) as Map<String, dynamic>;
    return OrderHistoryEntry.fromJson(result);
  }

  /// Task 46: the student's real order history (any status) — most recent
  /// first, backing both the "Past" (delivered) and "Cancelled" tabs of
  /// MyOrdersScreen from one fetch, replacing the old hardcoded fake
  /// entries and the in-memory-only CancelledOrdersController.
  Future<OrderHistoryPage> fetchOrderHistory({
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    final path = Uri(
      path: '/orders',
      queryParameters: {'page': '$page', 'limit': '$limit'},
    ).toString();
    final result = await client.get(path, token: token) as Map<String, dynamic>;
    return OrderHistoryPage.fromJson(result);
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

  /// Task 47: the runner's own real, running Pay on Delivery cash debt —
  /// backs the Wallet screen's "cash owed" total.
  Future<CashDebtSummary> fetchCashDebtSummary({required String token}) async {
    final result = await client.get('/runners/me/cash-debt', token: token) as Map<String, dynamic>;
    return CashDebtSummary.fromJson(result);
  }
}

/// Task 47: one entry in [CashDebtSummary] — a single Pay on Delivery
/// order's still-outstanding (pending or disputed) debt.
class CashDebtEntry {
  const CashDebtEntry({
    required this.orderId,
    required this.amountOwedKobo,
    required this.amountCollectedKobo,
    required this.status,
    required this.createdAt,
  });
  final String orderId;
  final int amountOwedKobo;
  final int amountCollectedKobo;

  /// 'pending' or 'disputed' — a settled debt never appears here at all
  /// (see OrdersService.getMyCashDebtSummary backend-side).
  final String status;
  final DateTime createdAt;

  factory CashDebtEntry.fromJson(Map<String, dynamic> json) => CashDebtEntry(
    orderId: json['orderId'] as String,
    amountOwedKobo: json['amountOwed'] as int,
    amountCollectedKobo: json['amountCollected'] as int,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class CashDebtSummary {
  const CashDebtSummary({required this.totalOwedKobo, required this.debts});
  final int totalOwedKobo;
  final List<CashDebtEntry> debts;

  factory CashDebtSummary.fromJson(Map<String, dynamic> json) => CashDebtSummary(
    totalOwedKobo: json['totalOwedKobo'] as int,
    debts: (json['debts'] as List).map((e) => CashDebtEntry.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
