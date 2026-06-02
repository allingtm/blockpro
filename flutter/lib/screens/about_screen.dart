import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/initial_sync_provider.dart';
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: BlockProLogo(size: 96, color: tokens.brandIcon),
            ),
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
                style: TextStyle(
                  fontSize: 14,
                  color: tokens.textMuted,
                ),
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
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {themeMode},
              onSelectionChanged: (selected) {
                ref
                    .read(brightnessModeProvider.notifier)
                    .set(selected.first);
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
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).colorScheme;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(needsInitialSyncProvider);
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
