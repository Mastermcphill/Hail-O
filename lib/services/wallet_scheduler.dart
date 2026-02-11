import 'package:sqflite/sqflite.dart';

import '../data/sqlite/dao/wallets_dao.dart';
import '../domain/models/wallet.dart';
import '../domain/services/finance_utils.dart';
import 'wallet_service.dart';

class WalletScheduler {
  WalletScheduler({required this.db, required this.walletService});

  final Database db;
  final WalletService walletService;

  Future<Map<String, Object>> runMondayUnlockMove({
    required DateTime nowUtc,
    required String idempotencySeed,
  }) async {
    final lagos = lagosFromUtc(nowUtc);
    final isMonday = lagos.weekday == DateTime.monday;
    final unlockWindowReached =
        lagos.hour > 0 || (lagos.hour == 0 && lagos.minute >= 1);

    if (!isMonday || !unlockWindowReached) {
      return <String, Object>{
        'ok': true,
        'skipped': true,
        'reason': 'outside_monday_unlock_window',
        'moved_wallet_count': 0,
        'moved_total_minor': 0,
      };
    }

    final wallets = await WalletsDao(
      db,
    ).listByTypeWithPositiveBalance(WalletType.driverB);

    var movedWalletCount = 0;
    var movedTotalMinor = 0;
    final batchTag = _batchTag(lagos);

    for (final wallet in wallets) {
      final ownerId = wallet.ownerId;
      if (ownerId.isEmpty) {
        continue;
      }
      final moved = await walletService.moveWalletBToA(
        ownerId: ownerId,
        referenceId: 'wallet_b_unlock_$batchTag',
        idempotencyKey: '$idempotencySeed:$batchTag:$ownerId',
      );
      if (moved > 0) {
        movedWalletCount += 1;
        movedTotalMinor += moved;
      }
    }

    return <String, Object>{
      'ok': true,
      'skipped': false,
      'batch': batchTag,
      'moved_wallet_count': movedWalletCount,
      'moved_total_minor': movedTotalMinor,
    };
  }

  String _batchTag(DateTime lagos) {
    final y = lagos.year.toString().padLeft(4, '0');
    final m = lagos.month.toString().padLeft(2, '0');
    final d = lagos.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
