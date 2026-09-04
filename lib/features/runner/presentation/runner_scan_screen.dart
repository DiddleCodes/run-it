import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/orders_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../../ordering/application/order_tracking_controller.dart';
import '../application/runner_controller.dart';
import '../domain/runner_models.dart';
import 'delivery_proof_capture_screen.dart';
import 'handoff_photo_capture_screen.dart';

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
  String? _errorMessage;

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
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _completeScan(code);
  }

  /// Task 11: the scanned/entered value is now checked against the real
  /// backend before anything advances — no optimistic UI. A mismatch (or
  /// rate-limit) shows a clear error and leaves the scanner ready to try
  /// again; it never silently "succeeds" the way the pre-Task-11 demo did.
  Future<void> _completeScan(String code) async {
    if (_handled) return;
    setState(() {
      _handled = true;
      _errorMessage = null;
    });
    unawaited(_controller.stop());
    HapticFeedback.mediumImpact();

    final active = ref.read(runnerControllerProvider).activeDelivery;
    // Task 21b: the real claimed order's own id — DeliveryJob.id is the
    // backend orderId (see MatchingRepository.listAvailable) now that
    // acceptJob() goes through a real claim, not orderTrackingProvider's
    // (a *different*, student-side, single-device local simulation of
    // whichever order this same device most recently placed as a student —
    // see its own doc comment. Only relevant below as an opportunistic
    // same-device testing convenience, never as the verification target).
    final orderId = active?.job.id;
    final notifier = ref.read(runnerControllerProvider.notifier);

    if (active == null || orderId == null) {
      // Nothing real to verify against — same "just show success" fallback
      // as before, since there is no active delivery/order in play.
      await _showSuccessAndClose();
      return;
    }

    final isPickup = active.status == DeliveryStage.accepted;
    bool verified;
    if (isPickup) {
      // Task 30: the required restaurant-handoff photo — captured before
      // the pickup code is even sent, since the backend rejects a
      // verify-pickup call with no photo (see VerifyPickupDto's own doc
      // comment). A cancelled/failed capture is treated exactly like a
      // failed verification below: nothing advances, scanner resumes.
      final handoffPhotoUrl = await _captureHandoffPhoto();
      verified = handoffPhotoUrl != null &&
          await _verifyPickup(orderId, code, handoffPhotoUrl);
    } else {
      verified = await _verifyDelivery(orderId, code);
    }

    if (!verified) {
      if (!mounted) return;
      setState(() => _handled = false);
      unawaited(_controller.start());
      return;
    }

    if (isPickup) {
      notifier.confirmPickup();
      _syncOrderTrackingIfSameOrder(orderId, (n) => n.markPickedUp());
    } else {
      notifier.confirmDropoff();
    }
    await _showSuccessAndClose();
  }

  /// Same-device testing convenience only (see `_completeScan`'s doc
  /// comment): if this device's own student-side order-tracking session
  /// happens to be watching the exact order just verified — i.e. someone
  /// is testing both sides of one order in a single app session — mirror
  /// the stage there too. A no-op for the normal, real case of a runner
  /// verifying a different student's order on their own device.
  void _syncOrderTrackingIfSameOrder(
    String orderId,
    void Function(OrderTrackingController) apply,
  ) {
    if (ref.read(orderTrackingProvider).orderId != orderId) return;
    apply(ref.read(orderTrackingProvider.notifier));
  }

  /// Task 21b: the real signed-in runner's own token — `EscrowPartyGuard`
  /// requires it to belong to whichever runner actually won this order's
  /// claim (Task 21a), which `acceptJob()` now always is. The old demo
  /// runner identity (`DemoIdentityService.ensureRunnerUserId`/
  /// `mintTokenFor`) retired with the single-offer flow it existed for —
  /// using it here would 403 against a really-claimed order, since that
  /// identity was never the one who claimed it.
  String? _runnerToken() => ref.read(authControllerProvider)?.accessToken;

  /// Task 30: pushes the handoff-photo capture screen and returns the real
  /// uploaded URL, or `null` if the runner backs out (or their session
  /// expired) — either way, the caller must not proceed to verify-pickup
  /// without one.
  Future<String?> _captureHandoffPhoto() async {
    final token = _runnerToken();
    if (token == null) {
      _showVerificationError('Your session has expired. Sign in again to continue.');
      return null;
    }
    if (!mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => HandoffPhotoCaptureScreen(token: token)),
    );
  }

  Future<bool> _verifyPickup(String orderId, String code, String handoffPhotoUrl) async {
    final token = _runnerToken();
    if (token == null) {
      return _showVerificationError('Your session has expired. Sign in again to continue.');
    }
    try {
      await ref
          .read(ordersRepositoryProvider)
          .verifyPickup(
            orderId: orderId,
            code: code,
            handoffPhotoUrl: handoffPhotoUrl,
            token: token,
          );
      return true;
    } on ApiException catch (e) {
      return _showVerificationError(e.message);
    } catch (_) {
      return _showVerificationError(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  Future<bool> _verifyDelivery(String orderId, String code) async {
    final token = _runnerToken();
    if (token == null) {
      return _showVerificationError('Your session has expired. Sign in again to continue.');
    }
    try {
      final outcome = await ref
          .read(ordersRepositoryProvider)
          .verifyDelivery(orderId: orderId, code: code, token: token);
      // Only a fully successful release reflects real confirmed backend
      // state (no optimistic UI on order/payment state) — a stuck payout
      // leg still means the PIN matched, but the student's own tracking
      // session must not show "Delivered" until the backend actually says
      // so.
      if (outcome == DeliveryVerificationResult.delivered) {
        _syncOrderTrackingIfSameOrder(orderId, (n) => n.markDelivered());
      }
      _pendingSuccessMessage = outcome == DeliveryVerificationResult.delivered
          ? 'Delivery confirmed — payout sent.'
          : 'Delivery confirmed — payout processing.';
      return true;
    } on ApiException catch (e) {
      return _showVerificationError(e.message);
    } catch (_) {
      return _showVerificationError(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  String? _pendingSuccessMessage;

  bool _showVerificationError(String message) {
    if (!mounted) return false;
    setState(() => _errorMessage = message);
    ref.read(appNotificationProvider.notifier).error(message);
    // Auto-dismisses the on-screen overlay so it never blocks the frame
    // indefinitely — the toast above already gives a persistent record.
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _errorMessage == message) setState(() => _errorMessage = null);
    });
    return false;
  }

  Future<void> _showSuccessAndClose() async {
    if (!mounted) return;
    setState(() => _success = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final message = _pendingSuccessMessage;
    if (message != null) {
      ref.read(appNotificationProvider.notifier).success(message);
    }
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
        onSubmit: (code) {
          Navigator.pop(sheetContext);
          _completeScan(code);
        },
      ),
    );
  }

  void _submitPhotoProofInstead() {
    final orderId = ref.read(orderTrackingProvider).orderId;
    if (orderId == null) {
      _stubAction('No active delivery to submit proof for.');
      return;
    }
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(builder: (_) => DeliveryProofCaptureScreen(orderId: orderId)),
        )
        .then((submitted) {
          if (!mounted || submitted != true) return;
          ref.read(runnerControllerProvider.notifier).confirmDropoff();
          _close();
        });
  }

  void _stubAction(String message) =>
      ref.read(appNotificationProvider.notifier).info(message);

  @override
  Widget build(BuildContext context) {
    // Task 10 performance audit: this screen has its own continuously
    // animating scan-line (see _ScanFrameOverlay) — not rebuilding it on
    // unrelated session churn (e.g. the per-second offer countdown) matters
    // more here than most screens.
    final active = ref.watch(runnerControllerProvider.select((s) => s.activeDelivery));
    final scanContext = scanContextFor(active);
    final isDeliveryStep = active != null && active.status != DeliveryStage.accepted;

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
                // Fallback when the student's phone is unavailable (Task
                // 11) — delivery step only, since a missed pickup code has
                // no equivalent "just take a photo" resolution.
                if (isDeliveryStep) ...[
                  const SizedBox(height: 8),
                  _PhotoProofPill(onTap: _handled ? null : _submitPhotoProofInstead),
                ],
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
          if (_errorMessage != null) _ScanErrorOverlay(message: _errorMessage!),
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

/// Task 11's delivery-step fallback — visible only when a student's phone
/// is unavailable and no PIN can be entered.
class _PhotoProofPill extends StatelessWidget {
  const _PhotoProofPill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.camera, size: 15, color: Colors.white),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                "Can't get the code? Submit photo proof",
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
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
                    // Task 10 performance audit: this is the one part of the
                    // scan screen repainting on every tick (1.8s repeat,
                    // indefinitely for as long as the screen is open) —
                    // RepaintBoundary wraps the moving content (not
                    // Positioned itself: Positioned is a ParentDataWidget
                    // and must stay Stack's direct child, or it can't hand
                    // its offset to RenderStack) so that repaint stays
                    // scoped to the line, off the static corner brackets and
                    // the live camera preview beneath this overlay.
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => Positioned(
                        top: 10 + _controller.value * (frame - 20),
                        left: 10,
                        right: 10,
                        child: RepaintBoundary(
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

/// Task 11's "clear error state on mismatch — not a silent failure":
/// same scale-in language as [_ScanSuccessOverlay], red/X instead of
/// green/check, plus the message itself so it's legible without relying
/// solely on the toast.
class _ScanErrorOverlay extends StatelessWidget {
  const _ScanErrorOverlay({required this.message});
  final String message;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: .5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualCodeSheet extends StatefulWidget {
  const _ManualCodeSheet({required this.onSubmit});
  final ValueChanged<String> onSubmit;

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
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 4821'),
            onSubmitted: (_) => widget.onSubmit(_controller.text.trim()),
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
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => widget.onSubmit(value.text.trim()),
                child: const Text('Confirm'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
