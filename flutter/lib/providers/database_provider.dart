import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

/// Singleton database instance.
///
/// Initialized in main.dart and overridden into the ProviderContainer.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
