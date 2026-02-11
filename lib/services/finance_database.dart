import 'package:sqflite/sqflite.dart';

import '../data/sqlite/hailo_database.dart';

enum WalletType {
  driverA('driver_a'),
  driverB('driver_b'),
  driverC('driver_c'),
  fleetOwner('fleet_owner'),
  platform('platform');

  const WalletType(this.value);
  final String value;
}

class FinanceDatabase {
  static const String defaultDbName = 'hail_o_backend_core.db';

  static Future<Database> open({String? databasePath}) {
    return HailODatabase(
      databaseName: defaultDbName,
    ).open(databasePath: databasePath);
  }
}

String isoNowUtc([DateTime? value]) =>
    (value ?? DateTime.now().toUtc()).toIso8601String();

DateTime lagosFromUtc(DateTime utc) =>
    utc.toUtc().add(const Duration(hours: 1));

int percentOf(int amountMinor, int percent) {
  if (amountMinor <= 0 || percent <= 0) {
    return 0;
  }
  return (amountMinor * percent) ~/ 100;
}
