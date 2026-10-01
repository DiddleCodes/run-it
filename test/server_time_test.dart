import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/matching_repository.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/utils/server_time.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/chat/domain/chat_models.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/order_detail_screen.dart';
import 'package:run_it/features/wallet/data/wallet_repository.dart';

// The backend always sends UTC. 08:30Z is 9:30 AM in Lagos (WAT, +1).
const _placedUtc = '2026-10-01T08:30:00.000Z';
// 23:30Z on Sep 30 is already Oct 1 in Lagos — the date itself shifts.
const _deliveredUtc = '2026-09-30T23:30:00.000Z';

DateTime _local(String iso) => DateTime.parse(iso).toLocal();
DateTime _utc(String iso) => DateTime.parse(iso);

/// These tests run in the machine's own zone (WAT here). On a UTC machine
/// local == UTC, so the "never the UTC reading" checks have nothing to
/// tell apart and are skipped; the isUtc checks still apply everywhere.
final _offset = DateTime.now().timeZoneOffset;

Map<String, dynamic> _orderJson() => {
  'id': 'order-1790832731040039',
  'status': 'delivered',
  'vendorName': 'Golden Crust Bakery',
  'totalAmount': 144500,
  'items': [
    {'name': 'Chicken Pie', 'quantity': 1, 'priceKobo': 90000},
  ],
  'createdAt': _placedUtc,
  'acceptedAt': _placedUtc,
  'pickedUpAt': _placedUtc,
  'deliveredAt': _deliveredUtc,
};

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    user: const UserProfile(
      id: 'student-1',
      name: 'Ayanfe O.',
      contact: 'a@student.ui.edu.ng',
      accountType: AccountType.student,
      campusId: 'ui',
    ),
  );
}

class _Orders extends OrdersRepository {
  @override
  Future<OrderHistoryEntry> fetchOrderDetail({required String orderId, required String token}) async =>
      OrderHistoryEntry.fromJson(_orderJson());

  @override
  Future<OrderHistoryPage> fetchOrderHistory({int page = 1, int limit = 20, required String token}) async =>
      OrderHistoryPage(items: [OrderHistoryEntry.fromJson(_orderJson())], total: 1, page: 1, limit: 20);
}

ApiClient _answering(Object body) =>
    ApiClient(httpClient: MockClient((_) async => http.Response(jsonEncode(body), 200)));

void main() {
  group('Server timestamps are parsed into local (Lagos) time, once', () {
    test('the shared parser keeps the instant but makes it local', () {
      final parsed = parseServerTime(_placedUtc);
      expect(parsed.isUtc, isFalse);
      expect(parsed.isAtSameMomentAs(_utc(_placedUtc)), isTrue); // same moment in time
      expect(parsed.hour, _utc(_placedUtc).add(_offset).hour);
      expect(parseServerTimeOrNull(null), isNull);
    });

    test('order history: every lifecycle timestamp', () {
      final order = OrderHistoryEntry.fromJson({..._orderJson(), 'cancelledAt': _placedUtc, 'declinedAt': _placedUtc});
      for (final at in [
        order.createdAt,
        order.acceptedAt!,
        order.pickedUpAt!,
        order.deliveredAt!,
        order.cancelledAt!,
        order.declinedAt!,
      ]) {
        expect(at.isUtc, isFalse);
      }
      expect(order.deliveredAt, _local(_deliveredUtc));
    });

    test('a saved (cached) order comes back as the same moment, still local', () {
      final order = OrderHistoryEntry.fromJson(_orderJson());
      final roundTripped = OrderHistoryEntry.fromJson(order.toJson());
      expect(roundTripped.createdAt, order.createdAt);
      expect(roundTripped.deliveredAt, order.deliveredAt);
      expect(roundTripped.createdAt.isUtc, isFalse);
    });

    test('wallet transactions', () async {
      final repository = WalletRepository(
        client: _answering([
          {'id': 't1', 'type': 'debit', 'amount': 144500, 'status': 'success', 'createdAt': _placedUtc},
        ]),
      );
      final transactions = await repository.getTransactions(userId: 'student-1', token: 't');
      expect(transactions.single.occurredAt.isUtc, isFalse);
      expect(transactions.single.occurredAt, _local(_placedUtc));
    });

    test('runner job offers', () async {
      final repository = MatchingRepository(
        client: _answering([
          {
            'orderId': 'order-1',
            'vendorName': 'Golden Crust Bakery',
            'payoutAmount': 20000,
            'totalAmount': 144500,
            'createdAt': _placedUtc,
          },
        ]),
      );
      final jobs = await repository.listAvailable(token: 't');
      expect(jobs.single.offeredAt.isUtc, isFalse);
    });

    test('runner cash-debt entries', () {
      final entry = CashDebtEntry.fromJson({
        'orderId': 'order-1',
        'amountOwed': 144500,
        'amountCollected': 0,
        'status': 'pending',
        'createdAt': _placedUtc,
      });
      expect(entry.createdAt.isUtc, isFalse);
    });

    test('chat (already local) goes through the same parser', () {
      final message = ChatMessage.fromJson({
        'id': 'm1',
        'orderId': 'order-1',
        'senderUserId': 'runner-1',
        'body': 'On my way',
        'createdAt': _placedUtc,
        'readAt': null,
      });
      expect(message.createdAt.isUtc, isFalse);
    });
  });

  group('Screens show Lagos time', () {
    testWidgets('order detail timeline', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            ordersRepositoryProvider.overrideWithValue(_Orders()),
          ],
          child: const MaterialApp(home: OrderDetailScreen(orderId: 'order-1790832731040039')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final format = DateFormat('MMM d, h:mm a');
      expect(find.text('Placed\n${format.format(_local(_placedUtc))}'), findsOneWidget);
      if (_offset != Duration.zero) {
        expect(find.textContaining(format.format(_utc(_placedUtc))), findsNothing);
      }
    });

    testWidgets('My Orders: the delivered date is the Lagos date', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            ordersRepositoryProvider.overrideWithValue(_Orders()),
          ],
          child: const MaterialApp(home: MyOrdersScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Past'));
      await tester.pump(const Duration(milliseconds: 300));

      final local = _local(_deliveredUtc);
      final yesterday = DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 1));
      final expected = DateUtils.dateOnly(local) == yesterday ? 'Yesterday' : DateFormat('MMM d').format(local);
      expect(find.text('Delivered $expected'), findsOneWidget);
      if (_offset > Duration.zero) {
        // In Lagos 23:30Z Sep 30 is Oct 1 — the UTC date would be a day early.
        expect(find.text('Delivered Sep 30'), findsNothing);
      }
    });
  });
}
