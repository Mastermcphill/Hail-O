import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_ledger_entry.dart';
import '../sqlite/dao/wallet_ledger_dao.dart';
import '../sqlite/dao/wallets_dao.dart';
import 'wallet_repository.dart';

class SqliteWalletRepository implements WalletRepository {
  const SqliteWalletRepository({
    required WalletsDao walletsDao,
    required WalletLedgerDao walletLedgerDao,
  }) : _walletsDao = walletsDao,
       _walletLedgerDao = walletLedgerDao;

  final WalletsDao _walletsDao;
  final WalletLedgerDao _walletLedgerDao;

  @override
  Future<int> appendLedger(WalletLedgerEntry entry) =>
      _walletLedgerDao.append(entry);

  @override
  Future<Wallet?> getWallet(String ownerId, WalletType walletType) {
    return _walletsDao.find(ownerId, walletType);
  }

  @override
  Future<List<WalletLedgerEntry>> listLedger(
    String ownerId,
    WalletType walletType,
  ) {
    return _walletLedgerDao.listByWallet(ownerId, walletType);
  }

  @override
  Future<List<Wallet>> listWallets(String ownerId) =>
      _walletsDao.listByOwner(ownerId);

  @override
  Future<void> upsertWallet(Wallet wallet) => _walletsDao.upsert(wallet);
}
