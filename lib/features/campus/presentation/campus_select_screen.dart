import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';

class _Campus {
  const _Campus(this.name, this.initials);
  final String name;
  final String initials;
}

const _campuses = [
  _Campus('University of Ibadan', 'UI'),
  _Campus('Bingham University', 'BU'),
  _Campus('Obafemi Awolowo University', 'OA'),
  _Campus('Covenant University', 'CU'),
];

class CampusSelectScreen extends StatefulWidget {
  const CampusSelectScreen({super.key});

  @override
  State<CampusSelectScreen> createState() => _CampusSelectScreenState();
}

class _CampusSelectScreenState extends State<CampusSelectScreen> {
  String _query = '';
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBg = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final filtered = _campuses
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(height: 8),
              Text(
                'Where are you based?',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: onBg),
              ),
              const SizedBox(height: 6),
              Text(
                'This helps us match you with stores and runners nearby.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: 24),
              AppTextField(
                hintText: 'Search for your campus',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 20, right: 12),
                  child: Icon(Icons.location_on_outlined, size: 20),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final campus = filtered[index];
                    final selected = _selected == campus.name;

                    return _CampusTile(
                      campus: campus,
                      selected: selected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = campus.name);
                      },
                    );
                  },
                ),
              ),
              Text(
                'You can request deliveries and start earning anytime — switch modes from your profile after signup.',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: secondary),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Continue',
                onPressed: _selected == null ? null : () {},
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampusTile extends StatelessWidget {
  const _CampusTile({
    required this.campus,
    required this.selected,
    required this.onTap,
  });

  final _Campus campus;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final onBg = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.emphasized,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.amber : border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: isDark ? AppColors.darkShadow : AppColors.lightShadow,
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.amber.withValues(alpha: selected ? 1 : 0.14),
              ),
              child: Text(
                campus.initials,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? (isDark ? AppColors.darkOnAmber : AppColors.lightOnAmber)
                      : AppColors.amber,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                campus.name,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: onBg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: AppMotion.base,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: selected
                  ? Container(
                      key: const ValueKey('checked'),
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: isDark
                            ? AppColors.darkOnAmber
                            : AppColors.lightOnAmber,
                      ),
                    )
                  : Container(
                      key: const ValueKey('unchecked'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: border, width: 1.5),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
