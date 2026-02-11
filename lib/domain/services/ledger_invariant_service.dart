import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/payout_records_dao.dart';
import '../../data/sqlite/dao/wallet_ledger_dao.dart';
import '../../data/sqlite/dao/wallet_reversals_dao.dart';
import '../../data/sqlite/dao/wallets_dao.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';

class LedgerInvariantService {
  const LedgerInvariantService(this.db);

  final Database db;

  Future<Map<String, Object?>> verifySnapshot() async {
    final anomalies = <Map<String, Object?>>[];

    final wallets = await WalletsDao(db).listAll();
    final allEntries = await WalletLedgerDao(db).listAll();

    final byWallet = <String, List<WalletLedgerEntry>>{};
    for (final entry in allEntries) {
      final key = _walletKey(entry.ownerId, entry.walletType);
      byWallet.putIfAbsent(key, () => <WalletLedgerEntry>[]).add(entry);
    }

    final idempotencySeen = <String>{};
    for (final entry in allEntries) {
      final marker = '${entry.idempotencyScope}|${entry.idempotencyKey}';
      if (!idempotencySeen.add(marker)) {
        anomalies.add(<String, Object?>{
          'kind': 'duplicate_wallet_ledger_idempotency',
          'scope': entry.idempotencyScope,
          'key': entry.idempotencyKey,
        });
      }
    }

    for (final wallet in wallets) {
      final key = _walletKey(wallet.ownerId, wallet.walletType);
      final entries = byWallet[key] ?? const <WalletLedgerEntry>[];
      if (entries.isEmpty) {
        if (wallet.balanceMinor != 0) {
          anomalies.add(<String, Object?>{
            'kind': 'wallet_balance_without_ledger',
            'owner_id': wallet.ownerId,
            'wallet_type': wallet.walletType.dbValue,
            'balance_minor': wallet.balanceMinor,
          });
        }
        continue;
      }

      var running = 0;
      var initialized = false;
      for (final entry in entries) {
        if (!initialized) {
          running = entry.direction == LedgerDirection.credit
              ? entry.balanceAfterMinor - entry.amountMinor
              : entry.balanceAfterMinor + entry.amountMinor;
          initialized = true;
        }
        running += entry.direction == LedgerDirection.credit
            ? entry.amountMinor
            : -entry.amountMinor;
        if (running != entry.balanceAfterMinor) {
          anomalies.add(<String, Object?>{
            'kind': 'ledger_running_balance_mismatch',
            'owner_id': entry.ownerId,
            'wallet_type': entry.walletType.dbValue,
            'ledger_id': entry.id,
            'expected': running,
            'actual': entry.balanceAfterMinor,
          });
        }
      }
      if (running != wallet.balanceMinor) {
        anomalies.add(<String, Object?>{
          'kind': 'wallet_vs_ledger_balance_mismatch',
          'owner_id': wallet.ownerId,
          'wallet_type': wallet.walletType.dbValue,
          'wallet_balance_minor': wallet.balanceMinor,
          'ledger_balance_minor': running,
        });
      }
    }

    final reversals = await WalletReversalsDao(db).listAll();
    final reversalOriginalSeen = <int>{};
    final reversalLedgerSeen = <int>{};
    for (final reversal in reversals) {
      if (!reversalOriginalSeen.add(reversal.originalLedgerId)) {
        anomalies.add(<String, Object?>{
          'kind': 'duplicate_reversal_original_link',
          'original_ledger_id': reversal.originalLedgerId,
        });
      }
      if (!reversalLedgerSeen.add(reversal.reversalLedgerId)) {
        anomalies.add(<String, Object?>{
          'kind': 'duplicate_reversal_ledger_link',
          'reversal_ledger_id': reversal.reversalLedgerId,
        });
      }
    }

    final payoutRows = await db.query(
      'payout_records',
      columns: <String>['escrow_id', 'COUNT(*) AS row_count'],
      groupBy: 'escrow_id',
      having: 'COUNT(*) > 1',
    );
    for (final row in payoutRows) {
      anomalies.add(<String, Object?>{
        'kind': 'duplicate_payout_per_escrow',
        'escrow_id': row['escrow_id'],
        'count': row['row_count'],
      });
    }

    final payoutsByRideRows = await db.query(
      'payout_records',
      columns: <String>['ride_id'],
    );
    final payoutDao = PayoutRecordsDao(db);
    for (final row in payoutsByRideRows) {
      final rideId = row['ride_id'] as String?;
      if (rideId == null) {
        continue;
      }
      final latest = await payoutDao.findLatestByRideId(rideId);
      if (latest == null) {
        anomalies.add(<String, Object?>{
          'kind': 'payout_lookup_failed',
          'ride_id': rideId,
        });
      }
    }

    return <String, Object?>{
      'ok': anomalies.isEmpty,
      'anomalies': anomalies,
      'anomaly_count': anomalies.length,
    };
  }

  String _walletKey(String ownerId, WalletType walletType) {
    return '$ownerId|${walletType.dbValue}';
  }
}
