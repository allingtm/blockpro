import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/asset.dart';
import '../models/building.dart';
import '../providers/assets_provider.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/asset_status.dart';
import '../utils/qr_utils.dart';
import '../widgets/common/widgets.dart';

/// Full-screen QR scanner reached from the Blocks-list FAB.
///
/// Scans an asset QR code (the on-site URL with an `?asset=<id>` param), resolves
/// it against the local DB, and shows the found asset as a tappable card over the
/// frozen camera. Tapping opens that asset's inspection checklist.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  MobileScannerController? _controller;

  /// Set once we've reached a terminal state (a code was decoded), so the rapid
  /// detect stream is ignored until the user explicitly scans again.
  bool _handled = false;

  /// Non-null once a decoded QR parsed to a valid asset id (drives the lookup).
  /// While [_handled], a null value means the decoded QR wasn't recognised.
  String? _scannedId;

  /// `mobile_scanner` only implements Android/iOS. On desktop/web (e.g. running
  /// the app on Windows during dev) we render a friendly fallback instead of
  /// constructing [MobileScanner], which would otherwise throw.
  bool get _scanningSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_scanningSupported) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        // Only react to QR codes so stray product/1D barcodes don't trip the
        // "not recognised" state.
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    // Releases the camera. Fire-and-forget — the widget is going away.
    unawaited(_controller?.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    String? foundId;
    var sawCode = false;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      sawCode = true;
      final id = assetIdFromScan(raw);
      if (id != null) {
        foundId = id;
        break;
      }
    }
    // Nothing decodable in this frame — keep scanning.
    if (!sawCode) return;
    // A QR was decoded: reach a terminal state (found or unrecognised) and
    // freeze the viewfinder. The result UI is driven by the flags below, so the
    // flow stays correct even if stop() no-ops.
    setState(() {
      _handled = true;
      _scannedId = foundId; // null ⇒ unrecognised
    });
    unawaited(_controller?.stop());
  }

  void _scanAgain() {
    setState(() {
      _handled = false;
      _scannedId = null;
    });
    unawaited(_controller?.start());
  }

  /// Open the asset's inspection, replacing the scanner so Back returns to the
  /// Blocks list rather than the camera.
  void _open(Asset asset) {
    context.pushReplacement('/inspection/${asset.id}', extra: asset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BlockProAppBar(title: 'Scan QR'),
      body: _scanningSupported
          ? _buildScanner()
          : const _UnsupportedBody(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) =>
              _CameraError(error: error, onRetry: _scanAgain),
        ),
        // The aiming frame only while still scanning.
        if (!_handled) const _ScanFrameOverlay(),
        // On a terminal state, cover the (now stopped, grey) camera with an
        // opaque result screen so only the outcome is shown.
        if (_handled)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _scannedId != null
                        ? _ResultPanel(
                            assetId: _scannedId!,
                            onOpen: _open,
                            onScanAgain: _scanAgain,
                          )
                        : _NotFound(
                            message: 'Not a recognised QR code.',
                            icon: Icons.qr_code_scanner,
                            onScanAgain: _scanAgain,
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dimmed surround with a clear square cut-out to aim the code at.
class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// Bottom panel that resolves the scanned id and shows the result.
class _ResultPanel extends ConsumerWidget {
  const _ResultPanel({
    required this.assetId,
    required this.onOpen,
    required this.onScanAgain,
  });

  final String assetId;
  final void Function(Asset asset) onOpen;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(scannedAssetProvider(assetId));
    // Layout (SafeArea / centering / padding) is owned by the overlay in
    // `_buildScanner`; this just returns the outcome content.
    return result.when(
      loading: () => const _PanelShell(
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Looking up asset…'),
          ],
        ),
      ),
      error: (_, _) => _NotFound(
        message: 'Could not read that code. Try again.',
        onScanAgain: onScanAgain,
      ),
      data: (data) {
        if (data == null) {
          return _NotFound(
            message:
                'That asset isn\'t in your data. Refresh your blocks and try again.',
            onScanAgain: onScanAgain,
          );
        }
        return _FoundCard(
          asset: data.asset,
          building: data.building,
          onOpen: onOpen,
        );
      },
    );
  }
}

/// Plain surface used while loading, matching the result card footprint.
class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.cardSurface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// The matched asset, shown as a striped card; tapping it opens the inspection.
class _FoundCard extends StatelessWidget {
  const _FoundCard({
    required this.asset,
    required this.building,
    required this.onOpen,
  });

  final Asset asset;
  final Building building;
  final void Function(Asset asset) onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stripe = colourForStatus(assetStatusFor(asset));
    final placement = [asset.floor, asset.location]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');

    return StripedCard(
      stripeColor: stripe,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      onTap: () => onOpen(asset),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.displayName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: tokens.textStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  building.name,
                  style: TextStyle(fontSize: 14, color: tokens.textMuted),
                ),
                if (placement.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    placement,
                    style: TextStyle(fontSize: 13, color: tokens.textFaint),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Tap to open inspection',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kActionBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: tokens.textFaint),
        ],
      ),
    );
  }
}

/// Message card for a non-actionable outcome: a decoded QR that isn't a
/// recognised BlockPro code, or a valid code whose asset isn't in the user's
/// data. Offers a "Scan again" action.
class _NotFound extends StatelessWidget {
  const _NotFound({
    required this.message,
    required this.onScanAgain,
    this.icon = Icons.search_off,
  });

  final String message;
  final VoidCallback onScanAgain;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: kStatusAmber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 15, color: tokens.textStrong),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Scan again',
            icon: Icons.qr_code_scanner,
            variant: AppButtonVariant.outline,
            onPressed: onScanAgain,
          ),
        ],
      ),
    );
  }
}

/// Camera error surface (e.g. permission denied).
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            denied
                ? 'Camera access is needed to scan QR codes. Enable it for BlockPro in your device settings.'
                : 'The camera could not be started.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Try again',
            icon: Icons.refresh,
            fullWidth: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Fallback for platforms `mobile_scanner` doesn't support (desktop/web).
class _UnsupportedBody extends StatelessWidget {
  const _UnsupportedBody();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 72, color: tokens.textFaint),
            const SizedBox(height: 16),
            Text(
              'QR scanning is only available on the mobile app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: tokens.textStrong),
            ),
          ],
        ),
      ),
    );
  }
}
