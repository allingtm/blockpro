import 'package:flutter/material.dart';

import '../../models/outbox_entry.dart';
import '../../theme/app_palettes.dart';

/// Small pill shown on assets/buildings that have a queued offline completion.
///
/// Visual sibling of [DraftChip]. Colour/label track the [OutboxStatus];
/// `failed` and `needsReview` are tappable (pass [onTap]) for manual retry.
class OutboxStatusChip extends StatelessWidget {
  const OutboxStatusChip({super.key, required this.status, this.onTap});

  final OutboxStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      OutboxStatus.pending => ('Queued', kStatusAmber),
      OutboxStatus.sending => ('Sending…', kActionBlue),
      OutboxStatus.needsReview => ('Review', kStatusRed),
      OutboxStatus.failed => ('Retry', kStatusRed),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: chip,
    );
  }
}
