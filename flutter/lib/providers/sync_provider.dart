import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/api_repository.dart';
import '../repositories/sync_repository.dart';
import 'database_provider.dart';

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final api = ref.watch(apiRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  return SyncRepository(api, db);
});
