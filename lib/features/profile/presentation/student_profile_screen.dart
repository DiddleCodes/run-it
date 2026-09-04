import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/campus_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../ordering/application/order_tracking_controller.dart';
import '../../ordering/presentation/my_orders_screen.dart' show orderHistoryProvider;
import '../../ordering/presentation/widgets/ordering_components.dart' show naira;

/// Deterministic per-user demo rating — there's no ratings concept for a
/// student in this data model yet, so this varies sensibly between users
/// rather than showing a hardcoded literal (same spirit as the runner
/// side's own `_demoRating`).
double _demoRating(String userId) => 4.5 + (userId.hashCode.abs() % 5) / 10;

class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider)?.user;
    if (user == null) return const SizedBox.shrink();
    final history = ref.watch(orderHistoryProvider);
    // Task 10 performance audit: this screen only cares whether an order is
    // active and, if so, its total — not every intermediate stage change,
    // which is what a plain watch of the whole session would rebuild on.
    final (isActive, activeTotal) = ref.watch(
      orderTrackingProvider.select((s) => (s.isActive, s.total)),
    );
    final ordersCount = history.length + (isActive ? 1 : 0);
    final totalSpent =
        history.fold(0, (sum, e) => sum + e.total) + (isActive ? activeTotal : 0);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, AppSpacing.lg, 32),
          children: [
            _ProfileHeader(
              onSettingsTap: () => ref
                  .read(appNotificationProvider.notifier)
                  .info('Settings shortcuts are below.'),
              onBellTap: () => ref
                  .read(appNotificationProvider.notifier)
                  .info('Notifications are coming soon.'),
            ),
            const SizedBox(height: 16),
            _IdentityCard(user: user, onTap: () => _showPersonalInfo(context, user)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.receipt_long_rounded,
                    label: 'Orders',
                    value: ordersCount.toString(),
                  ),
                ),
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Total Spent',
                    value: naira(totalSpent),
                  ),
                ),
                Expanded(
                  child: _ProfileStat(
                    icon: Icons.star_rounded,
                    label: 'Rating',
                    value: _demoRating(user.id).toStringAsFixed(1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.ml),
            _PlusBanner(onTap: () => context.push(AppRoutes.runItPlus)),
            const SizedBox(height: 24),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.location_on_outlined,
                  title: 'Delivery Address',
                  subtitle: ref.watch(campusNameProvider(user.campusId)) ?? 'your campus',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Delivery addresses are coming soon.'),
                ),
                _SettingsRow(
                  icon: Icons.credit_card_outlined,
                  title: 'Payment Methods',
                  subtitle: 'Card, Bank & Wallet',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Payment methods are coming soon.'),
                ),
                _SettingsRow(
                  icon: Icons.history_rounded,
                  title: 'Order History',
                  subtitle: 'View past orders',
                  onTap: () => context.push(AppRoutes.studentOrders),
                ),
                _SettingsRow(
                  icon: Icons.favorite_border_rounded,
                  title: 'Favorites',
                  subtitle: 'Your saved stores',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Favorites are coming soon.'),
                ),
                _SettingsRow(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & Support',
                  subtitle: 'Get help or chat with us',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Reach us at support@run-it.app.'),
                ),
                _SettingsRow(
                  icon: Icons.card_giftcard_rounded,
                  title: 'Invite Friends',
                  subtitle: 'Earn rewards',
                  onTap: () => ref
                      .read(appNotificationProvider.notifier)
                      .info('Referrals are coming soon.'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  destructive: true,
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonalInfo(BuildContext context, UserProfile user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _PersonalInfoSheet(user: user),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign back in to order again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(authControllerProvider.notifier).logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onSettingsTap, required this.onBellTap});
  final VoidCallback onSettingsTap;
  final VoidCallback onBellTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(color: AppColors.inkText, fontSize: 28),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage your account.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
            ],
          ),
        ),
        _HeaderIconButton(icon: CupertinoIcons.gear, onTap: onSettingsTap),
        const SizedBox(width: 8),
        _HeaderIconButton(icon: CupertinoIcons.bell, onTap: onBellTap),
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
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.maroonShadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.inkText, size: 19),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user, required this.onTap});
  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: AppElevation.card(false),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
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
                user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: AppColors.primaryMaroon, fontSize: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: AppColors.inkText),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.contact,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Student',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, color: AppColors.mutedText, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.accentRose, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: AppColors.primaryMaroon),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }
}

/// Visual placeholder only — see `RunItPlusScreen`. No entitlement logic
/// lives behind this banner.
class _PlusBanner extends StatelessWidget {
  const _PlusBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryMaroon, AppColors.primaryMaroonDeep],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.money_dollar, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RUN-It Plus',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: AppColors.onMaroon, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Get free delivery, exclusive deals & more.',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.onMaroon.withValues(alpha: .78)),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: AppColors.onMaroon.withValues(alpha: .8), size: 16),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, color: AppColors.borderSubtle, indent: 54),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.destructive = false,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.inkText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? AppColors.error : AppColors.primaryMaroon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(CupertinoIcons.chevron_right, color: AppColors.mutedText, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PersonalInfoSheet extends ConsumerWidget {
  const _PersonalInfoSheet({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <(String, String)>[
      ('Name', user.name),
      ('School email', user.contact),
      ('Campus', ref.watch(campusNameProvider(user.campusId)) ?? '—'),
      if (user.classOrGrade != null && user.classOrGrade!.isNotEmpty)
        ('Class / Grade', user.classOrGrade!),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Info',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 16),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: AppColors.mutedText),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.inkText),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
