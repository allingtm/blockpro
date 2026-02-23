import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connectivity_provider.dart';

/// Shows a cloud-off icon when the app is offline.
/// Place in an AppBar's `actions` list.
class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfflineAsync = ref.watch(isOfflineProvider);

    return isOfflineAsync.when(
      data: (isOffline) {
        if (!isOffline) return const SizedBox.shrink();
        return Tooltip(
          message: 'No internet connection',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(
              Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
