import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/application/chat_controllers.dart';
import '../../features/ordering/application/order_tracking_controller.dart';
import '../../features/ordering/application/ordering_providers.dart';
import '../../features/ordering/presentation/my_orders_screen.dart';
import '../../features/runner/application/runner_controller.dart';
import '../../features/wallet/application/wallet_controller.dart';
import '../theme/app_colors.dart';
import 'vendors_repository.dart';

/// Whether the device has a network at all, behind an interface so tests
/// can drive it. This is interface state (Wi-Fi/mobile/none), not proof the
/// backend is reachable — a request can still time out on a captive or
/// flaky network, which the request paths handle on their own.
abstract class ConnectivitySource {
  Future<bool> isOnline();
  Stream<bool> get onlineChanges;
}

class DeviceConnectivitySource implements ConnectivitySource {
  final _connectivity = Connectivity();

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged.map(_online);
}

final connectivitySourceProvider = Provider<ConnectivitySource>((ref) => DeviceConnectivitySource());

/// Online until the device says otherwise — never flash an offline banner
/// at startup before the first reading.
class OnlineStatus extends Notifier<bool> {
  @override
  bool build() {
    final source = ref.watch(connectivitySourceProvider);
    final subscription = source.onlineChanges.distinct().listen((online) => state = online);
    ref.onDispose(subscription.cancel);
    unawaited(
      source.isOnline().then((online) => state = online, onError: (_) {}),
    );
    return true;
  }
}

final isOnlineProvider = NotifierProvider<OnlineStatus, bool>(OnlineStatus.new);

/// When the connection comes back, reload what the student/runner is most
/// likely looking at — anything that failed while offline, or has gone
/// stale. Invalidating a provider nobody is watching costs nothing: it's
/// simply re-fetched the next time it's read. (The chat socket and the
/// runner dispatch socket reconnect on their own.)
final reconnectRefresherProvider = Provider<void>((ref) {
  ref.listen<bool>(isOnlineProvider, (wasOnline, online) {
    if (wasOnline != false || !online) return;
    ref
      ..invalidate(campusEateriesProvider)
      ..invalidate(vendorCategoriesProvider)
      ..invalidate(selectedVendorWithMenuProvider)
      ..invalidate(orderHistoryProvider)
      ..invalidate(walletBalanceProvider)
      ..invalidate(chatThreadsProvider)
      ..invalidate(accountNoticesProvider)
      ..invalidate(availableJobsProvider);
    unawaited(ref.read(orderTrackingProvider.notifier).refreshFromServer());
  });
});

/// A persistent strip above every screen while there's no connection —
/// the app shows what it already loaded rather than failing silently.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    if (online) return child;
    final topInset = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Material(
          color: AppColors.inkText,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You’re offline. We’ll refresh when you’re back.',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          // The strip already covers the status bar; the screen below it
          // shouldn't pad for it a second time.
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}
