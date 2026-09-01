import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/vendors_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/vendor_dashboard_models.dart';

class MetricsDateRange {
  const MetricsDateRange({this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  /// `null`/`null` means "let the backend apply its own default" — the
  /// last 30 days (see `VendorsService.metrics`'s own default window).
  static const defaultRange = MetricsDateRange();
}

/// The Metrics tab's own data — a date range plus whatever the backend's
/// real aggregate says for it. Never computed locally from the Orders
/// list: this always reflects a fresh `GET /vendors/me/metrics` call.
class RestaurantMetricsController extends AsyncNotifier<VendorMetrics> {
  MetricsDateRange _range = MetricsDateRange.defaultRange;

  MetricsDateRange get range => _range;

  @override
  Future<VendorMetrics> build() => _fetch();

  Future<VendorMetrics> _fetch() async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('RestaurantMetricsController.build() called with no active session');
    }
    return ref
        .read(vendorsRepositoryProvider)
        .fetchMetrics(from: _range.from, to: _range.to, token: session.accessToken);
  }

  Future<void> setRange(MetricsDateRange range) async {
    _range = range;
    state = const AsyncValue<VendorMetrics>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard<VendorMetrics>(_fetch);
  }

  Future<void> refresh() async {
    state = const AsyncValue<VendorMetrics>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard<VendorMetrics>(_fetch);
  }
}

final restaurantMetricsProvider = AsyncNotifierProvider<RestaurantMetricsController, VendorMetrics>(
  RestaurantMetricsController.new,
);
