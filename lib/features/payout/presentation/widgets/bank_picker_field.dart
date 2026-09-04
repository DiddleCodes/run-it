import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../application/payout_controller.dart';
import '../../domain/payout_models.dart';

/// A searchable bank selector — same trigger-field-opens-a-bottom-sheet
/// shape as [CampusPickerField], just backed by an async bank list (Task
/// 8b's `GET /payout-accounts/banks`, proxying Paystack's List Banks)
/// instead of a fixed local directory.
class BankPickerField extends ConsumerWidget {
  const BankPickerField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final Bank? selected;
  final ValueChanged<Bank> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const muted = AppColors.mutedText;
    const surface = AppColors.surfaceCard;
    const accent = AppColors.primaryMaroon;
    final hasError = errorText != null;
    final banksAsync = ref.watch(banksProvider);

    String placeholder() => switch (banksAsync) {
      AsyncData() => 'Choose your bank',
      AsyncError() => "Couldn't load banks — tap to retry",
      _ => 'Loading banks…',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: selected == null ? 'Choose your bank' : 'Bank: ${selected!.name}',
          child: GestureDetector(
            onTap: () => _handleTap(context, ref, banksAsync),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.ml, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.6), surface],
                  stops: const [0.0, 0.4],
                ),
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(
                  color: hasError ? AppColors.error : AppColors.borderSubtle,
                  width: hasError ? 1.5 : 1,
                ),
                boxShadow: AppElevation.card(false),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_rounded, size: 22, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selected?.name ?? placeholder(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: selected == null ? muted : onBg),
                    ),
                  ),
                  if (banksAsync.isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accentRose.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        banksAsync.hasError
                            ? Icons.refresh_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, AsyncValue<List<Bank>> banksAsync) {
    if (banksAsync.isLoading) return;
    if (banksAsync.hasError) {
      ref.invalidate(banksProvider);
      return;
    }
    final banks = banksAsync.valueOrNull ?? const [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BankSearchSheet(banks: banks, onSelected: onChanged),
    );
  }
}

class _BankSearchSheet extends StatefulWidget {
  const _BankSearchSheet({required this.banks, required this.onSelected});
  final List<Bank> banks;
  final ValueChanged<Bank> onSelected;

  @override
  State<_BankSearchSheet> createState() => _BankSearchSheetState();
}

class _BankSearchSheetState extends State<_BankSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final filtered = widget.banks
        .where((b) => b.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your bank',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: onBg),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            hintText: 'Search banks',
            autofocus: true,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 20, right: 12),
              child: Icon(Icons.search_rounded, size: 20),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(
                      'No banks match that search.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final bank = filtered[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(bank.name, style: const TextStyle(color: onBg)),
                        onTap: () {
                          widget.onSelected(bank);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
