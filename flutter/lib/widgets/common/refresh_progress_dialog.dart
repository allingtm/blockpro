import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/refresh_sync_provider.dart';
import '../../theme/app_palettes.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_tokens.dart';
import 'app_button.dart';

/// Asks the user to confirm a full data refresh.
///
/// Returns `true` if they chose to refresh, `false`/`null` otherwise.
Future<bool?> confirmRefreshDialog(BuildContext context) {
  final tokens = context.tokens;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: tokens.cardSurface,
      title: Text(
        'Refresh data?',
        style: TextStyle(fontWeight: FontWeight.w700, color: tokens.textStrong),
      ),
      content: Text(
        'This will re-download all blocks, assets and checklists from the '
        'server. It may take a little while.',
        style: TextStyle(color: tokens.textMuted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}

/// Runs a full refresh, showing a modal progress dialog. The dialog cannot be
/// dismissed by tapping outside; the user must let it finish or hit Cancel,
/// which aborts the sync and wipes local data.
///
/// The dialog starts the refresh itself (once it is subscribed to the
/// provider) and closes itself when the refresh completes or is cancelled.
Future<void> showRefreshProgressDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _RefreshProgressDialog(),
  );
}

class _RefreshProgressDialog extends ConsumerStatefulWidget {
  const _RefreshProgressDialog();

  @override
  ConsumerState<_RefreshProgressDialog> createState() =>
      _RefreshProgressDialogState();
}

class _RefreshProgressDialogState
    extends ConsumerState<_RefreshProgressDialog> {
  @override
  void initState() {
    super.initState();
    // Start the refresh after the first frame so this dialog is already
    // listening to the provider before any state updates are emitted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(refreshNotifierProvider.notifier).run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;
    final state = ref.watch(refreshNotifierProvider);

    // Auto-close once the refresh finishes or is cancelled.
    ref.listen(refreshNotifierProvider, (prev, next) {
      if (!next.isRunning) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    });

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: tokens.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        // Fixed width so the dialog doesn't resize as the status text below
        // changes length (e.g. "Downloading assets (3 / 12 blocks)").
        child: SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Refreshing data',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: tokens.textStrong,
                  ),
                ),
                const SizedBox(height: 24),
                // Spinner with the running progress percentage in its centre.
                // The track sits behind a determinate arc so it reads as a
                // gauge while still spinning when progress is indeterminate.
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _progressValue(state),
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          backgroundColor: colors.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            kActionBlue,
                          ),
                        ),
                      ),
                      // Percentage with cycling dots stacked directly beneath it,
                      // both centred inside the spinner.
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ProgressLabel(value: _progressValue(state)),
                          _AnimatedDots(active: state.isRunning),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  state.statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: tokens.textMuted),
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Cancel',
                  variant: AppButtonVariant.outline,
                  fullWidth: false,
                  onPressed: () =>
                      ref.read(refreshNotifierProvider.notifier).cancel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Cancelled → indeterminate spinner; otherwise the monotonic value the
  // notifier already computed (no recomputation here, so it can't flicker).
  double? _progressValue(RefreshState state) =>
      state.isCancelled ? null : state.progress;
}

/// The percentage shown inside the spinner. Falls back to a small pulsing dot
/// when progress can't be measured (indeterminate).
class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (value == null) {
      return const Icon(Icons.sync, size: 28, color: kActionBlue);
    }
    final pct = (value!.clamp(0.0, 1.0) * 100).round();
    return Text(
      '$pct%',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: tokens.textStrong,
      ),
    );
  }
}

/// Cycles "", ".", "..", "..." on a timer to signal ongoing work. Reserves a
/// fixed width so the surrounding layout doesn't jump as dots are added.
class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots({required this.active});

  final bool active;

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots> {
  Timer? _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_AnimatedDots old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _start();
    } else if (!widget.active && old.active) {
      _stop();
    }
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _count = (_count + 1) % 4);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed box so the % above doesn't shift as dots are added/removed.
    return SizedBox(
      height: 12,
      width: 30,
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          '.' * _count,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 0.7,
            color: kActionBlue,
          ),
        ),
      ),
    );
  }
}
