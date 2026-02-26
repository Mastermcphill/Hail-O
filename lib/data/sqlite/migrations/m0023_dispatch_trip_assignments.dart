import '../migration.dart';

class M0023DispatchTripAssignments extends Migration {
  const M0023DispatchTripAssignments();

  @override
  int get version => 23;

  @override
  String get name => 'm0023_dispatch_trip_assignments';

  @override
  String get checksum => 'm0023_dispatch_trip_assignments_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS trip_assignments (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL UNIQUE,
      driver_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('assigned', 'accepted', 'rejected', 'canceled')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(trip_id) REFERENCES trips(id) ON DELETE CASCADE,
      FOREIGN KEY(driver_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_trip_assignments_driver_status_created_desc
    ON trip_assignments(driver_id, status, created_at DESC)
    ''',
  ];
}
