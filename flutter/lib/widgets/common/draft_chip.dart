import 'package:flutter/material.dart';

import '../../theme/app_palettes.dart';

/// Small amber pill shown on assets/buildings that have an unsubmitted
/// local draft inspection.
class DraftChip extends StatelessWidget {
  const DraftChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kStatusAmber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kStatusAmber),
      ),
      child: const Text(
        'Draft',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: kStatusAmber,
        ),
      ),
    );
  }
}
