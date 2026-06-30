import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/initial_sync_provider.dart';
import '../../providers/outbox_provider.dart';
import '../../theme/app_palettes.dart';
import 'blockpro_logo.dart';

/// Brand AppBar: BlockPro logo, centred title with red badge.
/// Hardcoded dark navy regardless of theme brightness.
///
/// Shows a back arrow automatically when the route can pop. Add a trailing
/// widget via [trailing] if needed; an offline cloud icon is appended when
/// connectivity is lost.
class BlockProAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const BlockProAppBar({
    super.key,
    required this.title,
    this.badgeCount,
    this.trailing,
  });

  final String title;
  final int? badgeCount;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfflineAsync = ref.watch(isOfflineProvider);
    final isOffline = isOfflineAsync.valueOrNull ?? false;
    final pendingUploads = ref.watch(pendingCountProvider);
    final isSyncing =
        ref.watch(initialSyncNotifierProvider.select((s) => s.isSyncing));
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return AppBar(
      backgroundColor: kAppBarNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      titleSpacing: 0,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BlockProLogo(size: 44),
              ),
            ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badgeCount != null && badgeCount! > 0) ...[
            const SizedBox(width: 10),
            _Badge(count: badgeCount!),
          ],
        ],
      ),
      actions: [
        if (pendingUploads > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message:
                  '$pendingUploads inspection${pendingUploads == 1 ? '' : 's'} waiting to upload',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 3),
                  Text(
                    '$pendingUploads',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isOffline)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: 'No internet connection',
              child: Icon(Icons.cloud_off_rounded,
                  color: Colors.white70, size: 20),
            ),
          ),
        if (isSyncing) const _PulsingSyncIndicator(),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
        // Reserve right-edge space so the centred title aligns with the
        // logo on the left in the default (no-back-arrow) case.
        if (!canPop && trailing == null && !isOffline && pendingUploads == 0)
          const SizedBox(width: 56),
      ],
    );
  }
}

/// A cloud-download icon that gently pulses (fades in and out) while the
/// background sync is downloading data — calmer than a spinner and consistent
/// with the app bar's other cloud status icons (upload / offline). Shown on
/// every screen via [BlockProAppBar] while a sync is running.
class _PulsingSyncIndicator extends StatefulWidget {
  const _PulsingSyncIndicator();

  @override
  State<_PulsingSyncIndicator> createState() => _PulsingSyncIndicatorState();
}

class _PulsingSyncIndicatorState extends State<_PulsingSyncIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Downloading data…',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: const Icon(
              Icons.cloud_download_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: kStatusRed,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
