import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/moneybox_ledger_entry.dart';
import '../table_names.dart';

class MoneyBoxLedgerDao {
  const MoneyBoxLedgerDao(this.db);

  final DatabaseExecutor db;

  Future<int> append(MoneyBoxLedgerEntry entry) async {
    return db.insert(
      TableNames.moneyboxLedger,
      entry.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<MoneyBoxLedgerEntry>> listByOwner(String ownerId) async {
    final rows = await db.query(
      TableNames.moneyboxLedger,
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(MoneyBoxLedgerEntry.fromMap).toList(growable: false);
  }
}
