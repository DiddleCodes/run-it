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
        orderItems: const ['1 × Signature jollof'],
        total: 3550,
        eateryName: 'Tantalizers',
        deliveryLocationLabel: 'Queen Elizabeth II Hall · Room B12',
      );
      expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
      expect(container.read(orderTrackingProvider).runnerName, isNull);

      controller.advanceForTest();
      expect(
        container.read(orderTrackingProvider).stage,
        OrderStage.runnerAssigned,
      );
      expect(container.read(orderTrackingProvider).runnerName, isNotNull);

      controller.advanceForTest();
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);

      controller.advanceForTest();
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);
    },
  );

  test('resetOrder clears stage, runner, and timers for a fresh order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(orderTrackingProvider.notifier);

    controller.placeOrder(
      orderItems: const ['1 × Coconut fried rice'],
      total: 3050,
      eateryName: 'Tantalizers',
      deliveryLocationLabel: 'Sultan Bello Hall · Room A4',
    );
    controller.advanceForTest();
    controller.advanceForTest();
    controller.advanceForTest();
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
