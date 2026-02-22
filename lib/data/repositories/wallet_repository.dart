import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_ledger_entry.dart';

abstract class WalletRepository {
  Future<void> upsertWallet(Wallet wallet);
  Future<Wallet?> getWallet(String ownerId, WalletType walletType);
  Future<List<Wallet>> listWallets(String ownerId);
  Future<int> appendLedger(WalletLedgerEntry entry);
  Future<List<WalletLedgerEntry>> listLedger(
    String ownerId,
    WalletType walletType,
  );
}
