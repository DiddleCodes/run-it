import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/matching_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/runner/presentation/runner_jobs_screen.dart';
import 'package:run_it/features/runner/presentation/runner_screens.dart';

/// The exact shape `GET /matching/available` returns for the real ₦1,445
/// Golden Crust order from the Task 78 test run: every amount in kobo.
/// runnerShare is the flat RUNNER_DELIVERY_PAY (₦200).
final _backendJob = {
  'orderId': 'order-1790799324143924',
  'vendorId': 'a672fdb2-bcd6-410c-8b5d-fd7b878347db',
  'vendorName': 'Golden Crust Bakery',
  'deliveryLocationLabel': 'University of Ibadan · Drop-off point',
  'payoutAmount': 20000,
  'totalAmount': 144500,
  'isPayOnDelivery': false,
  'createdAt': '2026-09-30T20:15:24.000Z',
};

MatchingRepository _repositoryServing(List<Map<String, Object?>> jobs) => MatchingRepository(
  client: ApiClient(httpClient: MockClient((_) async => http.Response(jsonEncode(jobs), 200))),
);

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

class _SeededRunner extends RunnerController {
  _SeededRunner(this.session);
  final RunnerSession session;
  @override
  RunnerSession build() => session;
}

void main() {
  test('the backend sends kobo; a DeliveryJob holds naira (₦1,445 order, ₦200 pay)', () async {
    final [job] = await _repositoryServing([_backendJob]).listAvailable(token: 't');

    expect(job.totalAmount, 1445);
    expect(job.payoutAmount, 200);
  });

  test('koboToNaira', () {
    expect(koboToNaira(144500), 1445);
    expect(koboToNaira(20000), 200);
    expect(koboToNaira(0), 0);
  });

  testWidgets('Jobs → Available card shows ₦200 earnings and ₦1445 total, never the kobo values', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
          matchingRepositoryProvider.overrideWithValue(_repositoryServing([_backendJob])),
        ],
        child: const MaterialApp(home: RunnerJobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('₦200'), findsOneWidget);
    expect(find.text('₦1445'), findsOneWidget);
    expect(find.text('₦20000'), findsNothing);
    expect(find.text('₦144500'), findsNothing);
  });

  testWidgets('runner Home active card and the Earnings screen show the same real amounts', (tester) async {
    final [job] = await _repositoryServing([_backendJob]).listAvailable(token: 't');
    final session = RunnerSession(
      status: const RunnerStatus(availability: RunnerAvailability.online, isVerifiedRunner: true),
      activeDelivery: ActiveDelivery(job: job, status: DeliveryStage.accepted, orderItems: const [], orderNumber: '#24143924'),
      earnings: [
        EarningsRecord(
          deliveryId: job.id,
          amount: job.payoutAmount,
          completedAt: DateTime.now(),
          eateryName: job.eateryName,
          dropoffZone: job.dropoffZone,
        ),
      ],
    );
    Future<void> pump(Widget screen) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            runnerControllerProvider.overrideWith(() => _SeededRunner(session)),
            matchingRepositoryProvider.overrideWithValue(_repositoryServing(const [])),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    await pump(const RunnerHomeScreen());
    expect(find.text('₦200'), findsWidgets); // PAYOUT, and today's earnings
    expect(find.text('₦1445'), findsOneWidget); // ORDER TOTAL
    expect(find.textContaining('20000'), findsNothing);
    expect(find.textContaining('144500'), findsNothing);

    await pump(const EarningsScreen());
    expect(find.text('₦200'), findsWidgets);
    expect(find.textContaining('20000'), findsNothing);
  });
}
