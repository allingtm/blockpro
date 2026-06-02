import 'package:flutter/material.dart';

import '../../theme/app_theme_tokens.dart';

/// Card with a thick coloured stripe down the left edge.
/// Surface colour follows the theme so it works in light and dark mode.
/// Used for inspection list rows and individual question rows.
class StripedCard extends StatelessWidget {
  const StripedCard({
    super.key,
    required this.stripeColor,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.stripeWidth = 6,
  });

  final Color stripeColor;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double stripeWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
          color: context.tokens.cardSurface,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: stripeWidth, color: stripeColor),
                  Expanded(
                    child: Padding(
                      padding: padding,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
