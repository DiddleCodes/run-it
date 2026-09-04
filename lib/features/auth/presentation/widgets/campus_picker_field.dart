import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/campus_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_text_field.dart';

/// Task 26: no longer used at student/runner signup — a student's campus
/// is derived from their verified email domain, a runner's is admin-
/// assigned, and picking one here would silently contradict either (see
/// the Task 26 report). Its one remaining caller is the restaurant vendor
/// application wizard, where a selection is real, honest data now (Task
/// 27): backed by the real `GET /campuses` directory (not the old local
/// `kCampuses` stand-in), and sent to the backend as
/// `Vendor.requestedCampusId` — the applicant's own stated preference,
/// which pre-fills (never dictates) the admin's campus choice at approval.
class CampusPickerField extends StatelessWidget {
  const CampusPickerField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final CampusOption? selected;
  final ValueChanged<CampusOption> onChanged;
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

class _CampusSearchSheet extends ConsumerStatefulWidget {
  const _CampusSearchSheet({required this.onSelected});
  final ValueChanged<CampusOption> onSelected;

  @override
  ConsumerState<_CampusSearchSheet> createState() => _CampusSearchSheetState();
}

class _CampusSearchSheetState extends ConsumerState<_CampusSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final campuses = ref.watch(campusesProvider);

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
            child: campuses.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  "Couldn't load campuses. Check your connection and try again.",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              data: (list) {
                final filtered = list
                    .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(
                      'No campuses match that search.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.builder(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
