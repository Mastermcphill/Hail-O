import '../migration.dart';

class M0022DispatchTrips extends Migration {
  const M0022DispatchTrips();

  @override
  int get version => 22;

  @override
  String get name => 'm0022_dispatch_trips';

  @override
  String get checksum => 'm0022_dispatch_trips_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS trips (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(
        status IN (
          'created',
          'searching',
          'assigned',
          'enroute_pickup',
          'picked_up',
          'enroute_dropoff',
          'delivered',
          'canceled'
        )
      ),
      pickup_lat REAL NOT NULL,
      pickup_lng REAL NOT NULL,
      pickup_address TEXT,
      dropoff_lat REAL NOT NULL,
      dropoff_lng REAL NOT NULL,
      dropoff_address TEXT,
      notes TEXT,
      scheduled_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_trips_user_created_desc
    ON trips(user_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_trips_status_created_desc
    ON trips(status, created_at DESC)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS trip_events (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL,
      actor_user_id TEXT NOT NULL,
      from_status TEXT,
      to_status TEXT NOT NULL CHECK(
        to_status IN (
          'created',
          'searching',
          'assigned',
          'enroute_pickup',
          'picked_up',
          'enroute_dropoff',
          'delivered',
          'canceled'
        )
      ),
      metadata TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(trip_id) REFERENCES trips(id) ON DELETE CASCADE,
      FOREIGN KEY(actor_user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_trip_events_trip_created
    ON trip_events(trip_id, created_at)
    ''',
  ];
}
