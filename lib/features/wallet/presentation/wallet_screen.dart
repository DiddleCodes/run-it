import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../ordering/presentation/widgets/ordering_components.dart';
import '../application/wallet_controller.dart';
import '../domain/wallet_models.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _balanceHidden = false;

  void _openAddFunds() => _openAmountSheet(isWithdraw: false);
  void _openWithdraw() => _openAmountSheet(isWithdraw: true);

  void _openAmountSheet({required bool isWithdraw}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _AmountSheet(isWithdraw: isWithdraw),
    );
  }

  void _openTransfer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const _TransferStubSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(walletBalanceProvider);
    final transactions = ref.watch(walletTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 32),
          children: [
            Text(
              'Wallet',
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(color: AppColors.inkText, fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(
              'Add funds, track spending, enjoy more.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 18),
            _BalanceCard(
              balance: balance,
              hidden: _balanceHidden,
              onToggleHidden: () => setState(() => _balanceHidden = !_balanceHidden),
              onAddFunds: _openAddFunds,
              onWithdraw: _openWithdraw,
            ),
            const SizedBox(height: 16),
            _ReferralBanner(
              onTap: () => ref
                  .read(appNotificationProvider.notifier)
                  .info('Referrals are coming soon.'),
            ),
            const SizedBox(height: 24),
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.inkText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: CupertinoIcons.add_circled_solid,
                    label: 'Add Funds',
                    onTap: _openAddFunds,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: CupertinoIcons.arrow_2_squarepath,
                    label: 'Transfer',
                    onTap: _openTransfer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: CupertinoIcons.star_fill,
                    label: 'Rewards',
                    onTap: () => ref
                        .read(appNotificationProvider.notifier)
                        .info('Rewards are coming soon.'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: CupertinoIcons.clock_fill,
                    label: 'History',
                    onTap: () => ref
                        .read(appNotificationProvider.notifier)
                        .info('Full transaction history is coming soon.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent transactions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.inkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Full transaction history is coming soon.'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (transactions.isEmpty)
              const _EmptyTransactions()
            else
              ...transactions.map((txn) => _TransactionRow(transaction: txn)),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.hidden,
    required this.onToggleHidden,
    required this.onAddFunds,
    required this.onWithdraw,
  });
  final int balance;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final VoidCallback onAddFunds;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryMaroon, AppColors.primaryMaroonDeep],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryMaroon.withValues(alpha: .32),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // A decorative wallet/cash motif, faint in the corner — there's
          // no illustration asset for this yet, so this is a deliberately
          // simple vector placeholder rather than a fake photo.
          Positioned(
            right: -18,
            bottom: -18,
            child: Opacity(
              opacity: .14,
              child: Icon(
                CupertinoIcons.money_dollar_circle_fill,
                size: 140,
                color: AppColors.onMaroon,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Available Balance',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: AppColors.onMaroon.withValues(alpha: .78)),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onToggleHidden,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        hidden ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill,
                        size: 16,
                        color: AppColors.onMaroon.withValues(alpha: .78),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                hidden ? '₦••••••' : naira(balance),
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(color: AppColors.onMaroon, fontSize: 34),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.primaryMaroonDeep,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      onPressed: onAddFunds,
                      child: const Text('Add Funds'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onMaroon,
                        side: BorderSide(color: AppColors.onMaroon.withValues(alpha: .5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      onPressed: onWithdraw,
                      child: const Text('Withdraw'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralBanner extends StatelessWidget {
  const _ReferralBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldTint,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.gift_fill, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get ₦500 bonus',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Refer a friend and get rewarded.',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, color: AppColors.mutedText, size: 16),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryMaroon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});
  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final credit = transaction.kind == WalletTransactionKind.credit;
    final amountColor = credit ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: credit ? AppColors.successBackground : AppColors.accentRose,
              shape: BoxShape.circle,
            ),
            child: Icon(
              credit ? CupertinoIcons.arrow_down_left : CupertinoIcons.bag_fill,
              size: 18,
              color: credit ? AppColors.success : AppColors.primaryMaroon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.inkText),
                ),
                Text(
                  transaction.subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${credit ? '+' : '-'}${naira(transaction.amount)}',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
              ),
              Text(
                _formatWhen(transaction.occurredAt),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatWhen(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inHours < 24) return DateFormat('h:mm a').format(time);
  return DateFormat('MMM d').format(time);
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          'No transactions yet.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
        ),
      ),
    );
  }
}

const _quickAmounts = [500, 1000, 2000, 5000];

/// Add-Funds / Withdraw amount picker. STUB: on confirm this only updates
/// [walletBalanceProvider]'s local state and records a demo transaction —
/// no real payment-gateway call happens here (see the doc comment on
/// [WalletBalanceController]).
class _AmountSheet extends ConsumerStatefulWidget {
  const _AmountSheet({required this.isWithdraw});
  final bool isWithdraw;

  @override
  ConsumerState<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends ConsumerState<_AmountSheet> {
  int? _selectedAmount;
  final _customController = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int? get _amount {
    final custom = int.tryParse(_customController.text.trim());
    return custom != null && custom > 0 ? custom : _selectedAmount;
  }

  void _confirm() {
    final amount = _amount;
    if (amount == null) return;
    final controller = ref.read(walletBalanceProvider.notifier);
    if (widget.isWithdraw) {
      final ok = controller.mockWithdraw(amount);
      if (!ok) {
        ref
            .read(appNotificationProvider.notifier)
            .warning('That’s more than your available balance.');
        return;
      }
      ref.read(walletTransactionsProvider.notifier).recordMockWithdrawal(amount);
    } else {
      controller.mockAddFunds(amount);
      ref.read(walletTransactionsProvider.notifier).recordMockTopUp(amount);
    }
    setState(() => _confirmed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return _ConfirmationState(
        amount: _amount ?? 0,
        isWithdraw: widget.isWithdraw,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    final title = widget.isWithdraw ? 'Withdraw' : 'Add Funds';
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isWithdraw
                ? 'This is a stub — it only updates your local balance.'
                : 'This is a stub — no real payment is processed yet.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final amount in _quickAmounts)
                _AmountChip(
                  label: naira(amount),
                  selected: _selectedAmount == amount && _customController.text.isEmpty,
                  onTap: () => setState(() {
                    _selectedAmount = amount;
                    _customController.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Or enter a custom amount'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: AppColors.onMaroon,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _amount == null ? null : _confirm,
              child: Text(widget.isWithdraw ? 'Withdraw' : 'Add Funds'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryMaroon : AppColors.backgroundCream,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primaryMaroon : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? AppColors.onMaroon : AppColors.inkText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ConfirmationState extends StatelessWidget {
  const _ConfirmationState({
    required this.amount,
    required this.isWithdraw,
    required this.onDone,
  });
  final int amount;
  final bool isWithdraw;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.successBackground, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.checkmark_alt, color: AppColors.success, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            isWithdraw ? '${naira(amount)} withdrawn' : '${naira(amount)} added',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 6),
          Text(
            'Your wallet balance has been updated.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: AppColors.onMaroon,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transfer is a lighter stub than Add Funds/Withdraw — the task calls it
/// out as needing to be "clearly stubbed", not necessarily wired to real
/// balance state. Collects a recipient + amount but only ever confirms
/// locally; nothing is sent anywhere.
class _TransferStubSheet extends ConsumerStatefulWidget {
  const _TransferStubSheet();

  @override
  ConsumerState<_TransferStubSheet> createState() => _TransferStubSheetState();
}

class _TransferStubSheetState extends ConsumerState<_TransferStubSheet> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transfer',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'This is a stub — transfers aren’t sent anywhere yet.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _recipientController,
            decoration: const InputDecoration(hintText: 'Recipient username or email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Amount'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: AppColors.onMaroon,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ref
                    .read(appNotificationProvider.notifier)
                    .success('Transfer flow is a stub for now — nothing was sent.');
              },
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
