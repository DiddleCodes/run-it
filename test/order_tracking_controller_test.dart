import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';

void main() {
  test(
    'order progresses placed -> runnerAssigned -> pickedUp -> delivered',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(orderTrackingProvider.notifier);

      controller.placeOrder(
        orderId: 'order-test-1',
        orderItems: const ['1 × Signature jollof'],
        total: 3550,
        eateryName: 'Tantalizers',
        deliveryLocationLabel: 'Queen Elizabeth II Hall · Room B12',
      );
      expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
      expect(container.read(orderTrackingProvider).orderId, 'order-test-1');
      expect(container.read(orderTrackingProvider).runnerName, isNull);

      controller.advanceForTest();
      expect(
        container.read(orderTrackingProvider).stage,
        OrderStage.runnerAssigned,
      );
      expect(container.read(orderTrackingProvider).runnerName, isNotNull);

      // Task 11: pickedUp/delivered are no longer timer-driven — they only
      // ever advance via markPickedUp/markDelivered, called only after a
      // real verify-pickup/verify-delivery success (see RunnerScanScreen).
      // advanceForTest (the timer bypass) is a no-op past runnerAssigned.
      controller.advanceForTest();
      expect(
        container.read(orderTrackingProvider).stage,
        OrderStage.runnerAssigned,
      );

      controller.markPickedUp();
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);

      controller.markDelivered();
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);
    },
  );

  test('markPickedUp/markDelivered are no-ops out of order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(orderTrackingProvider.notifier);

    controller.placeOrder(
      orderId: 'order-test-order-guard',
      orderItems: const ['1 × Jollof'],
      total: 3000,
      eateryName: 'Tantalizers',
      deliveryLocationLabel: 'Hostel B',
    );

    // Still `placed` — no runner assigned yet — so neither call should do
    // anything.
    controller.markPickedUp();
    expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
    controller.markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.placed);

    controller.advanceForTest();
    expect(
      container.read(orderTrackingProvider).stage,
      OrderStage.runnerAssigned,
    );

    // Not yet picked up — a stray markDelivered() must not skip a stage.
    controller.markDelivered();
    expect(
      container.read(orderTrackingProvider).stage,
      OrderStage.runnerAssigned,
    );
  });

  test('resetOrder clears stage, runner, and timers for a fresh order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(orderTrackingProvider.notifier);

    controller.placeOrder(
      orderId: 'order-test-2',
      orderItems: const ['1 × Coconut fried rice'],
      total: 3050,
      eateryName: 'Tantalizers',
      deliveryLocationLabel: 'Sultan Bello Hall · Room A4',
    );
    controller.advanceForTest();
    controller.markPickedUp();
    controller.markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);

    controller.resetOrder();
    final reset = container.read(orderTrackingProvider);
    expect(reset.stage, isNull);
    expect(reset.runnerName, isNull);
    expect(reset.orderItems, isEmpty);
    expect(reset.total, 0);
    expect(reset.isActive, isFalse);

    // Advancing after reset must be a no-op — no leftover timer/state.
    controller.advanceForTest();
    expect(container.read(orderTrackingProvider).stage, isNull);
  });
}
