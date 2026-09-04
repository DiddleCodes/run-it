import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_paystack_plus/flutter_paystack_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/application/auth_controller.dart';
import '../../ordering/presentation/widgets/ordering_components.dart';
import '../../payout/application/payout_controller.dart';
import '../application/wallet_controller.dart';
import '../data/wallet_repository.dart';
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
    final balanceAsync = ref.watch(walletBalanceProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);
    final balance = balanceAsync.valueOrNull ?? 0;
    final transactions = transactionsAsync.valueOrNull ?? const <WalletTransaction>[];

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.read(walletBalanceProvider.notifier).refresh(),
            ref.read(walletTransactionsProvider.notifier).refresh(),
          ]),
          // CustomScrollView + SliverList.builder (Task 10 performance
          // audit): the header content above the transaction list is a
          // fixed handful of widgets, but the transactions themselves are
          // real, potentially-long backend data — a flat ListView(children:
          // [...transactions.map(...)]) built every row eagerly regardless
          // of scroll position. One lazy scrollable for the whole screen
          // avoids both that and the nested-scrollable-shrinkWrap trap.
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        loading: balanceAsync.isLoading && !balanceAsync.hasValue,
                        hidden: _balanceHidden,
                        onToggleHidden: () => setState(() => _balanceHidden = !_balanceHidden),
                        onAddFunds: _openAddFunds,
                        onWithdraw: _openWithdraw,
                      ),
                      if (balanceAsync.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            "Couldn't load your balance. Pull down to retry.",
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: AppColors.error),
                          ),
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
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                sliver: transactionsAsync.isLoading && !transactionsAsync.hasValue
                    ? const SliverToBoxAdapter(child: SkeletonList(count: 4))
                    : transactions.isEmpty
                    ? const SliverToBoxAdapter(child: _EmptyTransactions())
                    : SliverList.builder(
                        itemCount: transactions.length,
                        itemBuilder: (context, index) =>
                            _TransactionRow(transaction: transactions[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.loading,
    required this.hidden,
    required this.onToggleHidden,
    required this.onAddFunds,
    required this.onWithdraw,
  });
  final int balance;
  final bool loading;
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
              if (loading && !hidden)
                SkeletonBox(
                  width: 140,
                  height: 30,
                  baseColor: AppColors.onMaroon.withValues(alpha: 0.18),
                  shimmerColor: AppColors.onMaroon.withValues(alpha: 0.35),
                )
              else
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
    // Task 32: a withdrawal row can sit at 'pending' or resolve to
    // 'failed' (the wallet balance was already credited back by then —
    // see WebhooksService.applyVerifiedWithdrawalResult) — surfaced here
    // rather than silently showing a debit with no explanation for why the
    // current balance doesn't reflect it.
    final statusSuffix = switch (transaction.status) {
      'pending' => ' · Pending',
      'failed' => ' · Failed, refunded',
      _ => '',
    };
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
                  '${transaction.subtitle}$statusSuffix',
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

/// How many times to poll `GET /wallet/:userId/balance` after the Paystack
/// checkout UI closes, and how far apart — the webhook (not this client) is
/// the actual source of truth for whether the charge went through, so this
/// just waits for that to land rather than trusting Paystack's in-app
/// success/close callback as final. ~40s total gives a real webhook
/// delivery (typically sub-second to a few seconds) generous room without
/// leaving the sheet open indefinitely on a slow delivery.
const _balancePollAttempts = 20;
const _balancePollInterval = Duration(seconds: 2);

enum _AmountSheetPhase { form, launchingCheckout, confirmingPayment, result }

/// Add Funds is wired to the real Task 8b payments backend: it initializes
/// a Paystack transaction server-side, launches Paystack's hosted checkout
/// for it, then polls the real balance until the webhook-confirmed top-up
/// lands (see [_balancePollAttempts]) rather than trusting any client-side
/// "success" callback.
///
/// Withdraw (Task 32) is real too: it debits the wallet and initiates a
/// real Paystack transfer server-side (`WalletService.initiateWithdrawal`),
/// then polls the ledger row's own status the same way Add Funds polls the
/// balance — a withdrawal only shows as complete once the backend actually
/// confirms it, never on the request simply having been accepted.
class _AmountSheet extends ConsumerStatefulWidget {
  const _AmountSheet({required this.isWithdraw});
  final bool isWithdraw;

  @override
  ConsumerState<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends ConsumerState<_AmountSheet> {
  int? _selectedAmount;
  final _customController = TextEditingController();
  _AmountSheetPhase _phase = _AmountSheetPhase.form;
  int? _resolvedAmount;
  String? _errorMessage;
  bool _stillProcessing = false;
  bool _withdrawalFailed = false;
  bool _checkingPayoutAccount = false;

  @override
  void initState() {
    super.initState();
    if (widget.isWithdraw) _loadPayoutAccount();
  }

  Future<void> _loadPayoutAccount() async {
    setState(() => _checkingPayoutAccount = true);
    await ref.read(payoutControllerProvider.notifier).load();
    if (!mounted) return;
    setState(() => _checkingPayoutAccount = false);
  }

  Future<void> _addBankAccount() async {
    await context.push(AppRoutes.payoutAccount);
    if (!mounted) return;
    await _loadPayoutAccount();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int? get _amount {
    final custom = int.tryParse(_customController.text.trim());
    return custom != null && custom > 0 ? custom : _selectedAmount;
  }

  Future<void> _confirm() async {
    final amount = _amount;
    if (amount == null) return;

    if (widget.isWithdraw) {
      await _confirmWithdraw(amount);
      return;
    }

    final session = ref.read(authControllerProvider);
    if (session == null) return;
    final balanceBefore = ref.read(walletBalanceProvider).valueOrNull;

    setState(() {
      _phase = _AmountSheetPhase.launchingCheckout;
      _errorMessage = null;
    });

    try {
      final intent = await ref.read(walletRepositoryProvider).initializeFunding(
        userId: session.user.id,
        email: session.user.contact,
        amountNaira: amount,
        token: session.accessToken,
      );
      if (!mounted) return;

      await FlutterPaystackPlus.openPaystackPopup(
        context: context,
        customerEmail: session.user.contact,
        amount: (amount * 100).toString(),
        reference: intent.reference,
        authorizationUrl: intent.authorizationUrl,
        publicKey: paystackPublicKey,
        callBackUrl: paystackCallbackUrl,
        onSuccess: () {},
        onClosed: () {},
      );
      if (!mounted) return;

      setState(() => _phase = _AmountSheetPhase.confirmingPayment);
      final settledBalance = await _pollUntilBalanceIncreases(before: balanceBefore);
      if (!mounted) return;

      if (settledBalance == null) {
        setState(() {
          _phase = _AmountSheetPhase.result;
          _stillProcessing = true;
          _resolvedAmount = amount;
        });
        return;
      }
      ref.read(walletTransactionsProvider.notifier).refresh();
      setState(() {
        _phase = _AmountSheetPhase.result;
        _stillProcessing = false;
        _resolvedAmount = settledBalance - (balanceBefore ?? 0);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _AmountSheetPhase.form;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _AmountSheetPhase.form;
        _errorMessage = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  /// Returns the new balance once it's genuinely increased past [before],
  /// or `null` if it hasn't by the time polling gives up — a timeout, not a
  /// failure: the webhook may still land after this sheet is closed, and a
  /// later Wallet screen visit will simply show the real settled balance.
  Future<int?> _pollUntilBalanceIncreases({required int? before}) async {
    for (var attempt = 0; attempt < _balancePollAttempts; attempt++) {
      await Future<void>.delayed(_balancePollInterval);
      if (!mounted) return null;
      final current = await ref.read(walletBalanceProvider.notifier).refresh();
      if (before == null || current > before) return current;
    }
    return null;
  }

  /// Task 32: the wallet balance already left at request time (debited
  /// synchronously — see WalletService.initiateWithdrawal), so unlike Add
  /// Funds this can't poll for the balance to move; it polls the specific
  /// withdrawal row's own status instead, which the backend only ever
  /// flips once the real Paystack transfer.success/failed webhook lands
  /// (or ReconciliationService catches a lost one).
  Future<void> _confirmWithdraw(int amount) async {
    final session = ref.read(authControllerProvider);
    if (session == null) return;
    final balance = ref.read(walletBalanceProvider).valueOrNull ?? 0;
    if (amount > balance) {
      setState(() => _errorMessage = "You can't withdraw more than your ${naira(balance)} balance.");
      return;
    }

    setState(() {
      _phase = _AmountSheetPhase.launchingCheckout;
      _errorMessage = null;
    });

    try {
      final withdrawal = await ref
          .read(walletRepositoryProvider)
          .initiateWithdrawal(userId: session.user.id, amountNaira: amount, token: session.accessToken);
      if (!mounted) return;
      // The debit already happened — reflect it immediately rather than
      // waiting for the poll below to notice.
      ref.read(walletBalanceProvider.notifier).refresh();

      setState(() => _phase = _AmountSheetPhase.confirmingPayment);
      final outcome = await _pollUntilWithdrawalStatus(withdrawal.id);
      if (!mounted) return;

      ref.read(walletTransactionsProvider.notifier).refresh();
      if (outcome == 'failed') {
        // The backend already credited the balance back
        // (WebhooksService.applyVerifiedWithdrawalResult) — reflect that
        // real, restored balance rather than leaving the stale post-debit
        // one on screen underneath this result.
        ref.read(walletBalanceProvider.notifier).refresh();
      }
      setState(() {
        _phase = _AmountSheetPhase.result;
        _stillProcessing = outcome == null;
        _withdrawalFailed = outcome == 'failed';
        _resolvedAmount = amount;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _AmountSheetPhase.form;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _AmountSheetPhase.form;
        _errorMessage = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  /// Returns 'success', 'failed', or `null` if it's still 'pending' by the
  /// time polling gives up — same timeout-not-failure framing as
  /// [_pollUntilBalanceIncreases].
  Future<String?> _pollUntilWithdrawalStatus(String withdrawalId) async {
    final session = ref.read(authControllerProvider);
    if (session == null) return null;
    for (var attempt = 0; attempt < _balancePollAttempts; attempt++) {
      await Future<void>.delayed(_balancePollInterval);
      if (!mounted) return null;
      final transactions = await ref
          .read(walletRepositoryProvider)
          .getTransactions(userId: session.user.id, token: session.accessToken);
      for (final txn in transactions) {
        if (txn.id == withdrawalId && txn.status != 'pending') return txn.status;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _AmountSheetPhase.confirmingPayment) {
      return _ConfirmingPaymentState(isWithdraw: widget.isWithdraw);
    }
    if (_phase == _AmountSheetPhase.result) {
      return _ConfirmationState(
        amount: _resolvedAmount ?? 0,
        isWithdraw: widget.isWithdraw,
        stillProcessing: _stillProcessing,
        failed: _withdrawalFailed,
        onDone: () => Navigator.of(context).pop(),
      );
    }

    if (widget.isWithdraw && _checkingPayoutAccount) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final payoutAccount = widget.isWithdraw ? ref.watch(payoutControllerProvider) : null;
    if (widget.isWithdraw && payoutAccount == null) {
      return _NoPayoutAccountState(onAddAccount: _addBankAccount);
    }

    final launching = _phase == _AmountSheetPhase.launchingCheckout;
    final title = widget.isWithdraw ? 'Withdraw' : 'Add Funds';
    final balance = ref.watch(walletBalanceProvider).valueOrNull;
    final amountExceedsBalance = widget.isWithdraw && _amount != null && balance != null && _amount! > balance;
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
                ? 'Sent to ${payoutAccount!.maskedAccountNumber} — ${payoutAccount.bankName}.'
                : 'Pay securely with Paystack.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
          ),
          if (amountExceedsBalance) ...[
            const SizedBox(height: 10),
            Text(
              "That's more than your ${naira(balance)} balance.",
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.error),
            ),
          ] else if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.error),
            ),
          ],
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
              onPressed: (_amount == null || launching || amountExceedsBalance) ? null : _confirm,
              child: launching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.onMaroon,
                      ),
                    )
                  : Text(widget.isWithdraw ? 'Withdraw' : 'Add Funds'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmingPaymentState extends StatelessWidget {
  const _ConfirmingPaymentState({required this.isWithdraw});
  final bool isWithdraw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 40, 22, 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryMaroon,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isWithdraw ? 'Processing your withdrawal…' : 'Confirming payment…',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            "We're checking with Paystack — this only takes a moment.",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }
}

/// Task 32: shown in place of the amount form when a student hasn't
/// confirmed a bank account yet — reuses the same `PayoutAccountScreen`
/// (Task 8c Part B/25) restaurant and runner payouts already go through,
/// just reached from Withdraw instead of Profile > Payouts.
class _NoPayoutAccountState extends StatelessWidget {
  const _NoPayoutAccountState({required this.onAddAccount});
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.backgroundCream, shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_outlined, color: AppColors.primaryMaroon, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Add a bank account to withdraw',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: onBg, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            "We'll verify your details with your bank before saving.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
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
              onPressed: onAddAccount,
              child: const Text('Add bank account'),
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
    required this.stillProcessing,
    this.failed = false,
    required this.onDone,
  });
  final int amount;
  final bool isWithdraw;

  /// True when polling gave up before the balance actually moved — the
  /// payment may still be genuinely in flight (Paystack webhooks aren't
  /// always instant), so this is framed as "still confirming," never as a
  /// false-positive success or a false failure.
  final bool stillProcessing;

  /// Task 32: withdrawal-only — Paystack itself rejected/reversed the
  /// transfer after it was accepted. The backend already credited the
  /// wallet back (WebhooksService.applyVerifiedWithdrawalResult) by the
  /// time this ever renders, so this is reassurance, not a warning to act
  /// on.
  final bool failed;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final iconColor = failed ? AppColors.error : (stillProcessing ? AppColors.gold : AppColors.success);
    final iconBg = failed
        ? AppColors.error.withValues(alpha: 0.12)
        : (stillProcessing ? AppColors.goldTint : AppColors.successBackground);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(
              failed
                  ? Icons.close_rounded
                  : (stillProcessing ? Icons.hourglass_top_rounded : CupertinoIcons.checkmark_alt),
              color: iconColor,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            failed
                ? 'Withdrawal failed'
                : (stillProcessing
                      ? 'Still confirming your payment'
                      : (isWithdraw ? '${naira(amount)} withdrawn' : '${naira(amount)} added')),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? "Your bank rejected the transfer. The ${naira(amount)} is back in your wallet — nothing was lost."
                : (stillProcessing
                      ? "This can take a little longer than usual. Check back on your Wallet in a minute — we'll reflect it as soon as it lands."
                      : 'Your wallet balance has been updated.'),
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
