import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/asset_status.dart';
import 'database_provider.dart';

class BuildingBadge {
  final int red;
  final int amber;
  const BuildingBadge({this.red = 0, this.amber = 0});

  bool get hasAny => red > 0 || amber > 0;
}

/// Stream of per-building badge counts derived from the assets table.
///
/// Red and amber follow the same rule as the inspection cards
/// ([statusForDates]): red = overdue, amber = the server's `yellowDate`
/// threshold reached but not yet overdue. Buildings with zero assets aren't
/// present in the map — callers should treat a missing key as an empty
/// [BuildingBadge].
final buildingBadgesProvider =
    StreamProvider<Map<String, BuildingBadge>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.assetsDao.watchBuildingDueDates().map((rows) {
    final now = DateTime.now();
    final red = <String, int>{};
    final amber = <String, int>{};
    for (final row in rows) {
      switch (statusForDates(
          dueDate: row.dueDate, yellowDate: row.yellowDate, now: now)) {
        case AssetStatus.red:
          red[row.buildingId] = (red[row.buildingId] ?? 0) + 1;
        case AssetStatus.amber:
          amber[row.buildingId] = (amber[row.buildingId] ?? 0) + 1;
        case AssetStatus.green:
          break;
      }
    }
    final ids = {...red.keys, ...amber.keys};
    return {
      for (final id in ids)
        id: BuildingBadge(red: red[id] ?? 0, amber: amber[id] ?? 0),
    };
  });
});
