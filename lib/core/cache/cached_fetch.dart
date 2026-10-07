import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_models.dart';
import '../network/api_exception.dart';
import 'local_cache.dart';

/// Cache keys, always per signed-in user — one account never sees another
/// account's orders or balance on a shared phone.
abstract final class CacheKeys {
  // Scoped to the user because the list is scoped to their campus.
  static String vendors(String userId) => '$userId/vendors';
  // Public, same for everyone.
  static const categories = 'vendor-categories';
  static String menu(String vendorId) => 'menu/$vendorId';
  static const menuPrefix = 'menu/';
  static String orders(String userId) => '$userId/orders';
  static String wallet(String userId) => '$userId/wallet';
  static String notifications(String userId) => '$userId/notifications';
}

/// Keys whose screen is currently showing the saved copy rather than live
/// data, with when that copy was saved — what [CachedDataNote]-style
/// "Last updated" labels watch. A key leaves the map the moment fresh data
/// replaces the saved copy.
class StaleCacheNotifier extends StateNotifier<Map<String, DateTime>> {
  StaleCacheNotifier() : super(const {});

  void mark(String key, DateTime savedAt) {
    if (state[key] == savedAt) return;
    state = {...state, key: savedAt};
  }

  void clear(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final staleCacheProvider = StateNotifierProvider<StaleCacheNotifier, Map<String, DateTime>>(
  (ref) => StaleCacheNotifier(),
);

/// What this run of the app has already loaded live, and background
/// results waiting to be picked up by the provider that asked for them.
class CacheSession {
  final live = <String>{};
  final pending = <String, Object?>{};
  final inFlight = <String, Future<bool>>{};

  /// The next load of [key] asks the network (still falling back to the
  /// saved copy if there's no connection). For explicit refreshes — a
  /// pull-to-refresh, checkout re-reading the balance, a top-up polling
  /// for it to land — which must never be answered with the saved copy
  /// just because the background refresh hasn't finished yet.
  void forceNetwork(String key) {
    live.add(key);
    pending.remove(key);
  }
}

final cacheSessionProvider = Provider<CacheSession>((ref) => CacheSession());

/// Cache-then-refresh for a provider's fetch:
///
/// - First load this run with a saved copy: return the saved copy right
///   away (marked stale, so its screen says "Last updated …"), and fetch
///   in the background. When that answers, the provider rebuilds with the
///   fresh data — the same silent update a pull-to-refresh gives.
/// - Otherwise (already live this run, or nothing saved): a normal fetch,
///   saved on success. If the connection fails and there's a saved copy,
///   show that instead of an error. A real backend answer (an
///   [ApiException]) is never papered over with old data.
/// - Nothing saved and no connection: the usual error state.
/// One kind of cached data: where it's stored, how to fetch it, and how
/// it's turned into JSON and back.
class CachedSource<T> {
  const CachedSource({required this.key, required this.fetch, required this.encode, required this.decode});
  final String key;
  final Future<T> Function() fetch;
  final Object? Function(T value) encode;
  final T Function(Object? json) decode;
}

Future<T> cachedFetch<T>(Ref ref, CachedSource<T> source) async {
  final CachedSource(:key, :fetch, :encode, :decode) = source;
  final cache = ref.read(localCacheProvider);
  final session = ref.read(cacheSessionProvider);
  final stale = ref.read(staleCacheProvider.notifier);

  // A background refresh finished: this rebuild is it arriving.
  if (session.pending.containsKey(key)) {
    final value = decode(session.pending.remove(key));
    scheduleMicrotask(() => stale.clear(key));
    return value;
  }

  final saved = cache.read(key);
  if (saved != null && !session.live.contains(key)) {
    var current = true;
    ref.onDispose(() => current = false);
    final refresh = session.inFlight[key] ??= _refreshInBackground(cache, session, key, fetch, encode);
    unawaited(
      refresh.then((ok) {
        if (ok && current) ref.invalidateSelf();
      }),
    );
    // Providers may not change other providers mid-build.
    scheduleMicrotask(() => stale.mark(key, saved.savedAt));
    return decode(saved.json);
  }

  try {
    final value = await fetch();
    session.live.add(key);
    session.pending.remove(key);
    await cache.write(key, encode(value));
    stale.clear(key);
    return value;
  } on ApiException {
    rethrow;
  } catch (_) {
    if (saved == null) rethrow;
    stale.mark(key, saved.savedAt);
    return decode(saved.json);
  }
}

Future<bool> _refreshInBackground<T>(
  LocalCache cache,
  CacheSession session,
  String key,
  Future<T> Function() fetch,
  Object? Function(T value) encode,
) async {
  try {
    final json = encode(await fetch());
    await cache.write(key, json);
    session.live.add(key);
    session.pending[key] = json;
    return true;
  } catch (_) {
    // Still offline (or the backend refused): the saved copy stays up,
    // marked stale, until the next reconnect or pull-to-refresh.
    return false;
  } finally {
    session.inFlight.remove(key);
  }
}

/// Re-fetches [source] into the cache without any screen asking — the
/// reconnect refresh uses this so saved copies of screens that aren't open
/// are brought up to date too. A provider showing that data picks the
/// result up on its next rebuild. Returns whether it succeeded.
Future<bool> refreshCached<T>(Ref ref, CachedSource<T> source) {
  final cache = ref.read(localCacheProvider);
  final session = ref.read(cacheSessionProvider);
  return session.inFlight[source.key] ??= _refreshInBackground(
    cache,
    session,
    source.key,
    source.fetch,
    source.encode,
  );
}

/// Wipes the cache on an explicit "Log out" (not on a session merely
/// expiring, where the same person signs straight back in). Watched once
/// from the app root.
final cacheLifecycleProvider = Provider<void>((ref) {
  ref.listen<AuthSession?>(authControllerProvider, (previous, next) {
    if (previous == null || next != null) return;
    if (ref.read(authControllerProvider.notifier).expired) return;
    unawaited(ref.read(localCacheProvider).clear());
    ref.invalidate(cacheSessionProvider);
    ref.invalidate(staleCacheProvider);
  });
});
