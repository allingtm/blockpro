import 'package:flutter/material.dart';

import '../../theme/app_palettes.dart';
import '../../theme/app_theme_tokens.dart';

/// Shows a centred "Please wait / Loading..." modal with a spinner.
/// Returns a function that dismisses it.
VoidCallback showLoadingDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _LoadingDialog(),
  );
  return () {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  };
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: tokens.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please wait',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: tokens.textStrong,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 15,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(kActionBlue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
