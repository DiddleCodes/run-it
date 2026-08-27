import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// In-app toast/banner type. Determines both the accent color/icon and the
/// default auto-dismiss behavior: [error] persists until the user dismisses
/// or acts on it, everything else clears itself after ~4s.
enum AppNotificationType { info, success, warning, error }

class AppNotificationData {
  const AppNotificationData({
    required this.id,
    required this.type,
    required this.message,
    this.dismissing = false,
  });

  final String id;
  final AppNotificationType type;
  final String message;
  final bool dismissing;

  AppNotificationData copyWith({bool? dismissing}) => AppNotificationData(
    id: id,
    type: type,
    message: message,
    dismissing: dismissing ?? this.dismissing,
  );
}

/// Queue of active in-app notifications. This is the one reusable
/// component both Task 4's auth/KYC events and Task 9's dedicated
/// notifications feature build on — extend it there rather than
/// introducing a second toast system.
class AppNotificationController extends Notifier<List<AppNotificationData>> {
  final _timers = <String, Timer>{};
  var _nextId = 0;

  @override
  List<AppNotificationData> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return const [];
  }

  String show({
    required AppNotificationType type,
    required String message,
    bool? persistent,
  }) {
    final id = 'notif-${_nextId++}';
    state = [...state, AppNotificationData(id: id, type: type, message: message)];
    final shouldPersist = persistent ?? type == AppNotificationType.error;
    if (!shouldPersist) {
      _timers[id] = Timer(const Duration(seconds: 4), () => dismiss(id));
    }
    return id;
  }

  void info(String message) => show(type: AppNotificationType.info, message: message);
  void success(String message) => show(type: AppNotificationType.success, message: message);
  void warning(String message) => show(type: AppNotificationType.warning, message: message);
  void error(String message) => show(type: AppNotificationType.error, message: message);

  /// Begins the exit animation; the tile calls [remove] once it finishes.
  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    final index = state.indexWhere((n) => n.id == id);
    if (index == -1 || state[index].dismissing) return;
    state = [
      for (final n in state) if (n.id == id) n.copyWith(dismissing: true) else n,
    ];
  }

  void remove(String id) {
    state = state.where((n) => n.id != id).toList();
  }
}

final appNotificationProvider =
    NotifierProvider<AppNotificationController, List<AppNotificationData>>(
      AppNotificationController.new,
    );

/// Wrap the app's router output in this once, near the root, so any screen
/// can call `ref.read(appNotificationProvider.notifier).success(...)` and
/// have a banner slide in from the top regardless of what's on screen.
class AppNotificationHost extends ConsumerWidget {
  const AppNotificationHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(appNotificationProvider);
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + AppSpacing.sm,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: Column(
            children: [
              for (final n in notifications)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _NotificationTile(
                    key: ValueKey(n.id),
                    data: n,
                    onExitComplete: () =>
                        ref.read(appNotificationProvider.notifier).remove(n.id),
                    onDismissTap: () =>
                        ref.read(appNotificationProvider.notifier).dismiss(n.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({
    super.key,
    required this.data,
    required this.onExitComplete,
    required this.onDismissTap,
  });

  final AppNotificationData data;
  final VoidCallback onExitComplete;
  final VoidCallback onDismissTap;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  late final _slide = Tween<Offset>(
    begin: const Offset(0, -0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.emphasized));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _NotificationTile old) {
    super.didUpdateWidget(old);
    if (widget.data.dismissing && !old.data.dismissing) {
      _controller.reverse().whenComplete(widget.onExitComplete);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({IconData icon, Color color}) _style(BuildContext context) {
    return switch (widget.data.type) {
      AppNotificationType.success => (
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      ),
      AppNotificationType.error => (
        icon: Icons.error_rounded,
        color: AppColors.error,
      ),
      AppNotificationType.warning => (
        icon: Icons.warning_rounded,
        color: AppColors.warning,
      ),
      AppNotificationType.info => (
        icon: Icons.info_rounded,
        color: AppColors.mutedText,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    const surface = AppColors.surfaceCard;
    const text = AppColors.inkText;
    const border = AppColors.borderSubtle;

    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onDismissTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: border),
                boxShadow: AppElevation.raised(false),
              ),
              child: Row(
                children: [
                  Icon(style.icon, color: style.color, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.data.message,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: text, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
