import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_palettes.dart';

/// FloatingActionButton that opens the QR scanner (`/scan`).
///
/// Shared by the blocks list and the building-detail screen so an inspector can
/// jump straight to a scanned asset from either.
class ScanFab extends StatelessWidget {
  const ScanFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => context.push('/scan'),
      backgroundColor: kActionBlue,
      foregroundColor: Colors.white,
      tooltip: 'Scan asset QR code',
      child: const Icon(Icons.qr_code_scanner),
    );
  }
}
