import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../application/payout_controller.dart';
import '../domain/payout_models.dart';
import 'widgets/payout_account_form.dart';

/// Runner Profile's "Payouts" row (Task 8c Part B) — a real Add/Edit Payout
/// Account screen built on the shared [PayoutAccountForm]. Shows the
/// already-saved account (masked) with an Edit path back into the form
/// when one exists; drops straight into the form when it doesn't.
class PayoutAccountScreen extends ConsumerStatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  ConsumerState<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends ConsumerState<PayoutAccountScreen> {
  bool _loading = true;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(payoutControllerProvider.notifier).load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _editing = ref.read(payoutControllerProvider) == null;
    });
  }

  void _handleSaved(PayoutAccount account) {
    ref.read(appNotificationProvider.notifier).success('Payout account saved.');
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(payoutControllerProvider);
    const onBg = AppColors.inkText;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Payout Account',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: onBg, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: _editing || account == null
                            ? _EditForm(initialAccount: account, onSaved: _handleSaved)
                            : _SavedAccountSummary(
                                account: account,
                                onEdit: () => setState(() => _editing = true),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({required this.initialAccount, required this.onSaved});
  final PayoutAccount? initialAccount;
  final ValueChanged<PayoutAccount> onSaved;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryMaroon, AppColors.primaryMaroonDeep],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppElevation.raised(false),
            ),
            child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 34),
          ).animate().fadeIn(duration: 280.ms).scale(begin: const Offset(.85, .85)),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Where should we send your money?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(color: onBg, fontSize: 23),
        ),
        const SizedBox(height: 6),
        Text(
          "We'll verify these details with your bank before saving.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        PayoutAccountForm(initialAccount: initialAccount, onSaved: onSaved),
      ],
    );
  }
}

class _SavedAccountSummary extends StatelessWidget {
  const _SavedAccountSummary({required this.account, required this.onEdit});
  final PayoutAccount account;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    final rows = <(String, String)>[
      ('Bank', account.bankName),
      ('Account number', account.maskedAccountNumber),
      ('Account name', account.accountName),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.card(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_rounded, size: 17, color: AppColors.success),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Payout account',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg),
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                    'Edit',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: AppColors.primaryMaroon, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.borderSubtle),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: secondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: onBg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
