import 'dart:typed_data';

import '../../../core/network/campus_repository.dart' show CampusOption;

export '../../../core/network/campus_repository.dart' show CampusOption;

enum VendorApplicationStatus { draft, pending }

/// A prospective vendor's registration application — built up across the
/// Business Info / Contact & Location steps of the wizard and, on submit,
/// flipped to [VendorApplicationStatus.pending].
///
/// STUB: `submit()` just moves this local, in-memory record to `pending` —
/// nothing here is sent to the backend yet. The real `POST /vendors/me`
/// call happens right after, on `RestaurantProfileSetupScreen` (Task 12),
/// which prefills itself from this same record rather than asking the
/// restaurant to re-enter business name/category/description/campus
/// preference (Task 27). Submission goes into the real admin review queue
/// (Task 13c) straight into that screen, then the Restaurant Dashboard
/// shell — order/menu management is genuinely mobile scope now (Task 12),
/// not web-app-only.
class VendorApplication {
  const VendorApplication({
    this.businessName = '',
    this.category,
    this.description = '',
    this.contactName = '',
    this.contactPhone = '',
    this.campus,
    this.storefrontPhoto,
    this.payoutBankCode,
    this.payoutBankName,
    this.payoutAccountNumber,
    this.payoutAccountName,
    this.status = VendorApplicationStatus.draft,
  });

  final String businessName;
  // The canonical label of one of the backend's controlled vendor
  // categories (`GET /vendors/categories`) — these double as the filter
  // chips students already browse Home by, so a vendor's category has to
  // land on a value the student side actually understands. Picked via
  // `CategoryPickerField`, never typed free text, so it always matches
  // one of the backend's own values.
  final String? category;
  final String description;
  final String contactName;
  final String contactPhone;
  final CampusOption? campus;
  final Uint8List? storefrontPhoto;

  /// Set together, from the shared `PayoutAccountForm`'s resolved result
  /// (Task 8c Part A) — `payoutAccountName` is always what Paystack
  /// resolved, never typed by the vendor.
  final String? payoutBankCode;
  final String? payoutBankName;
  final String? payoutAccountNumber;
  final String? payoutAccountName;
  final VendorApplicationStatus status;

  bool get businessInfoComplete =>
      businessName.trim().isNotEmpty && category != null;
  bool get contactInfoComplete =>
      contactName.trim().isNotEmpty &&
      contactPhone.trim().isNotEmpty &&
      campus != null;
  bool get payoutInfoComplete =>
      payoutBankCode != null &&
      payoutAccountNumber != null &&
      payoutAccountName != null;
  bool get isSubmittable =>
      businessInfoComplete && contactInfoComplete && payoutInfoComplete;

  VendorApplication copyWith({
    String? businessName,
    String? category,
    String? description,
    String? contactName,
    String? contactPhone,
    CampusOption? campus,
    Uint8List? storefrontPhoto,
    bool clearStorefrontPhoto = false,
    String? payoutBankCode,
    String? payoutBankName,
    String? payoutAccountNumber,
    String? payoutAccountName,
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
    payoutBankCode: payoutBankCode ?? this.payoutBankCode,
    payoutBankName: payoutBankName ?? this.payoutBankName,
    payoutAccountNumber: payoutAccountNumber ?? this.payoutAccountNumber,
    payoutAccountName: payoutAccountName ?? this.payoutAccountName,
    status: status ?? this.status,
  );
}

/// The wizard's fixed step sequence — a single source of truth so the
/// progress bar's step count can never drift from the actual screens, the
/// same convention as KYC's `kycStepsFor`. Unlike KYC, this sequence never
/// branches (there's no runner-type-style fork for a vendor application),
/// but it's still centralized here rather than each step hardcoding its
/// own index/count.
enum VendorStepKind { businessInfo, contactLocation, payoutDetails, review }

const vendorSteps = [
  VendorStepKind.businessInfo,
  VendorStepKind.contactLocation,
  VendorStepKind.payoutDetails,
  VendorStepKind.review,
];
