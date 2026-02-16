import 'package:flutter/material.dart';
import '../../theme/app_theme_tokens.dart';

enum AppButtonVariant { primary, outline, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget child = isLoading
        ? SizedBox(
            height: tokens.iconSm,
            width: tokens.iconSm,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: tokens.iconSm),
                SizedBox(width: tokens.spacingSm),
              ],
              Text(text),
            ],
          );

    final style = switch (variant) {
      AppButtonVariant.primary => FilledButton.styleFrom(
          minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
        ),
      AppButtonVariant.outline => OutlinedButton.styleFrom(
          minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
        ),
      AppButtonVariant.ghost => TextButton.styleFrom(
          minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
        ),
    };

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: style,
          child: child,
        ),
      AppButtonVariant.outline => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: style,
          child: child,
        ),
      AppButtonVariant.ghost => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: style,
          child: child,
        ),
    };
  }
}
