import 'package:sqflite/sqflite.dart';

import '../../../domain/models/escrow_hold.dart';
import '../../../domain/errors/domain_errors.dart';
import '../table_names.dart';

class EscrowHoldsDao {
  const EscrowHoldsDao(this.db);

  final DatabaseExecutor db;

  Future<EscrowHold?> findById(String escrowId) async {
    final rows = await db.query(
      TableNames.escrowHolds,
      where: 'id = ?',
      whereArgs: <Object>[escrowId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return EscrowHold.fromMap(rows.first);
  }

  Future<bool> markReleasedIfHeld({
    required String escrowId,
    required String releaseMode,
    required String releasedAtIso,
    required String idempotencyScope,
    required String idempotencyKey,
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'escrow_release_requires_orchestrator',
      );
    }
    final updated = await db.update(
      TableNames.escrowHolds,
      <String, Object?>{
        'status': 'released',
        'release_mode': releaseMode,
        'released_at': releasedAtIso,
        'idempotency_scope': idempotencyScope,
        'idempotency_key': idempotencyKey,
      },
      where: 'id = ? AND status = ?',
      whereArgs: <Object>[escrowId, 'held'],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return updated > 0;
  }
}
