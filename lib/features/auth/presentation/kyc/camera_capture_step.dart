import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_spinner.dart';
import '../../../../core/widgets/primary_button.dart';

enum CaptureGuide { document, face }

/// One capture step (ID or selfie) shared by both the light (student) and
/// full (runner) KYC flows. There is no real document/face-detection model
/// wired up — "steady in frame" is simulated with a timed progress ring,
/// clearly separate from the real camera preview and real file capture
/// around it, which are genuine `camera` package calls.
class CameraCaptureStep extends StatefulWidget {
  const CameraCaptureStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.permissionRationale,
    required this.guide,
    required this.lensDirection,
    required this.onCaptured,
    this.livenessHint,
    this.primaryActionLabel = 'Allow camera access',
    this.tips,
  });

  final String title;
  final String subtitle;
  final String permissionRationale;
  final CaptureGuide guide;
  final CameraLensDirection lensDirection;
  final String? livenessHint;
  final ValueChanged<Uint8List> onCaptured;
  final String primaryActionLabel;

  /// Bulleted, check-icon tips shown under the permission rationale on the
  /// priming state — used for the ID-upload step.
  final List<String>? tips;

  @override
  State<CameraCaptureStep> createState() => _CameraCaptureStepState();
}

enum _Phase { priming, initializing, live, error, review }

class _CameraCaptureStepState extends State<CameraCaptureStep>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  _Phase _phase = _Phase.priming;
  String _errorMessage = '';
  Uint8List? _captured;
  Timer? _autoCaptureTimer;
  late final _steadyController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _steadyController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _requestAccess() async {
    setState(() => _phase = _Phase.initializing);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamerasAvailable', 'none found');
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == widget.lensDirection,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _phase = _Phase.live;
      });
      _beginSteadyDetection();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('denied') || text.contains('permission')) {
      return 'Camera access was denied. Please allow it in your device settings and try again.';
    }
    if (text.contains('nocamerasavailable') || text.contains('notfound')) {
      return 'No camera was found on this device.';
    }
    return "Couldn't open the camera. Please try again.";
  }

  void _beginSteadyDetection() {
    _steadyController.forward(from: 0);
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer(const Duration(milliseconds: 2400), _capture);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _autoCaptureTimer?.cancel();
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _captured = bytes;
        _phase = _Phase.review;
      });
      await controller.dispose();
      _controller = null;
    } catch (_) {
      _beginSteadyDetection();
    }
  }

  void _retake() {
    setState(() {
      _captured = null;
      _phase = _Phase.priming;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.priming:
        return _Priming(
          title: widget.title,
          subtitle: widget.subtitle,
          rationale: widget.permissionRationale,
          actionLabel: widget.primaryActionLabel,
          tips: widget.tips,
          onContinue: _requestAccess,
        );
      case _Phase.initializing:
        return const _CenteredMessage(
          spinner: true,
          message: 'Opening camera…',
        );
      case _Phase.error:
        return _CenteredMessage(
          message: _errorMessage,
          isError: true,
          onRetry: _requestAccess,
        );
      case _Phase.live:
        return widget.guide == CaptureGuide.face
            ? _FaceLivePreview(
                controller: _controller!,
                livenessHint: widget.livenessHint,
                steadyController: _steadyController,
                onManualCapture: _capture,
              )
            : _LivePreview(
                controller: _controller!,
                guide: widget.guide,
                steadyController: _steadyController,
                onManualCapture: _capture,
              );
      case _Phase.review:
        return _ReviewCaptured(
          image: _captured!,
          onRetake: _retake,
          onConfirm: () => widget.onCaptured(_captured!),
        );
    }
  }
}

class _Priming extends StatelessWidget {
  const _Priming({
    required this.title,
    required this.subtitle,
    required this.rationale,
    required this.actionLabel,
    required this.onContinue,
    this.tips,
  });
  final String title;
  final String subtitle;
  final String rationale;
  final String actionLabel;
  final List<String>? tips;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    const secondary = AppColors.mutedText;
    const surface = AppColors.surfaceCard;
    const border = AppColors.borderSubtle;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _CapturePlaceholderCard(icon: Icons.camera_alt_rounded),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: onBg),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: secondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    rationale,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: secondary),
                  ),
                ),
              ],
            ),
          ),
          if (tips != null && tips!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tip in tips!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: AppColors.primaryMaroon,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              tip,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: actionLabel, onPressed: onContinue),
        ],
      ),
    );
  }
}

/// The empty-state "photo will go here" frame shown while priming — a
/// dashed elevated card reads as "capture area" at a glance, rather than
/// the flat solid icon badge it replaces.
class _CapturePlaceholderCard extends StatelessWidget {
  const _CapturePlaceholderCard({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const surface = AppColors.surfaceCard;
    const dash = AppColors.borderSubtle;

    return SizedBox(
      width: double.infinity,
      height: 128,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: dash),
        child: Container(
          margin: const EdgeInsets.all(2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Icon(icon, size: 34, color: AppColors.mutedText),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color});
  final Color color;
  static const _radius = 20.0;
  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    var distance = 0.0;
    while (distance < metric.length) {
      final next = (distance + _dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.message,
    this.spinner = false,
    this.isError = false,
    this.onRetry,
  });
  final String message;
  final bool spinner;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final color = isError ? AppColors.error : onBg;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const AppSpinner(color: AppColors.primaryMaroon)
          else if (isError)
            Icon(Icons.error_outline_rounded, color: color, size: 36),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.controller,
    required this.guide,
    required this.steadyController,
    required this.onManualCapture,
  });
  final CameraController controller;
  final CaptureGuide guide;
  final AnimationController steadyController;
  final VoidCallback onManualCapture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                CustomPaint(
                  painter: _GuidePainter(guide: guide),
                  child: const SizedBox.expand(),
                ),
                Positioned(
                  bottom: AppSpacing.lg,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: onManualCapture,
                      child: AnimatedBuilder(
                        animation: steadyController,
                        builder: (context, _) => SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: steadyController.value,
                                strokeWidth: 3,
                                color: AppColors.accentRose,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Hold steady — capturing automatically',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// The selfie step's preview: a circular, rose-ringed camera view with a
/// capture FAB anchored at its bottom-right, rather than the full-frame
/// rectangular guide used for document capture.
class _FaceLivePreview extends StatelessWidget {
  const _FaceLivePreview({
    required this.controller,
    required this.steadyController,
    required this.onManualCapture,
    this.livenessHint,
  });
  final CameraController controller;
  final AnimationController steadyController;
  final VoidCallback onManualCapture;
  final String? livenessHint;

  @override
  Widget build(BuildContext context) {
    const diameter = 260.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: diameter + 24,
          height: diameter + 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentRose, width: 5),
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: diameter,
                    height: diameter,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize?.height ?? diameter,
                        height: controller.value.previewSize?.width ?? diameter,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: GestureDetector(
                  onTap: onManualCapture,
                  child: AnimatedBuilder(
                    animation: steadyController,
                    builder: (context, _) => SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: steadyController.value,
                            strokeWidth: 3,
                            color: AppColors.primaryMaroonDeep,
                            backgroundColor: AppColors.onMaroon.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryMaroon,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: AppColors.onMaroon,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          livenessHint ?? 'Center your face in the circle',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.guide});
  final CaptureGuide guide;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentRose
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.8,
      height: size.width * 0.52,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.guide != guide;
}

class _ReviewCaptured extends StatelessWidget {
  const _ReviewCaptured({
    required this.image,
    required this.onRetake,
    required this.onConfirm,
  });
  final Uint8List image;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    const secondary = AppColors.mutedText;

    return Column(
      children: [
        Text(
          'Pinch to zoom in and check the details are readable.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppElevation.raised(false),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(
                  image,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Use this photo', onPressed: onConfirm),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onRetake,
          style: TextButton.styleFrom(foregroundColor: secondary),
          child: const Text('Retake'),
        ),
      ],
    );
  }
}
