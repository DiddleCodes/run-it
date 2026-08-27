import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../application/runner_controller.dart';
import '../domain/runner_models.dart';

/// Which scan is expected right now, derived from the active delivery's
/// own status — never a context-blind generic prompt when there IS a job
/// to scan for. Falls back to a generic prompt only when there's truly no
/// active delivery (the scanner itself still works either way — scanning
/// with no active job just has nothing to advance). Pulled out as a pure
/// function (rather than inlined in `build`) so it's unit-testable
/// without mounting the camera widget, which needs a real platform
/// channel `flutter_test` can't provide.
({String label, String subject}) scanContextFor(ActiveDelivery? active) {
  if (active == null) {
    return (label: 'Scan to start or complete a delivery', subject: '');
  }
  final pickup = active.status == DeliveryStage.accepted;
  return (
    label: pickup ? 'Scanning pickup code' : 'Scanning delivery code',
    subject: pickup ? active.job.eateryName : active.job.dropoffZone,
  );
}

/// Full-screen camera scan flow. There's no real backend to validate a
/// scanned code against yet, so — same demo simplification as OTP
/// accepting any 6 digits — any detected barcode/QR value (or manually
/// entered code) counts as a successful scan. If there's an active
/// delivery, that advances its status; scanning with no active job just
/// shows the success moment with nothing to advance.
class RunnerScanScreen extends ConsumerStatefulWidget {
  const RunnerScanScreen({super.key});
  @override
  ConsumerState<RunnerScanScreen> createState() => _RunnerScanScreenState();
}

class _RunnerScanScreenState extends ConsumerState<RunnerScanScreen> {
  late final _controller = MobileScannerController();
  bool _handled = false;
  bool _torchOn = false;
  bool _success = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    context.canPop() ? context.pop() : context.go(AppRoutes.runnerHome);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // No torch on this device/camera — nothing to toggle.
    }
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    _completeScan();
  }

  Future<void> _completeScan() async {
    if (_handled) return;
    setState(() => _handled = true);
    unawaited(_controller.stop());
    HapticFeedback.mediumImpact();
    setState(() => _success = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final active = ref.read(runnerControllerProvider).activeDelivery;
    if (active != null) {
      final notifier = ref.read(runnerControllerProvider.notifier);
      if (active.status == DeliveryStage.accepted) {
        notifier.confirmPickup();
      } else {
        notifier.confirmDropoff();
      }
    }
    if (!mounted) return;
    _close();
  }

  void _enterManually() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _ManualCodeSheet(
        onSubmit: () {
          Navigator.pop(sheetContext);
          _completeScan();
        },
      ),
    );
  }

  void _stubAction(String message) =>
      ref.read(appNotificationProvider.notifier).info(message);

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(runnerControllerProvider).activeDelivery;
    final scanContext = scanContextFor(active);

    return Scaffold(
      backgroundColor: AppColors.scannerBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleDetect),
          const _ScanFrameOverlay(),
          SafeArea(
            child: Column(
              children: [
                _ContextBar(
                  torchOn: _torchOn,
                  onClose: _close,
                  onToggleTorch: _toggleTorch,
                ),
                const SizedBox(height: 10),
                _EnterCodePill(onTap: _handled ? null : _enterManually),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    scanContext.subject.isEmpty
                        ? scanContext.label
                        : '${scanContext.label} — ${scanContext.subject}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
                Text(
                  'Align QR code within the frame',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.scannerGreen),
                ),
                const SizedBox(height: 22),
                _BottomActionsRow(
                  onGalleryTap: () => _stubAction('Scanning from gallery is coming soon.'),
                  onMyCodeTap: () => _stubAction('Your runner QR code is coming soon.'),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
          if (_success) const _ScanSuccessOverlay(),
        ],
      ),
    );
  }
}

class _ContextBar extends StatelessWidget {
  const _ContextBar({
    required this.torchOn,
    required this.onClose,
    required this.onToggleTorch,
  });
  final bool torchOn;
  final VoidCallback onClose;
  final VoidCallback onToggleTorch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _RoundIconButton(icon: CupertinoIcons.xmark, onTap: onClose),
          Expanded(
            child: Text(
              'Scan',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          _RoundIconButton(
            icon: torchOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
            onTap: onToggleTorch,
            active: torchOn,
          ),
        ],
      ),
    );
  }
}

/// Floating manual-entry fallback, near the top of the scanner rather
/// than a plain link at the bottom.
class _EnterCodePill extends StatelessWidget {
  const _EnterCodePill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.keyboard, size: 15, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              'Enter code',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActionsRow extends StatelessWidget {
  const _BottomActionsRow({required this.onGalleryTap, required this.onMyCodeTap});
  final VoidCallback onGalleryTap;
  final VoidCallback onMyCodeTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: _BottomAction(
              icon: CupertinoIcons.photo,
              label: 'Scan from gallery',
              onTap: onGalleryTap,
            ),
          ),
          Container(width: 1, height: 34, color: Colors.white12),
          Expanded(
            child: _BottomAction(
              icon: CupertinoIcons.qrcode,
              label: 'My QR code',
              onTap: onMyCodeTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: .9)
              : Colors.black.withValues(alpha: .45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Semi-transparent scrim with a clear square cutout, animated corner
/// brackets, and a sweeping scan-line — the "viewfinder" look, purely
/// decorative on top of the live camera preview beneath it.
class _ScanFrameOverlay extends StatefulWidget {
  const _ScanFrameOverlay();
  @override
  State<_ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<_ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frame = (constraints.maxWidth * .72).clamp(0.0, 300.0);
          final vGap = (constraints.maxHeight - frame) / 2;
          final hGap = (constraints.maxWidth - frame) / 2;
          const scrim = Color(0x80000000);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Four scrim rectangles framing a clear center window —
              // simpler and more reliably correct than a blend-mode
              // "hole punch", at the cost of square (not rounded) corners
              // on the window itself.
              Positioned(top: 0, left: 0, right: 0, height: vGap, child: const ColoredBox(color: scrim)),
              Positioned(bottom: 0, left: 0, right: 0, height: vGap, child: const ColoredBox(color: scrim)),
              Positioned(top: vGap, bottom: vGap, left: 0, width: hGap, child: const ColoredBox(color: scrim)),
              Positioned(top: vGap, bottom: vGap, right: 0, width: hGap, child: const ColoredBox(color: scrim)),
              SizedBox(
                width: frame,
                height: frame,
                child: Stack(
                  children: [
                    CustomPaint(size: Size(frame, frame), painter: _CornerBracketsPainter()),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => Positioned(
                        top: 10 + _controller.value * (frame - 20),
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.scannerGreen.withValues(alpha: 0),
                                AppColors.scannerGreen,
                                AppColors.scannerGreen.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.scannerGreen.withValues(alpha: .7),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.scannerGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    const r = AppRadius.lg;

    void corner(Offset origin, Offset dx, Offset dy) {
      final path = Path()
        ..moveTo(origin.dx + dx.dx * len, origin.dy + dx.dy * len)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + dy.dx * len, origin.dy + dy.dy * len);
      canvas.drawPath(path, paint);
    }

    corner(const Offset(r, 0), const Offset(1, 0), const Offset(0, 1));
    corner(Offset(size.width - r, 0), const Offset(-1, 0), const Offset(0, 1));
    corner(Offset(0, size.height - r), const Offset(1, 0), const Offset(0, -1));
    corner(
      Offset(size.width, size.height - r),
      const Offset(-1, 0),
      const Offset(0, -1),
    );
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) => false;
}

/// Same green-circle-checkmark language as the KYC Verified badge — scale
/// + fade in, briefly, before the job status advances. Uses the
/// scanner's own green rather than the app-wide success color, since
/// it's part of this screen's dedicated dark/green sub-theme.
class _ScanSuccessOverlay extends StatelessWidget {
  const _ScanSuccessOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .55),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, value, child) =>
            Transform.scale(scale: value, child: child),
        child: Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.scannerGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.scannerGreen.withValues(alpha: .5),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.checkmark_alt,
            color: AppColors.scannerBackground,
            size: 44,
          ),
        ),
      ),
    );
  }
}

class _ManualCodeSheet extends StatefulWidget {
  const _ManualCodeSheet({required this.onSubmit});
  final VoidCallback onSubmit;

  @override
  State<_ManualCodeSheet> createState() => _ManualCodeSheetState();
}

class _ManualCodeSheetState extends State<_ManualCodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter code manually',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: AppColors.inkText, fontSize: 19),
          ),
          const SizedBox(height: 6),
          Text(
            'Use this if the camera can’t read the code.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'e.g. RI-2048'),
            onSubmitted: (_) => widget.onSubmit(),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                  foregroundColor: AppColors.onMaroon,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: value.text.trim().isEmpty ? null : widget.onSubmit,
                child: const Text('Confirm'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
