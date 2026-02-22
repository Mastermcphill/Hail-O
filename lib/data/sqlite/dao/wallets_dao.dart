import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/wallet.dart';
import '../table_names.dart';

class WalletsDao {
  const WalletsDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert(Wallet wallet, {required bool viaOrchestrator}) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'wallet_upsert_requires_orchestrator',
      );
    }
    await db.insert(
      TableNames.wallets,
      wallet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Wallet?> find(String ownerId, WalletType walletType) async {
    final rows = await db.query(
      TableNames.wallets,
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Wallet.fromMap(rows.first);
  }

  Future<List<Wallet>> listByOwner(String ownerId) async {
    final rows = await db.query(
      TableNames.wallets,
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Wallet.fromMap).toList(growable: false);
  }

  Future<List<Wallet>> listByTypeWithPositiveBalance(
    WalletType walletType,
  ) async {
    final rows = await db.query(
      TableNames.wallets,
      where: 'wallet_type = ? AND balance_minor > 0',
      whereArgs: <Object>[walletType.dbValue],
      orderBy: 'owner_id ASC',
    );
    return rows.map(Wallet.fromMap).toList(growable: false);
  }

  Future<List<Wallet>> listAll() async {
    final rows = await db.query(
      TableNames.wallets,
      orderBy: 'owner_id ASC, wallet_type ASC',
    );
    return rows.map(Wallet.fromMap).toList(growable: false);
  }
}
