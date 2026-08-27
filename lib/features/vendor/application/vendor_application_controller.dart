import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/vendor_models.dart';

class VendorApplicationController extends Notifier<VendorApplication> {
  @override
  VendorApplication build() => const VendorApplication();

  void setBusinessInfo({
    required String businessName,
    required VendorCategory category,
    String description = '',
  }) => state = state.copyWith(
    businessName: businessName,
    category: category,
    description: description,
  );

  void setContactInfo({
    required String contactName,
    required String contactPhone,
    required Campus campus,
  }) => state = state.copyWith(
    contactName: contactName,
    contactPhone: contactPhone,
    campus: campus,
  );

  void setStorefrontPhoto(Uint8List bytes) =>
      state = state.copyWith(storefrontPhoto: bytes);
  void clearStorefrontPhoto() =>
      state = state.copyWith(clearStorefrontPhoto: true);

  /// STUB — see [VendorApplication]'s doc comment. Only moves local state
  /// to pending; no request is actually sent anywhere.
  void submit() {
    if (!state.isSubmittable) return;
    state = state.copyWith(status: VendorApplicationStatus.pending);
  }

  void reset() => state = const VendorApplication();
}

final vendorApplicationProvider =
    NotifierProvider<VendorApplicationController, VendorApplication>(
      VendorApplicationController.new,
    );
