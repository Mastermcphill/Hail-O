import '../../domain/models/reconciliation_anomaly.dart';

abstract class ReconciliationRepository {
  Future<void> startRun({
    required String runId,
    required DateTime startedAt,
    required String status,
    String? notes,
  });

  Future<void> finishRun({
    required String runId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String status,
    String? notes,
  });

  Future<void> upsertAnomaly(ReconciliationAnomaly anomaly);
  Future<List<ReconciliationAnomaly>> listAnomalies(String runId);
}
