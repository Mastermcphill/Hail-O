import 'package:sqflite/sqflite.dart';

import '../../../domain/models/wallet.dart';
import '../../../domain/models/wallet_ledger_entry.dart';
import '../table_names.dart';

class WalletLedgerDao {
  const WalletLedgerDao(this.db);

  final Database db;

  Future<int> append(WalletLedgerEntry entry) async {
    return db.insert(
      TableNames.walletLedger,
      entry.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<WalletLedgerEntry>> listByWallet(
    String ownerId,
    WalletType walletType,
  ) async {
    final rows = await db.query(
      TableNames.walletLedger,
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(WalletLedgerEntry.fromMap).toList(growable: false);
  }
}
