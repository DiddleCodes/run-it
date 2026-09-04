import 'dart:math' as math;

/// Restaurant goes through the exact same session-creating auth funnel as
/// student/runner (verify → OTP → passcode → biometric) — see
/// `postBiometricDestination` — it just branches to the vendor-application
/// wizard afterward instead of KYC/Home. It never gets a `kycStatus`
/// beyond [KycStatus.none]; vendor review is tracked separately by
/// `VendorApplication.status`, not this session's own KYC state.
enum AccountType { student, runner, restaurant }

/// Which kind of runner this is — chosen on the Runner Type screen, right
/// before KYC capture, and persisted on [UserProfile] from then on (not
/// just transient wizard state) since later runtime checks — geofencing
/// chief among them — need to know it long after KYC capture finishes.
/// Determines both which ID types [KycCaptureScreen] accepts and whether
/// it requires a vehicle step.
enum RunnerType { studentRunner, independentRider }

/// An Independent Rider's declared vehicle — chosen on the KYC capture
/// wizard's vehicle-details step and, from `submitKyc()` onward, persisted
/// on [UserProfile] alongside [runnerType] rather than staying transient
/// wizard state, so Profile's Vehicle Info section has something real to
/// show/edit long after onboarding finishes.
enum VehicleType { bicycle, motorbike, keke }

/// Lenient, format-only plate/registration validation. There's no public
/// Nigerian government API to check a plate against, and many keke/bike
/// riders run informal or hand-painted plates that won't match a rigid
/// 3-letter/3-digit/2-letter pattern — so this only rejects obvious junk
/// (too short/long, or every character repeated, e.g. "000000"/"AAAA").
/// It is not a security control: the vehicle photo captured during KYC is
/// the real verification instrument, and this typed value is just a
/// searchable reference for support/dispute purposes, cross-checked
/// visually against that photo during manual review.
bool isPlausiblePlateNumber(String raw) {
  final value = raw.trim();
  if (value.length < 3 || value.length > 12) return false;
  if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(value)) return false;
  final alphanumeric = value.replaceAll('-', '');
  if (alphanumeric.isEmpty) return false;
  if (alphanumeric.split('').toSet().length == 1) return false;
  return true;
}

/// Shared by both student light-KYC and runner full-KYC — runners simply
/// pass through an extra selfie-match step before reaching the same states.
enum KycStatus { none, pending, verified, rejected }

/// A raw lat/lng reading — deliberately not tied to any location plugin's
/// own position type, so the geofence math in [Campus.contains] stays
/// plugin-free and trivially unit-testable.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

class Campus {
  const Campus({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 900,
  });
  final String id;
  final String name;

  /// Approximate campus-center coordinates — public-knowledge locations,
  /// precise enough for a "are you roughly on campus" geofence, not
  /// survey-grade.
  final double latitude;
  final double longitude;

  /// How far from center still counts as "on campus" — wide enough to
  /// cover a real campus footprint without needing a real boundary
  /// polygon for this prototype.
  final double radiusMeters;

  static const _earthRadiusMeters = 6371000.0;

  /// Great-circle ground distance from this campus's center to [point],
  /// via the haversine formula.
  double distanceMetersFrom(GeoPoint point) {
    final lat1 = latitude * math.pi / 180;
    final lat2 = point.latitude * math.pi / 180;
    final dLat = (point.latitude - latitude) * math.pi / 180;
    final dLng = (point.longitude - longitude) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  bool contains(GeoPoint point) => distanceMetersFrom(point) <= radiusMeters;
}

/// Task 26: NOT the campus directory anymore — the real one lives on the
/// backend now (`GET /campuses`, `Campus.campusId`/name on the signed-in
/// session), and nothing picks a campus from this list at signup. This is
/// purely a local geofence-coordinates reference for the Independent Rider
/// "are you on campus" check (`RunnerController._checkCampusBoundary`),
/// which the real backend `Campus` model has no lat/lng for (out of this
/// task's scope — see the Task 26 report). Matched by campus *name*
/// against whatever the backend returns, since the id here is no longer
/// meaningful outside this file. A school with no entry here simply can't
/// be geofence-checked; see that call site for how it degrades.
const kCampusGeofenceReference = [
  Campus(
    id: 'ui',
    name: 'University of Ibadan',
    latitude: 7.4432,
    longitude: 3.8993,
  ),
  Campus(
    id: 'bu',
    name: 'Bingham University',
    latitude: 8.9727,
    longitude: 7.6521,
  ),
  Campus(
    id: 'oau',
    name: 'Obafemi Awolowo University',
    latitude: 7.5181,
    longitude: 4.5284,
  ),
  Campus(
    id: 'cu',
    name: 'Covenant University',
    latitude: 6.6712,
    longitude: 3.1583,
  ),
];

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.contact,
    required this.accountType,
    this.campusId,
    this.classOrGrade,
    this.phone,
    this.kycStatus = KycStatus.none,
    this.kycRejectionReason,
    this.biometricEnabled = false,
    this.passcodeSet = false,
    this.runnerType,
    this.vehicleType,
    this.vehiclePlate,
  });

  final String id;
  final String name;
  final String contact;
  final AccountType accountType;

  /// Task 26: real and backend-derived/admin-assigned now, never picked by
  /// the user — null until a student's email domain resolves one (always
  /// true by the time a student account exists at all) or an admin assigns
  /// one to a restaurant/runner (may stay null for a while after signup).
  final String? campusId;

  /// Task 28: a runner's phone — collected at signup alongside `contact`
  /// (their email, the real OTP channel now), kept for admin
  /// dispute-resolution contact. Null for student/restaurant, which never
  /// collect a second contact field.
  final String? phone;

  /// Student's class/grade level, collected at signup — nullable since
  /// runners never provide one and it's optional for students too.
  final String? classOrGrade;
  final KycStatus kycStatus;
  final String? kycRejectionReason;
  final bool biometricEnabled;

  /// Students authenticate with a 6-digit passcode instead of KYC — this
  /// flips true once they complete the Set Passcode step. Runners never
  /// set one; their gating stays entirely on [kycStatus].
  final bool passcodeSet;

  /// Set once, when a runner first submits KYC (see
  /// `AuthController.submitKyc`) — null for students. Persisted (not just
  /// transient KYC-wizard state) so it survives well past onboarding: a
  /// resubmission after rejection needs it to reconstruct the right
  /// capture steps, and the Independent Rider geofence check needs it on
  /// every "go online" attempt, long after KYC ever ran.
  final RunnerType? runnerType;

  /// Independent Rider only — null for a student runner (no vehicle step)
  /// and for a student account entirely.
  final VehicleType? vehicleType;
  final String? vehiclePlate;

  /// Runners are gated behind Verified before they can see or accept jobs;
  /// students only need to exist to browse/order.
  bool get canAccessRunnerJobs =>
      accountType == AccountType.runner && kycStatus == KycStatus.verified;

  UserProfile copyWith({
    KycStatus? kycStatus,
    String? kycRejectionReason,
    bool clearRejectionReason = false,
    bool? biometricEnabled,
    bool? passcodeSet,
    RunnerType? runnerType,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) => UserProfile(
    id: id,
    name: name,
    contact: contact,
    accountType: accountType,
    campusId: campusId,
    classOrGrade: classOrGrade,
    phone: phone,
    kycStatus: kycStatus ?? this.kycStatus,
    kycRejectionReason: clearRejectionReason
        ? null
        : kycRejectionReason ?? this.kycRejectionReason,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    passcodeSet: passcodeSet ?? this.passcodeSet,
    runnerType: runnerType ?? this.runnerType,
    vehicleType: vehicleType ?? this.vehicleType,
    vehiclePlate: vehiclePlate ?? this.vehiclePlate,
  );
}

/// A real JWT + refresh-token pair issued by the backend (Task 34) — a
/// short-lived (1h) access token plus a long-lived (30d), server-side,
/// hashed, rotating refresh token (`POST /auth/refresh`). [expiresAt] is
/// the access token's own expiry only; the refresh token has no
/// client-visible expiry of its own (AuthController never needs one — a
/// refresh attempt against an expired/revoked one just fails, same as any
/// other rejection).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final UserProfile user;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    UserProfile? user,
  }) => AuthSession(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    user: user ?? this.user,
  );
}
