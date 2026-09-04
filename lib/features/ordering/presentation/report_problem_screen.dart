import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/orders_repository.dart';
import '../../../core/network/uploads_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/kyc/camera_capture_step.dart';

/// Task 30: the real student-facing "report a problem" entry point — Home
/// screen this app never had before (per the Task 28 audit: complaints
/// required going outside the app entirely). Reuses the existing Dispute
/// model/admin-review flow (`POST /orders/:orderId/report`); this screen
/// only collects a reason and an optional photo, then hands both to
/// [OrdersRepository.reportProblem].
class ReportProblemScreen extends ConsumerStatefulWidget {
  const ReportProblemScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ReportProblemScreen> createState() =>
      _ReportProblemScreenState();
}

class _ReportProblemScreenState extends ConsumerState<ReportProblemScreen> {
  final _reasonController = TextEditingController();
  Uint8List? _photo;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const _ReportPhotoCaptureScreen()),
    );
    if (bytes != null && mounted) setState(() => _photo = bytes);
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Tell us what went wrong.');
      return;
    }
    final token = ref.read(authControllerProvider)?.accessToken;
    if (token == null) {
      setState(() => _error = 'Your session has expired. Sign in again to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      String? photoUrl;
      final photo = _photo;
      if (photo != null) {
        photoUrl = await ref
            .read(uploadsRepositoryProvider)
            .uploadImage(
              bytes: photo,
              purpose: 'dispute-report',
              contentType: 'image/jpeg',
              token: token,
            );
      }
      await ref
          .read(ordersRepositoryProvider)
          .reportProblem(
            orderId: widget.orderId,
            reason: reason,
            photoUrl: photoUrl,
            token: token,
          );
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .info("We've received your report and will follow up.");
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException
            ? e.message
            : "Couldn't submit your report. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;

    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "What went wrong?",
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: onBg),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Describe the issue — our team will review your order and follow up.",
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _reasonController,
                maxLines: 5,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'e.g. My order arrived cold and missing an item.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_photo == null)
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _addPhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Add a photo (optional)'),
                )
              else
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(
                        _photo!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _photo = null),
                      child: const Text('Remove photo'),
                    ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Submit report',
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal capture-only screen — hands the raw bytes back to
/// [ReportProblemScreen], which uploads only at final submit time (so
/// backing out without submitting never wastes an upload).
class _ReportPhotoCaptureScreen extends StatelessWidget {
  const _ReportPhotoCaptureScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a photo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: CameraCaptureStep(
            title: 'Photo of the problem',
            subtitle: 'Shows what went wrong with your order.',
            permissionRationale:
                "We use your camera just for this photo — it's attached to your report.",
            guide: CaptureGuide.document,
            lensDirection: CameraLensDirection.back,
            primaryActionLabel: 'Take Photo',
            onCaptured: (bytes) => Navigator.of(context).pop(bytes),
          ),
        ),
      ),
    );
  }
}
