import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/common/widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final currentBrightness = ref.watch(brightnessModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [OfflineIndicator()],
      ),
      body: ListView(
        children: [
          // Appearance section
          _buildSectionHeader('Appearance', tokens),
          _buildBrightnessSelector(context, ref, currentBrightness, tokens),

          // Account section
          _buildSectionHeader('Account', tokens),
          _buildAccountSection(context, ref),

          // About section
          _buildSectionHeader('About', tokens),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, AppThemeTokens tokens) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          tokens.spacingLg, tokens.spacingXl, tokens.spacingLg, tokens.spacingSm),
      child: Text(title, style: AppTypography.titleMedium),
    );
  }

  Widget _buildBrightnessSelector(BuildContext context, WidgetRef ref,
      ThemeMode currentMode, AppThemeTokens tokens) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingLg, vertical: tokens.spacingSm),
      child: SegmentedButton<ThemeMode>(
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
        selected: {currentMode},
        onSelectionChanged: (selected) {
          ref.read(brightnessModeProvider.notifier).set(selected.first);
        },
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign Out'),
          onTap: () => _showSignOutDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showSignOutDialog(BuildContext context, WidgetRef ref) async {
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
            child: Text('Sign Out',
                style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );

    if (proceed != true || !context.mounted) return;

    await ref.read(authRepositoryProvider).signOut();
  }

  Widget _buildAboutSection() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        final buildNumber = snapshot.data?.buildNumber ?? '';
        return ListTile(
          leading: const Icon(Icons.info_outlined),
          title: const Text('App Version'),
          subtitle: Text('v$version ($buildNumber)'),
        );
      },
    );
  }
}
