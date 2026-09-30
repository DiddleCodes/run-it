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
/// Watched once from the app root; best-effort (offline just means the
/// student can open it from My Orders later).
final activeOrderRestorerProvider = Provider<void>((ref) {
  ref.listen<AuthSession?>(authControllerProvider, (previous, next) {
    if (next == null || next.user.accountType != AccountType.student) return;
    if (previous?.user.id == next.user.id) return;
    unawaited(restoreActiveOrder(ref, next));
  }, fireImmediately: true);
});

Future<void> restoreActiveOrder(Ref ref, AuthSession session) async {
  if (ref.read(orderTrackingProvider).orderId != null) return;
  try {
    final orders = ref.read(ordersRepositoryProvider);
    final history = await orders.fetchOrderHistory(token: session.accessToken);
    final active = history.items.where((o) => o.isInProgress).firstOrNull;
    if (active == null) return;
    String? pin;
    try {
      pin = await orders.fetchDeliveryPin(orderId: active.id, token: session.accessToken);
    } catch (_) {
      // The tracking screen already handles a missing PIN.
    }
    // Something may have started tracking while this was in flight.
    if (ref.read(orderTrackingProvider).orderId != null) return;
    ref.read(orderTrackingProvider.notifier).resumeOrder(active, deliveryPin: pin);
  } catch (_) {
    // Offline or the backend is unreachable: My Orders will show it later.
  }
}
