import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../../../ui/states.dart' show BroSpinner;

/// Shared controls for the auth surfaces (login / get started / confirmation).
const _errorColor = Color(0xFFFF8D8D);

/// Full-width volt pill CTA with proper disabled + loading behavior.
///
/// Built on [ElevatedButton] so keyboard activation, focus rings and
/// accessibility semantics come for free.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: app_colors.P.primary.withValues(alpha: 0.32),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: app_colors.P.primary,
          foregroundColor: app_colors.P.darkOnAccent,
          disabledBackgroundColor: app_colors.P.primary.withValues(alpha: 0.65),
          disabledForegroundColor: app_colors.P.darkOnAccent,
          shape: const StadiumBorder(),
          elevation: 0,
          padding: EdgeInsets.zero,
        ),
        child: loading
            ? Semantics(
                label: 'Please wait',
                child: BroSpinner(
                  size: 22,
                  strokeWidth: 2.5,
                  color: app_colors.P.darkOnAccent,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

/// Segmented Sign In / Create Account toggle.
class AuthModeToggle extends StatelessWidget {
  const AuthModeToggle({
    super.key,
    required this.isSignUp,
    required this.onChanged,
  });

  final bool isSignUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [('Sign In', false), ('Create Account', true)];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: app_colors.P.surfaceLow,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: app_colors.P.border),
      ),
      child: Row(
        children: [
          for (final (label, value) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: isSignUp == value,
                label: label,
                child: InkWell(
                  onTap: () => onChanged(value),
                  borderRadius: BorderRadius.circular(36),
                  focusColor: app_colors.P.primary.withValues(alpha: 0.18),
                  hoverColor: app_colors.P.primary.withValues(alpha: 0.06),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSignUp == value
                          ? app_colors.P.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: isSignUp == value
                          ? [
                              BoxShadow(
                                color: app_colors.P.primary
                                    .withValues(alpha: 0.3),
                                blurRadius: 16,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isSignUp == value
                            ? app_colors.P.darkOnAccent
                            : app_colors.P.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pill-shaped auth input matching the Electric Street design system.
///
/// Adds autofill hints, inline error + helper text and proper focus
/// semantics over the previous private field widget.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefix,
    required this.placeholder,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.suffixColor,
    this.isGuideTarget = false,
    this.onFocus,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints = const [],
    this.errorText,
    this.helperText,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefix;
  final String placeholder;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffix;
  final Color? suffixColor;
  final bool isGuideTarget;
  final VoidCallback? onFocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String> autofillHints;
  final String? errorText;
  final String? helperText;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.obscureText;

  @override
  void didUpdateWidget(covariant AuthTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final highlight = widget.isGuideTarget || hasError;
    final accent = hasError ? _errorColor : app_colors.P.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: app_colors.P.muted,
              letterSpacing: 0.08,
            ),
          ),
        ),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: app_colors.P.surfaceLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: highlight ? accent : app_colors.P.border,
              width: highlight ? 1.5 : 1,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: TextField(
            controller: widget.controller,
            obscureText: _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            onTap: widget.onFocus,
            autofillHints: widget.autofillHints,
            textCapitalization: widget.textCapitalization,
            autocorrect: widget.autocorrect,
            enableSuggestions: false,
            style: const TextStyle(color: app_colors.P.text, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              prefixIcon:
                  Icon(widget.prefix, color: app_colors.P.muted, size: 20),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              hintText: widget.placeholder,
              hintStyle:
                  TextStyle(color: app_colors.P.muted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              suffixIcon: widget.obscureText
                  ? IconButton(
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: app_colors.P.muted,
                        size: 20,
                      ),
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscured = !_obscured),
                    )
                  : (widget.suffix != null
                      ? Icon(widget.suffix,
                          color: widget.suffixColor ?? app_colors.P.muted,
                          size: 20)
                      : null),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              widget.errorText!,
              style: const TextStyle(fontSize: 12, color: _errorColor),
            ),
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              widget.helperText!,
              style: const TextStyle(
                fontSize: 12,
                color: app_colors.P.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Soft success/info banner for auth flows (e.g. "reset link sent").
class AuthNoticeBanner extends StatelessWidget {
  const AuthNoticeBanner({
    super.key,
    required this.message,
    this.icon = Icons.mark_email_read_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: app_colors.P.success.withValues(alpha: 0.10),
        border: Border.all(color: app_colors.P.success.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: app_colors.P.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: app_colors.P.text,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
