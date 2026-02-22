import '../migration.dart';

class M0019RideRequestMetadata extends Migration {
  const M0019RideRequestMetadata();

  @override
  int get version => 19;

  @override
  String get name => 'm0019_ride_request_metadata';

  @override
  String get checksum => 'm0019_ride_request_metadata_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS ride_request_metadata (
      ride_id TEXT PRIMARY KEY,
      scheduled_departure_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_ride_request_metadata_departure
    ON ride_request_metadata(scheduled_departure_at)
    ''',
  ];
}
