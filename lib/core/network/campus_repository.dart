import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Task 27: the real-time result of `GET /campuses/check-email` — purely
/// advisory (drives the signup field's live green/red state), never the
/// real enforcement. That's still the backend's 422 at OTP request/verify
/// time, which this deliberately mirrors the message of.
class CampusEmailCheck {
  const CampusEmailCheck({required this.valid, this.campusName, this.message});

  factory CampusEmailCheck.fromJson(Map<String, dynamic> json) => CampusEmailCheck(
    valid: json['valid'] as bool,
    campusName: json['campusName'] as String?,
    message: json['message'] as String?,
  );

  final bool valid;
  final String? campusName;
  final String? message;
}

/// Task 26: id + name only — matches `GET /campuses`, which deliberately
/// never exposes `allowedEmailDomains` (an enforcement detail, not client
/// display data).
class CampusOption {
  const CampusOption({required this.id, required this.name});

  factory CampusOption.fromJson(Map<String, dynamic> json) =>
      CampusOption(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

/// The real campus directory — replaces the old hardcoded `kCampuses`
/// static list. Nothing in signup uses this (a student's campus is
/// derived from their email domain, a restaurant/runner's is admin-
/// assigned — see the Task 26 report), so today its only consumer is
/// display: resolving a signed-in user's `campusId` to a real name.
class CampusRepository {
  const CampusRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<List<CampusOption>> list() async {
    final json = await client.get('/campuses') as List<dynamic>;
    return json
        .map((item) => CampusOption.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Task 27: the live signup-field check — never called until the email
  /// already looks syntactically complete (see `ValidatedField`'s own doc
  /// comment), so this never fires mid-keystroke.
  Future<CampusEmailCheck> checkEmail(String email) async {
    final path = Uri(
      path: '/campuses/check-email',
      queryParameters: {'email': email},
    ).toString();
    final json = await client.get(path) as Map<String, dynamic>;
    return CampusEmailCheck.fromJson(json);
  }
}

final campusRepositoryProvider = Provider<CampusRepository>(
  (ref) => const CampusRepository(),
);

/// Effectively static real reference data — fetched once per provider
/// container, same convention as `vendorCategoriesProvider`.
final campusesProvider = FutureProvider<List<CampusOption>>(
  (ref) => ref.read(campusRepositoryProvider).list(),
);

/// Every profile/greeting call site that used to read `user.campus.name`
/// off the old hardcoded directory now resolves it through here instead —
/// null while the real list is still loading/unavailable or [campusId]
/// doesn't (yet) match anything in it (e.g. a runner/restaurant with no
/// admin-assigned campus yet), never a thrown error, so a display-only
/// site can fall back to its own placeholder text rather than crash.
final campusNameProvider = Provider.family<String?, String?>((ref, campusId) {
  if (campusId == null) return null;
  final campuses = ref.watch(campusesProvider).valueOrNull;
  if (campuses == null) return null;
  for (final campus in campuses) {
    if (campus.id == campusId) return campus.name;
  }
  return null;
});
