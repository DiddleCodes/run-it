import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ordering/domain/pricing_service.dart';
import 'api_client.dart';

/// Task 70: `GET /pricing` — the numbers checkout must price with, straight
/// from the backend that enforces them.
class PricingRepository {
  const PricingRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<PricingConfig> fetch() async {
    final json = await client.get('/pricing') as Map<String, dynamic>;
    return PricingConfig.fromJson(json);
  }
}

final pricingRepositoryProvider = Provider<PricingRepository>(
  (ref) => const PricingRepository(),
);

/// Fetched once per provider container, same convention as
/// `platformFeaturesProvider`.
final pricingConfigFetchProvider = FutureProvider<PricingConfig>(
  (ref) => ref.read(pricingRepositoryProvider).fetch(),
);

/// What every basket/checkout total is computed with — the backend's live
/// values once loaded, its own defaults until then (or if the fetch fails;
/// the backend then rejects a stale fee rather than charging it).
final pricingConfigProvider = Provider<PricingConfig>(
  (ref) => ref.watch(pricingConfigFetchProvider).valueOrNull ?? PricingConfig.defaults,
);
