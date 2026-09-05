import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/campus_repository.dart';
import '../../../core/network/vendors_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../vendor/domain/vendor_dashboard_models.dart' show VendorCategoryOption;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/route_line.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/application/auth_controller.dart';
import '../../ordering/application/ordering_providers.dart';
import '../../ordering/domain/ordering_models.dart';
import '../../ordering/presentation/widgets/ordering_components.dart' show MenuImagePlaceholder;

/// Task 14/15: the backend's controlled category vocabulary (`GET
/// /vendors/categories`) — every vendor's own category is validated
/// against this same list at signup, so a chip here is always something a
/// vendor could actually be registered under, never a fragmented
/// near-duplicate. Shows every category, not just ones with a vendor in
/// them yet — an empty one just renders `_NoVendorsState`'s "No vendors in
/// this category yet" rather than the chip not existing at all.

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final _searchController = TextEditingController(text: ref.read(vendorSearchQueryProvider));
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // A keystroke-per-request would spam GET /vendors — this waits for a
  // short pause in typing before actually updating the shared search
  // query provider that drives the network fetch.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(vendorSearchQueryProvider.notifier).state = value;
    });
  }

  Future<void> _orderNow() async {
    final vendors = await ref.read(campusEateriesProvider.future);
    if (!mounted) return;
    if (vendors.isEmpty) {
      _notify(context, 'No vendors are available right now — check back soon.');
      return;
    }
    _openMenu(vendors.first.id);
  }

  void _openMenu(String vendorId) {
    ref.read(selectedVendorIdProvider.notifier).state = vendorId;
    context.push(AppRoutes.menu, extra: vendorId);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final category = ref.watch(vendorCategoryFilterProvider);
    final search = ref.watch(vendorSearchQueryProvider);
    final categoriesAsync = ref.watch(vendorCategoriesProvider);
    final vendorsAsync = ref.watch(campusEateriesProvider);
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 24, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What are you\ncraving today?',
                      style: textTheme.headlineLarge?.copyWith(
                        color: AppColors.inkText,
                        fontSize: 27,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Good food. Closer than you think.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.ml, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: _Search(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onFilterTap: () =>
                      _notify(context, 'Filters are coming soon.'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              // Naturally-sized scroller, not a hardcoded height — see the
              // vendor-card fix below and this task's overflow audit: a
              // fixed cross-axis extent on a horizontal scroller of chips
              // with real text has nowhere to grow at larger text scale.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 16, AppSpacing.lg, 8),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Category(
                      label: 'All',
                      icon: Icons.grid_view_rounded,
                      selected: category == null,
                      onTap: () => ref.read(vendorCategoryFilterProvider.notifier).state = null,
                    ),
                    // The backend's controlled category vocabulary (Task
                    // 15) — simply omitted while loading/empty/erroring —
                    // "All" alone is still a usable filter bar.
                    for (final option in categoriesAsync.valueOrNull ?? const <VendorCategoryOption>[]) ...[
                      const SizedBox(width: 10),
                      _Category(
                        label: option.label,
                        selected: category == option.label,
                        onTap: () => ref.read(vendorCategoryFilterProvider.notifier).state = option.label,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: _CampusPickCard(onOrderNow: _orderNow),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 28, AppSpacing.lg, 12),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Popular around campus',
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.inkText,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 124),
              sliver: SliverToBoxAdapter(
                child: vendorsAsync.when(
                  loading: () => const _VendorRowSkeleton(),
                  error: (_, _) => const _VendorsErrorState(),
                  data: (vendors) => vendors.isEmpty
                      ? _NoVendorsState(hasSearch: search.trim().isNotEmpty, hasCategory: category != null)
                      // A horizontal ListView needs a bounded cross-axis
                      // height from its parent — which used to be a
                      // hardcoded SizedBox, the exact anti-pattern behind
                      // this session's recurring overflow bug (fine at
                      // default text scale, overflows once Dynamic Type
                      // grows the card's name/rating text). A
                      // SingleChildScrollView instead takes whatever
                      // height its Row of cards naturally needs.
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var index = 0; index < vendors.length; index++) ...[
                                if (index > 0) const SizedBox(width: 14),
                                GestureDetector(
                                  onTap: () => _openMenu(vendors[index].id),
                                  child: SizedBox(
                                    width: 150,
                                    child: _Vendor(vendor: vendors[index])
                                        .animate(delay: (90 * index).ms)
                                        .fadeIn(duration: 360.ms)
                                        .moveX(begin: 12, end: 0, duration: 360.ms),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _notify(BuildContext context, String message) {
    ref.read(appNotificationProvider.notifier).info(message);
  }
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider)?.user;
    final campusName = ref.watch(campusNameProvider(user?.campusId)) ?? 'your campus';
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryMaroonDeep,
            borderRadius: BorderRadius.circular(15),
          ),
          // The real run-it. brand mark (cropped from the wordmark asset),
          // recolored to white via ColorFiltered since the source PNG
          // renders the icon in maroon — replaces the earlier generic
          // Material shopping-bag placeholder.
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              AppColors.onMaroon,
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/runit_icon_mark.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivering to',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 15,
                    color: AppColors.primaryMaroon,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      campusName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: AppColors.inkText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          icon: CupertinoIcons.bell,
          onTap: () => ref
              .read(appNotificationProvider.notifier)
              .info('Notifications are coming soon.'),
        ),
        const SizedBox(width: 8),
        _AvatarButton(
          name: user?.name ?? '?',
          onTap: () => context.push(AppRoutes.studentProfile),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Icon(icon, color: AppColors.inkText, size: 21),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accentRoseDeep, AppColors.accentRose],
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.primaryMaroon),
            ),
          ),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.backgroundCream, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller, required this.onChanged, required this.onFilterTap});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Row(
      children: [
        const Icon(CupertinoIcons.search, color: AppColors.mutedText, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.inkText),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search meals, stores, or cravings...',
              hintStyle: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
          ),
        ),
        InkWell(
          onTap: onFilterTap,
          customBorder: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              CupertinoIcons.slider_horizontal_3,
              size: 19,
              color: AppColors.primaryMaroon,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Category extends StatelessWidget {
  const _Category({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  // Only "All" gets a decorative icon — vendor categories are an
  // open-ended, backend-managed vocabulary (Task 15), so there's no
  // reliable icon to map an arbitrary one to without guessing.
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: 220.ms,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryMaroon : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: selected ? AppColors.primaryMaroon : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.onMaroon : AppColors.mutedText,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? AppColors.onMaroon : AppColors.inkText,
            ),
          ),
        ],
      ),
    ),
  );
}

/// PART A fix: the previous card forced a fixed `height: 222` while its
/// `Column` used a `Spacer()` to push content to the bottom — at real text
/// scale the tag + headline + subtext + CTA together exceeded that fixed
/// height, overflowing. This version has no fixed height at all: the
/// `Column` sizes to its own content (plain `SizedBox` gaps, no `Spacer`),
/// so the card simply grows to fit whatever's inside it, including the
/// CTA button and background illustration this task adds.
class _CampusPickCard extends StatelessWidget {
  const _CampusPickCard({required this.onOrderNow});
  final VoidCallback onOrderNow;
  @override
  Widget build(BuildContext context) =>
      Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.primaryMaroonDeep,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.maroonShadow,
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                // A faint campus-landmark motif in the background — no
                // illustration asset for this exists yet, so this is a
                // deliberately simple vector placeholder, not a fake photo.
                Positioned(
                  right: -24,
                  top: -10,
                  bottom: -10,
                  width: 190,
                  child: Opacity(
                    opacity: .14,
                    child: Icon(
                      Icons.account_balance_rounded,
                      size: 210,
                      color: AppColors.accentRose,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryMaroonDeep,
                          AppColors.primaryMaroonDeep.withValues(alpha: .88),
                          Colors.transparent,
                        ],
                        stops: const [0, .50, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, AppSpacing.ml, AppSpacing.ml, AppSpacing.ml),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryMaroon,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CAMPUS PICK',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: AppColors.onMaroon,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: Text(
                          'Your lunch break, upgraded.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white, fontSize: 22),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 220,
                        child: Text(
                          'Fast drops from the spots you already love.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: .72),
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: onOrderNow,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.ml,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Order Now',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: AppColors.primaryMaroonDeep,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                CupertinoIcons.arrow_right,
                                size: 16,
                                color: AppColors.primaryMaroonDeep,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 500.ms)
          .moveY(begin: 10, end: 0, duration: 500.ms);
}

/// A vertical card sized for the horizontal "Popular around campus"
/// scroller — thumbnail on top, name/blurb below. Task 48: `vendor.rating`
/// is now real once a restaurant has any ratings — shown alongside the
/// blurb rather than replacing it, still null (and hidden) for an
/// unrated vendor rather than a fabricated number.
class _Vendor extends StatelessWidget {
  const _Vendor({required this.vendor});
  final Eatery vendor;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MenuImagePlaceholder(seed: vendor.id, imageUrl: vendor.bannerUrl, size: 130),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Text(
                vendor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 15, color: AppColors.inkText),
              ),
            ),
            if (vendor.rating != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
              const SizedBox(width: 2),
              Text(
                vendor.rating!.toStringAsFixed(1),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
        if (vendor.blurb != null) ...[
          const SizedBox(height: 4),
          Text(
            vendor.blurb!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.mutedText),
          ),
        ],
      ],
    ),
  );
}

/// Loading placeholder for "Popular around campus" — reuses [SkeletonBox]
/// (Task 10) shaped like [_Vendor]'s own layout, rather than a bare
/// spinner or a blank gap while `GET /vendors` resolves.
class _VendorRowSkeleton extends StatelessWidget {
  const _VendorRowSkeleton();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 130, height: 130, borderRadius: 16),
                SizedBox(height: 9),
                SkeletonBox(width: 90, height: 15),
                SizedBox(height: 6),
                SkeletonBox(width: 60, height: 12),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _VendorsErrorState extends StatelessWidget {
  const _VendorsErrorState();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "Couldn't load vendors. Pull down to try again.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
        ),
      ],
    ),
  );
}

/// Distinguishes "your search matched nothing" from "this category is
/// genuinely empty" from "there's simply nothing here yet" — a single
/// generic message would leave a student guessing whether to try a
/// different word or a different filter.
class _NoVendorsState extends StatelessWidget {
  const _NoVendorsState({required this.hasSearch, required this.hasCategory});
  final bool hasSearch;
  final bool hasCategory;
  @override
  Widget build(BuildContext context) {
    final message = hasSearch
        ? 'No vendors found for your search.'
        : hasCategory
        ? 'No vendors in this category yet.'
        : 'No vendors around campus yet.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RouteLineEmptyIllustration(width: 160, height: 90),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }
}
