import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../ordering/presentation/widgets/ordering_components.dart' show naira;

/// Task 47: the runner's "mark as paid" confirmation for a Pay on Delivery
/// order — pushed before `verify-delivery` is ever called for one (see
/// RunnerScanScreen._completeScan), since the backend hard-requires this
/// figure for a Pay on Delivery order's delivery verification to succeed
/// at all (OrdersService.verifyDelivery's own doc comment). Pops with the
/// kobo amount actually collected, or `null` if the runner backs out —
/// either way, nothing is sent to the backend from this screen itself.
///
/// A mismatch isn't a separate "report a problem" flow here: whatever
/// figure is entered travels straight into the same verify-delivery call,
/// and the backend itself opens a real Dispute if it doesn't match the
/// order total (see CashCollectionDebt's own schema doc comment) — this
/// screen's only job is collecting an honest number, not deciding what to
/// do about a mismatch.
class CashCollectionScreen extends StatefulWidget {
  const CashCollectionScreen({super.key, required this.orderTotalKobo});
  final int orderTotalKobo;

  @override
  State<CashCollectionScreen> createState() => _CashCollectionScreenState();
}

class _CashCollectionScreenState extends State<CashCollectionScreen> {
  bool _reportingMismatch = false;
  late final _amountController = TextEditingController(
    text: (widget.orderTotalKobo ~/ 100).toString(),
  );

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _confirmExact() => Navigator.of(context).pop(widget.orderTotalKobo);

  void _confirmReported() {
    final naira = int.tryParse(_amountController.text.trim());
    if (naira == null || naira < 0) return;
    Navigator.of(context).pop(naira * 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collect payment')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.goldTint, shape: BoxShape.circle),
                child: const Icon(Icons.payments_outlined, size: 30, color: AppColors.primaryMaroonDeep),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'This is a cash order',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.inkText),
              ),
              const SizedBox(height: 6),
              Text(
                'Collect the full amount from the student before confirming delivery.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  children: [
                    Text(
                      'Amount to collect',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      naira(widget.orderTotalKobo ~/ 100),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(color: AppColors.inkText, fontSize: 32),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (!_reportingMismatch) ...[
                PrimaryButton(
                  label: 'Collected ${naira(widget.orderTotalKobo ~/ 100)} — mark as paid',
                  onPressed: _confirmExact,
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => setState(() => _reportingMismatch = true),
                  child: const Text("I collected a different amount"),
                ),
              ] else ...[
                Text(
                  'What did you actually collect?',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.inkText),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "If this doesn't match the order total, we'll flag it for review automatically.",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  leadingText: '₦',
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'Confirm amount', onPressed: _confirmReported),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => setState(() => _reportingMismatch = false),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
