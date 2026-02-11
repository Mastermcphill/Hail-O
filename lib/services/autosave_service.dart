import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/moneybox_repository.dart';
import '../data/repositories/sqlite_moneybox_repository.dart';
import '../data/repositories/sqlite_wallet_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/sqlite/dao/idempotency_dao.dart';
import '../data/sqlite/dao/moneybox_accounts_dao.dart';
import '../data/sqlite/dao/moneybox_ledger_dao.dart';
import '../data/sqlite/dao/wallet_ledger_dao.dart';
import '../data/sqlite/dao/wallets_dao.dart';
import '../domain/models/moneybox_account.dart';
import '../domain/models/moneybox_ledger_entry.dart';
import '../domain/models/wallet.dart';
import '../domain/models/wallet_ledger_entry.dart';
import '../domain/services/finance_utils.dart';
import 'moneybox_service.dart';

class AutosaveService {
  AutosaveService(
    this.db, {
    required this.moneyBoxService,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final MoneyBoxService moneyBoxService;
  final DateTime Function() _nowUtc;

  static const String confirmedCommissionCredit = 'confirmed_commission_credit';

  Future<Map<String, Object?>> applyOnConfirmedCommissionCredit({
    required String ownerId,
    required WalletType destinationWalletType,
    required int grossAmountMinor,
    required String sourceKind,
    required String referenceId,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    if (grossAmountMinor <= 0) {
      throw ArgumentError('grossAmountMinor must be > 0');
    }
    if (sourceKind != confirmedCommissionCredit) {
      return <String, Object?>{
        'ok': false,
        'error': 'autosave_source_not_allowed',
      };
    }

    const scope = 'autosave_split_credit';
    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readHash(txn, scope: scope, key: idempotencyKey);
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      final moneyboxRepo = _moneyBoxRepositoryFor(txn);
      final walletRepo = _walletRepositoryFor(txn);
      final account = await _ensureMoneyBoxAccountTx(txn, ownerId);

      final autosavePercent = account.autosavePercent.clamp(0, 30);
      final savedMinor = autosavePercent >= 1
          ? percentOf(grossAmountMinor, autosavePercent)
          : 0;
      final remainderMinor = grossAmountMinor - savedMinor;

      var principalAfter = account.principalMinor;
      var projectedBonusAfter = account.projectedBonusMinor;
      var expectedAfter = account.expectedAtMaturityMinor;
      final now = _nowUtc();

      if (savedMinor > 0) {
        principalAfter = account.principalMinor + savedMinor;
        projectedBonusAfter = moneyBoxService.projectedBonusFor(
          principalMinor: principalAfter,
          tier: account.tier.value,
        );
        expectedAfter = principalAfter + projectedBonusAfter;

        await moneyboxRepo.upsertAccount(
          MoneyBoxAccount(
            ownerId: account.ownerId,
            tier: account.tier,
            status: account.status,
            lockStart: account.lockStart,
            autoOpenDate: account.autoOpenDate,
            maturityDate: account.maturityDate,
            principalMinor: principalAfter,
            projectedBonusMinor: projectedBonusAfter,
            expectedAtMaturityMinor: expectedAfter,
            autosavePercent: account.autosavePercent,
            bonusEligible: account.bonusEligible,
            createdAt: account.createdAt,
            updatedAt: now,
          ),
        );

        await moneyboxRepo.appendLedger(
          MoneyBoxLedgerEntry(
            ownerId: ownerId,
            entryType: 'autosave_credit',
            amountMinor: savedMinor,
            principalAfterMinor: principalAfter,
            projectedBonusAfterMinor: projectedBonusAfter,
            expectedAfterMinor: expectedAfter,
            sourceKind: sourceKind,
            referenceId: referenceId,
            idempotencyScope: scope,
            idempotencyKey: '$idempotencyKey:moneybox',
            createdAt: now,
          ),
        );
      }

      var destinationWallet = await _ensureWalletTx(
        txn,
        ownerId: ownerId,
        walletType: destinationWalletType,
      );

      if (remainderMinor > 0) {
        final walletAfter = destinationWallet.balanceMinor + remainderMinor;
        destinationWallet = Wallet(
          ownerId: destinationWallet.ownerId,
          walletType: destinationWallet.walletType,
          balanceMinor: walletAfter,
          reservedMinor: destinationWallet.reservedMinor,
          currency: destinationWallet.currency,
          createdAt: destinationWallet.createdAt,
          updatedAt: now,
        );
        await walletRepo.upsertWallet(destinationWallet);
        await walletRepo.appendLedger(
          WalletLedgerEntry(
            ownerId: ownerId,
            walletType: destinationWalletType,
            direction: LedgerDirection.credit,
            amountMinor: remainderMinor,
            balanceAfterMinor: walletAfter,
            kind: confirmedCommissionCredit,
            referenceId: referenceId,
            idempotencyScope: scope,
            idempotencyKey: '$idempotencyKey:wallet',
            createdAt: now,
          ),
        );
      }

      final result = <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'gross_minor': grossAmountMinor,
        'saved_minor': savedMinor,
        'remainder_minor': remainderMinor,
        'autosave_percent': autosavePercent,
        'wallet_balance_after_minor': destinationWallet.balanceMinor,
        'moneybox_principal_after_minor': principalAfter,
        'moneybox_projected_bonus_after_minor': projectedBonusAfter,
        'moneybox_expected_after_minor': expectedAfter,
      };

      await _finalize(txn, scope: scope, key: idempotencyKey, result: result);
      return result;
    });
  }

  Future<MoneyBoxAccount> _ensureMoneyBoxAccountTx(
    DatabaseExecutor txn,
    String ownerId,
  ) async {
    final repo = _moneyBoxRepositoryFor(txn);
    final existing = await repo.getAccount(ownerId);
    if (existing != null) {
      return existing;
    }
    final now = _nowUtc();
    final account = MoneyBoxAccount(
      ownerId: ownerId,
      tier: MoneyBoxTier.tier1,
      status: 'active',
      lockStart: now,
      autoOpenDate: now.add(const Duration(days: 29)),
      maturityDate: now.add(const Duration(days: 30)),
      principalMinor: 0,
      projectedBonusMinor: 0,
      expectedAtMaturityMinor: 0,
      autosavePercent: 0,
      bonusEligible: true,
      createdAt: now,
      updatedAt: now,
    );
    await repo.upsertAccount(account);
    return (await repo.getAccount(ownerId))!;
  }

  Future<Wallet> _ensureWalletTx(
    DatabaseExecutor txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final repo = _walletRepositoryFor(txn);
    final existing = await repo.getWallet(ownerId, walletType);
    if (existing != null) {
      return existing;
    }

    final now = _nowUtc();
    final wallet = Wallet(
      ownerId: ownerId,
      walletType: walletType,
      balanceMinor: 0,
      reservedMinor: 0,
      currency: 'NGN',
      updatedAt: now,
      createdAt: now,
    );
    await repo.upsertWallet(wallet);
    return wallet;
  }

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
  }

  Future<bool> _claimIdempotency(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
  }) async {
    final claim = await IdempotencyDao(txn).claim(scope: scope, key: key);
    return claim.isNewClaim;
  }

  Future<String> _readHash(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
  }) async {
    final record = await IdempotencyDao(txn).get(scope: scope, key: key);
    return record?.resultHash ?? '';
  }

  Future<void> _finalize(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
    required Map<String, Object?> result,
  }) async {
    final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
    await IdempotencyDao(
      txn,
    ).finalizeSuccess(scope: scope, key: key, resultHash: hash);
  }

  MoneyBoxRepository _moneyBoxRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteMoneyBoxRepository(
      accountsDao: MoneyBoxAccountsDao(txnOrDb),
      ledgerDao: MoneyBoxLedgerDao(txnOrDb),
    );
  }

  WalletRepository _walletRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteWalletRepository(
      walletsDao: WalletsDao(txnOrDb),
      walletLedgerDao: WalletLedgerDao(txnOrDb),
    );
  }
}
