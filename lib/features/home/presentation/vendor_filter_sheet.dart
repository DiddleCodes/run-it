import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../ordering/application/ordering_providers.dart';
import '../../ordering/domain/vendor_filters.dart';
import '../../../core/utils/money.dart';

/// Opens the Home filter sheet. Choices only apply on "Show results", so
/// the list doesn't refetch on every tap.
Future<void> showVendorFilterSheet(BuildContext context) {
  // Otherwise closing the sheet hands focus back to the search field and
  // the keyboard pops up over the results just filtered.
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const VendorFilterSheet(),
  );
}

class VendorFilterSheet extends ConsumerStatefulWidget {
  const VendorFilterSheet({super.key});

  @override
  ConsumerState<VendorFilterSheet> createState() => _VendorFilterSheetState();
}

class _VendorFilterSheetState extends ConsumerState<VendorFilterSheet> {
  late var _draft = ref.read(vendorFiltersProvider);

  void _apply() {
    ref.read(vendorFiltersProvider.notifier).state = _draft;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 20, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Filters', style: textTheme.headlineSmall?.copyWith(color: AppColors.inkText)),
                ),
                TextButton(
                  onPressed: _draft.isDefault ? null : () => setState(() => _draft = const VendorFilters()),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryMaroon),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Sort by'),
            _Options(
              children: [
                for (final sort in VendorSort.values)
                  _Option(
                    label: sort.label,
                    selected: _draft.sort == sort,
                    onTap: () => setState(() => _draft = _draft.copyWith(sort: sort)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Rating'),
            _Options(
              children: [
                _Option(
                  label: 'Any',
                  selected: _draft.minRating == null,
                  onTap: () => setState(() => _draft = _draft.copyWith(minRating: () => null)),
                ),
                for (final rating in VendorFilters.ratingOptions)
                  _Option(
                    label: '★ ${rating.toStringAsFixed(1)}+',
                    selected: _draft.minRating == rating,
                    onTap: () => setState(() => _draft = _draft.copyWith(minRating: () => rating)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Has items under'),
            _Options(
              children: [
                _Option(
                  label: 'Any price',
                  selected: _draft.maxPriceNaira == null,
                  onTap: () => setState(() => _draft = _draft.copyWith(maxPriceNaira: () => null)),
                ),
                for (final price in VendorFilters.priceOptions)
                  _Option(
                    label: naira(price),
                    selected: _draft.maxPriceNaira == price,
                    onTap: () => setState(() => _draft = _draft.copyWith(maxPriceNaira: () => price)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Show results', onPressed: _apply),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.mutedText),
    ),
  );
}

class _Options extends StatelessWidget {
  const _Options({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: children);
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryMaroon : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.primaryMaroon : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.onMaroon : AppColors.inkText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
