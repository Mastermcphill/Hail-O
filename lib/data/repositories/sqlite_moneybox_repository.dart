import '../../domain/models/moneybox_account.dart';
import '../../domain/models/moneybox_ledger_entry.dart';
import '../sqlite/dao/moneybox_accounts_dao.dart';
import '../sqlite/dao/moneybox_ledger_dao.dart';
import 'moneybox_repository.dart';

class SqliteMoneyBoxRepository implements MoneyBoxRepository {
  const SqliteMoneyBoxRepository({
    required MoneyBoxAccountsDao accountsDao,
    required MoneyBoxLedgerDao ledgerDao,
  }) : _accountsDao = accountsDao,
       _ledgerDao = ledgerDao;

  final MoneyBoxAccountsDao _accountsDao;
  final MoneyBoxLedgerDao _ledgerDao;

  @override
  Future<int> appendLedger(MoneyBoxLedgerEntry entry) =>
      _ledgerDao.append(entry);

  @override
  Future<MoneyBoxAccount?> getAccount(String ownerId) =>
      _accountsDao.findByOwner(ownerId);

  @override
  Future<List<MoneyBoxLedgerEntry>> listLedger(String ownerId) {
    return _ledgerDao.listByOwner(ownerId);
  }

  @override
  Future<void> upsertAccount(MoneyBoxAccount account) =>
      _accountsDao.upsert(account);
}
