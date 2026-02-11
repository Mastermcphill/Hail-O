import 'package:sqflite/sqflite.dart';

import '../../../domain/models/offline_download_event.dart';
import '../table_names.dart';

class OfflineDownloadEventsDao {
  const OfflineDownloadEventsDao(this.db);

  final Database db;

  Future<int> insert(OfflineDownloadEvent event) async {
    return db.insert(
      TableNames.offlineDownloadEvents,
      event.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<OfflineDownloadEvent>> listByRegion(String regionId) async {
    final rows = await db.query(
      TableNames.offlineDownloadEvents,
      where: 'region_id = ?',
      whereArgs: <Object>[regionId],
      orderBy: 'ts DESC, id DESC',
    );
    return rows.map(OfflineDownloadEvent.fromMap).toList(growable: false);
  }

  Future<void> deleteByRegion(String regionId) async {
    await db.delete(
      TableNames.offlineDownloadEvents,
      where: 'region_id = ?',
      whereArgs: <Object>[regionId],
    );
  }
}
