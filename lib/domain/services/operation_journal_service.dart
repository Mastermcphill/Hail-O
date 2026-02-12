import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/operation_journal_dao.dart';
import '../models/operation_journal_entry.dart';

class OperationJournalBeginResult {
  const OperationJournalBeginResult({required this.entry, required this.isNew});

  final OperationJournalEntry entry;
  final bool isNew;
}

class OperationJournalService {
  OperationJournalService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _dao = OperationJournalDao(db);

  final DatabaseExecutor db;
  final DateTime Function() _nowUtc;
  final OperationJournalDao _dao;

  Future<OperationJournalBeginResult> begin({
    required String opType,
    required String entityType,
    required String entityId,
    required String idempotencyScope,
    required String idempotencyKey,
    required String traceId,
    required String metadataJson,
  }) async {
    final normalizedScope = idempotencyScope.trim();
    final normalizedKey = idempotencyKey.trim();
    if (normalizedScope.isEmpty || normalizedKey.isEmpty) {
      throw ArgumentError('idempotency scope/key required');
    }
    final now = _nowUtc();
    final entry = OperationJournalEntry(
      id: 'op:$normalizedScope:$normalizedKey',
      opType: opType.trim().isEmpty ? 'UNKNOWN' : opType.trim(),
      entityType: entityType.trim().isEmpty ? 'unknown' : entityType.trim(),
      entityId: entityId.trim(),
      idempotencyScope: normalizedScope,
      idempotencyKey: normalizedKey,
      traceId: traceId.trim().isEmpty
          ? 'trace:$normalizedScope:$normalizedKey'
          : traceId.trim(),
      status: OperationJournalStatus.started,
      startedAt: now,
      updatedAt: now,
      metadataJson: metadataJson,
    );
    try {
      await _dao.insert(entry);
      return OperationJournalBeginResult(entry: entry, isNew: true);
    } on DatabaseException catch (_) {
      final existing = await _dao.findByScopeKey(
        idempotencyScope: normalizedScope,
        idempotencyKey: normalizedKey,
      );
      if (existing == null) {
        rethrow;
      }
      return OperationJournalBeginResult(entry: existing, isNew: false);
    }
  }

  Future<void> commit({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    await _dao.updateStatus(
      idempotencyScope: idempotencyScope,
      idempotencyKey: idempotencyKey,
      status: OperationJournalStatus.committed,
      updatedAt: _nowUtc(),
      lastError: null,
    );
  }

  Future<void> fail({
    required String idempotencyScope,
    required String idempotencyKey,
    required String errorMessage,
  }) async {
    await _dao.updateStatus(
      idempotencyScope: idempotencyScope,
      idempotencyKey: idempotencyKey,
      status: OperationJournalStatus.failed,
      updatedAt: _nowUtc(),
      lastError: errorMessage,
    );
  }

  Future<void> rollback({
    required String idempotencyScope,
    required String idempotencyKey,
    String? reason,
  }) async {
    await _dao.updateStatus(
      idempotencyScope: idempotencyScope,
      idempotencyKey: idempotencyKey,
      status: OperationJournalStatus.rolledBack,
      updatedAt: _nowUtc(),
      lastError: reason,
    );
  }

  Future<OperationJournalEntry?> getByScopeKey({
    required String idempotencyScope,
    required String idempotencyKey,
  }) {
    return _dao.findByScopeKey(
      idempotencyScope: idempotencyScope,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<List<OperationJournalEntry>> listRecoverableEntries() {
    return _dao.listByStatuses(const <OperationJournalStatus>[
      OperationJournalStatus.started,
      OperationJournalStatus.failed,
    ]);
  }
}
