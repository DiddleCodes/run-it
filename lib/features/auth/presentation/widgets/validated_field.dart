import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_spinner.dart';
import '../../../../core/widgets/app_text_field.dart';

/// A text field with debounced inline validation: a green check once the
/// value passes [validator], a shake + red border once it's been touched
/// and fails. Validation only runs ~350ms after the user pauses typing,
/// so it never flags a field mid-keystroke.
///
/// [asyncValidator] adds a second, optional check that only ever runs
/// after [validator] already passes (Task 27) — so it never fires on
/// obviously-incomplete input (e.g. a still-being-typed email domain), the
/// same "don't flash red mid-type" guarantee [validator] itself has. While
/// it's in flight the field shows a small spinner instead of the green
/// check; a stale response (superseded by newer typing) is discarded. It's
/// advisory only — nothing here blocks [validateNow], since the real
/// enforcement for whatever this is checking lives server-side regardless.
class ValidatedField extends StatefulWidget {
  const ValidatedField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.validator,
    this.asyncValidator,
    this.leadingText,
    this.prefixIcon,
    this.keyboardType,
    this.onValidChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String value) validator;
  final Future<String?> Function(String value)? asyncValidator;
  final String? leadingText;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final ValueChanged<bool>? onValidChanged;

  @override
  State<ValidatedField> createState() => ValidatedFieldState();
}

class ValidatedFieldState extends State<ValidatedField>
    with SingleTickerProviderStateMixin {
  Timer? _debounce;
  String? _error;
  bool _touched = false;
  bool _checking = false;
  int _requestGen = 0;
  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final _shake = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: -4.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

  bool get isValid =>
      _touched && widget.validator(widget.controller.text) == null;

  /// Forces validation immediately (e.g. on submit-attempt) rather than
  /// waiting for the debounce — used to surface all errors at once when
  /// the user taps "Continue" with untouched fields.
  bool validateNow() {
    _debounce?.cancel();
    final error = widget.validator(widget.controller.text);
    setState(() {
      _touched = true;
      _error = error;
    });
    if (error != null) _shakeController.forward(from: 0);
    widget.onValidChanged?.call(error == null);
    return error == null;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final error = widget.validator(value);
      final wasInvalid = _touched && _error != null;
      setState(() {
        _touched = true;
        _error = error;
        _checking = false;
      });
      if (error != null) {
        if (wasInvalid) _shakeController.forward(from: 0);
        widget.onValidChanged?.call(false);
        return;
      }
      widget.onValidChanged?.call(true);

      final asyncValidator = widget.asyncValidator;
      if (asyncValidator == null) return;
      final gen = ++_requestGen;
      setState(() => _checking = true);
      asyncValidator(value).then((asyncError) {
        // A newer keystroke (or a dispose) superseded this request —
        // its answer no longer describes what's in the field.
        if (!mounted || gen != _requestGen) return;
        final wasInvalidNow = _touched && _error != null;
        setState(() {
          _checking = false;
          _error = asyncError;
        });
        if (asyncError != null && wasInvalidNow) _shakeController.forward(from: 0);
        widget.onValidChanged?.call(asyncError == null);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _touched && _error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shake.value, 0),
            child: child,
          ),
          child: AppTextField(
            controller: widget.controller,
            hintText: widget.hintText,
            leadingText: widget.leadingText,
            prefixIcon: widget.prefixIcon,
            keyboardType: widget.keyboardType,
            hasError: hasError,
            onChanged: _onChanged,
            suffixIcon: _checking
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: AppSpinner(size: 16, strokeWidth: 2, color: AppColors.mutedText),
                  )
                : _touched && !hasError
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.success,
                  )
                : null,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.error),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
