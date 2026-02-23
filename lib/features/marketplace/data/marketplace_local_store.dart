import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/offer.dart';
import '../models/outbox_item.dart';
import '../models/purchase_snapshot.dart';
import '../models/timeline_event.dart';

class MarketplaceLocalStore {
  MarketplaceLocalStore({this.databaseName = 'marketplace_cache.db'});

  final String databaseName;
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, databaseName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE marketplace_meta(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE marketplace_offers_cache(
            id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE marketplace_purchase_cache(
            purchase_id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            version INTEGER NOT NULL,
            etag TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE marketplace_assignments_cache(
            purchase_id TEXT NOT NULL,
            seat_index INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            version INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (purchase_id, seat_index)
          )
        ''');
        await db.execute('''
          CREATE TABLE marketplace_timeline_cache(
            purchase_id TEXT NOT NULL,
            event_key TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            event_at INTEGER NOT NULL,
            cursor TEXT,
            PRIMARY KEY (purchase_id, event_key)
          )
        ''');
        await db.execute('''
          CREATE TABLE marketplace_outbox(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            purchase_id TEXT,
            idempotency_key TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            base_version INTEGER,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            next_retry_at INTEGER,
            created_at INTEGER NOT NULL,
            last_error TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_marketplace_outbox_status_next_retry
          ON marketplace_outbox(status, next_retry_at, created_at)
        ''');
      },
    );
    return _db!;
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<void> setMeta(String key, String value) async {
    final db = await _database();
    await db.insert('marketplace_meta', <String, Object?>{
      'key': key,
      'value': value,
      'updated_at': _nowMillis(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getMeta(String key) async {
    final db = await _database();
    final rows = await db.query(
      'marketplace_meta',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value']?.toString();
  }

  Future<void> cacheOffers(
    List<MarketplaceOffer> offers, {
    String? etag,
  }) async {
    final db = await _database();
    final batch = db.batch();
    final now = _nowMillis();
    batch.delete('marketplace_offers_cache');
    for (final offer in offers) {
      batch.insert('marketplace_offers_cache', <String, Object?>{
        'id': offer.id,
        'payload_json': jsonEncode(offer.toJson()),
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
    if (etag != null && etag.trim().isNotEmpty) {
      await setMeta('lastOffersEtag', etag.trim());
    }
    await setMeta('offersLastSyncAt', DateTime.now().toUtc().toIso8601String());
  }

  Future<List<MarketplaceOffer>> readOffers() async {
    final db = await _database();
    final rows = await db.query(
      'marketplace_offers_cache',
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) {
          final payload = _decodeMap(row['payload_json']);
          return MarketplaceOffer.fromJson(payload);
        })
        .toList(growable: false);
  }

  Future<void> cachePurchase(
    MarketplacePurchaseSnapshot snapshot, {
    String? etag,
  }) async {
    final db = await _database();
    final now = _nowMillis();
    await db.insert('marketplace_purchase_cache', <String, Object?>{
      'purchase_id': snapshot.purchaseId,
      'payload_json': jsonEncode(snapshot.toJson()),
      'version': snapshot.version,
      'etag': etag,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.delete(
      'marketplace_assignments_cache',
      where: 'purchase_id = ?',
      whereArgs: <Object?>[snapshot.purchaseId],
    );
    for (final assignment in snapshot.assignments) {
      await db.insert(
        'marketplace_assignments_cache',
        <String, Object?>{
          'purchase_id': snapshot.purchaseId,
          'seat_index': assignment.seatIndex,
          'payload_json': jsonEncode(assignment.toJson()),
          'version': snapshot.assignmentsVersion,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await setMeta(
      'lastPurchaseVersion:${snapshot.purchaseId}',
      '${snapshot.version}',
    );
    if (etag != null && etag.trim().isNotEmpty) {
      await setMeta('purchaseEtag:${snapshot.purchaseId}', etag.trim());
    }
    await setMeta(
      'purchaseLastSyncAt:${snapshot.purchaseId}',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<MarketplacePurchaseSnapshot?> readPurchase(String purchaseId) async {
    final db = await _database();
    final rows = await db.query(
      'marketplace_purchase_cache',
      where: 'purchase_id = ?',
      whereArgs: <Object?>[purchaseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final payload = _decodeMap(rows.first['payload_json']);
    return MarketplacePurchaseSnapshot.fromJson(payload);
  }

  Future<void> mergeTimeline(
    String purchaseId,
    List<MarketplaceTimelineEvent> events, {
    String? latestEventAt,
    String? cursor,
  }) async {
    final db = await _database();
    final batch = db.batch();
    for (final event in events) {
      final eventKey = _timelineEventKey(event);
      batch.insert('marketplace_timeline_cache', <String, Object?>{
        'purchase_id': purchaseId,
        'event_key': eventKey,
        'payload_json': jsonEncode(event.toJson()),
        'event_at': event.timestamp?.millisecondsSinceEpoch ?? 0,
        'cursor': event.cursor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    if (latestEventAt != null && latestEventAt.trim().isNotEmpty) {
      await setMeta('lastTimelineAt:$purchaseId', latestEventAt);
    }
    if (cursor != null && cursor.trim().isNotEmpty) {
      await setMeta('lastTimelineCursor:$purchaseId', cursor);
    }
  }

  Future<List<MarketplaceTimelineEvent>> readTimeline(String purchaseId) async {
    final db = await _database();
    final rows = await db.query(
      'marketplace_timeline_cache',
      where: 'purchase_id = ?',
      whereArgs: <Object?>[purchaseId],
      orderBy: 'event_at ASC, event_key ASC',
    );
    return rows
        .map((row) {
          final payload = _decodeMap(row['payload_json']);
          return MarketplaceTimelineEvent.fromJson(payload);
        })
        .toList(growable: false);
  }

  Future<void> upsertOutboxItem(MarketplaceOutboxItem item) async {
    final db = await _database();
    await db.insert('marketplace_outbox', <String, Object?>{
      'id': item.id,
      'type': item.type.value,
      'purchase_id': item.purchaseId,
      'idempotency_key': item.idempotencyKey,
      'payload_json': jsonEncode(item.payload),
      'base_version': item.baseVersion,
      'status': item.status.value,
      'attempts': item.attempts,
      'next_retry_at': item.nextRetryAt?.millisecondsSinceEpoch,
      'created_at': item.createdAt.millisecondsSinceEpoch,
      'last_error': item.lastError,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MarketplaceOutboxItem>> readDueOutboxItems({
    DateTime? nowUtc,
  }) async {
    final db = await _database();
    final now = (nowUtc ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final rows = await db.query(
      'marketplace_outbox',
      where:
          '(status = ? OR status = ?) AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: <Object?>[
        MarketplaceOutboxStatus.queued.value,
        MarketplaceOutboxStatus.failed.value,
        now,
      ],
      orderBy: 'created_at ASC',
    );
    return rows.map(_outboxFromRow).toList(growable: false);
  }

  Future<void> updateOutboxStatus({
    required String id,
    required MarketplaceOutboxStatus status,
    required int attempts,
    DateTime? nextRetryAt,
    String? lastError,
    int? baseVersion,
  }) async {
    final db = await _database();
    await db.update(
      'marketplace_outbox',
      <String, Object?>{
        'status': status.value,
        'attempts': attempts,
        'next_retry_at': nextRetryAt?.millisecondsSinceEpoch,
        'last_error': lastError,
        'base_version': baseVersion,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteOutboxItem(String id) async {
    final db = await _database();
    await db.delete(
      'marketplace_outbox',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<MarketplaceOutboxItem>> readAllOutboxItems() async {
    final db = await _database();
    final rows = await db.query(
      'marketplace_outbox',
      orderBy: 'created_at ASC',
    );
    return rows.map(_outboxFromRow).toList(growable: false);
  }

  MarketplaceOutboxItem _outboxFromRow(Map<String, Object?> row) {
    return MarketplaceOutboxItem(
      id: row['id']?.toString() ?? '',
      type: MarketplaceOutboxType.fromValue(row['type']?.toString() ?? ''),
      purchaseId: row['purchase_id']?.toString(),
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      payload: _decodeMap(row['payload_json']),
      baseVersion: (row['base_version'] as num?)?.toInt(),
      status: MarketplaceOutboxStatus.fromValue(
        row['status']?.toString() ?? MarketplaceOutboxStatus.queued.value,
      ),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: _millisToDateTime(row['next_retry_at']),
      createdAt: _millisToDateTime(row['created_at']) ?? DateTime.now().toUtc(),
      lastError: row['last_error']?.toString(),
    );
  }

  DateTime? _millisToDateTime(Object? value) {
    final millis = (value as num?)?.toInt();
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  int _nowMillis() => DateTime.now().toUtc().millisecondsSinceEpoch;

  String _timelineEventKey(MarketplaceTimelineEvent event) {
    final cursor = event.cursor ?? '';
    final timestamp = event.timestamp?.toIso8601String() ?? '';
    return '$cursor|${event.type}|$timestamp|${event.description}';
  }

  Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        );
      }
    }
    return <String, dynamic>{};
  }
}
