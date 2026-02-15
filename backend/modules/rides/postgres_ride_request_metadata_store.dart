import '../../../lib/domain/models/ride_request_metadata.dart';

import '../../infra/postgres_provider.dart';
import 'ride_request_metadata_store.dart';

class PostgresRideRequestMetadataStore extends RideRequestMetadataStore {
  PostgresRideRequestMetadataStore(this._postgresProvider);

  final PostgresProvider _postgresProvider;

  @override
  Future<RideRequestMetadata?> findByRideId(String rideId) async {
    final connection = await _postgresProvider.open();
    final result = await connection.query(
      '''
      SELECT ride_id, scheduled_departure_at, created_at, updated_at
      FROM ride_request_metadata
      WHERE ride_id = @ride_id
      LIMIT 1
      ''',
      substitutionValues: <String, Object?>{'ride_id': rideId},
    );
    if (result.isEmpty) {
      return null;
    }
    final row = result.first;
    final scheduledAt = row[1];
    if (scheduledAt is! DateTime) {
      return null;
    }
    return RideRequestMetadata(
      rideId: row[0] as String,
      scheduledDepartureAt: scheduledAt.toUtc(),
      createdAt: (row[2] as DateTime).toUtc(),
      updatedAt: (row[3] as DateTime).toUtc(),
    );
  }

  @override
  Future<void> upsert(RideRequestMetadata metadata) async {
    final connection = await _postgresProvider.open();
    await connection.query(
      '''
      INSERT INTO ride_request_metadata(
        ride_id,
        rider_id,
        scheduled_departure_at,
        quote_json,
        request_json,
        created_at,
        updated_at
      )
      VALUES(
        @ride_id,
        @rider_id,
        @scheduled_departure_at,
        @quote_json,
        @request_json,
        @created_at,
        @updated_at
      )
      ON CONFLICT (ride_id)
      DO UPDATE
      SET
        scheduled_departure_at = EXCLUDED.scheduled_departure_at,
        quote_json = EXCLUDED.quote_json,
        request_json = EXCLUDED.request_json,
        updated_at = EXCLUDED.updated_at
      ''',
      substitutionValues: <String, Object?>{
        'ride_id': metadata.rideId,
        'rider_id': '',
        'scheduled_departure_at': metadata.scheduledDepartureAt.toUtc(),
        'quote_json': '{}',
        'request_json': '{}',
        'created_at': metadata.createdAt.toUtc(),
        'updated_at': metadata.updatedAt.toUtc(),
      },
    );
  }
}
