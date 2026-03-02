import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/initial_sync_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/common/widgets.dart';

class InitialSyncScreen extends ConsumerStatefulWidget {
  const InitialSyncScreen({super.key});

  @override
  ConsumerState<InitialSyncScreen> createState() => _InitialSyncScreenState();
}

class _InitialSyncScreenState extends ConsumerState<InitialSyncScreen> {
  @override
  void initState() {
    super.initState();
    // Start the sync as soon as the screen mounts.
    Future.microtask(() {
      ref.read(initialSyncNotifierProvider.notifier).runSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(initialSyncNotifierProvider);
    final tokens = context.tokens;
    final colors = context.colors;

    // Navigate to home after a brief delay when complete.
    ref.listen(initialSyncNotifierProvider, (prev, next) {
      if (next.isComplete && !(prev?.isComplete ?? false)) {
        // Invalidate so the router knows the DB now has data.
        ref.invalidate(needsInitialSyncProvider);
        final router = GoRouter.of(context);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) router.go('/home');
        });
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing2xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App branding
                Image.asset(
                  'assets/images/app_launcher_icon.png',
                  width: tokens.iconXl,
                  height: tokens.iconXl,
                ),
                SizedBox(height: tokens.spacingXl),
                Text('BlockPro', style: AppTypography.displayLarge),
                SizedBox(height: tokens.spacing3xl),

                // Progress steps
                _SyncStepRow(
                  label: 'Signed in',
                  step: SyncStep.signingIn,
                  currentStep: state.currentStep,
                ),
                SizedBox(height: tokens.spacingLg),
                _SyncStepRow(
                  label: 'Downloading buildings',
                  step: SyncStep.downloadingBuildings,
                  currentStep: state.currentStep,
                ),
                SizedBox(height: tokens.spacingLg),
                _SyncStepRow(
                  label: 'Ready',
                  step: SyncStep.complete,
                  currentStep: state.currentStep,
                ),

                SizedBox(height: tokens.spacing2xl),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  child: LinearProgressIndicator(
                    value: state.hasError ? null : _progressValue(state),
                    minHeight: 4,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: state.hasError ? colors.error : colors.primary,
                  ),
                ),

                // Error + retry
                if (state.hasError) ...[
                  SizedBox(height: tokens.spacingXl),
                  Text(
                    state.error!,
                    style: AppTypography.bodyMedium
                        .copyWith(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tokens.spacingLg),
                  AppButton(
                    text: 'Retry',
                    icon: Icons.refresh,
                    variant: AppButtonVariant.outline,
                    fullWidth: false,
                    onPressed: () =>
                        ref.read(initialSyncNotifierProvider.notifier).retry(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _progressValue(InitialSyncState state) {
    return switch (state.currentStep) {
      SyncStep.signingIn => 0.2,
      SyncStep.downloadingBuildings => 0.6,
      SyncStep.complete => 1.0,
    };
  }
}

class _SyncStepRow extends StatelessWidget {
  final String label;
  final SyncStep step;
  final SyncStep currentStep;

  const _SyncStepRow({
    required this.label,
    required this.step,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isComplete = step.index < currentStep.index;
    final isCurrent = step == currentStep;

    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: isComplete
              ? Icon(Icons.check_circle, color: colors.primary, size: 24)
              : isCurrent
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.primary,
                      ),
                    )
                  : Icon(Icons.circle_outlined,
                      color: colors.onSurfaceVariant, size: 24),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: AppTypography.bodyLarge.copyWith(
            color: isComplete || isCurrent
                ? colors.onSurface
                : colors.onSurfaceVariant,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
