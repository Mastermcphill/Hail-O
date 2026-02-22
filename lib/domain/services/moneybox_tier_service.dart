import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';

class MoneyBoxTierConfig {
  const MoneyBoxTierConfig({
    required this.tier,
    required this.lockDurationDays,
    required this.openLeadDays,
    required this.bonusPercent,
  });

  final int tier;
  final int lockDurationDays;
  final int openLeadDays;
  final int bonusPercent;
}

class MoneyBoxPenaltyResult {
  const MoneyBoxPenaltyResult({
    required this.penaltyPercent,
    required this.penaltyMinor,
  });

  final int penaltyPercent;
  final int penaltyMinor;
}

class MoneyBoxTierService {
  MoneyBoxTierService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeSelectTier = 'moneybox.select_tier';
  static const String _scopeOpenEarly = 'moneybox.open_early';
  static const String _scopeRestart = 'moneybox.restart_cycle';

  static const Map<int, MoneyBoxTierConfig> _tiers = <int, MoneyBoxTierConfig>{
    1: MoneyBoxTierConfig(
      tier: 1,
      lockDurationDays: 30,
      openLeadDays: 1,
      bonusPercent: 0,
    ),
    2: MoneyBoxTierConfig(
      tier: 2,
      lockDurationDays: 120,
      openLeadDays: 3,
      bonusPercent: 3,
    ),
    3: MoneyBoxTierConfig(
      tier: 3,
      lockDurationDays: 210,
      openLeadDays: 8,
      bonusPercent: 8,
    ),
    4: MoneyBoxTierConfig(
      tier: 4,
      lockDurationDays: 330,
      openLeadDays: 15,
      bonusPercent: 15,
    ),
  };

  MoneyBoxTierConfig configForTier(int tier) {
    return _tiers[tier] ?? _tiers[1]!;
  }

  Future<Map<String, Object?>> selectTier({
    required String ownerId,
    required int tier,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final claim = await _idempotencyStore.claim(
      scope: _scopeSelectTier,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final now = _nowUtc();
    final config = configForTier(tier);

    final result = await db.transaction((txn) async {
      final account = await _ensureAccount(txn, ownerId, now);
      final principal = (account['principal_minor'] as int?) ?? 0;
      final lockStart = now;
      final maturityDate = lockStart.add(
        Duration(days: config.lockDurationDays),
      );
      final autoOpenDate = maturityDate.subtract(
        Duration(days: config.openLeadDays),
      );
      final projectedBonus = _projectBonus(principal, config.bonusPercent);

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'tier': config.tier,
          'status': 'locked',
          'lock_start': _iso(lockStart),
          'auto_open_date': _iso(autoOpenDate),
          'maturity_date': _iso(maturityDate),
          'projected_bonus_minor': projectedBonus,
          'expected_at_maturity_minor': principal + projectedBonus,
          'bonus_eligible': 1,
          'updated_at': _iso(now),
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      return <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'tier': config.tier,
        'bonus_percent': config.bonusPercent,
        'lock_start': _iso(lockStart),
        'auto_open_date': _iso(autoOpenDate),
        'maturity_date': _iso(maturityDate),
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeSelectTier,
      key: idempotencyKey,
      resultHash: _hashResult(result),
    );
    return result;
  }

  Future<Map<String, Object?>> openEarly({
    required String ownerId,
    required DateTime openedAtUtc,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final claim = await _idempotencyStore.claim(
      scope: _scopeOpenEarly,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final result = await db.transaction((txn) async {
      final account = await _ensureAccount(txn, ownerId, openedAtUtc);
      final principal = (account['principal_minor'] as int?) ?? 0;
      final lockStart = DateTime.parse(account['lock_start'] as String).toUtc();
      final autoOpenDate = DateTime.parse(
        account['auto_open_date'] as String,
      ).toUtc();
      final penalty = calculateEarlyWithdrawalPenalty(
        principalMinor: principal,
        lockStartUtc: lockStart,
        autoOpenDateUtc: autoOpenDate,
        openedAtUtc: openedAtUtc,
      );
      final openedBeforeAutoOpen = openedAtUtc.isBefore(autoOpenDate);
      final bonusEligible = openedBeforeAutoOpen ? 0 : 1;
      final projectedBonus = openedBeforeAutoOpen
          ? 0
          : ((account['projected_bonus_minor'] as int?) ?? 0);

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'status': 'opened',
          'bonus_eligible': bonusEligible,
          'projected_bonus_minor': projectedBonus,
          'expected_at_maturity_minor': principal + projectedBonus,
          'updated_at': _iso(openedAtUtc),
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      return <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'opened_early': openedBeforeAutoOpen,
        'penalty_percent': penalty.penaltyPercent,
        'penalty_minor': penalty.penaltyMinor,
        'bonus_voided': openedBeforeAutoOpen,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeOpenEarly,
      key: idempotencyKey,
      resultHash: _hashResult(result),
    );
    return result;
  }

  Future<Map<String, Object?>> restartCycle({
    required String ownerId,
    int? tier,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final claim = await _idempotencyStore.claim(
      scope: _scopeRestart,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final now = _nowUtc();
    final result = await db.transaction((txn) async {
      final account = await _ensureAccount(txn, ownerId, now);
      final selectedTier = tier ?? ((account['tier'] as int?) ?? 1);
      final config = configForTier(selectedTier);
      final principal = (account['principal_minor'] as int?) ?? 0;
      final projectedBonus = _projectBonus(principal, config.bonusPercent);
      final maturityDate = now.add(Duration(days: config.lockDurationDays));
      final autoOpenDate = maturityDate.subtract(
        Duration(days: config.openLeadDays),
      );

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'tier': config.tier,
          'status': 'locked',
          'lock_start': _iso(now),
          'auto_open_date': _iso(autoOpenDate),
          'maturity_date': _iso(maturityDate),
          'projected_bonus_minor': projectedBonus,
          'expected_at_maturity_minor': principal + projectedBonus,
          'bonus_eligible': 1,
          'updated_at': _iso(now),
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      return <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'tier': config.tier,
        'bonus_eligible': true,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeRestart,
      key: idempotencyKey,
      resultHash: _hashResult(result),
    );
    return result;
  }

  MoneyBoxPenaltyResult calculateEarlyWithdrawalPenalty({
    required int principalMinor,
    required DateTime lockStartUtc,
    required DateTime autoOpenDateUtc,
    required DateTime openedAtUtc,
  }) {
    if (principalMinor <= 0 || !openedAtUtc.isBefore(autoOpenDateUtc)) {
      return const MoneyBoxPenaltyResult(penaltyPercent: 0, penaltyMinor: 0);
    }

    final totalSeconds = autoOpenDateUtc.difference(lockStartUtc).inSeconds;
    if (totalSeconds <= 0) {
      return const MoneyBoxPenaltyResult(penaltyPercent: 0, penaltyMinor: 0);
    }

    final elapsedSeconds = openedAtUtc
        .difference(lockStartUtc)
        .inSeconds
        .clamp(0, totalSeconds);
    final firstCut = totalSeconds / 3;
    final secondCut = firstCut * 2;

    final penaltyPercent = elapsedSeconds < firstCut
        ? 7
        : elapsedSeconds < secondCut
        ? 5
        : 2;
    final penaltyMinor = (principalMinor * penaltyPercent) ~/ 100;
    return MoneyBoxPenaltyResult(
      penaltyPercent: penaltyPercent,
      penaltyMinor: penaltyMinor,
    );
  }

  Future<Map<String, Object?>> _ensureAccount(
    Transaction txn,
    String ownerId,
    DateTime now,
  ) async {
    final rows = await txn.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Map<String, Object?>.from(rows.first);
    }

    final config = configForTier(1);
    final maturityDate = now.add(Duration(days: config.lockDurationDays));
    final autoOpenDate = maturityDate.subtract(
      Duration(days: config.openLeadDays),
    );
    await txn.insert('moneybox_accounts', <String, Object?>{
      'owner_id': ownerId,
      'tier': 1,
      'status': 'locked',
      'lock_start': _iso(now),
      'auto_open_date': _iso(autoOpenDate),
      'maturity_date': _iso(maturityDate),
      'principal_minor': 0,
      'projected_bonus_minor': 0,
      'expected_at_maturity_minor': 0,
      'autosave_percent': 0,
      'bonus_eligible': 1,
      'created_at': _iso(now),
      'updated_at': _iso(now),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final inserted = await txn.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    return Map<String, Object?>.from(inserted.first);
  }

  int _projectBonus(int principalMinor, int bonusPercent) {
    if (principalMinor <= 0 || bonusPercent <= 0) {
      return 0;
    }
    return (principalMinor * bonusPercent) ~/ 100;
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hashResult(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotency key is required');
    }
  }
}
