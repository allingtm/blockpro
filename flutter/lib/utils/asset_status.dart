import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../theme/app_palettes.dart';

/// Date-based status used by the inspection cards and the building badges.
///
/// red    — due date is in the past (overdue)
/// amber  — due date is today or within the next 7 days
/// green  — due date is more than 7 days away, or none set
enum AssetStatus { red, amber, green }

AssetStatus assetStatusFor(Asset asset, {DateTime? now}) {
  final due = asset.dueDate;
  if (due == null) return AssetStatus.green;
  final today = _dateOnly(now ?? DateTime.now());
  final dueDay = _dateOnly(due);
  if (dueDay.isBefore(today)) return AssetStatus.red;
  if (dueDay.difference(today).inDays <= 7) return AssetStatus.amber;
  return AssetStatus.green;
}

Color colourForStatus(AssetStatus status) {
  return switch (status) {
    AssetStatus.red => kStatusRed,
    AssetStatus.amber => kStatusAmber,
    AssetStatus.green => kStatusGreen,
  };
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
