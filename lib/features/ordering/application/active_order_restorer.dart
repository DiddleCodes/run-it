import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/orders_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'order_tracking_controller.dart';

/// Live tracking only exists in memory, so an app restart used to leave a
/// student with an order in progress and no tracking screen, no runner
/// card and no way back into the order's chat except by tapping a push.
///
/// When a student signs in (including resuming after a restart) with no
/// order being tracked, this asks the backend for their most recent order
/// still in progress and picks it back up, delivery PIN and all. My Orders'
/// Active tab lists every in-progress order as a second way back in.
/// Watched once from the app root. If the backend can't be reached at
/// sign-in, it tries again a few times, and again whenever the device comes
/// back online (see reconnectRefresherProvider).
final activeOrderRestorerProvider = Provider<void>((ref) {
  ref.listen<AuthSession?>(authControllerProvider, (previous, next) {
    if (next == null || next.user.accountType != AccountType.student) return;
    if (previous?.user.id == next.user.id) return;
    unawaited(restoreActiveOrder(ref, next));
  }, fireImmediately: true);
});

/// How long to wait before each retry when the backend can't be reached.
final restoreRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [Duration(seconds: 3), Duration(seconds: 10), Duration(seconds: 30)],
);

Future<void> restoreActiveOrder(Ref ref, AuthSession session) async {
  var alive = true;
  ref.onDispose(() => alive = false);
  final delays = ref.read(restoreRetryDelaysProvider);
  for (var attempt = 0; ; attempt++) {
    // Stop once something is tracked, or the student signed out/switched.
    if (!alive || ref.read(orderTrackingProvider).orderId != null) return;
    final current = ref.read(authControllerProvider);
    if (current == null || current.user.id != session.user.id) return;
    try {
      final orders = ref.read(ordersRepositoryProvider);
      final history = await orders.fetchOrderHistory(token: current.accessToken);
      final active = history.items.where((o) => o.isInProgress).firstOrNull;
      if (active == null) return;
      String? pin;
      try {
        pin = await orders.fetchDeliveryPin(orderId: active.id, token: current.accessToken);
      } catch (_) {
        // The tracking screen already handles a missing PIN.
      }
      // Something may have started tracking while this was in flight.
      if (!alive || ref.read(orderTrackingProvider).orderId != null) return;
      ref.read(orderTrackingProvider.notifier).resumeOrder(active, deliveryPin: pin);
      return;
    } catch (_) {
      // Unreachable: try again shortly. Once out of retries, a reconnect
      // or My Orders still gets the student back to it.
      if (attempt >= delays.length) return;
      await Future<void>.delayed(delays[attempt]);
    }
  }
}
