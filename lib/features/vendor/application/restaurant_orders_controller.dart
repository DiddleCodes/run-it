import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/vendors_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/vendor_dashboard_models.dart';

/// The Orders tab's own list — defaults to the live kitchen queue (no
/// status filter; see `VendorsService.listIncomingOrders`'s doc comment
/// backend-side for exactly which statuses that covers). No optimistic
/// UI: [advanceStatus] never mutates local state directly — every
/// transition is only reflected once a full refetch confirms the backend
/// actually applied it.
class RestaurantOrdersController extends AsyncNotifier<VendorOrdersPage> {
  RestaurantOrderStatus? _statusFilter;

  RestaurantOrderStatus? get statusFilter => _statusFilter;

  @override
  Future<VendorOrdersPage> build() => _fetch();

  Future<VendorOrdersPage> _fetch() async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('RestaurantOrdersController.build() called with no active session');
    }
    return ref
        .read(vendorsRepositoryProvider)
        .fetchOrders(status: _statusFilter, token: session.accessToken);
  }

  Future<void> setStatusFilter(RestaurantOrderStatus? status) async {
    _statusFilter = status;
    await refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue<VendorOrdersPage>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard<VendorOrdersPage>(_fetch);
  }

  /// Throws on failure (an [ApiException] or transport error) — callers
  /// show the real rejection rather than assuming success. On success, the
  /// list is refetched from the confirmed backend state before this
  /// resolves.
  Future<void> advanceStatus(String orderId, RestaurantOrderStatus newStatus) async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('advanceStatus() called with no active session');
    }
    await ref
        .read(vendorsRepositoryProvider)
        .advanceOrderStatus(orderId: orderId, status: newStatus, token: session.accessToken);
    await refresh();
  }
}

final restaurantOrdersProvider = AsyncNotifierProvider<RestaurantOrdersController, VendorOrdersPage>(
  RestaurantOrdersController.new,
);
