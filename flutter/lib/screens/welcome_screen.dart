import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/common/widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.spacing2xl),
            child: Column(
              children: [
                BlockProLogo(
                  size: tokens.icon2xl,
                  color: tokens.brandIcon,
                ),
                SizedBox(height: tokens.spacing3xl),
                Text('BlockPro', style: AppTypography.displayLarge),
                SizedBox(height: tokens.spacingMd),
                Text(
                  'Building management made simple',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tokens.spacing4xl),
                AppButton(
                  text: 'Sign In',
                  onPressed: () => context.go('/login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
