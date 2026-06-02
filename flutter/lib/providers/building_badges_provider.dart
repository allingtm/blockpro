import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

class BuildingBadge {
  final int red;
  final int amber;
  const BuildingBadge({this.red = 0, this.amber = 0});

  bool get hasAny => red > 0 || amber > 0;
}

/// Stream of per-building badge counts derived from the assets table.
///
/// Red    = assets with `dueDate < today`.
/// Amber  = assets with `dueDate >= today && dueDate <= today + 7 days`.
/// Buildings with zero assets aren't present in the map — callers should
/// treat a missing key as an empty [BuildingBadge].
final buildingBadgesProvider =
    StreamProvider<Map<String, BuildingBadge>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.assetsDao.watchBuildingDueDates().map((rows) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDays = today.add(const Duration(days: 7));
    final red = <String, int>{};
    final amber = <String, int>{};
    for (final row in rows) {
      final due = row.dueDate;
      if (due == null) continue;
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(today)) {
        red[row.buildingId] = (red[row.buildingId] ?? 0) + 1;
      } else if (!dueDay.isAfter(sevenDays)) {
        amber[row.buildingId] = (amber[row.buildingId] ?? 0) + 1;
      }
    }
    final ids = {...red.keys, ...amber.keys};
    return {
      for (final id in ids)
        id: BuildingBadge(red: red[id] ?? 0, amber: amber[id] ?? 0),
    };
  });
});
