import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/network/matching_repository.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/runner/presentation/runner_screens.dart';

const _orderId = 'order-1790799324143924';

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    user: const UserProfile(
      id: 'runner-1',
      name: 'Test Runner',
      contact: 'testrunner@runit.dev',
      accountType: AccountType.runner,
      campusId: 'ui',
      kycStatus: KycStatus.verified,
      runnerType: RunnerType.studentRunner,
    ),
  );
}

class _ClaimingEscrow extends EscrowRepository {
  @override
  Future<ClaimResult> claim({required String orderId, required String token}) async => ClaimResult.claimed;
}

class _NoJobs extends MatchingRepository {
  @override
  Future<List<DeliveryJob>> listAvailable({required String token}) async => const [];
}

/// `GET /orders/:id` as the backend answers the assigned runner.
class _Orders extends OrdersRepository {
  var failuresLeft = 0;
  final requested = <String>[];

  @override
  Future<OrderHistoryEntry> fetchOrderDetail({required String orderId, required String token}) async {
    requested.add(orderId);
    if (failuresLeft > 0) {
      failuresLeft--;
      throw Exception('network down');
    }
    return OrderHistoryEntry.fromJson({
      'id': orderId,
      'status': 'preparing',
      'vendorName': 'Golden Crust Bakery',
      'totalAmount': 144500,
      'items': [
        {'name': 'Chicken Pie', 'quantity': 1, 'priceKobo': 90000},
        {'name': 'Puff Puff (6pc)', 'quantity': 2, 'priceKobo': 90000},
      ],
      'createdAt': '2026-09-30T20:15:24.000Z',
    });
  }
}

DeliveryJob _job() => DeliveryJob(
  id: _orderId,
  eateryName: 'Golden Crust Bakery',
  eateryLocation: 'Student Centre, Main Walk',
  dropoffZone: 'University of Ibadan · Drop-off point',
  dropoffLocation: 'University of Ibadan · Drop-off point',
  payoutAmount: 200,
  totalAmount: 1445,
  offeredAt: DateTime.now(),
);

ProviderContainer _container(_Orders orders) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuthController.new),
      escrowRepositoryProvider.overrideWithValue(_ClaimingEscrow()),
      matchingRepositoryProvider.overrideWithValue(_NoJobs()),
      ordersRepositoryProvider.overrideWithValue(orders),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('accepting a job shows the real order: its reference, then its real items', () async {
    final orders = _Orders();
    final container = _container(orders);
    final controller = container.read(runnerControllerProvider.notifier);
    await controller.toggleAvailability();

    await controller.acceptJob(_job());
    var active = container.read(runnerControllerProvider).activeDelivery!;
    expect(active.orderNumber, '#24143924');
    expect(active.orderItems, isNull); // loading — never placeholder items

    await Future<void>.delayed(Duration.zero);
    active = container.read(runnerControllerProvider).activeDelivery!;
    expect(orders.requested, [_orderId]);
    expect(active.orderItems, ['1 × Chicken Pie', '2 × Puff Puff (6pc)']);
  });

  test('a failed item fetch is shown as failed, and retrying loads them', () async {
    final orders = _Orders()..failuresLeft = 1;
    final container = _container(orders);
    final controller = container.read(runnerControllerProvider.notifier);
    await controller.toggleAvailability();

    await controller.acceptJob(_job());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(runnerControllerProvider).activeDelivery!.itemsLoadFailed, isTrue);

    await controller.loadActiveOrderItems();
    final active = container.read(runnerControllerProvider).activeDelivery!;
    expect(active.itemsLoadFailed, isFalse);
    expect(active.orderItems, ['1 × Chicken Pie', '2 × Puff Puff (6pc)']);
  });

  testWidgets('the delivery screen shows the real order, not demo data', (tester) async {
    final orders = _Orders();
    final container = _container(orders);
    final controller = container.read(runnerControllerProvider.notifier);
    await controller.toggleAvailability();
    await controller.acceptJob(_job());

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: ActiveDeliveryScreen())),
    );
    await tester.pump();

    expect(find.text('ORDER #24143924'), findsOneWidget);
    expect(find.text('1 × Chicken Pie'), findsOneWidget);
    expect(find.text('2 × Puff Puff (6pc)'), findsOneWidget);
    expect(find.textContaining('RI-2048'), findsNothing);
    expect(find.textContaining('Signature jollof'), findsNothing);

    // Going online opened the dispatch socket, whose connect timeout would
    // otherwise still be pending at teardown.
    container.dispose();
    await tester.pump(const Duration(seconds: 21));
  });
}
