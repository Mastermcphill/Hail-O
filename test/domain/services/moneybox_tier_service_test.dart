import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/moneybox_liquidation_service.dart';
import 'package:hail_o_finance_core/domain/services/moneybox_tier_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'penalty calculation follows first/second/final/after-open segments',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = MoneyBoxTierService(
        db,
        nowUtc: () => DateTime.utc(2026, 1, 1),
      );

      final lockStart = DateTime.utc(2026, 1, 1, 0, 0);
      final autoOpen = DateTime.utc(2026, 1, 31, 0, 0);
      const principal = 10000;

      final firstThird = service.calculateEarlyWithdrawalPenalty(
        principalMinor: principal,
        lockStartUtc: lockStart,
        autoOpenDateUtc: autoOpen,
        openedAtUtc: lockStart.add(const Duration(days: 5)),
      );
      expect(firstThird.penaltyPercent, 7);
      expect(firstThird.penaltyMinor, 700);

      final secondThird = service.calculateEarlyWithdrawalPenalty(
        principalMinor: principal,
        lockStartUtc: lockStart,
        autoOpenDateUtc: autoOpen,
        openedAtUtc: lockStart.add(const Duration(days: 15)),
      );
      expect(secondThird.penaltyPercent, 5);
      expect(secondThird.penaltyMinor, 500);

      final finalSegment = service.calculateEarlyWithdrawalPenalty(
        principalMinor: principal,
        lockStartUtc: lockStart,
        autoOpenDateUtc: autoOpen,
        openedAtUtc: lockStart.add(const Duration(days: 25)),
      );
      expect(finalSegment.penaltyPercent, 2);
      expect(finalSegment.penaltyMinor, 200);

      final afterOpen = service.calculateEarlyWithdrawalPenalty(
        principalMinor: principal,
        lockStartUtc: lockStart,
        autoOpenDateUtc: autoOpen,
        openedAtUtc: autoOpen.add(const Duration(seconds: 1)),
      );
      expect(afterOpen.penaltyPercent, 0);
      expect(afterOpen.penaltyMinor, 0);
    },
  );

  test('open early before open day voids bonus for cycle', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 1);

    await db.insert('moneybox_accounts', <String, Object?>{
      'owner_id': 'owner_bonus_void',
      'tier': 2,
      'status': 'locked',
      'lock_start': DateTime.utc(2026, 1, 1).toIso8601String(),
      'auto_open_date': DateTime.utc(2026, 4, 28).toIso8601String(),
      'maturity_date': DateTime.utc(2026, 5, 1).toIso8601String(),
      'principal_minor': 10000,
      'projected_bonus_minor': 300,
      'expected_at_maturity_minor': 10300,
      'autosave_percent': 10,
      'bonus_eligible': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final service = MoneyBoxTierService(db, nowUtc: () => now);
    final result = await service.openEarly(
      ownerId: 'owner_bonus_void',
      openedAtUtc: DateTime.utc(2026, 3, 1),
      idempotencyKey: 'open_early_bonus_void_1',
    );
    expect(result['bonus_voided'], true);

    final row = (await db.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: const <Object>['owner_bonus_void'],
      limit: 1,
    )).first;
    expect(row['bonus_eligible'], 0);
    expect(row['projected_bonus_minor'], 0);
  });

  test('suspension liquidation is idempotent and ledger-backed', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 15);

    await db.insert('moneybox_accounts', <String, Object?>{
      'owner_id': 'owner_liq_idem',
      'tier': 3,
      'status': 'locked',
      'lock_start': now.toIso8601String(),
      'auto_open_date': now.add(const Duration(days: 200)).toIso8601String(),
      'maturity_date': now.add(const Duration(days: 210)).toIso8601String(),
      'principal_minor': 20000,
      'projected_bonus_minor': 1600,
      'expected_at_maturity_minor': 21600,
      'autosave_percent': 20,
      'bonus_eligible': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final service = MoneyBoxLiquidationService(db, nowUtc: () => now);
    final first = await service.liquidateOnSuspensionOrBan(
      ownerId: 'owner_liq_idem',
      reason: 'suspended',
      idempotencyKey: 'liq_idem_1',
    );
    expect(first['liquidated_minor'], 20000);

    final second = await service.liquidateOnSuspensionOrBan(
      ownerId: 'owner_liq_idem',
      reason: 'suspended',
      idempotencyKey: 'liq_idem_1',
    );
    expect(second['replayed'], true);

    final walletLedgerRows = await db.query(
      'wallet_ledger',
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: const <Object>[
        'moneybox.liquidate.suspension',
        'liq_idem_1:wallet',
      ],
    );
    final moneyboxLedgerRows = await db.query(
      'moneybox_ledger',
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: const <Object>[
        'moneybox.liquidate.suspension',
        'liq_idem_1:moneybox',
      ],
    );

    expect(walletLedgerRows.length, 1);
    expect(moneyboxLedgerRows.length, 1);
  });
}
