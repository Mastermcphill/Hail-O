import 'package:hail_o_finance_core/sqlite_api.dart';

import 'liquidation_repository.dart';

class SqliteLiquidationRepository implements LiquidationRepository {
  const SqliteLiquidationRepository(this.db);

  final Database db;

  @override
  Future<List<Map<String, Object?>>> listLiquidationEvents(String ownerId) {
    return db.query(
      'moneybox_liquidation_events',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      orderBy: 'created_at DESC',
    );
  }

  @override
  Future<void> recordLiquidationEvent({
    required String eventId,
    required String ownerId,
    required String reason,
    required int principalMinor,
    required int penaltyMinor,
    required String? harmedPartyId,
    required String status,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  }) async {
    await db.insert('moneybox_liquidation_events', <String, Object?>{
      'event_id': eventId,
      'owner_id': ownerId,
      'reason': reason,
      'principal_minor': principalMinor,
      'penalty_minor': penaltyMinor,
      'harmed_party_id': harmedPartyId,
      'status': status,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }
}
