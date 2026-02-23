import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/theme_provider.dart';
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
