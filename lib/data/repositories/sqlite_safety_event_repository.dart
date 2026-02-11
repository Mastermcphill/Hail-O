import 'package:sqflite/sqflite.dart';

import 'safety_event_repository.dart';

class SqliteSafetyEventRepository implements SafetyEventRepository {
  const SqliteSafetyEventRepository(this.db);

  final Database db;

  @override
  Future<void> insertEvent({
    required String id,
    required String rideId,
    required String eventType,
    required String payloadJson,
    required DateTime createdAt,
  }) {
    return db.insert('safety_events', <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'event_type': eventType,
      'payload_json': payloadJson,
      'created_at': createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<List<Map<String, Object?>>> listEventsByRide(String rideId) {
    return db.query(
      'safety_events',
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at DESC',
    );
  }
}
