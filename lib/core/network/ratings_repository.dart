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

/// Task 14 Part D — `POST /orders/:orderId/rating` and the public
/// `GET /runners/:id/rating-summary`. A 409 ("this order has already been
/// rated") is a normal, expected [ApiException] here just like any other
/// backend rejection elsewhere in this codebase — callers decide how to
/// present it (the rating prompt treats it as a soft success rather than
/// an alarming error, since from the student's perspective nothing is
/// actually wrong).
class RatingsRepository {
  const RatingsRepository({this.client = const ApiClient()});
  final ApiClient client;

  Future<void> rate({
    required String orderId,
    required int stars,
    String? comment,
    required String token,
  }) async {
    await client.post(
      '/orders/$orderId/rating',
      token: token,
      body: {
        'stars': stars,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
    );
  }

  Future<RunnerRatingSummary> fetchRunnerRatingSummary(String runnerId) async {
    final json = await client.get('/runners/$runnerId/rating-summary') as Map<String, dynamic>;
    return RunnerRatingSummary.fromJson(json);
  }
}
