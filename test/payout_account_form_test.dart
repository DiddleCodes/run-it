import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/features/payout/application/payout_controller.dart';
import 'package:run_it/features/payout/domain/payout_models.dart';
import 'package:run_it/features/payout/presentation/widgets/payout_account_form.dart';

/// Never touches the network — [verifyAndSave] is overridden to return
/// (or throw) exactly what a real `POST /payout-accounts` call would, so
/// this file tests the form's own verify -> confirm state machine, not
/// Task 8b's backend.
class _SucceedingPayoutController extends PayoutController {
  @override
  Future<List<Bank>> fetchBanks() async => const [Bank(name: 'GTBank', code: '058')];

  @override
  Future<PayoutAccount> verifyAndSave({
    required Bank bank,
    required String accountNumber,
  }) async {
    final account = PayoutAccount(
      bankCode: bank.code,
      bankName: bank.name,
      accountNumber: accountNumber,
      accountName: 'Kemi Adebayo',
    );
    state = account;
    return account;
  }
}

class _FailingPayoutController extends PayoutController {
  @override
  Future<List<Bank>> fetchBanks() async => const [Bank(name: 'GTBank', code: '058')];

  @override
  Future<PayoutAccount> verifyAndSave({
    required Bank bank,
    required String accountNumber,
  }) async {
    throw const ApiException(422, 'Could not verify bank account details with Paystack');
  }
}

Future<void> _fillAndTapVerify(WidgetTester tester) async {
  await tester.tap(find.text('Choose your bank'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GTBank'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '0123454417');
  await tester.tap(find.text('Verify'));
  await tester.pump();
  // A real (advancing) duration, not a bare pump() — flushes the
  // zero-duration Timer flutter_animate schedules to kick off the
  // just-mounted confirmation/error card's .animate() effects, which a
  // duration-less pump leaves pending at test teardown.
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('PayoutAccountForm — verify -> confirm flow', () {
    testWidgets(
      'shows the resolved account holder\'s name for confirmation before calling onSaved',
      (tester) async {
        PayoutAccount? saved;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              payoutControllerProvider.overrideWith(() => _SucceedingPayoutController()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PayoutAccountForm(onSaved: (account) => saved = account),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await _fillAndTapVerify(tester);

        // Resolved for confirmation — not yet handed back to the caller.
        expect(find.text('Is this you?'), findsOneWidget);
        expect(find.text('Kemi Adebayo'), findsOneWidget);
        expect(find.textContaining('•••• 4417'), findsOneWidget);
        expect(saved, isNull);

        await tester.tap(find.text("Yes, that's me"));
        await tester.pump();

        expect(saved, isNotNull);
        expect(saved!.accountName, 'Kemi Adebayo');
        expect(saved!.bankCode, '058');
      },
    );

    testWidgets(
      '"Not you?" returns to the editable fields without calling onSaved',
      (tester) async {
        PayoutAccount? saved;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              payoutControllerProvider.overrideWith(() => _SucceedingPayoutController()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PayoutAccountForm(onSaved: (account) => saved = account),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _fillAndTapVerify(tester);

        await tester.tap(find.text('Not you? Edit the details'));
        await tester.pump();

        expect(find.text('Is this you?'), findsNothing);
        expect(find.text('Verify'), findsOneWidget);
        expect(saved, isNull);
      },
    );

    testWidgets(
      'shows the backend\'s specific rejection, not an ambiguous failure, and lets the user retry',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              payoutControllerProvider.overrideWith(() => _FailingPayoutController()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PayoutAccountForm(onSaved: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await _fillAndTapVerify(tester);

        expect(
          find.text('Could not verify bank account details with Paystack'),
          findsOneWidget,
        );
        expect(find.textContaining('Something went wrong'), findsNothing);
        // Still editable — the bank/account-number fields are right there
        // to fix and retry, not a dead end.
        expect(find.text('GTBank'), findsOneWidget);
        expect(find.text('Verify'), findsOneWidget);
      },
    );
  });
}
