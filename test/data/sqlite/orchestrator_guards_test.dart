import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/disputes_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/escrow_holds_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/payout_records_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_reversals_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallets_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/models/dispute.dart';
import 'package:hail_o_finance_core/domain/models/payout_record.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/models/wallet_ledger_entry.dart';
import 'package:hail_o_finance_core/domain/models/wallet_reversal_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('wallet mutation DAOs require orchestrator guard flag', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    final now = DateTime.utc(2026, 1, 1);
    final walletsDao = WalletsDao(db);
    final walletLedgerDao = WalletLedgerDao(db);

    await expectLater(
      () => walletsDao.upsert(
        Wallet(
          ownerId: 'owner_guard',
          walletType: WalletType.driverA,
          balanceMinor: 0,
          reservedMinor: 0,
          currency: 'NGN',
          updatedAt: now,
          createdAt: now,
        ),
        viaOrchestrator: false,
      ),
      throwsA(isA<DomainInvariantError>()),
    );

    await expectLater(
      () => walletLedgerDao.append(
        WalletLedgerEntry(
          ownerId: 'owner_guard',
          walletType: WalletType.driverA,
          direction: LedgerDirection.credit,
          amountMinor: 100,
          balanceAfterMinor: 100,
          kind: 'guard_test',
          referenceId: 'ref_guard',
          idempotencyScope: 'guard.scope',
          idempotencyKey: 'guard.key',
          createdAt: now,
        ),
        viaOrchestrator: false,
      ),
      throwsA(isA<DomainInvariantError>()),
    );
  });

  test(
    'escrow/payout/dispute/reversal DAOs require orchestrator guard flag',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final now = DateTime.utc(2026, 1, 1);

      await expectLater(
        () => EscrowHoldsDao(db).markReleasedIfHeld(
          escrowId: 'escrow_guard',
          releaseMode: 'manual_override',
          releasedAtIso: now.toIso8601String(),
          idempotencyScope: 'escrow.release',
          idempotencyKey: 'escrow.guard',
          viaOrchestrator: false,
        ),
        throwsA(isA<DomainInvariantError>()),
      );

      await expectLater(
        () => PayoutRecordsDao(db).insert(
          PayoutRecord(
            id: 'payout_guard',
            rideId: 'ride_guard',
            escrowId: 'escrow_guard',
            trigger: 'manual_override',
            status: 'completed',
            recipientOwnerId: 'owner_guard',
            recipientWalletType: WalletType.driverA.dbValue,
            totalPaidMinor: 0,
            commissionGrossMinor: 0,
            commissionSavedMinor: 0,
            commissionRemainderMinor: 0,
            premiumLockedMinor: 0,
            driverAllowanceMinor: 0,
            cashDebtMinor: 0,
            penaltyDueMinor: 0,
            breakdownJson: '{}',
            idempotencyScope: 'payout.scope',
            idempotencyKey: 'payout.key',
            createdAt: now,
          ),
          viaOrchestrator: false,
        ),
        throwsA(isA<DomainInvariantError>()),
      );

      await expectLater(
        () => DisputesDao(db).insert(
          DisputeRecord(
            id: 'dispute_guard',
            rideId: 'ride_guard',
            openedBy: 'admin_guard',
            status: 'open',
            reason: 'guard test',
            createdAt: now,
          ),
          viaOrchestrator: false,
        ),
        throwsA(isA<DomainInvariantError>()),
      );

      await expectLater(
        () => WalletReversalsDao(db).insert(
          WalletReversalRecord(
            id: 'reversal_guard',
            originalLedgerId: 1,
            reversalLedgerId: 2,
            requestedByUserId: 'admin_guard',
            reason: 'guard test',
            idempotencyScope: 'reversal.scope',
            idempotencyKey: 'reversal.key',
            createdAt: now,
          ),
          viaOrchestrator: false,
        ),
        throwsA(isA<DomainInvariantError>()),
      );
    },
  );
}
