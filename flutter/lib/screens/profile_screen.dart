import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/common/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final colors = context.colors;
    final profileAsync = ref.watch(userProfileNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [OfflineIndicator()],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Text('No profile data',
                  style: AppTypography.bodyLarge
                      .copyWith(color: colors.onSurfaceVariant)),
            );
          }
          return Padding(
            padding: EdgeInsets.all(tokens.spacingXl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: tokens.iconLg / 2,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    profile.fullName.characters.first.toUpperCase(),
                    style: AppTypography.headlineLarge
                        .copyWith(color: colors.onPrimaryContainer),
                  ),
                ),
                SizedBox(height: tokens.spacingXl),
                Text(profile.fullName, style: AppTypography.headlineMedium),
                SizedBox(height: tokens.spacingSm),
                Text(profile.email,
                    style: AppTypography.bodyLarge
                        .copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error loading profile: $error',
              style: TextStyle(color: colors.error)),
        ),
      ),
    );
  }
}
