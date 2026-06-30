import 'package:flutter/material.dart';

import '../../theme/app_theme_tokens.dart';

/// Asks the user to confirm a full data refresh.
///
/// Returns `true` if they chose to refresh, `false`/`null` otherwise. The refresh
/// itself then runs in the background (wipe + re-download, like app startup) via
/// `initialSyncNotifierProvider.refresh()` — there is no longer a progress dialog.
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
