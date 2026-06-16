import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../theme/app_palettes.dart';

/// Date-based status used by the inspection cards and the building badges.
///
/// red    — due date is in the past (overdue)
/// amber  — the server's `yellowDate` warning threshold has been reached
///          (today is on/after it) but the asset is not yet overdue
/// green  — otherwise, including when no `yellowDate` is set (amber is a
///          server-provided concept; without a `yellowDate` there is no amber
///          phase, the asset stays green until it goes overdue)
enum AssetStatus { red, amber, green }

/// Status from the raw dates, so the card view ([assetStatusFor]) and the
/// building-badge counts share one rule.
AssetStatus statusForDates({
  DateTime? dueDate,
  DateTime? yellowDate,
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  if (dueDate != null && _dateOnly(dueDate).isBefore(today)) {
    return AssetStatus.red;
  }
  if (yellowDate != null && !today.isBefore(_dateOnly(yellowDate))) {
    return AssetStatus.amber;
  }
  return AssetStatus.green;
}

AssetStatus assetStatusFor(Asset asset, {DateTime? now}) => statusForDates(
      dueDate: asset.dueDate,
      yellowDate: asset.yellowDate,
      now: now,
    );

Color colourForStatus(AssetStatus status) {
  return switch (status) {
    AssetStatus.red => kStatusRed,
    AssetStatus.amber => kStatusAmber,
    AssetStatus.green => kStatusGreen,
  };
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
