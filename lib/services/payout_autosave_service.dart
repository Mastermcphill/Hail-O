import 'dart:convert';

import 'package:hailo_shared/sqlite_api.dart';

class AutosaveBankDestination {
  const AutosaveBankDestination({
    required this.accountNumber,
    required this.bankCode,
    required this.name,
  });

  final String accountNumber;
  final String bankCode;
  final String name;

  String get maskedAccountNumber {
    final normalized = accountNumber.trim();
    if (normalized.isEmpty) {
      return '****';
    }
    final suffix = normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
    return '****$suffix';
  }

  Map<String, Object?> toMaskedMap({required String recipientCode}) {
    return <String, Object?>{
      'bank_code': bankCode.trim(),
      'name': name.trim(),
      'masked_account_number': maskedAccountNumber,
      'recipient_code': recipientCode,
    };
  }
}

class SettlementTransferRecipientResult {
  const SettlementTransferRecipientResult({
    required this.recipientCode,
    this.raw = const <String, Object?>{},
  });

  final String recipientCode;
  final Map<String, Object?> raw;
}

class SettlementTransferResult {
  const SettlementTransferResult({
    required this.transferCode,
    required this.status,
    this.raw = const <String, Object?>{},
  });

  final String transferCode;
  final String status;
  final Map<String, Object?> raw;
}

abstract class SettlementTransferProvider {
  const SettlementTransferProvider();

  Future<SettlementTransferRecipientResult> createTransferRecipient({
    required String accountNumber,
    required String bankCode,
    required String name,
  });

  Future<SettlementTransferResult> initiateTransfer({
    required String recipientCode,
    required int amountMinor,
    required String reference,
    required String reason,
  });
}

class DeterministicSettlementTransferProvider
    extends SettlementTransferProvider {
  const DeterministicSettlementTransferProvider();

  @override
  Future<SettlementTransferRecipientResult> createTransferRecipient({
    required String accountNumber,
    required String bankCode,
    required String name,
  }) async {
    final normalizedAccount = accountNumber.trim();
    final suffix = normalizedAccount.length <= 4
        ? normalizedAccount
        : normalizedAccount.substring(normalizedAccount.length - 4);
    final label = name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return SettlementTransferRecipientResult(
      recipientCode:
          'rcpt_${bankCode.trim()}_${suffix}_${label.isEmpty ? 'dest' : label}',
      raw: <String, Object?>{
        'mode': 'deterministic',
        'bank_code': bankCode.trim(),
        'name': name.trim(),
        'masked_account_number': normalizedAccount.isEmpty
            ? '****'
            : '****$suffix',
      },
    );
  }

  @override
  Future<SettlementTransferResult> initiateTransfer({
    required String recipientCode,
    required int amountMinor,
    required String reference,
    required String reason,
  }) async {
    return SettlementTransferResult(
      transferCode: 'trf_${reference.replaceAll(':', '_')}',
      status: 'SUCCESS',
      raw: <String, Object?>{
        'mode': 'deterministic',
        'recipient_code': recipientCode,
        'amount_minor': amountMinor,
        'reference': reference,
        'reason': reason,
      },
    );
  }
}

class PayoutAutosaveService {
  PayoutAutosaveService(
    this.db, {
    SettlementTransferProvider? transferProvider,
    DateTime Function()? nowUtc,
    double exitFeeRate = 0.02,
    int exitFeeCapMinor = 1000000,
  }) : _transferProvider =
           transferProvider ?? const DeterministicSettlementTransferProvider(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _exitFeeRate = exitFeeRate < 0 ? 0 : exitFeeRate,
       _exitFeeCapMinor = exitFeeCapMinor < 0 ? 0 : exitFeeCapMinor;

  final Database db;
  final SettlementTransferProvider _transferProvider;
  final DateTime Function() _nowUtc;
  final double _exitFeeRate;
  final int _exitFeeCapMinor;

  static const String internalCommissionCredit = 'confirmed_commission_credit';

  Future<Map<String, Object?>> getStatus({required String userId}) async {
    final plan = await _findPlan(db, userId.trim());
    if (plan == null) {
      return <String, Object?>{
        'ok': true,
        'configured': false,
        'status': 'NOT_CONFIGURED',
        'bonus_eligible': false,
        'totals': const <String, Object?>{
          'total_autosaved_minor': 0,
          'total_bonus_minor': 0,
          'total_exit_fees_minor': 0,
        },
        'masked_destinations': const <String, Object?>{},
      };
    }
    return _statusFromPlan(db, plan);
  }

  Future<List<Map<String, Object?>>> listLedger({
    required String userId,
    int limit = 50,
  }) async {
    final rows = await db.query(
      'autosave_ledger',
      where: 'user_id = ?',
      whereArgs: <Object>[userId.trim()],
      orderBy: 'id DESC',
      limit: _normalizedLimit(limit),
    );
    return rows.map(_ledgerRowToMap).toList(growable: false);
  }

  Future<Map<String, Object?>> configurePlan({
    required String userId,
    required bool autosaveEnabled,
    required int tier,
    required int autosavePercent,
    required AutosaveBankDestination mainBank,
    required AutosaveBankDestination savingsBank,
    String? idempotencyKey,
  }) async {
    final normalizedUserId = userId.trim();
    final safeTier = _normalizeTier(tier);
    final safePercent = _normalizePercent(autosavePercent);
    final referenceSeed = (idempotencyKey ?? '').trim().isEmpty
        ? _nowUtc().millisecondsSinceEpoch.toString()
        : idempotencyKey!.trim();

    final mainRecipient = await _transferProvider.createTransferRecipient(
      accountNumber: mainBank.accountNumber.trim(),
      bankCode: mainBank.bankCode.trim(),
      name: mainBank.name.trim(),
    );
    final savingsRecipient = await _transferProvider.createTransferRecipient(
      accountNumber: savingsBank.accountNumber.trim(),
      bankCode: savingsBank.bankCode.trim(),
      name: savingsBank.name.trim(),
    );

    await db.transaction((txn) async {
      await _assertDriverUser(txn, normalizedUserId);
      final existing = await _findPlan(txn, normalizedUserId);
      final nowIso = _nowUtc().toIso8601String();
      final lockDays = _lockDaysForTier(safeTier);
      final status = autosaveEnabled ? 'ACTIVE' : 'PAUSED';
      final planValues = <String, Object?>{
        'user_id': normalizedUserId,
        'tier': safeTier,
        'lock_days': lockDays,
        'autosave_enabled': autosaveEnabled ? 1 : 0,
        'autosave_percent': safePercent,
        'status': status,
        'started_at': nowIso,
        'maturity_at': _nowUtc()
            .add(Duration(days: lockDays))
            .toIso8601String(),
        'bonus_rate': _bonusRateForTier(safeTier),
        'bonus_eligible': 1,
        'main_recipient_code': mainRecipient.recipientCode,
        'savings_recipient_code': savingsRecipient.recipientCode,
        'updated_at': nowIso,
      };

      int planId;
      if (existing == null) {
        planId = await txn.insert('autosave_plans', <String, Object?>{
          ...planValues,
          'bonus_paid_at': null,
          'total_autosaved_minor': 0,
          'total_bonus_minor': 0,
          'total_exit_fees_minor': 0,
          'last_applied_payout_ledger_id': null,
          'created_at': nowIso,
        });
      } else {
        await txn.update(
          'autosave_plans',
          planValues,
          where: 'id = ?',
          whereArgs: <Object>[_asInt(existing['id'])],
        );
        planId = _asInt(existing['id']);
      }

      final ledgerReference = existing == null
          ? 'plan_open:$normalizedUserId:$referenceSeed'
          : 'plan_change:$normalizedUserId:$referenceSeed';
      if (!await _ledgerReferenceExists(txn, ledgerReference)) {
        await txn.insert('autosave_ledger', <String, Object?>{
          'user_id': normalizedUserId,
          'plan_id': planId,
          'payout_ledger_id': null,
          'entry_type': existing == null ? 'PLAN_OPEN' : 'PLAN_CHANGE',
          'amount_minor': 0,
          'reference': ledgerReference,
          'meta_json': jsonEncode(<String, Object?>{
            'main_destination': mainBank.toMaskedMap(
              recipientCode: mainRecipient.recipientCode,
            ),
            'savings_destination': savingsBank.toMaskedMap(
              recipientCode: savingsRecipient.recipientCode,
            ),
            'recipient_meta': <String, Object?>{
              'main': mainRecipient.raw,
              'savings': savingsRecipient.raw,
            },
            'autosave_enabled': autosaveEnabled,
            'autosave_percent': safePercent,
            'tier': safeTier,
          }),
          'created_at': nowIso,
        });
      }
    });

    return getStatus(userId: normalizedUserId);
  }

  Future<Map<String, Object?>> disablePlan({
    required String userId,
    String reason = '',
    String? idempotencyKey,
  }) async {
    final normalizedUserId = userId.trim();
    await db.transaction((txn) async {
      final plan = await _findPlan(txn, normalizedUserId);
      if (plan == null) {
        return;
      }

      final now = _nowUtc();
      final nowIso = now.toIso8601String();
      final planId = _asInt(plan['id']);
      final referenceSeed = (idempotencyKey ?? '').trim().isEmpty
          ? _yyyyMmDd(now)
          : idempotencyKey!.trim();
      final maturityAt = _asDateTime(plan['maturity_at']);
      final isEarly = maturityAt == null || now.isBefore(maturityAt);

      if (isEarly) {
        final exitFeeMinor = _computeExitFeeMinor(
          totalAutosavedMinor: _asInt(plan['total_autosaved_minor']),
        );
        await txn.update(
          'autosave_plans',
          <String, Object?>{
            'autosave_enabled': 0,
            'status': 'PAUSED',
            'bonus_eligible': 0,
            'total_exit_fees_minor':
                _asInt(plan['total_exit_fees_minor']) + exitFeeMinor,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: <Object>[planId],
        );
        await _appendLedgerIfMissing(
          txn,
          userId: normalizedUserId,
          planId: planId,
          entryType: 'EXIT_FEE',
          amountMinor: exitFeeMinor,
          reference: 'exitfee:$planId:$referenceSeed',
          meta: <String, Object?>{
            'reason': reason.trim(),
            'rate': _exitFeeRate,
            'cap_minor': _exitFeeCapMinor,
          },
        );
        await _appendLedgerIfMissing(
          txn,
          userId: normalizedUserId,
          planId: planId,
          entryType: 'PLAN_PAUSE',
          amountMinor: 0,
          reference: 'plan_pause:$planId:$referenceSeed',
          meta: <String, Object?>{'reason': reason.trim()},
        );
        return;
      }

      await txn.update(
        'autosave_plans',
        <String, Object?>{
          'autosave_enabled': 0,
          'status': 'CLOSED',
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[planId],
      );
      await _appendLedgerIfMissing(
        txn,
        userId: normalizedUserId,
        planId: planId,
        entryType: 'PLAN_CLOSE',
        amountMinor: 0,
        reference: 'plan_close:$planId:$referenceSeed',
        meta: <String, Object?>{'reason': reason.trim()},
      );
    });

    return getStatus(userId: normalizedUserId);
  }

  Future<Map<String, Object?>> applyOnPayout({
    required String userId,
    required String payoutLedgerId,
    required int payoutMinor,
    String? tripId,
  }) {
    return db.transaction(
      (txn) => applyOnPayoutWithExecutor(
        executor: txn,
        userId: userId,
        payoutLedgerId: payoutLedgerId,
        payoutMinor: payoutMinor,
        tripId: tripId,
      ),
    );
  }

  Future<Map<String, Object?>> applyOnPayoutWithExecutor({
    required DatabaseExecutor executor,
    required String userId,
    required String payoutLedgerId,
    required int payoutMinor,
    String? tripId,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedPayoutId = payoutLedgerId.trim();
    if (normalizedUserId.isEmpty || normalizedPayoutId.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'handled_externally': false,
        'error': 'autosave_plan_or_payout_missing',
      };
    }
    if (payoutMinor <= 0) {
      return const <String, Object?>{
        'ok': true,
        'handled_externally': false,
        'saved_minor': 0,
        'main_minor': 0,
        'fee_collected_minor': 0,
      };
    }

    final plan = await _findPlan(executor, normalizedUserId);
    if (plan == null) {
      return const <String, Object?>{
        'ok': true,
        'handled_externally': false,
        'saved_minor': 0,
        'main_minor': 0,
        'fee_collected_minor': 0,
      };
    }

    final planId = _asInt(plan['id']);
    final status = _stringOrEmpty(plan['status']).toUpperCase();
    final splitEnabled =
        _asBool(plan['autosave_enabled']) && status == 'ACTIVE';
    final mainRecipientCode = _stringOrEmpty(plan['main_recipient_code']);
    final savingsRecipientCode = _stringOrEmpty(plan['savings_recipient_code']);
    final canTransferMain = status != 'CLOSED' && mainRecipientCode.isNotEmpty;
    if (!canTransferMain || (splitEnabled && savingsRecipientCode.isEmpty)) {
      return const <String, Object?>{
        'ok': true,
        'handled_externally': false,
        'saved_minor': 0,
        'main_minor': 0,
        'fee_collected_minor': 0,
      };
    }
    if (await _isTransferBlocked(executor, normalizedUserId)) {
      return const <String, Object?>{
        'ok': true,
        'handled_externally': false,
        'blocked': true,
        'saved_minor': 0,
        'main_minor': 0,
        'fee_collected_minor': 0,
      };
    }

    final splitReference = 'autosave:$normalizedPayoutId';
    final existingSplit = await _findLedgerByReference(
      executor,
      splitReference,
    );
    if (existingSplit != null) {
      final meta = _decodeJsonMap(existingSplit['meta_json']);
      return <String, Object?>{
        'ok': true,
        'handled_externally': true,
        'replayed': true,
        'saved_minor': _asInt(existingSplit['amount_minor']),
        'main_minor': _asInt(meta['main_minor']),
        'fee_collected_minor': _asInt(meta['fee_collected_minor']),
        'split_active': meta['split_active'] == true,
      };
    }

    var savingsMinor = splitEnabled
        ? ((payoutMinor * _asInt(plan['autosave_percent'])) ~/ 100)
        : 0;
    if (savingsMinor < 0) {
      savingsMinor = 0;
    }
    var mainMinor = payoutMinor - savingsMinor;
    final outstandingExitFeeMinor = await _outstandingExitFeeMinor(
      executor,
      planId,
    );
    final feeCollectedMinor = outstandingExitFeeMinor < mainMinor
        ? outstandingExitFeeMinor
        : mainMinor;
    mainMinor -= feeCollectedMinor;

    if (feeCollectedMinor > 0) {
      final feeReference =
          'autosave_exitfee_collect:$planId:$normalizedPayoutId';
      await _recordInternalTransfer(
        executor,
        userId: normalizedUserId,
        tripId: tripId,
        payoutLedgerId: normalizedPayoutId,
        kind: 'EXIT_FEE',
        amountMinor: feeCollectedMinor,
        recipientCode: 'platform_exit_fee',
        providerReference: feeReference,
        meta: <String, Object?>{'plan_id': planId, 'net_deduction': true},
      );
      await _appendLedgerIfMissing(
        executor,
        userId: normalizedUserId,
        planId: planId,
        payoutLedgerId: normalizedPayoutId,
        entryType: 'EXIT_FEE_COLLECTED',
        amountMinor: feeCollectedMinor,
        reference: feeReference,
        meta: <String, Object?>{
          'outstanding_before_minor': outstandingExitFeeMinor,
        },
      );
    }

    if (mainMinor > 0) {
      await _createProviderTransfer(
        executor,
        userId: normalizedUserId,
        tripId: tripId,
        payoutLedgerId: normalizedPayoutId,
        kind: 'MAIN',
        amountMinor: mainMinor,
        recipientCode: mainRecipientCode,
        providerReference: 'payout_main:$normalizedPayoutId',
        reason: 'Driver main payout',
      );
    }
    if (savingsMinor > 0) {
      await _createProviderTransfer(
        executor,
        userId: normalizedUserId,
        tripId: tripId,
        payoutLedgerId: normalizedPayoutId,
        kind: 'SAVINGS',
        amountMinor: savingsMinor,
        recipientCode: savingsRecipientCode,
        providerReference: 'payout_save:$normalizedPayoutId',
        reason: 'Driver autosave payout',
      );
    }

    await _appendLedgerIfMissing(
      executor,
      userId: normalizedUserId,
      planId: planId,
      payoutLedgerId: normalizedPayoutId,
      entryType: 'AUTOSAVE_SPLIT',
      amountMinor: savingsMinor,
      reference: splitReference,
      meta: <String, Object?>{
        'main_minor': mainMinor,
        'fee_collected_minor': feeCollectedMinor,
        'split_active': splitEnabled,
      },
    );

    await executor.update(
      'autosave_plans',
      <String, Object?>{
        'total_autosaved_minor':
            _asInt(plan['total_autosaved_minor']) + savingsMinor,
        'last_applied_payout_ledger_id': normalizedPayoutId,
        'updated_at': _nowUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object>[planId],
    );

    return <String, Object?>{
      'ok': true,
      'handled_externally': true,
      'saved_minor': savingsMinor,
      'main_minor': mainMinor,
      'fee_collected_minor': feeCollectedMinor,
      'split_active': splitEnabled,
    };
  }

  Future<Map<String, Object?>> runMaturitySweep({DateTime? asOfUtc}) async {
    final asOf = (asOfUtc ?? _nowUtc()).toUtc();
    final planRows = await db.query(
      'autosave_plans',
      where:
          'status = ? AND bonus_eligible = 1 AND bonus_paid_at IS NULL AND maturity_at <= ?',
      whereArgs: <Object>['ACTIVE', asOf.toIso8601String()],
      orderBy: 'maturity_at ASC',
    );
    var maturedCount = 0;
    var bonusPaidCount = 0;

    for (final row in planRows) {
      final result = await _matureSinglePlan(_asInt(row['id']));
      if (result['matured'] == true) {
        maturedCount += 1;
      }
      if (result['bonus_paid'] == true) {
        bonusPaidCount += 1;
      }
    }

    return <String, Object?>{
      'ok': true,
      'matured_count': maturedCount,
      'bonus_paid_count': bonusPaidCount,
    };
  }

  Future<Map<String, Object?>> _matureSinglePlan(int planId) {
    return db.transaction((txn) async {
      final plan = await _findPlanById(txn, planId);
      if (plan == null) {
        return const <String, Object?>{'matured': false, 'bonus_paid': false};
      }
      final status = _stringOrEmpty(plan['status']).toUpperCase();
      if (status != 'ACTIVE' ||
          !_asBool(plan['bonus_eligible']) ||
          _stringOrEmpty(plan['bonus_paid_at']).isNotEmpty) {
        return const <String, Object?>{'matured': false, 'bonus_paid': false};
      }

      final now = _nowUtc();
      final planUserId = _stringOrEmpty(plan['user_id']);
      final savingsRecipientCode = _stringOrEmpty(
        plan['savings_recipient_code'],
      );
      final bonusMinor =
          (_asInt(plan['total_autosaved_minor']) *
                  _asDouble(plan['bonus_rate']))
              .floor();
      var bonusPaid = false;

      if (bonusMinor > 0 && savingsRecipientCode.isNotEmpty) {
        final providerReference = 'autosave_bonus:$planId:${_yyyyMmDd(now)}';
        await _createProviderTransfer(
          txn,
          userId: planUserId,
          tripId: null,
          payoutLedgerId: null,
          kind: 'BONUS',
          amountMinor: bonusMinor,
          recipientCode: savingsRecipientCode,
          providerReference: providerReference,
          reason: 'Driver autosave maturity bonus',
        );
        await _appendLedgerIfMissing(
          txn,
          userId: planUserId,
          planId: planId,
          entryType: 'BONUS',
          amountMinor: bonusMinor,
          reference: 'bonus:$planId:${_yyyyMmDd(now)}',
          meta: <String, Object?>{'provider_reference': providerReference},
        );
        bonusPaid = true;
      }

      await txn.update(
        'autosave_plans',
        <String, Object?>{
          'status': 'MATURED',
          'bonus_paid_at': bonusPaid
              ? now.toIso8601String()
              : plan['bonus_paid_at'],
          'total_bonus_minor':
              _asInt(plan['total_bonus_minor']) + (bonusPaid ? bonusMinor : 0),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object>[planId],
      );

      return <String, Object?>{'matured': true, 'bonus_paid': bonusPaid};
    });
  }

  Future<void> _assertDriverUser(
    DatabaseExecutor executor,
    String normalizedUserId,
  ) async {
    final rows = await executor.query(
      'users',
      columns: <String>['role'],
      where: 'id = ?',
      whereArgs: <Object>[normalizedUserId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('driver_user_not_found');
    }
    final role = _stringOrEmpty(rows.first['role']).toLowerCase();
    if (role.isNotEmpty && role != 'driver') {
      throw StateError('autosave_driver_only');
    }
  }

  Future<Map<String, Object?>?> _findPlan(
    DatabaseExecutor executor,
    String userId,
  ) async {
    final rows = await executor.query(
      'autosave_plans',
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _findPlanById(
    DatabaseExecutor executor,
    int planId,
  ) async {
    final rows = await executor.query(
      'autosave_plans',
      where: 'id = ?',
      whereArgs: <Object>[planId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>> _statusFromPlan(
    DatabaseExecutor executor,
    Map<String, Object?> plan,
  ) async {
    final planId = _asInt(plan['id']);
    final configMeta = await _latestConfigMeta(executor, planId);
    return <String, Object?>{
      'ok': true,
      'configured': true,
      'status': _stringOrEmpty(plan['status']),
      'tier': _asInt(plan['tier']),
      'autosave_percent': _asInt(plan['autosave_percent']),
      'started_at': _stringOrNull(plan['started_at']),
      'maturity_at': _stringOrNull(plan['maturity_at']),
      'bonus_rate': _asDouble(plan['bonus_rate']),
      'bonus_eligible': _asBool(plan['bonus_eligible']),
      'totals': <String, Object?>{
        'total_autosaved_minor': _asInt(plan['total_autosaved_minor']),
        'total_bonus_minor': _asInt(plan['total_bonus_minor']),
        'total_exit_fees_minor': _asInt(plan['total_exit_fees_minor']),
      },
      'masked_destinations': configMeta,
    };
  }

  Future<Map<String, Object?>> _latestConfigMeta(
    DatabaseExecutor executor,
    int planId,
  ) async {
    final rows = await executor.query(
      'autosave_ledger',
      columns: <String>['meta_json'],
      where: 'plan_id = ? AND entry_type IN (?, ?, ?)',
      whereArgs: <Object>[planId, 'PLAN_OPEN', 'PLAN_CHANGE', 'PLAN_RESUME'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return const <String, Object?>{};
    }
    final meta = _decodeJsonMap(rows.first['meta_json']);
    return <String, Object?>{
      'main': meta['main_destination'] is Map
          ? Map<String, Object?>.from(meta['main_destination'] as Map)
          : const <String, Object?>{},
      'savings': meta['savings_destination'] is Map
          ? Map<String, Object?>.from(meta['savings_destination'] as Map)
          : const <String, Object?>{},
    };
  }

  Future<void> _appendLedgerIfMissing(
    DatabaseExecutor executor, {
    required String userId,
    required int planId,
    String? payoutLedgerId,
    required String entryType,
    required int amountMinor,
    required String reference,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    if (await _ledgerReferenceExists(executor, reference)) {
      return;
    }
    await executor.insert('autosave_ledger', <String, Object?>{
      'user_id': userId,
      'plan_id': planId,
      'payout_ledger_id': payoutLedgerId,
      'entry_type': entryType,
      'amount_minor': amountMinor,
      'reference': reference,
      'meta_json': jsonEncode(meta),
      'created_at': _nowUtc().toIso8601String(),
    });
  }

  Future<bool> _ledgerReferenceExists(
    DatabaseExecutor executor,
    String reference,
  ) async {
    final row = await _findLedgerByReference(executor, reference);
    return row != null;
  }

  Future<Map<String, Object?>?> _findLedgerByReference(
    DatabaseExecutor executor,
    String reference,
  ) async {
    final rows = await executor.query(
      'autosave_ledger',
      where: 'reference = ?',
      whereArgs: <Object>[reference],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<void> _createProviderTransfer(
    DatabaseExecutor executor, {
    required String userId,
    required String? tripId,
    required String? payoutLedgerId,
    required String kind,
    required int amountMinor,
    required String recipientCode,
    required String providerReference,
    required String reason,
  }) async {
    if (amountMinor <= 0) {
      return;
    }
    final existing = await executor.query(
      'payout_transfers',
      where: 'provider_reference = ?',
      whereArgs: <Object>[providerReference],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }
    final result = await _transferProvider.initiateTransfer(
      recipientCode: recipientCode,
      amountMinor: amountMinor,
      reference: providerReference,
      reason: reason,
    );
    await executor.insert('payout_transfers', <String, Object?>{
      'user_id': userId,
      'trip_id': tripId,
      'payout_ledger_id': payoutLedgerId,
      'kind': kind,
      'amount_minor': amountMinor,
      'recipient_code': recipientCode,
      'provider_transfer_code': result.transferCode,
      'provider_reference': providerReference,
      'status': _normalizeTransferStatus(result.status),
      'meta_json': jsonEncode(result.raw),
      'created_at': _nowUtc().toIso8601String(),
      'updated_at': _nowUtc().toIso8601String(),
    });
  }

  Future<void> _recordInternalTransfer(
    DatabaseExecutor executor, {
    required String userId,
    required String? tripId,
    required String? payoutLedgerId,
    required String kind,
    required int amountMinor,
    required String recipientCode,
    required String providerReference,
    required Map<String, Object?> meta,
  }) async {
    if (amountMinor <= 0) {
      return;
    }
    final existing = await executor.query(
      'payout_transfers',
      where: 'provider_reference = ?',
      whereArgs: <Object>[providerReference],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }
    await executor.insert('payout_transfers', <String, Object?>{
      'user_id': userId,
      'trip_id': tripId,
      'payout_ledger_id': payoutLedgerId,
      'kind': kind,
      'amount_minor': amountMinor,
      'recipient_code': recipientCode,
      'provider_transfer_code': null,
      'provider_reference': providerReference,
      'status': 'SUCCESS',
      'meta_json': jsonEncode(meta),
      'created_at': _nowUtc().toIso8601String(),
      'updated_at': _nowUtc().toIso8601String(),
    });
  }

  Future<int> _outstandingExitFeeMinor(
    DatabaseExecutor executor,
    int planId,
  ) async {
    final assessedRows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS amount
      FROM autosave_ledger
      WHERE plan_id = ? AND entry_type = ?
      ''',
      <Object>[planId, 'EXIT_FEE'],
    );
    final collectedRows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS amount
      FROM autosave_ledger
      WHERE plan_id = ? AND entry_type = ?
      ''',
      <Object>[planId, 'EXIT_FEE_COLLECTED'],
    );
    final assessed = assessedRows.isEmpty
        ? 0
        : _asInt(assessedRows.first['amount']);
    final collected = collectedRows.isEmpty
        ? 0
        : _asInt(collectedRows.first['amount']);
    final outstanding = assessed - collected;
    return outstanding < 0 ? 0 : outstanding;
  }

  Future<bool> _isTransferBlocked(
    DatabaseExecutor executor,
    String userId,
  ) async {
    final userRows = await executor.query(
      'users',
      columns: <String>['is_blocked', 'disabled_at'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (userRows.isNotEmpty) {
      final row = userRows.first;
      if (_asBool(row['is_blocked']) ||
          _stringOrEmpty(row['disabled_at']).isNotEmpty) {
        return true;
      }
    }

    final walletRows = await executor.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN wallet_type = 'driver_a' THEN balance_minor ELSE 0 END), 0) AS wallet_a_minor,
        COALESCE(SUM(CASE WHEN wallet_type = 'driver_c' THEN balance_minor ELSE 0 END), 0) AS wallet_c_minor
      FROM wallets
      WHERE owner_id = ?
      ''',
      <Object>[userId],
    );
    if (walletRows.isEmpty) {
      return false;
    }
    return _asInt(walletRows.first['wallet_c_minor']) >
        _asInt(walletRows.first['wallet_a_minor']);
  }

  Map<String, Object?> _ledgerRowToMap(Map<String, Object?> row) {
    return <String, Object?>{
      'id': _asInt(row['id']),
      'user_id': _stringOrEmpty(row['user_id']),
      'plan_id': _asInt(row['plan_id']),
      'payout_ledger_id': _stringOrNull(row['payout_ledger_id']),
      'entry_type': _stringOrEmpty(row['entry_type']),
      'amount_minor': _asInt(row['amount_minor']),
      'reference': _stringOrEmpty(row['reference']),
      'meta': _decodeJsonMap(row['meta_json']),
      'created_at': _stringOrNull(row['created_at']),
    };
  }

  int _normalizeTier(int tier) {
    if (tier < 1) {
      return 1;
    }
    if (tier > 4) {
      return 4;
    }
    return tier;
  }

  int _normalizePercent(int percent) {
    if (percent < 1) {
      return 1;
    }
    if (percent > 30) {
      return 30;
    }
    return percent;
  }

  int _lockDaysForTier(int tier) {
    switch (tier) {
      case 2:
        return 120;
      case 3:
        return 210;
      case 4:
        return 330;
      case 1:
      default:
        return 30;
    }
  }

  double _bonusRateForTier(int tier) {
    switch (tier) {
      case 2:
        return 0.03;
      case 3:
        return 0.08;
      case 4:
        return 0.15;
      case 1:
      default:
        return 0;
    }
  }

  int _computeExitFeeMinor({required int totalAutosavedMinor}) {
    final raw = (totalAutosavedMinor * _exitFeeRate).round();
    if (raw <= 0) {
      return 0;
    }
    if (raw > _exitFeeCapMinor) {
      return _exitFeeCapMinor;
    }
    return raw;
  }

  String _normalizeTransferStatus(String rawStatus) {
    final normalized = rawStatus.trim().toUpperCase();
    switch (normalized) {
      case 'SUCCESS':
      case 'FAILED':
      case 'REVERSED':
      case 'PENDING':
        return normalized;
      default:
        return 'PENDING';
    }
  }

  int _normalizedLimit(int value) {
    if (value <= 0) {
      return 50;
    }
    if (value > 200) {
      return 200;
    }
    return value;
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value.toInt() == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  String _stringOrEmpty(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  String? _stringOrNull(Object? value) {
    final normalized = _stringOrEmpty(value);
    return normalized.isEmpty ? null : normalized;
  }

  DateTime? _asDateTime(Object? value) {
    final normalized = _stringOrEmpty(value);
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  Map<String, Object?> _decodeJsonMap(Object? value) {
    final raw = _stringOrEmpty(value);
    if (raw.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, nestedValue) =>
              MapEntry<String, Object?>(key.toString(), nestedValue),
        );
      }
    } catch (_) {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }

  String _yyyyMmDd(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}$month$day';
  }
}
