import '../../domain/models/reconciliation_anomaly.dart';
import '../sqlite/dao/reconciliation_dao.dart';
import 'reconciliation_repository.dart';

class SqliteReconciliationRepository implements ReconciliationRepository {
  const SqliteReconciliationRepository(this._dao);

  final ReconciliationDao _dao;

  @override
  Future<void> finishRun({
    required String runId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String status,
    String? notes,
  }) {
    return _dao.insertRun(
      runId: runId,
      startedAt: startedAt.toUtc().toIso8601String(),
      finishedAt: finishedAt.toUtc().toIso8601String(),
      status: status,
      notes: notes,
    );
  }

  @override
  Future<List<ReconciliationAnomaly>> listAnomalies(String runId) {
    return _dao.listAnomaliesByRun(runId);
  }

  @override
  Future<void> startRun({
    required String runId,
    required DateTime startedAt,
    required String status,
    String? notes,
  }) {
    return _dao.insertRun(
      runId: runId,
      startedAt: startedAt.toUtc().toIso8601String(),
      status: status,
      notes: notes,
    );
  }

  @override
  Future<void> upsertAnomaly(ReconciliationAnomaly anomaly) {
    return _dao.upsertAnomaly(anomaly);
  }
}
