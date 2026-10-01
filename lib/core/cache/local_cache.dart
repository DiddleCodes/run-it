import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

/// One saved API response and when it was saved.
class CacheEntry {
  const CacheEntry(this.json, this.savedAt);
  final Object? json;
  final DateTime savedAt;
}

/// The last-loaded copy of read-mostly browsing data — the restaurant
/// list, menus, order history and wallet balance — so a returning user who
/// opens the app with no signal sees something real instead of skeletons
/// and "Couldn't load vendors". Only ever a fallback: see [cachedFetch].
///
/// Never holds anything payment- or chat-related beyond the balance shown
/// on screen; those have their own real-time/safety handling.
abstract class LocalCache {
  CacheEntry? read(String key);
  Future<void> write(String key, Object? json);
  Iterable<String> get keys;
  Future<void> clear();
}

/// Backed by one Hive box of JSON strings, opened in `main()`.
class HiveLocalCache implements LocalCache {
  HiveLocalCache(this._box);
  final Box<String> _box;

  static const boxName = 'api_cache';

  static Future<HiveLocalCache> open() async => HiveLocalCache(await Hive.openBox<String>(boxName));

  @override
  CacheEntry? read(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CacheEntry(decoded['data'], DateTime.parse(decoded['savedAt'] as String));
    } catch (_) {
      return null; // A corrupt entry is just a miss.
    }
  }

  @override
  Future<void> write(String key, Object? json) =>
      _box.put(key, jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'data': json}));

  @override
  Iterable<String> get keys => _box.keys.cast<String>();

  @override
  Future<void> clear() => _box.clear();
}

/// In-memory stand-in: the default until `main()` provides the Hive one,
/// so tests and anything running without disk behave the same way.
class MemoryLocalCache implements LocalCache {
  MemoryLocalCache({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final _entries = <String, CacheEntry>{};

  @override
  CacheEntry? read(String key) => _entries[key];

  @override
  Future<void> write(String key, Object? json) async =>
      // Round-tripped through JSON, like the Hive cache, so a value that
      // can't be stored fails here too.
      _entries[key] = CacheEntry(jsonDecode(jsonEncode(json)), _clock());

  @override
  Iterable<String> get keys => _entries.keys;

  @override
  Future<void> clear() async => _entries.clear();
}

final localCacheProvider = Provider<LocalCache>((ref) => MemoryLocalCache());
