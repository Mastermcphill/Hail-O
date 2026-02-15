import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/offline_region_record.dart';
import '../table_names.dart';

class OfflineRegionsDao {
  const OfflineRegionsDao(this.db);

  final Database db;

  Future<void> upsert(OfflineRegionRecord record) async {
    await db.insert(
      TableNames.offlineRegions,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateProgress({
    required String regionId,
    required int downloadedBytes,
    required int completedResources,
    required String status,
  }) async {
    await db.update(
      TableNames.offlineRegions,
      <String, Object?>{
        'downloaded_bytes': downloadedBytes,
        'completed_resources': completedResources,
        'status': status,
      },
      where: 'region_id = ?',
      whereArgs: <Object>[regionId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<OfflineRegionRecord?> findById(String regionId) async {
    final rows = await db.query(
      TableNames.offlineRegions,
      where: 'region_id = ?',
      whereArgs: <Object>[regionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OfflineRegionRecord.fromMap(rows.first);
  }

  Future<List<OfflineRegionRecord>> listAll() async {
    final rows = await db.query(
      TableNames.offlineRegions,
      orderBy: 'created_at DESC',
    );
    return rows.map(OfflineRegionRecord.fromMap).toList(growable: false);
  }

  Future<void> deleteById(String regionId) async {
    await db.transaction((txn) async {
      await txn.delete(
        TableNames.offlineDownloadEvents,
        where: 'region_id = ?',
        whereArgs: <Object>[regionId],
      );
      await txn.delete(
        TableNames.offlineRegions,
        where: 'region_id = ?',
        whereArgs: <Object>[regionId],
      );
    });
  }
}
