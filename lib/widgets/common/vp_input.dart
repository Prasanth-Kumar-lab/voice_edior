import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';

/// Pro-grade text input with glassmorphism surface, floating label,
/// animated gradient focus ring, password visibility toggle,
/// and inline shake validation error animation (no plain snackbars).
class VpInput extends StatefulWidget {
  const VpInput({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final IconData? prefixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VpInput> createState() => _VpInputState();
}

class _VpInputState extends State<VpInput> with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  bool _obscure = true;
  bool _focused = false;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _obscure = widget.isPassword;
    _focusNode = FocusNode()
      ..addListener(() {
        setState(() => _focused = _focusNode.hasFocus);
      });

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    if (widget.errorText != null) {
      _shakeCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(VpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorText != null && widget.errorText != oldWidget.errorText) {
      _shakeCtrl.forward(from: 0.0);
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;
    final bool hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    // Shake offset calculation for smooth inline error feedback
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final double shake = hasError
            ? (1.0 - _shakeCtrl.value) *
                10.0 *
                (1 - 2 * ((_shakeCtrl.value * 6).floor() % 2))
            : 0.0;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Glass input wrapper
          AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.entrance,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceAlt.withValues(alpha: 0.72)
                  : AppColors.lightSurfaceAlt,
              borderRadius: AppRadius.button,
              border: Border.all(
                color: hasError
                    ? AppColors.danger
                    : (_focused
                        ? AppColors.accentBright
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                width: _focused || hasError ? 1.5 : 1.0,
              ),
              boxShadow: [
                if (_focused && !hasError)
                  BoxShadow(
                    color: AppColors.accentBright.withValues(alpha: isDark ? 0.22 : 0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                if (hasError)
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: isDark ? 0.30 : 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.isPassword && _obscure,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.text(b),
              ),
              cursorColor: AppColors.accentBright,
              decoration: InputDecoration(
                border: InputBorder.none,
                labelText: widget.label,
                labelStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: hasError
                      ? AppColors.danger
                      : (_focused ? AppColors.accentBright : AppColors.muted(b)),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.muted(b).withValues(alpha: 0.7),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        size: 20,
                        color: hasError
                            ? AppColors.danger
                            : (_focused ? AppColors.accentBright : AppColors.muted(b)),
                      )
                    : null,
                suffixIcon: widget.isPassword
                    ? IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.muted(b),
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
                isDense: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ),

          // Inline animated error label
          AnimatedSize(
            duration: AppMotion.fast,
            curve: AppMotion.entrance,
            child: hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.errorText!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
