import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/initial_sync_provider.dart';
import '../providers/outbox_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(brightnessModeProvider);
    final colors = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return Scaffold(
      appBar: const BlockProAppBar(title: 'About'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: BlockProLogo(size: 96, color: tokens.brandIcon)),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'BlockPro',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: tokens.textStrong,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Building management made simple',
                  style: TextStyle(fontSize: 14, color: tokens.textMuted),
                ),
              ),
              const SizedBox(height: 36),
              _SectionLabel('Appearance'),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selected) {
                  ref.read(brightnessModeProvider.notifier).set(selected.first);
                },
              ),
              const SizedBox(height: 32),
              _SectionLabel('App version'),
              const SizedBox(height: 8),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '...';
                  final build = snapshot.data?.buildNumber ?? '';
                  return Text(
                    'v$version${build.isNotEmpty ? ' ($build)' : ''}',
                    style: const TextStyle(fontSize: 14),
                  );
                },
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.error),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 28),
                _SectionLabel('Debug'),
                const SizedBox(height: 8),
                const _DebugAuditButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).colorScheme;

    // Warn explicitly if there are completed inspections still waiting to upload
    // — signing out discards them (the outbox is purged on logout).
    final pending = (await ref.read(outboxStoreProvider).readAll()).length;
    if (!context.mounted) return;
    final message = pending > 0
        ? 'You have $pending completed inspection${pending == 1 ? '' : 's'} '
              "that haven't been uploaded yet. Signing out will discard "
              '${pending == 1 ? 'it' : 'them'}. Continue?'
        : 'Are you sure you want to sign out?';

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pending > 0 ? 'Discard unsent inspections?' : 'Sign Out?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              pending > 0 ? 'Sign Out & Discard' : 'Sign Out',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(needsInitialSyncProvider);
  }
}

/// Debug-only trigger that re-fetches EVERY asset's checklist (bypassing the
/// incremental timestamp skip) so the data-audit instrumentation captures all
/// `app_fetch_checklist_single` responses, including ones carrying remedials.
/// Does not wipe the DB, drafts, or outbox.
class _DebugAuditButton extends ConsumerStatefulWidget {
  const _DebugAuditButton();

  @override
  ConsumerState<_DebugAuditButton> createState() => _DebugAuditButtonState();
}

class _DebugAuditButtonState extends ConsumerState<_DebugAuditButton> {
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Audit sync started — re-fetching ALL checklists…'),
      ),
    );
    try {
      await ref.read(syncRepositoryProvider).syncAll(forceFullChecklists: true);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Audit sync complete — see the data_audit/ folder in '
            'the app documents directory.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Audit sync failed: $e')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _running ? null : _run,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: _running
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.bug_report),
      label: Text(_running ? 'Auditing…' : 'Run full data audit sync'),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  // ignore: unused_element_parameter
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: context.tokens.textMuted,
      ),
    );
  }
}
