import 'package:flutter/material.dart';
import '../../theme/app_theme_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Card(
      margin: margin ?? EdgeInsets.symmetric(vertical: tokens.spacingSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Padding(
          padding: padding ?? EdgeInsets.all(tokens.spacingMd),
          child: child,
        ),
      ),
    );
  }
}
