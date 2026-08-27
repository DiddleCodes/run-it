import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _category = 0;
  static const _categories = <(String, IconData)>[
    ('All', Icons.grid_view_rounded),
    ('Meals', Icons.restaurant_rounded),
    ('Snacks', Icons.cookie_rounded),
    ('Drinks', Icons.local_drink_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(22, 12, 22, 0),
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
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
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              sliver: SliverToBoxAdapter(
                child: _Search(
                  onFilterTap: () => _notify(context, 'Filters are coming soon.'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, index) => _Category(
                    item: _categories[index],
                    selected: _category == index,
                    onTap: () => setState(() => _category = index),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              sliver: SliverToBoxAdapter(
                child: _CampusPickCard(
                  onOrderNow: () => context.push(AppRoutes.menu),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Popular around campus',
                        style: textTheme.titleLarge?.copyWith(color: AppColors.inkText),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _notify(context, 'A full vendor list is coming soon.'),
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 182,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 124),
                  scrollDirection: Axis.horizontal,
                  itemCount: _vendors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => context.push(AppRoutes.menu),
                    child: SizedBox(
                      width: 150,
                      child: _Vendor(vendor: _vendors[index])
                          .animate(delay: (90 * index).ms)
                          .fadeIn(duration: 360.ms)
                          .moveX(begin: 12, end: 0, duration: 360.ms),
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
    final campusName = user?.campus.name ?? 'your campus';
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
            colorFilter: const ColorFilter.mode(AppColors.onMaroon, BlendMode.srcIn),
            child: Image.asset('assets/images/runit_icon_mark.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivering to',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                ),
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
        _IconBadgeButton(
          icon: CupertinoIcons.bell,
          badged: true,
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

class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({required this.icon, required this.onTap, this.badged = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool badged;

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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: AppColors.inkText, size: 21),
            if (badged)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.primaryMaroon),
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
  const _Search({required this.onFilterTap});
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
          child: Text(
            'Search meals, stores, or cravings...',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
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
  const _Category({required this.item, required this.selected, required this.onTap});
  final (String, IconData) item;
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.primaryMaroon : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            item.$2,
            size: 18,
            color: selected ? AppColors.onMaroon : AppColors.mutedText,
          ),
          const SizedBox(width: 8),
          Text(
            item.$1,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: selected ? AppColors.onMaroon : AppColors.inkText),
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
                  padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: onOrderNow,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Order Now',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

typedef _VendorData = (String, String, String, int);
const _vendors = <_VendorData>[
  ('Tantalizers', 'Jollof rice · Chicken · Sides', '12 min', 0xFFE7B957),
  ('Café 167', 'Coffee · Pastries · Breakfast', '8 min', 0xFFD8A58B),
  ('Mama’s Kitchen', 'Local bowls · Soups · Swallows', '18 min', 0xFFA9B8A1),
];

/// A vertical card sized for the horizontal "Popular around campus"
/// scroller — thumbnail on top, name/rating below, matching the reference
/// layout rather than the old full-width list row.
class _Vendor extends StatelessWidget {
  const _Vendor({required this.vendor});
  final _VendorData vendor;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 84,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color(vendor.$4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            vendor.$1 == 'Café 167'
                ? Icons.coffee_rounded
                : Icons.restaurant_rounded,
            size: 30,
            color: AppColors.primaryMaroonDeep,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          vendor.$1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: 15, color: AppColors.inkText),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 14, color: AppColors.primaryMaroon),
            const SizedBox(width: 2),
            Text(
              '4.8',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.circle, size: 3, color: AppColors.mutedText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                vendor.$3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
