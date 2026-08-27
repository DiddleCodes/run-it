import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ordering_models.dart';

const _mockRunnerNames = ['Chidi A.', 'Amaka O.', 'Tunde B.', 'Ngozi E.'];

class OrderTrackingSession {
  const OrderTrackingSession({
    this.stage,
    this.runnerName,
    this.orderItems = const [],
    this.total = 0,
    this.eateryName = '',
    this.deliveryLocationLabel = '',
  });

  final OrderStage? stage;
  final String? runnerName;
  final List<String> orderItems;
  final int total;
  final String eateryName;
  final String deliveryLocationLabel;

  bool get isActive => stage != null;

  OrderTrackingSession copyWith({OrderStage? stage, String? runnerName}) =>
      OrderTrackingSession(
        stage: stage ?? this.stage,
        runnerName: runnerName ?? this.runnerName,
        orderItems: orderItems,
        total: total,
        eateryName: eateryName,
        deliveryLocationLabel: deliveryLocationLabel,
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

  void placeOrder({
    required List<String> orderItems,
    required int total,
    required String eateryName,
    required String deliveryLocationLabel,
  }) {
    _cancelTimer();
    state = OrderTrackingSession(
      stage: OrderStage.placed,
      orderItems: orderItems,
      total: total,
      eateryName: eateryName,
      deliveryLocationLabel: deliveryLocationLabel,
    );
    _scheduleNext();
  }

  void _scheduleNext() {
    _stageTimer?.cancel();
    _stageTimer = Timer(const Duration(seconds: 4), _advance);
  }

  void _advance() {
    switch (state.stage) {
      case OrderStage.placed:
        state = state.copyWith(
          stage: OrderStage.runnerAssigned,
          runnerName: _mockRunnerNames[_random.nextInt(_mockRunnerNames.length)],
        );
        _scheduleNext();
      case OrderStage.runnerAssigned:
        state = state.copyWith(stage: OrderStage.pickedUp);
        _scheduleNext();
      case OrderStage.pickedUp:
        state = state.copyWith(stage: OrderStage.delivered);
      case OrderStage.delivered:
      case null:
        break;
    }
  }

  /// Bypasses the timer for deterministic tests/previews, mirroring
  /// `RunnerController.simulateOfferNow`.
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
