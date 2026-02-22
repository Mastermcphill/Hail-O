import 'dart:convert';

import '../../infra/postgres_provider.dart';
import 'ride_request_metadata_store.dart';

class PostgresOperationalRecordStore extends OperationalRecordStore {
  PostgresOperationalRecordStore(this._postgresProvider);

  final PostgresProvider _postgresProvider;

  @override
  Future<void> logWrite({
    required String operationType,
    required String entityId,
    required String actorUserId,
    required String idempotencyKey,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    await _postgresProvider.withConnection((connection) async {
      await connection.query(
        '''
        INSERT INTO operational_records(
          operation_type,
          entity_id,
          actor_user_id,
          idempotency_key,
          payload_json,
          created_at
        )
        VALUES(
          @operation_type,
          @entity_id,
          @actor_user_id,
          @idempotency_key,
          @payload_json,
          NOW()
        )
        ON CONFLICT (operation_type, entity_id, idempotency_key)
        DO NOTHING
        ''',
        substitutionValues: <String, Object?>{
          'operation_type': operationType,
          'entity_id': entityId,
          'actor_user_id': actorUserId,
          'idempotency_key': idempotencyKey,
          'payload_json': jsonEncode(payload),
        },
      );
    });
  }
}
