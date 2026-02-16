import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_tokens.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_utils.dart';
import '../../widgets/common/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // GoRouter redirect handles navigation to /home
    } catch (e) {
      setState(() {
        _error = getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing2xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome Back', style: AppTypography.displayLarge),
              SizedBox(height: tokens.spacing3xl),
              AppTextField.email(
                controller: _emailController,
              ),
              SizedBox(height: tokens.spacingLg),
              AppTextField.password(
                controller: _passwordController,
              ),
              SizedBox(height: tokens.spacingXl),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: colors.error)),
                SizedBox(height: tokens.spacingLg),
              ],
              AppButton(
                text: 'Sign In',
                onPressed: _handleLogin,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
