import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/campus_repository.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_notification.dart';
import '../../../../core/widgets/checklist_row.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/segmented_progress_bar.dart';
import '../../application/auth_controller.dart';
import '../../application/kyc_flow_controller.dart';
import '../../domain/auth_models.dart';
import 'camera_capture_step.dart';

/// ID → Selfie → [Vehicle Photo → Vehicle Details, independent riders
/// only] → Almost There for runners; ID → Student Details → Almost There
/// for students, since light KYC skips the selfie-match step full KYC
/// requires.
class KycCaptureScreen extends ConsumerStatefulWidget {
  const KycCaptureScreen({super.key});

  @override
  ConsumerState<KycCaptureScreen> createState() => _KycCaptureScreenState();
}

class _KycCaptureScreenState extends ConsumerState<KycCaptureScreen> {
  int _step = 0;
  IdType _studentRunnerIdType = IdType.studentId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider);
    final user = session?.user;
    if (user == null) return const SizedBox.shrink();
    final isRunner = user.accountType == AccountType.runner;
    final capture = ref.watch(kycFlowProvider);
    final steps = kycStepsFor(isRunner, capture);
    // The capture step list can shrink (e.g. toggling runner type mid-flow
    // isn't possible today, but defensive clamping costs nothing).
    if (_step >= steps.length) _step = steps.length - 1;

    final screen = Scaffold(
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
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    )
                  else
                    const SizedBox(width: 32),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SegmentedProgressBar(
                      stepCount: steps.length,
                      currentIndex: _step,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _buildStep(context, isRunner, user, capture, steps),
              ),
            ],
          ),
        ),
      ),
    );

    return screen;
  }

  Widget _buildStep(
    BuildContext context,
    bool isRunner,
    UserProfile user,
    KycCapture capture,
    List<KycStepKind> steps,
  ) {
    switch (steps[_step]) {
      case KycStepKind.id:
        return _buildIdStep(isRunner, capture);
      case KycStepKind.selfie:
        return CameraCaptureStep(
          key: const ValueKey('selfie-step'),
          title: 'Take a Selfie',
          subtitle: "We'll match this against your ID photo.",
          permissionRationale: 'Your front camera is used only for this one photo, matched once against your ID.',
          guide: CaptureGuide.face,
          lensDirection: CameraLensDirection.front,
          primaryActionLabel: 'Enable Camera',
          livenessHint: 'Center your face and blink once',
          onCaptured: (bytes) {
            ref.read(kycFlowProvider.notifier).setSelfie(bytes);
            setState(() => _step += 1);
          },
        );
      case KycStepKind.studentDetails:
        return _StudentDetailsStep(
          user: user,
          onContinue: () => setState(() => _step += 1),
        );
      case KycStepKind.vehiclePhoto:
        return CameraCaptureStep(
          key: const ValueKey('vehicle-photo-step'),
          title: 'Photo of Your Vehicle',
          subtitle: 'Bicycle, motorbike, or keke — the full vehicle, clearly visible.',
          permissionRationale: "We use your camera just for this photo — it isn't stored anywhere except your verification record.",
          guide: CaptureGuide.document,
          lensDirection: CameraLensDirection.back,
          primaryActionLabel: 'Take Vehicle Photo',
          tips: const [
            'Fit the whole vehicle in frame',
            'Use good lighting with no glare',
            "Make sure the plate is readable, if it has one",
          ],
          onCaptured: (bytes) {
            ref.read(kycFlowProvider.notifier).setVehiclePhoto(bytes);
            setState(() => _step += 1);
          },
        );
      case KycStepKind.vehicleDetails:
        return _VehicleDetailsStep(
          capture: capture,
          onContinue: () => setState(() => _step += 1),
        );
      case KycStepKind.almostThere:
        return _AlmostThereStep(
          isRunner: isRunner,
          capture: capture,
          onEditId: () => setState(() => _step = steps.indexOf(KycStepKind.id)),
          onEditSelfie: steps.contains(KycStepKind.selfie)
              ? () => setState(() => _step = steps.indexOf(KycStepKind.selfie))
              : null,
          onEditStudentDetails: steps.contains(KycStepKind.studentDetails)
              ? () => setState(
                  () => _step = steps.indexOf(KycStepKind.studentDetails),
                )
              : null,
          onEditVehicle: steps.contains(KycStepKind.vehiclePhoto)
              ? () => setState(
                  () => _step = steps.indexOf(KycStepKind.vehiclePhoto),
                )
              : null,
        );
    }
  }

  Widget _buildIdStep(bool isRunner, KycCapture capture) {
    if (!isRunner) {
      // Light KYC (students) — unchanged copy from before this task.
      return CameraCaptureStep(
        key: const ValueKey('id-step'),
        title: 'Upload Student ID',
        subtitle: 'Student ID card, or any campus-issued ID with your photo.',
        permissionRationale: "We use your camera just for this photo — it isn't stored anywhere except your verification record.",
        guide: CaptureGuide.document,
        lensDirection: CameraLensDirection.back,
        primaryActionLabel: 'Upload ID Card',
        tips: const [
          'Use good lighting with no glare',
          'Keep all four corners of the card in frame',
          'Make sure your name and photo are readable',
        ],
        onCaptured: (bytes) {
          ref.read(kycFlowProvider.notifier).setId(bytes);
          setState(() => _step += 1);
        },
      );
    }

    if (capture.runnerType == RunnerType.independentRider) {
      return CameraCaptureStep(
        key: const ValueKey('id-step-govt'),
        title: 'Upload Government ID',
        subtitle:
            "A national ID, driver's license, or voter's card with your photo.",
        permissionRationale: "We use your camera just for this photo — it isn't stored anywhere except your verification record.",
        guide: CaptureGuide.document,
        lensDirection: CameraLensDirection.back,
        primaryActionLabel: 'Upload ID',
        tips: const [
          'Use good lighting with no glare',
          'Keep all four corners of the card in frame',
          'Make sure your name and photo are readable',
        ],
        onCaptured: (bytes) {
          ref
              .read(kycFlowProvider.notifier)
              .setId(bytes, idType: IdType.governmentId);
          setState(() => _step += 1);
        },
      );
    }

    // Student runner — either ID type works.
    final isStudentId = _studentRunnerIdType == IdType.studentId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdTypeToggle(
          value: _studentRunnerIdType,
          onChanged: (type) => setState(() => _studentRunnerIdType = type),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: CameraCaptureStep(
            key: ValueKey('id-step-$_studentRunnerIdType'),
            title: isStudentId ? 'Upload Student ID' : 'Upload Government ID',
            subtitle: isStudentId
                ? 'Student ID card, or any campus-issued ID with your photo.'
                : "A national ID, driver's license, or voter's card with your photo.",
            permissionRationale: "We use your camera just for this photo — it isn't stored anywhere except your verification record.",
            guide: CaptureGuide.document,
            lensDirection: CameraLensDirection.back,
            primaryActionLabel: 'Upload ID',
            tips: const [
              'Use good lighting with no glare',
              'Keep all four corners of the card in frame',
              'Make sure your name and photo are readable',
            ],
            onCaptured: (bytes) {
              ref
                  .read(kycFlowProvider.notifier)
                  .setId(bytes, idType: _studentRunnerIdType);
              setState(() => _step += 1);
            },
          ),
        ),
      ],
    );
  }
}

/// A government ID vs. student ID isn't a binary the light-weight
/// [CameraCaptureStep] widget itself needs to know about — it just
/// captures whatever's in frame — so the choice lives in this thin toggle
/// above it, which only changes copy and the recorded [IdType].
class _IdTypeToggle extends StatelessWidget {
  const _IdTypeToggle({required this.value, required this.onChanged});
  final IdType value;
  final ValueChanged<IdType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.borderSubtle.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'Student ID', IdType.studentId)),
          Expanded(
            child: _segment(context, 'Government ID', IdType.governmentId),
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, IdType type) {
    final selected = value == type;
    return GestureDetector(
      onTap: () {
        if (!selected) {
          HapticFeedback.selectionClick();
          onChanged(type);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryMaroon : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? AppColors.onMaroon : AppColors.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StudentDetailsStep extends ConsumerWidget {
  const _StudentDetailsStep({required this.user, required this.onContinue});
  final UserProfile user;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    final rows = <(String, String)>[
      ('Full Name', user.name),
      ('School', ref.watch(campusNameProvider(user.campusId)) ?? '—'),
      if (user.classOrGrade != null && user.classOrGrade!.isNotEmpty)
        ('Class / Grade', user.classOrGrade!),
      ('Student Email / Phone', user.contact),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Details',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: onBg),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Confirm this is you before we continue.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final (label, value) = rows[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: secondary, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: onBg, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Continue', onPressed: onContinue),
      ],
    );
  }
}

/// Vehicle type + plate/registration number, following the vehicle photo
/// capture — a bicycle has no plate to register, so [VehicleType.bicycle]
/// is the one selection where the plate field is optional.
class _VehicleDetailsStep extends ConsumerStatefulWidget {
  const _VehicleDetailsStep({required this.capture, required this.onContinue});
  final KycCapture capture;
  final VoidCallback onContinue;

  @override
  ConsumerState<_VehicleDetailsStep> createState() =>
      _VehicleDetailsStepState();
}

class _VehicleDetailsStepState extends ConsumerState<_VehicleDetailsStep> {
  late VehicleType? _type = widget.capture.vehicleType;
  late final _plateController = TextEditingController(
    text: widget.capture.plateNumber ?? '',
  );
  bool _showError = false;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  bool get _plateRequired => _type != null && _type != VehicleType.bicycle;

  void _selectType(VehicleType type) {
    HapticFeedback.selectionClick();
    setState(() {
      _type = type;
      _showError = false;
    });
  }

  void _continue() {
    final type = _type;
    final plate = _plateController.text.trim();
    if (type == null) {
      setState(() => _showError = true);
      return;
    }
    final plateOk =
        type == VehicleType.bicycle || isPlausiblePlateNumber(plate);
    if (!plateOk) {
      setState(() => _showError = true);
      return;
    }
    ref.read(kycFlowProvider.notifier).setVehicleType(type);
    ref.read(kycFlowProvider.notifier).setPlateNumber(plate);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const surface = AppColors.surfaceCard;
    const errorColor = AppColors.error;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentRose,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: AppColors.primaryMaroon,
              size: 30,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Vehicle Details',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: onBg),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'What will you be delivering on?',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (final type in VehicleType.values) ...[
                if (type != VehicleType.values.first)
                  const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _VehicleTypeChip(
                    type: type,
                    selected: _type == type,
                    onTap: () => _selectType(type),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _plateRequired
                ? 'Plate / registration number'
                : 'Plate / registration number (optional)',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color:
                    _showError &&
                        _plateRequired &&
                        !isPlausiblePlateNumber(_plateController.text)
                    ? errorColor
                    : AppColors.borderSubtle,
              ),
              boxShadow: AppElevation.card(false),
            ),
            child: TextField(
              controller: _plateController,
              textCapitalization: TextCapitalization.characters,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: onBg),
              decoration: InputDecoration(
                hintText: 'e.g. ABC-123-XY',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.ml,
                  vertical: 16,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 8),
                  child: Icon(
                    Icons.confirmation_number_rounded,
                    size: 20,
                    color: AppColors.primaryMaroon,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
              ),
            ),
          ),
          if (_showError) ...[
            const SizedBox(height: 6),
            Text(
              _type == null ? 'Choose a vehicle type to continue.' : 'Enter a valid plate/registration number for a motorised vehicle.',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: errorColor),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'Continue', onPressed: _continue),
        ],
      ),
    );
  }
}

class _VehicleTypeChip extends StatelessWidget {
  const _VehicleTypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });
  final VehicleType type;
  final bool selected;
  final VoidCallback onTap;

  (IconData, String) get _content => switch (type) {
    VehicleType.bicycle => (Icons.pedal_bike_rounded, 'Bicycle'),
    VehicleType.motorbike => (Icons.two_wheeler_rounded, 'Motorbike'),
    VehicleType.keke => (Icons.electric_rickshaw_rounded, 'Keke'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _content;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryMaroon : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primaryMaroon : AppColors.borderSubtle,
          ),
          boxShadow: selected ? AppElevation.raised(false) : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.onMaroon : AppColors.primaryMaroon,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.onMaroon : AppColors.inkText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlmostThereStep extends ConsumerStatefulWidget {
  const _AlmostThereStep({
    required this.isRunner,
    required this.capture,
    required this.onEditId,
    this.onEditSelfie,
    this.onEditStudentDetails,
    this.onEditVehicle,
  });

  final bool isRunner;
  final KycCapture capture;
  final VoidCallback onEditId;
  final VoidCallback? onEditSelfie;
  final VoidCallback? onEditStudentDetails;
  final VoidCallback? onEditVehicle;

  @override
  ConsumerState<_AlmostThereStep> createState() => _AlmostThereStepState();
}

class _AlmostThereStepState extends ConsumerState<_AlmostThereStep> {
  bool _submitting = false;

  /// Task 29: the real runner path — uploads the three captured photos and
  /// registers them for admin review. Unlike the student branch below,
  /// this is a real network round trip that can genuinely fail (no Brevo-
  /// style local fallback makes sense for a photo upload), so it needs a
  /// loading state and real error handling rather than an instant,
  /// can't-fail local state flip.
  Future<void> _submitRunner() async {
    final capture = widget.capture;
    final idImage = capture.idImage;
    final selfieImage = capture.selfieImage;
    final runnerType = capture.runnerType;
    // Defensive only — KycCaptureScreen's own step sequencing never reaches
    // this button without all of these already captured.
    if (idImage == null || selfieImage == null || runnerType == null) return;

    setState(() => _submitting = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .submitKycForReview(
          runnerType: runnerType,
          idType: capture.idType,
          idImage: idImage,
          selfieImage: selfieImage,
          vehiclePhoto: capture.vehiclePhoto,
          vehicleType: capture.vehicleType,
          vehiclePlate: capture.plateNumber,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      ref
          .read(appNotificationProvider.notifier)
          .error("Couldn't submit for verification. Check your connection and try again.");
      return;
    }
    ref.read(kycFlowProvider.notifier).reset();
    ref.read(appNotificationProvider.notifier).info('KYC submitted for review.');
    context.go(AppRoutes.kycStatus);
  }

  /// Light KYC (student) — unchanged local fake-resolution path, out of
  /// Task 29's scope (see its own report).
  void _submitStudent() {
    ref
        .read(authControllerProvider.notifier)
        .submitKyc(
          runnerType: widget.capture.runnerType,
          vehicleType: widget.capture.vehicleType,
          vehiclePlate: widget.capture.plateNumber,
        );
    ref.read(kycFlowProvider.notifier).reset();
    ref.read(appNotificationProvider.notifier).info('KYC submitted for review.');
    context.go(AppRoutes.kycStatus);
  }

  @override
  Widget build(BuildContext context) {
    final capture = widget.capture;
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Almost there',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: onBg),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "Here's what we'll submit for review.",
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderSubtle),
              boxShadow: AppElevation.card(false),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: widget.onEditId,
                    child: ChecklistRow(
                      label: capture.idType == IdType.governmentId
                          ? 'Government ID Uploaded'
                          : 'ID Card Uploaded',
                      complete: capture.hasId,
                    ),
                  ),
                  if (widget.onEditSelfie != null)
                    GestureDetector(
                      onTap: widget.onEditSelfie,
                      child: ChecklistRow(
                        label: 'Selfie Captured',
                        complete: capture.hasSelfie,
                      ),
                    ),
                  if (widget.onEditStudentDetails != null)
                    GestureDetector(
                      onTap: widget.onEditStudentDetails,
                      child: const ChecklistRow(
                        label: 'Student Details Completed',
                      ),
                    ),
                  if (widget.onEditVehicle != null)
                    GestureDetector(
                      onTap: widget.onEditVehicle,
                      child: ChecklistRow(
                        label: 'Vehicle Details Added',
                        complete: capture.vehicleStepComplete,
                      ),
                    ),
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.borderSubtle,
                  ),
                  const ChecklistRow(
                    label: 'Your data is encrypted and only used for verification.',
                    icon: Icons.lock_outline_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Submit for Verification',
          loading: _submitting,
          onPressed: _submitting
              ? null
              : (widget.isRunner ? _submitRunner : _submitStudent),
        ),
      ],
    );
  }
}
