import '../../domain/models/moneybox_account.dart';
import '../../domain/models/moneybox_ledger_entry.dart';

abstract class MoneyBoxRepository {
  Future<void> upsertAccount(MoneyBoxAccount account);
  Future<MoneyBoxAccount?> getAccount(String ownerId);
  Future<int> appendLedger(MoneyBoxLedgerEntry entry);
  Future<List<MoneyBoxLedgerEntry>> listLedger(String ownerId);
}
