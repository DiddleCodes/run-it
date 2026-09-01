import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

final demoIdentityServiceProvider = Provider<DemoIdentityService>(
  (ref) => const DemoIdentityService(),
);

/// Task 8b/8c's backend has no Orders or runner-matching module at all —
/// `OrderEscrow.orderId` is a bare string, and `hold()`/`release()` need
/// real `restaurantUserId`/`runnerUserId` backend User UUIDs. But this
/// app's eatery/runner matching (Tasks 5/6) is entirely local mock data
/// with no backend identity of its own, and there's no way to resolve a
/// real restaurant/runner id from it.
///
/// This service is the documented bridge: it provisions one fixed demo
/// restaurant User and one fixed demo runner User per device install (via
/// the backend's unauthenticated `POST /users`), caches their real backend
/// ids in secure storage, and reuses them for every order this device
/// places or delivers. It's what lets real money actually move through the
/// live backend for this build, standing in for whichever real
/// restaurant/runner a proper Orders/matching backend would resolve.
///
/// TODO(production-blocker, tracked): replace this with real per-order
/// restaurant/runner identities once a real Orders/runner-matching backend
/// exists — tracked alongside `AuthRepository`'s dev-token follow-up.
class DemoIdentityService {
  const DemoIdentityService({
    this.client = const ApiClient(),
    this.secureStorage = const FlutterSecureStorage(),
  });

  final ApiClient client;
  final FlutterSecureStorage secureStorage;

  static const _restaurantKey = 'runit_demo_restaurant_user_id_v1';
  static const _runnerKey = 'runit_demo_runner_user_id_v1';

  Future<String> ensureRestaurantUserId() =>
      _ensure(_restaurantKey, 'restaurant', 'demo-restaurant');

  Future<String> ensureRunnerUserId() => _ensure(_runnerKey, 'runner', 'demo-runner');

  Future<String> _ensure(String storageKey, String accountType, String label) async {
    final cached = await secureStorage.read(key: storageKey);
    if (cached != null) return cached;

    // A fresh, randomly-suffixed email every time this is first provisioned
    // on a device — `email` is `@unique` backend-side, so a fixed literal
    // would collide the second time any device (or test run) tried to seed
    // one against a shared backend.
    final email = '$label-${DateTime.now().microsecondsSinceEpoch}@run-it.internal';
    final user =
        await client.post('/users', body: {'email': email, 'accountType': accountType})
            as Map<String, dynamic>;
    final id = user['id'] as String;
    await secureStorage.write(key: storageKey, value: id);
    return id;
  }

  /// Mints a fresh JWT scoped to [userId] — used for the demo runner
  /// identity specifically, since the human actually holding the scanner
  /// during a delivery-confirmation scan is signed in under their own
  /// (different) session, not this demo identity. See this class's own
  /// doc comment for why that split exists.
  Future<String> mintTokenFor({required String userId, required String accountType}) async {
    final json =
        await client.post(
              '/auth/dev-token',
              body: {'userId': userId, 'accountType': accountType, 'role': 'user'},
            )
            as Map<String, dynamic>;
    return json['accessToken'] as String;
  }
}
