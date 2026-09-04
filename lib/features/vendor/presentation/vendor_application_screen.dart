import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/segmented_progress_bar.dart';
import '../../auth/presentation/kyc/camera_capture_step.dart';
import '../../auth/presentation/widgets/campus_picker_field.dart';
import '../../auth/presentation/widgets/validated_field.dart';
import '../../payout/domain/payout_models.dart';
import '../../payout/presentation/widgets/payout_account_form.dart';
import '../application/vendor_application_controller.dart';
import '../domain/vendor_models.dart';
import 'widgets/category_picker_field.dart';

/// Business Info → Contact & Location → Review, one route/screen with an
/// internal step index — same wizard shape as [KycCaptureScreen] (shared
/// chrome, back button decrements `_step` instead of popping a route,
/// "Edit" from Review jumps `_step` directly rather than re-pushing
/// screens). Reached once, right after biometric setup (or a skip), via
/// `postBiometricDestination` — never re-entered mid-flow by any other
/// route, so step 0 has nothing meaningful to pop back to (same as KYC).
class VendorApplicationScreen extends ConsumerStatefulWidget {
  const VendorApplicationScreen({super.key});

  @override
  ConsumerState<VendorApplicationScreen> createState() =>
      _VendorApplicationScreenState();
}

class _VendorApplicationScreenState
    extends ConsumerState<VendorApplicationScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final application = ref.watch(vendorApplicationProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      onPressed: () => setState(() => _step -= 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    )
                  else
                    const SizedBox(width: 44),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SegmentedProgressBar(
                      stepCount: vendorSteps.length,
                      currentIndex: _step,
                      filledColor: AppColors.accentForest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: _buildStep(application)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(VendorApplication application) {
    switch (vendorSteps[_step]) {
      case VendorStepKind.businessInfo:
        return _BusinessInfoStep(
          key: const ValueKey('vendor-business-info'),
          application: application,
          onContinue: () => setState(() => _step += 1),
        );
      case VendorStepKind.contactLocation:
        return _ContactLocationStep(
          key: const ValueKey('vendor-contact-location'),
          application: application,
          onContinue: () => setState(() => _step += 1),
        );
      case VendorStepKind.payoutDetails:
        return _PayoutDetailsStep(
          key: const ValueKey('vendor-payout-details'),
          application: application,
          onContinue: () => setState(() => _step += 1),
        );
      case VendorStepKind.review:
        return _ReviewStep(
          application: application,
          onEditBusiness: () => setState(
            () => _step = vendorSteps.indexOf(VendorStepKind.businessInfo),
          ),
          onEditContact: () => setState(
            () => _step = vendorSteps.indexOf(VendorStepKind.contactLocation),
          ),
          onEditPayout: () => setState(
            () => _step = vendorSteps.indexOf(VendorStepKind.payoutDetails),
          ),
        );
    }
  }
}

/// Hero icon badge shared by all three steps — same elevated
/// gradient-circle treatment as the KYC intro/Create Account hero badges,
/// just in the restaurant role's forest-green accent instead of rose, so
/// the whole wizard visually reads as a continuation of the "I'm a
/// Restaurant" choice on Account Type rather than a generic form.
class _StepHero extends StatelessWidget {
  const _StepHero({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentForest, AppColors.accentForestDeep],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppElevation.raised(false),
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    ).animate().fadeIn(duration: 280.ms).scale(begin: const Offset(.85, .85));
  }
}

class _BusinessInfoStep extends ConsumerStatefulWidget {
  const _BusinessInfoStep({
    super.key,
    required this.application,
    required this.onContinue,
  });
  final VendorApplication application;
  final VoidCallback onContinue;

  @override
  ConsumerState<_BusinessInfoStep> createState() => _BusinessInfoStepState();
}

class _BusinessInfoStepState extends ConsumerState<_BusinessInfoStep> {
  late final _nameController = TextEditingController(
    text: widget.application.businessName,
  );
  late final _descriptionController = TextEditingController(
    text: widget.application.description,
  );
  final _nameFieldKey = GlobalKey<ValidatedFieldState>();
  late String? _category = widget.application.category;
  String? _categoryError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _continue() {
    final nameOk = _nameFieldKey.currentState?.validateNow() ?? false;
    final category = _category;
    setState(
      () => _categoryError = category == null ? 'Choose a category to continue.' : null,
    );
    if (!nameOk || category == null) return;

    ref
        .read(vendorApplicationProvider.notifier)
        .setBusinessInfo(
          businessName: _nameController.text.trim(),
          category: category,
          description: _descriptionController.text.trim(),
        );
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    var stagger = 0;
    Widget staggered(Widget child) {
      final delay = Duration(milliseconds: 60 * stagger++);
      return child
          .animate()
          .fadeIn(delay: delay, duration: 240.ms)
          .moveY(begin: 10, end: 0);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _StepHero(icon: Icons.storefront_rounded)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Tell us about your business',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: onBg, fontSize: 25),
          ).animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
          const SizedBox(height: 6),
          Text(
            'A few details so students know what you serve.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          staggered(
            ValidatedField(
              key: _nameFieldKey,
              controller: _nameController,
              hintText: "e.g. Mama Kemi's Kitchen",
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 20, right: 12),
                child: Icon(
                  Icons.storefront_rounded,
                  size: 22,
                  color: AppColors.accentForest,
                ),
              ),
              validator: (value) =>
                  value.trim().length < 2 ? 'Enter your business name.' : null,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          staggered(
            Text(
              'Category',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: onBg),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          staggered(
            CategoryPickerField(
              selected: _category,
              errorText: _categoryError,
              onChanged: (category) {
                HapticFeedback.selectionClick();
                setState(() {
                  _category = category;
                  _categoryError = null;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          staggered(
            ValidatedField(
              controller: _descriptionController,
              hintText: 'Short description (optional)',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 20, right: 12),
                child: Icon(
                  Icons.notes_rounded,
                  size: 22,
                  color: AppColors.accentForest,
                ),
              ),
              validator: (_) => null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          staggered(PrimaryButton(label: 'Continue', onPressed: _continue)),
        ],
      ),
    );
  }
}

class _ContactLocationStep extends ConsumerStatefulWidget {
  const _ContactLocationStep({
    super.key,
    required this.application,
    required this.onContinue,
  });
  final VendorApplication application;
  final VoidCallback onContinue;

  @override
  ConsumerState<_ContactLocationStep> createState() =>
      _ContactLocationStepState();
}

class _ContactLocationStepState extends ConsumerState<_ContactLocationStep> {
  late final _nameController = TextEditingController(
    text: widget.application.contactName,
  );
  late final _phoneController = TextEditingController(
    text: widget.application.contactPhone,
  );
  final _nameFieldKey = GlobalKey<ValidatedFieldState>();
  final _phoneFieldKey = GlobalKey<ValidatedFieldState>();
  late CampusOption? _campus = widget.application.campus;
  String? _campusError;
  late Uint8List? _photo = widget.application.storefrontPhoto;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _continue() {
    final nameOk = _nameFieldKey.currentState?.validateNow() ?? false;
    final phoneOk = _phoneFieldKey.currentState?.validateNow() ?? false;
    final campus = _campus;
    setState(
      () => _campusError = campus == null
          ? 'Choose your storefront location.'
          : null,
    );
    if (!nameOk || !phoneOk || campus == null) return;

    final notifier = ref.read(vendorApplicationProvider.notifier);
    notifier.setContactInfo(
      contactName: _nameController.text.trim(),
      contactPhone: _phoneController.text.trim(),
      campus: campus,
    );
    final photo = _photo;
    if (photo != null) notifier.setStorefrontPhoto(photo);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    var stagger = 0;
    Widget staggered(Widget child) {
      final delay = Duration(milliseconds: 60 * stagger++);
      return child
          .animate()
          .fadeIn(delay: delay, duration: 240.ms)
          .moveY(begin: 10, end: 0);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _StepHero(icon: Icons.location_on_rounded)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Contact & location',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: onBg, fontSize: 25),
          ).animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
          const SizedBox(height: 6),
          Text(
            "Who should we reach, and where's your storefront?",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          staggered(
            ValidatedField(
              key: _nameFieldKey,
              controller: _nameController,
              hintText: 'Contact person name',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 20, right: 12),
                child: Icon(
                  Icons.person_rounded,
                  size: 22,
                  color: AppColors.accentForest,
                ),
              ),
              validator: (value) =>
                  value.trim().length < 2 ? "Enter the contact's name." : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          staggered(
            ValidatedField(
              key: _phoneFieldKey,
              controller: _phoneController,
              hintText: 'Phone number',
              keyboardType: TextInputType.phone,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 20, right: 12),
                child: Icon(
                  Icons.call_rounded,
                  size: 22,
                  color: AppColors.accentForest,
                ),
              ),
              validator: (value) {
                final digits = value.replaceAll(RegExp(r'\D'), '');
                return digits.length >= 10
                    ? null
                    : 'Enter a valid phone number.';
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          staggered(
            CampusPickerField(
              selected: _campus,
              errorText: _campusError,
              onChanged: (campus) => setState(() {
                _campus = campus;
                _campusError = null;
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          staggered(
            Text(
              'Storefront photo (optional)',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: onBg),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          staggered(
            SizedBox(
              height: 320,
              child: CameraCaptureStep(
                key: const ValueKey('vendor-storefront-photo'),
                title: 'Storefront Photo',
                subtitle: 'Your shop front or space — shown on your dashboard listing.',
                permissionRationale: "We use your camera just for this photo — it's only used for your listing.",
                guide: CaptureGuide.document,
                lensDirection: CameraLensDirection.back,
                primaryActionLabel: 'Take Storefront Photo',
                tips: const [
                  'Good lighting helps your listing stand out',
                  'Fit your signage or entrance in frame',
                ],
                onCaptured: (bytes) => setState(() => _photo = bytes),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          staggered(PrimaryButton(label: 'Continue', onPressed: _continue)),
        ],
      ),
    );
  }
}

/// Task 8c Part C: the wizard's new third step, built on the same shared
/// [PayoutAccountForm] Runner Profile uses (Part A/B) — a restaurant
/// account reaches this already authenticated (see [AuthSession]'s doc
/// comment: it goes through the same session-creating funnel as
/// student/runner, just branching into this wizard afterward instead of
/// KYC/Home), so the form's backend call has a real user id/token to work
/// with here too.
class _PayoutDetailsStep extends ConsumerWidget {
  const _PayoutDetailsStep({
    super.key,
    required this.application,
    required this.onContinue,
  });
  final VendorApplication application;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    final initialAccount = application.payoutBankCode == null
        ? null
        : PayoutAccount(
            bankCode: application.payoutBankCode!,
            bankName: application.payoutBankName!,
            accountNumber: application.payoutAccountNumber!,
            accountName: application.payoutAccountName!,
          );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _StepHero(icon: Icons.account_balance_rounded)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Payout details',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: onBg, fontSize: 25),
          ).animate().fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
          const SizedBox(height: 6),
          Text(
            "Where we'll send your share of every order.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          PayoutAccountForm(
            initialAccount: initialAccount,
            onSaved: (account) {
              ref
                  .read(vendorApplicationProvider.notifier)
                  .setPayoutInfo(
                    bankCode: account.bankCode,
                    bankName: account.bankName,
                    accountNumber: account.accountNumber,
                    accountName: account.accountName,
                  );
              onContinue();
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({
    required this.application,
    required this.onEditBusiness,
    required this.onEditContact,
    required this.onEditPayout,
  });
  final VendorApplication application;
  final VoidCallback onEditBusiness;
  final VoidCallback onEditContact;
  final VoidCallback onEditPayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _StepHero(icon: Icons.fact_check_rounded)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Review & submit',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(color: onBg, fontSize: 25),
          ),
          const SizedBox(height: 6),
          Text(
            "Here's what we'll send for review.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          _ReviewCard(
            icon: Icons.storefront_rounded,
            title: 'Business',
            onEdit: onEditBusiness,
            rows: [
              ('Name', application.businessName),
              ('Category', application.category ?? '—'),
              if (application.description.trim().isNotEmpty)
                ('Description', application.description.trim()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ReviewCard(
            icon: Icons.location_on_rounded,
            title: 'Contact & Location',
            onEdit: onEditContact,
            rows: [
              ('Contact', application.contactName),
              ('Phone', application.contactPhone),
              ('Campus', application.campus?.name ?? '—'),
              (
                'Storefront photo',
                application.storefrontPhoto != null ? 'Added' : 'Not added',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ReviewCard(
            icon: Icons.account_balance_rounded,
            title: 'Payout Details',
            onEdit: onEditPayout,
            rows: [
              ('Bank', application.payoutBankName ?? '—'),
              (
                'Account number',
                application.payoutAccountNumber == null
                    ? '—'
                    : '•••• ${application.payoutAccountNumber!.substring(application.payoutAccountNumber!.length - 4)}',
              ),
              ('Account name', application.payoutAccountName ?? '—'),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Submit',
            onPressed: application.isSubmittable
                ? () {
                    // Task 12: auto-approved on submission (temporary
                    // stopgap — see VendorsService.upsertMyVendor's own
                    // doc comment for the tracked follow-up) — there's no
                    // review wait to hand off to, so this goes straight
                    // into confirming the real business profile instead of
                    // a dead-end pending screen.
                    ref.read(vendorApplicationProvider.notifier).submit();
                    context.go(AppRoutes.restaurantProfileSetup);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.icon,
    required this.title,
    required this.rows,
    required this.onEdit,
  });
  final IconData icon;
  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.card(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentForest.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: AppColors.accentForest),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: onBg),
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Text(
                    'Edit',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.accentForest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.borderSubtle),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: secondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: onBg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
