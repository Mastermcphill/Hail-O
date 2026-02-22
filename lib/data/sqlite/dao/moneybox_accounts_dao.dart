import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/moneybox_account.dart';
import '../table_names.dart';

class MoneyBoxAccountsDao {
  const MoneyBoxAccountsDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert(MoneyBoxAccount account) async {
    await db.insert(
      TableNames.moneyboxAccounts,
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MoneyBoxAccount?> findByOwner(String ownerId) async {
    final rows = await db.query(
      TableNames.moneyboxAccounts,
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MoneyBoxAccount.fromMap(rows.first);
  }
}
