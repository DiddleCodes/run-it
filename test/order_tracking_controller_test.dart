import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';

import 'support/server_orders.dart';

const _orderId = 'order-test-1';

(ProviderContainer, OrderTrackingController) _placed() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final controller = container.read(orderTrackingProvider.notifier)
    ..placeOrder(
      orderId: _orderId,
      orderItems: const ['1 × Signature jollof'],
      total: 3550,
      eateryName: 'Tantalizers',
      deliveryLocationLabel: 'Queen Elizabeth II Hall · Room B12',
    );
  return (container, controller);
}

void main() {
  test('Task 73: placing an order starts at placed with no runner — nothing is ever invented', () {
    final (container, _) = _placed();
    final session = container.read(orderTrackingProvider);
    expect(session.stage, OrderStage.placed);
    expect(session.orderId, _orderId);
    expect(session.runnerName, isNull);
  });

  test('Task 73: maps each real backend status to its stage, with the real runner name once claimed', () {
    final (container, controller) = _placed();
    OrderTrackingSession session() => container.read(orderTrackingProvider);

    controller.applyServerOrder(serverOrder(_orderId, 'placed'));
    expect(session().stage, OrderStage.placed);

    // Accepted, not yet claimed by any runner.
    controller.applyServerOrder(serverOrder(_orderId, 'preparing'));
    expect(session().stage, OrderStage.preparing);
    expect(session().runnerName, isNull);

    controller.applyServerOrder(serverOrder(_orderId, 'ready_for_pickup'));
    expect(session().stage, OrderStage.preparing);

    // A real runner claimed it.
    controller.applyServerOrder(serverOrder(_orderId, 'ready_for_pickup', runnerName: 'Amaka N.'));
    expect(session().stage, OrderStage.runnerAssigned);
    expect(session().runnerName, 'Amaka N.');

    controller.applyServerOrder(serverOrder(_orderId, 'picked_up', runnerName: 'Amaka N.'));
    expect(session().stage, OrderStage.pickedUp);

    controller.applyServerOrder(serverOrder(_orderId, 'delivered', runnerName: 'Amaka N.'));
    expect(session().stage, OrderStage.delivered);
  });

  test('Task 73: forward-only — a stale snapshot never moves the tracker backwards', () {
    final (container, controller) = _placed();
    controller.applyServerOrder(serverOrder(_orderId, 'picked_up', runnerName: 'Amaka N.'));

    controller.applyServerOrder(serverOrder(_orderId, 'placed'));
    controller.applyServerOrder(serverOrder(_orderId, 'preparing'));

    expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);
    expect(container.read(orderTrackingProvider).runnerName, 'Amaka N.');
  });

  test('Task 73: ignores a snapshot for some other order', () {
    final (container, controller) = _placed();
    controller.applyServerOrder(serverOrder('someone-elses-order', 'ready_for_pickup', runnerName: 'Tunde B.'));

    expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
    expect(container.read(orderTrackingProvider).runnerName, isNull);
  });

  test("the student's own confirmation is never overwritten by a later delivered snapshot", () {
    final (container, controller) = _placed();
    controller
      ..applyServerOrder(serverOrder(_orderId, 'delivered', runnerName: 'Amaka N.'))
      ..confirmDelivery();
    expect(container.read(orderTrackingProvider).stage, OrderStage.confirmed);

    controller.applyServerOrder(serverOrder(_orderId, 'delivered', runnerName: 'Amaka N.'));
    expect(container.read(orderTrackingProvider).stage, OrderStage.confirmed);
  });

  test('markPickedUp/markDelivered are no-ops out of order', () {
    final (container, controller) = _placed();

    // The restaurant hasn't even accepted — nothing can have been picked up.
    controller.markPickedUp();
    expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
    controller.markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.placed);

    controller.applyServerOrder(serverOrder(_orderId, 'ready_for_pickup', runnerName: 'Amaka N.'));
    // Not yet picked up — a stray markDelivered() must not skip a stage.
    controller.markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.runnerAssigned);

    // A real verify-pickup on this device.
    controller.markPickedUp();
    expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);
    controller.markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);
  });

  test('resetOrder clears stage, runner, and polling for a fresh order', () {
    final (container, controller) = _placed();
    controller
      ..applyServerOrder(serverOrder(_orderId, 'ready_for_pickup', runnerName: 'Amaka N.'))
      ..markPickedUp()
      ..markDelivered();
    expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);

    controller.resetOrder();
    final reset = container.read(orderTrackingProvider);
    expect(reset.stage, isNull);
    expect(reset.runnerName, isNull);
    expect(reset.orderItems, isEmpty);
    expect(reset.total, 0);
    expect(reset.isActive, isFalse);

    // A snapshot for the old order after reset is ignored.
    controller.applyServerOrder(serverOrder(_orderId, 'picked_up', runnerName: 'Amaka N.'));
    expect(container.read(orderTrackingProvider).stage, isNull);
  });
}
