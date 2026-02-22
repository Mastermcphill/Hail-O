import 'ride_request_metadata_store.dart';

class SqliteOperationalRecordStore extends OperationalRecordStore {
  const SqliteOperationalRecordStore();

  @override
  Future<void> logWrite({
    required String operationType,
    required String entityId,
    required String actorUserId,
    required String idempotencyKey,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {}
}
