import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/vendors_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_spinner.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/vendor_dashboard_models.dart';

/// A searchable category selector — same trigger-field-opens-a-bottom-sheet
/// shape as [BankPickerField], backed by the backend's controlled vendor
/// category vocabulary (`GET /vendors/categories`) instead of a fixed local
/// enum. Picking from a fetched list (rather than typing free text) is what
/// keeps "Nigerian Food"/"nigerian food"/"Naija Dishes" from ever becoming
/// separate, un-mergeable category chips as more vendors sign up.
class CategoryPickerField extends ConsumerWidget {
  const CategoryPickerField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final String? selected;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const muted = AppColors.mutedText;
    const surface = AppColors.surfaceCard;
    const accent = AppColors.primaryMaroon;
    final hasError = errorText != null;
    final categoriesAsync = ref.watch(vendorCategoriesProvider);

    String placeholder() => switch (categoriesAsync) {
      AsyncData() => 'Choose a category',
      AsyncError() => "Couldn't load categories — tap to retry",
      _ => 'Loading categories…',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: selected == null ? 'Choose a category' : 'Category: $selected',
          child: GestureDetector(
            onTap: () => _handleTap(context, ref, categoriesAsync),
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
                  const Icon(Icons.restaurant_menu_rounded, size: 22, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selected ?? placeholder(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: selected == null ? muted : onBg),
                    ),
                  ),
                  if (categoriesAsync.isLoading)
                    const AppSpinner(size: 18, strokeWidth: 2)
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
                        categoriesAsync.hasError
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

  void _handleTap(BuildContext context, WidgetRef ref, AsyncValue<List<VendorCategoryOption>> categoriesAsync) {
    if (categoriesAsync.isLoading) return;
    if (categoriesAsync.hasError) {
      ref.invalidate(vendorCategoriesProvider);
      return;
    }
    final categories = categoriesAsync.valueOrNull ?? const [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySearchSheet(categories: categories, onSelected: onChanged),
    );
  }
}

class _CategorySearchSheet extends StatefulWidget {
  const _CategorySearchSheet({required this.categories, required this.onSelected});
  final List<VendorCategoryOption> categories;
  final ValueChanged<String> onSelected;

  @override
  State<_CategorySearchSheet> createState() => _CategorySearchSheetState();
}

class _CategorySearchSheetState extends State<_CategorySearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final filtered = widget.categories
        .where((c) => c.label.toLowerCase().contains(_query.toLowerCase()))
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
            'Choose a category',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: onBg),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            hintText: 'Search categories',
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
                      'No categories match that search.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final category = filtered[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(category.label, style: const TextStyle(color: onBg)),
                        onTap: () {
                          widget.onSelected(category.label);
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
