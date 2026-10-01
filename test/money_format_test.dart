import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/utils/money.dart';
import 'package:run_it/features/ordering/presentation/widgets/ordering_components.dart'
    show PriceRow;
import 'package:run_it/features/wallet/data/wallet_repository.dart';

void main() {
  group('formatKobo — the one money format', () {
    test('whole naira get two decimals', () {
      expect(formatKobo(90000), '₦900.00');
      expect(formatKobo(0), '₦0.00');
      expect(formatKobo(100), '₦1.00');
    });

    test('thousands are separated', () {
      expect(formatKobo(144500), '₦1,445.00');
      expect(formatKobo(14450000), '₦144,500.00');
      expect(formatKobo(123456789012), '₦1,234,567,890.12');
    });

    test('kobo that are not whole naira are kept, never rounded away', () {
      expect(formatKobo(144450), '₦1,444.50');
      expect(formatKobo(144405), '₦1,444.05');
      expect(formatKobo(1), '₦0.01');
      expect(formatKobo(99), '₦0.99');
    });

    test('negative amounts put the sign before the ₦', () {
      expect(formatKobo(-144450), '-₦1,444.50');
    });
  });

  group('naira — the same format for amounts held in naira', () {
    test('whole and fractional naira', () {
      expect(naira(1445), '₦1,445.00');
      expect(naira(144500), '₦144,500.00');
      expect(naira(1444.5), '₦1,444.50');
      expect(naira(0.1 + 0.2), '₦0.30'); // no floating-point leftovers
    });
  });

  test('a wallet balance and transaction with kobo keep them all the way to the screen', () async {
    final repository = WalletRepository(
      client: ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/balance')
                  ? {'balanceKobo': 144450}
                  : [
                      {
                        'id': 't1',
                        'type': 'credit',
                        'amount': 20050,
                        'status': 'success',
                        'createdAt': '2026-10-01T08:30:00.000Z',
                      },
                    ],
            ),
            200,
          ),
        ),
      ),
    );
    expect(
      naira(await repository.getBalance(userId: 'u', token: 't')),
      '₦1,444.50',
    );
    expect(
      naira(
        (await repository.getTransactions(
          userId: 'u',
          token: 't',
        )).single.amount,
      ),
      '₦200.50',
    );
  });

  testWidgets('a price breakdown lines every amount up on one right edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PriceRow(label: 'Items', amount: 900),
              PriceRow(label: 'Packaging', amount: 0),
              PriceRow(label: 'Service fee (5%)', amount: 45),
              PriceRow(label: 'Total', amount: 1445, emphasized: true),
            ],
          ),
        ),
      ),
    );

    final rightEdges = {
      for (final amount in ['₦900.00', '₦0.00', '₦45.00', '₦1,445.00'])
        tester.getTopRight(find.text(amount)).dx,
    };
    expect(rightEdges, hasLength(1));

    // Labels bold; Total heavier still.
    final items = tester.widget<Text>(find.text('Items')).style!.fontWeight!;
    final total = tester.widget<Text>(find.text('Total')).style!.fontWeight!;
    expect(items.value, greaterThanOrEqualTo(FontWeight.w600.value));
    expect(total.value, greaterThan(items.value));
  });
}
