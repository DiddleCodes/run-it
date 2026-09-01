import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/auth_models.dart';

/// A searchable campus selector — deliberately not free text, since a
/// typed-in campus name can't be used to scope queries later. Opens a
/// bottom sheet with a search field over the fixed campus directory.
class CampusPickerField extends StatelessWidget {
  const CampusPickerField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final Campus? selected;
  final ValueChanged<Campus> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const muted = AppColors.mutedText;
    const surface = AppColors.surfaceCard;
    const accent = AppColors.primaryMaroon;
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: selected == null
              ? 'Choose your campus'
              : 'Campus: ${selected!.name}',
          child: GestureDetector(
            onTap: () => _openPicker(context),
            child: Container(
              // Padding-driven height, not a fixed one — a long campus
              // name (there's no length cap on `Campus.name`) shouldn't be
              // able to overflow a hardcoded box at larger Dynamic Type
              // scale; maxLines/ellipsis below keeps it visually a single
              // "field" regardless.
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.6), surface],
                  stops: const [0.0, 0.4],
                ),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: hasError ? AppColors.error : AppColors.borderSubtle,
                  width: hasError ? 1.5 : 1,
                ),
                boxShadow: AppElevation.card(false),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, size: 22, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selected?.name ?? 'Choose your campus',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: selected == null ? muted : onBg),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentRose.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.expand_more_rounded,
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
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _CampusSearchSheet(onSelected: onChanged),
    );
  }
}

class _CampusSearchSheet extends StatefulWidget {
  const _CampusSearchSheet({required this.onSelected});
  final ValueChanged<Campus> onSelected;

  @override
  State<_CampusSearchSheet> createState() => _CampusSearchSheetState();
}

class _CampusSearchSheetState extends State<_CampusSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final filtered = kCampuses
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
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
            'Choose your campus',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: onBg),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            hintText: 'Search campuses',
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
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Text(
                      'No campuses match that search.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final campus = filtered[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(campus.name, style: TextStyle(color: onBg)),
                        onTap: () {
                          widget.onSelected(campus);
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
