import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/presentation/widgets/validated_field.dart';
import '../../application/payout_controller.dart';
import '../../domain/payout_models.dart';
import 'bank_picker_field.dart';

/// PART A's shared component — bank picker + account number + a "Verify"
/// step that resolves the real account holder's name via the backend
/// before anything is treated as final, reused verbatim by Runner
/// Profile's Payouts screen (Part B) and the vendor wizard's Payout
/// Details step (Part C).
///
/// The backend (Task 8b) couples verify-via-Paystack and persist into one
/// atomic `POST /payout-accounts` call, so by the time the resolved name is
/// on screen it has already been saved server-side. The "Is this you?"
/// step below is therefore a client-side confirmation of what just
/// happened, not a second network round trip — [onSaved] fires the moment
/// the user acknowledges it, and "Not you?" simply lets them retype and
/// re-submit (a fresh, equally safe upsert).
class PayoutAccountForm extends ConsumerStatefulWidget {
  const PayoutAccountForm({
    super.key,
    this.initialAccount,
    required this.onSaved,
  });

  /// Prefills the bank/account-number fields when editing an already-saved
  /// account — the form still always starts on the editable fields, not a
  /// stale confirmation, since only a fresh resolve can be trusted.
  final PayoutAccount? initialAccount;
  final ValueChanged<PayoutAccount> onSaved;

  @override
  ConsumerState<PayoutAccountForm> createState() => _PayoutAccountFormState();
}

class _PayoutAccountFormState extends ConsumerState<PayoutAccountForm> {
  late Bank? _bank = widget.initialAccount?.bank;
  late final _accountNumberController = TextEditingController(
    text: widget.initialAccount?.accountNumber ?? '',
  );
  final _accountNumberKey = GlobalKey<ValidatedFieldState>();
  String? _bankError;
  bool _verifying = false;
  String? _verifyError;
  PayoutAccount? _resolved;

  @override
  void dispose() {
    _accountNumberController.dispose();
    super.dispose();
  }

  String? _validateAccountNumber(String value) {
    final digits = value.trim();
    if (digits.length != 10 || int.tryParse(digits) == null) {
      return 'Enter a valid 10-digit account number.';
    }
    return null;
  }

  Future<void> _verify() async {
    final bank = _bank;
    final numberOk = _accountNumberKey.currentState?.validateNow() ?? false;
    setState(() => _bankError = bank == null ? 'Choose your bank.' : null);
    if (bank == null || !numberOk) return;

    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    try {
      final account = await ref.read(payoutControllerProvider.notifier).verifyAndSave(
        bank: bank,
        accountNumber: _accountNumberController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _resolved = account;
        _verifying = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifyError = e.message;
        _verifying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifyError = "Couldn't reach the server — check your connection and try again.";
        _verifying = false;
      });
    }
  }

  void _editAgain() => setState(() => _resolved = null);

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (resolved != null) {
      return _ConfirmationCard(
        account: resolved,
        onConfirm: () => widget.onSaved(resolved),
        onEditAgain: _editAgain,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BankPickerField(
          selected: _bank,
          errorText: _bankError,
          onChanged: (bank) => setState(() {
            _bank = bank;
            _bankError = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        ValidatedField(
          key: _accountNumberKey,
          controller: _accountNumberController,
          hintText: '10-digit account number',
          keyboardType: TextInputType.number,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 20, right: 12),
            child: Icon(Icons.tag_rounded, size: 22, color: AppColors.primaryMaroon),
          ),
          validator: _validateAccountNumber,
        ),
        if (_verifyError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorBanner(message: _verifyError!),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Verify',
          loading: _verifying,
          onPressed: _verify,
        ),
      ],
    );
  }
}

/// A clear, specific rejection — never an ambiguous "something went
/// wrong". [message] is either the backend's own rejection text (e.g.
/// Paystack couldn't resolve the pair) or an explicit connectivity note.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentRose,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: AppColors.inkText, height: 1.4),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).moveY(begin: 6, end: 0);
  }
}

/// "Is this you? — [Name]" — the standard pattern for catching a mistyped
/// account number before money ever depends on it, shown once the backend
/// has actually resolved a real account holder's name via Paystack.
class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.account,
    required this.onConfirm,
    required this.onEditAgain,
  });

  final PayoutAccount account;
  final VoidCallback onConfirm;
  final VoidCallback onEditAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.raised(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.successBackground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 30),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Is this you?',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 6),
          Text(
            account.accountName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.primaryMaroon, fontSize: 21),
          ),
          const SizedBox(height: 4),
          Text(
            '${account.bankName} · ${account.maskedAccountNumber}',
            style: AppTypography.mono(fontSize: 13, color: AppColors.mutedText),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: "Yes, that's me", onPressed: onConfirm),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: onEditAgain,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Not you? Edit the details',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: AppColors.primaryMaroon, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).scale(begin: const Offset(.96, .96));
  }
}
