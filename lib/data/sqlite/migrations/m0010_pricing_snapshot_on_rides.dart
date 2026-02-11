import '../migration.dart';

class M0010PricingSnapshotOnRides extends Migration {
  const M0010PricingSnapshotOnRides();

  @override
  int get version => 10;

  @override
  String get name => 'm0010_pricing_snapshot_on_rides';

  @override
  String get checksum => 'm0010_pricing_snapshot_on_rides_v1';

  @override
  List<String> get upSql => <String>[
    '''
    ALTER TABLE rides ADD COLUMN pricing_version TEXT NOT NULL DEFAULT 'legacy_v0'
    ''',
    '''
    ALTER TABLE rides ADD COLUMN pricing_breakdown_json TEXT NOT NULL DEFAULT '{}'
    ''',
    '''
    ALTER TABLE rides ADD COLUMN quoted_fare_minor INTEGER NOT NULL DEFAULT 0
    ''',
  ];
}
