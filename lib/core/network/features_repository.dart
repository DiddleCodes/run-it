import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Task 67: the backend's platform-wide launch switches (`GET /features`,
/// backed by its `features` config block). The backend is the single
/// source of truth and the real enforcement — this only lets the app hide
/// a globally-disabled feature entirely rather than offer something the
/// server would reject anyway.
class PlatformFeatures {
  const PlatformFeatures({required this.podEnabled});

  factory PlatformFeatures.fromJson(Map<String, dynamic> json) =>
      PlatformFeatures(podEnabled: json['podEnabled'] == true);

  /// Pay on Delivery (Task 47), independent of any restaurant's own
  /// `payAtDeliveryEnabled` opt-in.
  final bool podEnabled;
}

class FeaturesRepository {
  const FeaturesRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<PlatformFeatures> fetch() async {
    final json = await client.get('/features') as Map<String, dynamic>;
    return PlatformFeatures.fromJson(json);
  }
}

final featuresRepositoryProvider = Provider<FeaturesRepository>(
  (ref) => const FeaturesRepository(),
);

/// Fetched once per provider container, same convention as
/// `campusesProvider`.
final platformFeaturesProvider = FutureProvider<PlatformFeatures>(
  (ref) => ref.read(featuresRepositoryProvider).fetch(),
);

/// Whether Pay on Delivery exists at all right now. False while loading or
/// if the fetch fails — a switched-off feature must never flash into view,
/// and the backend rejects POD on its own regardless.
final podEnabledProvider = Provider<bool>(
  (ref) => ref.watch(platformFeaturesProvider).valueOrNull?.podEnabled ?? false,
);
