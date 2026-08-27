import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';

/// A text field with debounced inline validation: a green check once the
/// value passes [validator], a shake + red border once it's been touched
/// and fails. Validation only runs ~350ms after the user pauses typing,
/// so it never flags a field mid-keystroke.
class ValidatedField extends StatefulWidget {
  const ValidatedField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.validator,
    this.leadingText,
    this.prefixIcon,
    this.keyboardType,
    this.onValidChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String value) validator;
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
      });
      if (error != null && wasInvalid) _shakeController.forward(from: 0);
      widget.onValidChanged?.call(error == null);
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
            suffixIcon: _touched && !hasError
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
