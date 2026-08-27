import 'dart:typed_data';

import '../../auth/domain/auth_models.dart' show Campus;

export '../../auth/domain/auth_models.dart' show Campus;

/// Fixed set a vendor picks one of on Business Info — deliberately a short,
/// closed list (not free text) since these double as the filter chips
/// students already browse Home by, so a vendor's category has to land on
/// a value the student side actually understands.
enum VendorCategory { nigerian, fastFood, snacks, drinks, bakery, other }

extension VendorCategoryLabel on VendorCategory {
  String get label => switch (this) {
    VendorCategory.nigerian => 'Nigerian',
    VendorCategory.fastFood => 'Fast Food',
    VendorCategory.snacks => 'Snacks',
    VendorCategory.drinks => 'Drinks',
    VendorCategory.bakery => 'Bakery',
    VendorCategory.other => 'Other',
  };
}

enum VendorApplicationStatus { draft, pending }

/// A prospective vendor's registration application — built up across the
/// Business Info / Contact & Location steps of the wizard and, on submit,
/// flipped to [VendorApplicationStatus.pending].
///
/// STUB: there is no real application-review backend yet. `submit()` just
/// moves this local, in-memory record to `pending` — same convention as
/// `AuthController.submitKyc`, which moves a runner/student to
/// [KycStatus.pending] with no real review queue behind it either. A real
/// implementation would POST this and track a server-issued application
/// id; approval would arrive by email with dashboard access, not by any
/// further mobile screen (menu/order management is explicitly web-app
/// scope — see `vendor_pending_screen.dart`).
class VendorApplication {
  const VendorApplication({
    this.businessName = '',
    this.category,
    this.description = '',
    this.contactName = '',
    this.contactPhone = '',
    this.campus,
    this.storefrontPhoto,
    this.status = VendorApplicationStatus.draft,
  });

  final String businessName;
  final VendorCategory? category;
  final String description;
  final String contactName;
  final String contactPhone;
  final Campus? campus;
  final Uint8List? storefrontPhoto;
  final VendorApplicationStatus status;

  bool get businessInfoComplete =>
      businessName.trim().isNotEmpty && category != null;
  bool get contactInfoComplete =>
      contactName.trim().isNotEmpty &&
      contactPhone.trim().isNotEmpty &&
      campus != null;
  bool get isSubmittable => businessInfoComplete && contactInfoComplete;

  VendorApplication copyWith({
    String? businessName,
    VendorCategory? category,
    String? description,
    String? contactName,
    String? contactPhone,
    Campus? campus,
    Uint8List? storefrontPhoto,
    bool clearStorefrontPhoto = false,
    VendorApplicationStatus? status,
  }) => VendorApplication(
    businessName: businessName ?? this.businessName,
    category: category ?? this.category,
    description: description ?? this.description,
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
    campus: campus ?? this.campus,
    storefrontPhoto: clearStorefrontPhoto
        ? null
        : storefrontPhoto ?? this.storefrontPhoto,
    status: status ?? this.status,
  );
}

/// The wizard's fixed step sequence — a single source of truth so the
/// progress bar's step count can never drift from the actual screens, the
/// same convention as KYC's `kycStepsFor`. Unlike KYC, this sequence never
/// branches (there's no runner-type-style fork for a vendor application),
/// but it's still centralized here rather than each step hardcoding its
/// own index/count.
enum VendorStepKind { businessInfo, contactLocation, review }

const vendorSteps = [
  VendorStepKind.businessInfo,
  VendorStepKind.contactLocation,
  VendorStepKind.review,
];
