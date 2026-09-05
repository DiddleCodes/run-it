import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final ratingsRepositoryProvider = Provider<RatingsRepository>(
  (ref) => const RatingsRepository(),
);

/// `GET /runners/:id/rating-summary`'s own shape — the real aggregate
/// behind Runner Profile's Rating stat (Task 14 Part D), replacing the
/// screen's old `_demoRating` client-side fake.
class RunnerRatingSummary {
  const RunnerRatingSummary({
    required this.runnerId,
    required this.averageRating,
    required this.ratingCount,
  });
  final String runnerId;
  final double averageRating;
  final int ratingCount;

  factory RunnerRatingSummary.fromJson(Map<String, dynamic> json) => RunnerRatingSummary(
    runnerId: json['runnerId'] as String,
    averageRating: (json['averageRating'] as num).toDouble(),
    ratingCount: json['ratingCount'] as int,
  );
}

/// Task 48: the restaurant-side counterpart to [RunnerRatingSummary] —
/// `GET /vendors/:id/rating-summary`'s own shape.
class VendorRatingSummary {
  const VendorRatingSummary({
    required this.vendorId,
    required this.averageRating,
    required this.ratingCount,
  });
  final String vendorId;
  final double averageRating;
  final int ratingCount;

  factory VendorRatingSummary.fromJson(Map<String, dynamic> json) => VendorRatingSummary(
    vendorId: json['vendorId'] as String,
    averageRating: (json['averageRating'] as num).toDouble(),
    ratingCount: json['ratingCount'] as int,
  );
}

/// Task 14 Part D — `POST /orders/:orderId/rating` and the public
/// `GET /runners/:id/rating-summary`. A 409 ("this order has already been
/// rated") is a normal, expected [ApiException] here just like any other
/// backend rejection elsewhere in this codebase — callers decide how to
/// present it (the rating prompt treats it as a soft success rather than
/// an alarming error, since from the student's perspective nothing is
/// actually wrong).
///
/// Task 48: [rate] now covers the restaurant too — [runnerStars]/
/// [vendorStars] are independently optional, so a caller can submit either,
/// both, or (on a retry after a partial success) neither already-rated
/// party in one call.
class RatingsRepository {
  const RatingsRepository({this.client = const ApiClient()});
  final ApiClient client;

  Future<void> rate({
    required String orderId,
    int? runnerStars,
    String? runnerComment,
    int? vendorStars,
    String? vendorComment,
    required String token,
  }) async {
    await client.post(
      '/orders/$orderId/rating',
      token: token,
      body: {
        if (runnerStars != null)
          'runner': {
            'stars': runnerStars,
            if (runnerComment != null && runnerComment.trim().isNotEmpty) 'comment': runnerComment.trim(),
          },
        if (vendorStars != null)
          'vendor': {
            'stars': vendorStars,
            if (vendorComment != null && vendorComment.trim().isNotEmpty) 'comment': vendorComment.trim(),
          },
      },
    );
  }

  Future<RunnerRatingSummary> fetchRunnerRatingSummary(String runnerId) async {
    final json = await client.get('/runners/$runnerId/rating-summary') as Map<String, dynamic>;
    return RunnerRatingSummary.fromJson(json);
  }

  Future<VendorRatingSummary> fetchVendorRatingSummary(String vendorId) async {
    final json = await client.get('/vendors/$vendorId/rating-summary') as Map<String, dynamic>;
    return VendorRatingSummary.fromJson(json);
  }
}
