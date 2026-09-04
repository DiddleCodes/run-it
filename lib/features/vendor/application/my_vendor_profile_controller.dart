import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/vendors_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/vendor_dashboard_models.dart';

/// The restaurant's own real backend profile — every Restaurant Dashboard
/// screen (Orders/Menu/Metrics/Profile) assumes this already exists (it's
/// created by the first-run profile-completion screen before the shell is
/// ever reached), so a fetch failure here is a genuine error state, not a
/// "not set up yet" one to quietly tolerate.
class MyVendorProfileController extends AsyncNotifier<MyVendorProfile> {
  @override
  Future<MyVendorProfile> build() => _fetch();

  Future<MyVendorProfile> _fetch() async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('MyVendorProfileController.build() called with no active session');
    }
    return ref.read(vendorsRepositoryProvider).fetchMyVendor(token: session.accessToken);
  }

  Future<void> refresh() async {
    state = const AsyncValue<MyVendorProfile>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard<MyVendorProfile>(_fetch);
  }

  /// Real backend confirmation only — the screen calling this shows the
  /// updated profile once this resolves, never before.
  Future<MyVendorProfile> save({
    required String businessName,
    required String category,
    String? description,
    String? logoUrl,
    String? requestedCampusId,
  }) async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('save() called with no active session');
    }
    final updated = await ref
        .read(vendorsRepositoryProvider)
        .upsertMyVendor(
          businessName: businessName,
          category: category,
          description: description,
          logoUrl: logoUrl,
          requestedCampusId: requestedCampusId,
          token: session.accessToken,
        );
    state = AsyncValue.data(updated);
    return updated;
  }
}

final myVendorProfileProvider = AsyncNotifierProvider<MyVendorProfileController, MyVendorProfile>(
  MyVendorProfileController.new,
);
