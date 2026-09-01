import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../routing/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../../features/ordering/application/ordering_providers.dart';

/// Which persona is driving [AppNavShell] — determines the 4-tab set and
/// the raised center action (Scan for a runner, Basket for a student, +
/// Add Item for a restaurant) without duplicating the whole nav-bar widget
/// per role. Add a case here (and to [_tabsFor]/[_centerFor]) rather than
/// building a third standalone nav-bar widget for any future persona.
enum AppRole { student, runner, restaurant }

class _TabSpec {
  const _TabSpec({
    required this.icon,
    required this.filledIcon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final IconData filledIcon;
  final String label;
  final String route;
}

class _CenterSpec {
  const _CenterSpec({
    required this.icon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final String label;
  final String route;
}

List<_TabSpec> _tabsFor(AppRole role) => switch (role) {
  AppRole.runner => const [
    _TabSpec(
      icon: CupertinoIcons.house,
      filledIcon: CupertinoIcons.house_fill,
      label: 'Home',
      route: AppRoutes.runnerHome,
    ),
    _TabSpec(
      icon: CupertinoIcons.bag,
      filledIcon: CupertinoIcons.bag_fill,
      label: 'Jobs',
      route: AppRoutes.runnerJobs,
    ),
    _TabSpec(
      icon: CupertinoIcons.chat_bubble,
      filledIcon: CupertinoIcons.chat_bubble_fill,
      label: 'Messages',
      route: AppRoutes.runnerMessages,
    ),
    _TabSpec(
      icon: CupertinoIcons.person,
      filledIcon: CupertinoIcons.person_fill,
      label: 'Profile',
      route: AppRoutes.runnerProfile,
    ),
  ],
  AppRole.student => const [
    _TabSpec(
      icon: CupertinoIcons.house,
      filledIcon: CupertinoIcons.house_fill,
      label: 'Home',
      route: AppRoutes.home,
    ),
    _TabSpec(
      icon: CupertinoIcons.doc_text,
      filledIcon: CupertinoIcons.doc_text_fill,
      label: 'Orders',
      route: AppRoutes.studentOrders,
    ),
    _TabSpec(
      icon: CupertinoIcons.creditcard,
      filledIcon: CupertinoIcons.creditcard_fill,
      label: 'Wallet',
      route: AppRoutes.studentWallet,
    ),
    _TabSpec(
      icon: CupertinoIcons.person,
      filledIcon: CupertinoIcons.person_fill,
      label: 'Profile',
      route: AppRoutes.studentProfile,
    ),
  ],
  AppRole.restaurant => const [
    _TabSpec(
      icon: CupertinoIcons.doc_text,
      filledIcon: CupertinoIcons.doc_text_fill,
      label: 'Orders',
      route: AppRoutes.restaurantOrders,
    ),
    _TabSpec(
      icon: CupertinoIcons.square_list,
      filledIcon: CupertinoIcons.square_list_fill,
      label: 'Menu',
      route: AppRoutes.restaurantMenu,
    ),
    _TabSpec(
      icon: CupertinoIcons.chart_bar,
      filledIcon: CupertinoIcons.chart_bar_fill,
      label: 'Metrics',
      route: AppRoutes.restaurantMetrics,
    ),
    _TabSpec(
      icon: CupertinoIcons.person,
      filledIcon: CupertinoIcons.person_fill,
      label: 'Profile',
      route: AppRoutes.restaurantProfile,
    ),
  ],
};

_CenterSpec _centerFor(AppRole role) => switch (role) {
  AppRole.runner => const _CenterSpec(
    icon: CupertinoIcons.viewfinder,
    label: 'Scan',
    route: AppRoutes.runnerScan,
  ),
  AppRole.student => const _CenterSpec(
    icon: CupertinoIcons.bag_fill,
    label: 'Basket',
    route: AppRoutes.basket,
  ),
  // A quick-access shortcut, not a role-inappropriate borrowed icon
  // (there's no scan/basket equivalent for a kitchen) — jumps straight
  // into Add Item from anywhere in the shell, since that's the action a
  // restaurant owner reaches for most often day to day.
  AppRole.restaurant => const _CenterSpec(
    icon: CupertinoIcons.add,
    label: 'Add Item',
    route: AppRoutes.restaurantMenuAdd,
  ),
};

/// Shared bottom-nav scaffold for both the runner and student main-screen
/// shells — same visual treatment (translucent white surface, rounded top
/// corners, subtle shadow, spring-feeling tab transitions) either way; only
/// the 4 tabs and the raised center action differ, driven by [role]. The
/// center action's own screen (Scan / Basket) is deliberately never wrapped
/// in this shell itself — same as a runner never sees this bar while the
/// camera viewfinder is open — so it has no "selected" state of its own.
class AppNavShell extends ConsumerWidget {
  const AppNavShell({super.key, required this.role, required this.child});
  final AppRole role;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final tabs = _tabsFor(role);
    final activeIndex = tabs.indexWhere((t) => t.route == location);
    final center = _centerFor(role);
    final basketCount = role == AppRole.student
        ? ref
              .watch(basketProvider)
              .items
              .fold(0, (sum, item) => sum + item.quantity)
        : 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: _AppNavBar(
        tabs: tabs,
        activeIndex: activeIndex,
        center: center,
        centerBadgeCount: basketCount,
        onSelectTab: (spec) {
          if (spec.route != location) context.go(spec.route);
        },
        onSelectCenter: () => context.go(center.route),
      ),
    );
  }
}

/// Thin, role-preset wrapper — kept as its own named class (rather than
/// every call site writing `AppNavShell(role: AppRole.runner, ...)`) so
/// existing route builders/tests that reference `RunnerShell` by name
/// don't need to change.
class RunnerShell extends StatelessWidget {
  const RunnerShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AppNavShell(role: AppRole.runner, child: child);
}

/// Student-side counterpart to [RunnerShell] — wraps Home/Orders/Wallet/
/// Profile. Menu/Basket/Checkout/OrderTracking stay unwrapped, same as the
/// runner's Offer/Delivery/Earnings/Scan screens.
class StudentShell extends StatelessWidget {
  const StudentShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AppNavShell(role: AppRole.student, child: child);
}

/// Task 12's Restaurant Dashboard shell — wraps Orders/Menu/Metrics/
/// Profile. The Add Item screen (this role's raised center action) stays
/// unwrapped, same convention as the other two roles' own full-screen
/// center destinations.
class RestaurantShell extends StatelessWidget {
  const RestaurantShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AppNavShell(role: AppRole.restaurant, child: child);
}

class _AppNavBar extends StatelessWidget {
  const _AppNavBar({
    required this.tabs,
    required this.activeIndex,
    required this.center,
    required this.centerBadgeCount,
    required this.onSelectTab,
    required this.onSelectCenter,
  });
  final List<_TabSpec> tabs;
  final int activeIndex;
  final _CenterSpec center;
  final int centerBadgeCount;
  final ValueChanged<_TabSpec> onSelectTab;
  final VoidCallback onSelectCenter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // This bar's height is intentionally fixed (it anchors the raised
      // center button's positioning math) with very little vertical slack
      // around each tab's icon + label — at full Dynamic Type scaling the
      // label alone can exceed that slack and overflow. Compact,
      // icon-anchored navigation chrome like this is exactly where iOS
      // itself caps how far a tab bar's label grows, rather than letting
      // it scale without bound, so clamp scaling here instead of fighting
      // the fixed layout everywhere else in the app still scales freely.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: SizedBox(
          height: 82,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard.withValues(alpha: .96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.maroonShadow,
                        blurRadius: 18,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i == tabs.length ~/ 2)
                            // Reserves the center gap the raised action
                            // floats above — its own label lives here so all
                            // 5 slots stay equal-width and evenly spaced.
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 38),
                                child: Text(
                                  center.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.mutedText,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: _NavTab(
                              icon: tabs[i].icon,
                              filledIcon: tabs[i].filledIcon,
                              label: tabs[i].label,
                              selected: activeIndex == i,
                              onTap: () => onSelectTab(tabs[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _CenterButton(
                icon: center.icon,
                badgeCount: centerBadgeCount,
                onTap: onSelectCenter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.icon,
    required this.filledIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData filledIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.primaryMaroon
        : AppColors.mutedText;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Padding(
          // Tightened from 12 to leave the icon+label Column more of the
          // bar's fixed 68px slot to grow into at larger Dynamic Type
          // scale (paired with the clamp above) rather than overflowing.
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                // A little spring-like overshoot on the selected icon
                // rather than a plain linear/ease transition.
                scale: widget.selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    widget.selected ? widget.filledIcon : widget.icon,
                    key: ValueKey(widget.selected),
                    color: color,
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised circular center action, sitting above the bar line. A small red
/// numbered badge overlays it when [badgeCount] is positive (the
/// student-side basket count; always 0 — no badge — for the runner's Scan).
class _CenterButton extends StatefulWidget {
  const _CenterButton({
    required this.icon,
    required this.badgeCount,
    required this.onTap,
  });
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<_CenterButton> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryMaroon,
                    AppColors.primaryMaroonDeep,
                  ],
                ),
                border: Border.all(color: AppColors.surfaceCard, width: 4),
                // Two stacked shadows — a tight contact shadow plus a
                // soft, wider glow — so the button reads as elevated
                // above the bar rather than a flat circle overlapping it.
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: AppColors.primaryMaroon.withValues(alpha: .38),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: AppColors.onMaroon, size: 24),
            ),
            if (widget.badgeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.surfaceCard, width: 2),
                  ),
                  child: Text(
                    '${widget.badgeCount}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
