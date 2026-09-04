import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ordering_models.dart';

const _mockRunnerNames = ['Chidi A.', 'Amaka O.', 'Tunde B.', 'Ngozi E.'];

class OrderTrackingSession {
  const OrderTrackingSession({
    this.stage,
    this.orderId,
    this.runnerName,
    this.orderItems = const [],
    this.total = 0,
    this.eateryName = '',
    this.deliveryLocationLabel = '',
    this.deliveryPin,
    this.justPlaced = false,
  });

  final OrderStage? stage;

  /// The real backend `orderId` this session's escrow hold was created
  /// under (Task 8d) — `null` until [OrderTrackingController.placeOrder]
  /// runs. Read by the runner Scan screen (pickup/delivery verification)
  /// and this screen's own Cancel action (refund), since all of them need
  /// to reference the exact same order the hold call created.
  final String? orderId;
  final String? runnerName;
  final List<String> orderItems;
  final int total;
  final String eateryName;
  final String deliveryLocationLabel;

  /// The real backend-generated PIN (Task 11) the student shows the runner
  /// in person at drop-off — fetched once, right after the hold succeeds
  /// (see CheckoutScreen), since it's a static value from the moment the
  /// order was created. `null` only if that fetch failed (a connectivity
  /// blip); OrderTrackingScreen falls back to a "check your connection"
  /// notice rather than blocking or fabricating a code.
  final String? deliveryPin;

  /// Task 43: true only for the one render right after [placeOrder] runs —
  /// OrderTrackingScreen plays its "payment confirmed" beat exactly once
  /// off this, then calls [OrderTrackingController.acknowledgeJustPlaced]
  /// so revisiting an already-placed order (backgrounding the app,
  /// navigating away and back) never replays it.
  final bool justPlaced;

  bool get isActive => stage != null;

  OrderTrackingSession copyWith({OrderStage? stage, String? runnerName, bool? justPlaced}) =>
      OrderTrackingSession(
        stage: stage ?? this.stage,
        orderId: orderId,
        runnerName: runnerName ?? this.runnerName,
        orderItems: orderItems,
        total: total,
        eateryName: eateryName,
        deliveryLocationLabel: deliveryLocationLabel,
        deliveryPin: deliveryPin,
        justPlaced: justPlaced ?? this.justPlaced,
      );
}

/// Drives the student-facing order lifecycle. There is no live backend yet
/// (that lands in Task 5+), so progression is simulated locally with a
/// timer per stage — enough to demonstrate the full placed → delivered loop
/// end to end without a real runner-side connection.
class OrderTrackingController extends Notifier<OrderTrackingSession> {
  Timer? _stageTimer;
  final _random = Random();

  @override
  OrderTrackingSession build() {
    ref.onDispose(_cancelTimer);
    return const OrderTrackingSession();
  }

  /// [orderId] is the real backend id the caller's escrow `hold` call
  /// already succeeded under (Task 8d) — this only ever runs once that
  /// hold is confirmed, never before it. [deliveryPin] is the real
  /// backend-generated PIN fetched right after that same hold (Task 11);
  /// `null` only if that fetch itself failed.
  void placeOrder({
    required String orderId,
    required List<String> orderItems,
    required int total,
    required String eateryName,
    required String deliveryLocationLabel,
    String? deliveryPin,
  }) {
    _cancelTimer();
    state = OrderTrackingSession(
      stage: OrderStage.placed,
      orderId: orderId,
      orderItems: orderItems,
      total: total,
      eateryName: eateryName,
      deliveryLocationLabel: deliveryLocationLabel,
      deliveryPin: deliveryPin,
      justPlaced: true,
    );
    _scheduleNext();
  }

  /// Called once OrderTrackingScreen's "payment confirmed" beat has played
  /// — a no-op otherwise so a stray call after the order has since moved on
  /// (or been reset) can't resurrect a stale flag.
  void acknowledgeJustPlaced() {
    if (!state.justPlaced) return;
    state = state.copyWith(justPlaced: false);
  }

  void _scheduleNext() {
    _stageTimer?.cancel();
    _stageTimer = Timer(const Duration(seconds: 4), _advance);
  }

  /// Only `placed -> runnerAssigned` is still timer-simulated — there is no
  /// real runner-matching backend yet. `pickedUp` and `delivered` (Task 11)
  /// are never reached from here; see [markPickedUp]/[markDelivered].
  void _advance() {
    if (state.stage == OrderStage.placed) {
      state = state.copyWith(
        stage: OrderStage.runnerAssigned,
        runnerName: _mockRunnerNames[_random.nextInt(_mockRunnerNames.length)],
      );
    }
  }

  /// Called only after the runner's real `verify-pickup` backend call has
  /// actually succeeded (Task 11, see RunnerScanScreen) — never
  /// optimistically, and never by a timer. No-op unless a runner has
  /// genuinely been assigned, so it can't fire twice or out of order.
  void markPickedUp() {
    if (state.stage != OrderStage.runnerAssigned) return;
    state = state.copyWith(stage: OrderStage.pickedUp);
  }

  /// Called only after the runner's real `verify-delivery` backend call has
  /// actually succeeded (Task 11) — this is now the ONLY path that reaches
  /// `delivered`. No-op unless the order was genuinely picked up first.
  void markDelivered() {
    if (state.stage != OrderStage.pickedUp) return;
    state = state.copyWith(stage: OrderStage.delivered);
  }

  /// The one stage transition that is never automatic — a student tap on
  /// OrderTrackingScreen once the order has actually arrived, per Task 10.
  /// No-op unless the order is genuinely `delivered`, so it can't be
  /// invoked twice or out of order.
  void confirmDelivery() {
    if (state.stage != OrderStage.delivered) return;
    state = state.copyWith(stage: OrderStage.confirmed);
  }

  /// Bypasses the timer for deterministic tests/previews, mirroring
  /// `RunnerController.simulateOfferNow`. Only ever advances
  /// `placed -> runnerAssigned` now — see [markPickedUp]/[markDelivered]
  /// for the stages Task 11 gates on a real backend call.
  void advanceForTest() => _advance();

  void resetOrder() {
    _cancelTimer();
    state = const OrderTrackingSession();
  }

  void _cancelTimer() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }
}

final orderTrackingProvider =
    NotifierProvider<OrderTrackingController, OrderTrackingSession>(
      OrderTrackingController.new,
    );
