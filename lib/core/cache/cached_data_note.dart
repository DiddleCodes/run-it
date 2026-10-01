import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import 'cached_fetch.dart';

/// "Last updated 3:12 PM" — shown only while the screen is showing the
/// saved copy for [cacheKey] instead of live data, so old data is never
/// mistaken for live. Disappears as soon as fresh data arrives.
class CachedDataNote extends ConsumerWidget {
  const CachedDataNote({super.key, required this.cacheKey, this.padding = EdgeInsets.zero, this.color});

  final String? cacheKey;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = cacheKey;
    final savedAt = key == null ? null : ref.watch(staleCacheProvider.select((stale) => stale[key]));
    if (savedAt == null) return const SizedBox.shrink();
    final tint = color ?? AppColors.mutedText;
    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.clock, size: 13, color: tint),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Last updated ${describeSavedAt(context, savedAt)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// "3:12 PM" today, "yesterday, 3:12 PM", otherwise "Sep 30, 3:12 PM".
String describeSavedAt(BuildContext context, DateTime savedAt, {DateTime? now}) {
  final localizations = MaterialLocalizations.of(context);
  final local = savedAt.toLocal();
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(local);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) return 'yesterday, $time';
  return '${localizations.formatShortMonthDay(local)}, $time';
}
