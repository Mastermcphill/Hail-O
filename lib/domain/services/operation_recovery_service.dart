import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../models/idempotency_record.dart';
import '../models/operation_journal_entry.dart';
import 'operation_journal_service.dart';

typedef OperationRecoveryHandler =
    Future<bool> Function(OperationJournalEntry entry);

class OperationRecoveryService {
  OperationRecoveryService(
    this.db, {
    OperationJournalService? journalService,
    Map<String, OperationRecoveryHandler> handlers =
        const <String, OperationRecoveryHandler>{},
  }) : _journalService = journalService ?? OperationJournalService(db),
       _idempotencyStore = IdempotencyDao(db),
       _handlers = handlers;

  final DatabaseExecutor db;
  final OperationJournalService _journalService;
  final IdempotencyStore _idempotencyStore;
  final Map<String, OperationRecoveryHandler> _handlers;

  Future<Map<String, Object?>> recover() async {
    final entries = await _journalService.listRecoverableEntries();
    var committed = 0;
    var failed = 0;
    final unresolved = <String>[];

    for (final entry in entries) {
      final idempotency = await _idempotencyStore.get(
        scope: entry.idempotencyScope,
        key: entry.idempotencyKey,
      );
      if (idempotency?.status == IdempotencyStatus.success) {
        await _journalService.commit(
          idempotencyScope: entry.idempotencyScope,
          idempotencyKey: entry.idempotencyKey,
        );
        committed++;
        continue;
      }

      final handler = _handlers[entry.opType];
      if (handler == null) {
        await _journalService.fail(
          idempotencyScope: entry.idempotencyScope,
          idempotencyKey: entry.idempotencyKey,
          errorMessage: 'recovery_handler_missing:${entry.opType}',
        );
        failed++;
        unresolved.add(entry.id);
        continue;
      }

      try {
        final recovered = await handler(entry);
        if (recovered) {
          await _journalService.commit(
            idempotencyScope: entry.idempotencyScope,
            idempotencyKey: entry.idempotencyKey,
          );
          committed++;
        } else {
          await _journalService.fail(
            idempotencyScope: entry.idempotencyScope,
            idempotencyKey: entry.idempotencyKey,
            errorMessage: 'recovery_handler_returned_false',
          );
          failed++;
          unresolved.add(entry.id);
        }
      } catch (error) {
        await _journalService.fail(
          idempotencyScope: entry.idempotencyScope,
          idempotencyKey: entry.idempotencyKey,
          errorMessage: _safeError(error),
        );
        failed++;
        unresolved.add(entry.id);
      }
    }

    return <String, Object?>{
      'ok': unresolved.isEmpty,
      'processed': entries.length,
      'committed': committed,
      'failed': failed,
      'unresolved_operation_ids': unresolved,
    };
  }

  String _safeError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) {
      return 'unknown_recovery_error';
    }
    if (text.length > 500) {
      return text.substring(0, 500);
    }
    return text;
  }
}
