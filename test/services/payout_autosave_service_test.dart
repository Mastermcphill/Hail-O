import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/data/sqlite/hailo_database.dart';
import 'package:hailo_core/services/payout_autosave_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PayoutAutosaveService', () {
    test('configure plan stores recipient codes', () async {
      final now = DateTime.utc(2026, 3, 2, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      await _seedDriver(db, 'driver_cfg', now);

      final service = PayoutAutosaveService(
        db,
        transferProvider: _FakeTransferProvider(),
        nowUtc: () => now,
      );

      final payload = await service.configurePlan(
        userId: 'driver_cfg',
        autosaveEnabled: true,
        tier: 2,
        autosavePercent: 15,
        mainBank: const AutosaveBankDestination(
          accountNumber: '0001112223',
          bankCode: '058',
          name: 'Main Dest',
        ),
        savingsBank: const AutosaveBankDestination(
          accountNumber: '4445556667',
          bankCode: '033',
          name: 'Savings Dest',
        ),
        idempotencyKey: 'cfg_1',
      );

      expect(payload['configured'], true);
      expect(payload['status'], 'ACTIVE');

      final rows = await db.query(
        'autosave_plans',
        where: 'user_id = ?',
        whereArgs: const <Object>['driver_cfg'],
        limit: 1,
      );
      expect(rows, hasLength(1));
      expect(rows.first['main_recipient_code'], 'rcpt_main_2223');
      expect(rows.first['savings_recipient_code'], 'rcpt_save_6667');
    });

    test(
      'disable early creates exit fee and next payout collects it',
      () async {
        final now = DateTime.utc(2026, 3, 2, 12);
        final later = now.add(const Duration(days: 1));
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);
        await _seedDriver(db, 'driver_exit', now);

        final provider = _FakeTransferProvider();
        final service = PayoutAutosaveService(
          db,
          transferProvider: provider,
          nowUtc: () => now,
        );

        await service.configurePlan(
          userId: 'driver_exit',
          autosaveEnabled: true,
          tier: 1,
          autosavePercent: 10,
          mainBank: const AutosaveBankDestination(
            accountNumber: '0001112223',
            bankCode: '058',
            name: 'Main Dest',
          ),
          savingsBank: const AutosaveBankDestination(
            accountNumber: '4445556667',
            bankCode: '033',
            name: 'Savings Dest',
          ),
        );
        await service.applyOnPayout(
          userId: 'driver_exit',
          payoutLedgerId: 'payout:first',
          payoutMinor: 10000,
          tripId: 'ride_first',
        );

        final disableService = PayoutAutosaveService(
          db,
          transferProvider: provider,
          nowUtc: () => later,
        );
        await disableService.disablePlan(
          userId: 'driver_exit',
          reason: 'need flexibility',
        );

        final afterDisable = await disableService.applyOnPayout(
          userId: 'driver_exit',
          payoutLedgerId: 'payout:second',
          payoutMinor: 1000,
          tripId: 'ride_second',
        );

        expect(afterDisable['handled_externally'], true);
        expect(afterDisable['saved_minor'], 0);
        expect(afterDisable['main_minor'], 990);
        expect(afterDisable['fee_collected_minor'], 10);

        final feeRows = await db.query(
          'autosave_ledger',
          where: 'entry_type = ?',
          whereArgs: const <Object>['EXIT_FEE_COLLECTED'],
        );
        expect(feeRows, hasLength(1));
        expect(feeRows.first['amount_minor'], 10);
      },
    );

    test('maturity bonus runs once', () async {
      final now = DateTime.utc(2026, 3, 2, 12);
      final matureAt = now.add(const Duration(days: 130));
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      await _seedDriver(db, 'driver_bonus', now);

      final provider = _FakeTransferProvider();
      final service = PayoutAutosaveService(
        db,
        transferProvider: provider,
        nowUtc: () => now,
      );

      await service.configurePlan(
        userId: 'driver_bonus',
        autosaveEnabled: true,
        tier: 2,
        autosavePercent: 10,
        mainBank: const AutosaveBankDestination(
          accountNumber: '0001112223',
          bankCode: '058',
          name: 'Main Dest',
        ),
        savingsBank: const AutosaveBankDestination(
          accountNumber: '4445556667',
          bankCode: '033',
          name: 'Savings Dest',
        ),
      );
      await db.update(
        'autosave_plans',
        <String, Object?>{
          'total_autosaved_minor': 20000,
          'maturity_at': now
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        },
        where: 'user_id = ?',
        whereArgs: const <Object>['driver_bonus'],
      );

      final matureService = PayoutAutosaveService(
        db,
        transferProvider: provider,
        nowUtc: () => matureAt,
      );
      final first = await matureService.runMaturitySweep(asOfUtc: matureAt);
      final second = await matureService.runMaturitySweep(asOfUtc: matureAt);

      expect(first['matured_count'], 1);
      expect(first['bonus_paid_count'], 1);
      expect(second['matured_count'], 0);
      expect(second['bonus_paid_count'], 0);

      final transferRows = await db.query(
        'payout_transfers',
        where: 'kind = ?',
        whereArgs: const <Object>['BONUS'],
      );
      expect(transferRows, hasLength(1));
      expect(transferRows.first['amount_minor'], 600);
    });

    test('blocked driver creates no transfer rows', () async {
      final now = DateTime.utc(2026, 3, 2, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      await _seedDriver(db, 'driver_blocked', now, isBlocked: true);

      final service = PayoutAutosaveService(
        db,
        transferProvider: _FakeTransferProvider(),
        nowUtc: () => now,
      );

      await service.configurePlan(
        userId: 'driver_blocked',
        autosaveEnabled: true,
        tier: 1,
        autosavePercent: 10,
        mainBank: const AutosaveBankDestination(
          accountNumber: '0001112223',
          bankCode: '058',
          name: 'Main Dest',
        ),
        savingsBank: const AutosaveBankDestination(
          accountNumber: '4445556667',
          bankCode: '033',
          name: 'Savings Dest',
        ),
      );

      final result = await service.applyOnPayout(
        userId: 'driver_blocked',
        payoutLedgerId: 'payout:blocked',
        payoutMinor: 10000,
      );

      expect(result['handled_externally'], false);
      expect(result['blocked'], true);

      final transferRows = await db.query('payout_transfers');
      final splitRows = await db.query(
        'autosave_ledger',
        where: 'entry_type = ?',
        whereArgs: const <Object>['AUTOSAVE_SPLIT'],
      );
      expect(transferRows, isEmpty);
      expect(splitRows, isEmpty);
    });
  });
}

Future<void> _seedDriver(
  Database db,
  String userId,
  DateTime now, {
  bool isBlocked = false,
}) {
  return db.insert('users', <String, Object?>{
    'id': userId,
    'role': 'driver',
    'is_blocked': isBlocked ? 1 : 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

class _FakeTransferProvider extends SettlementTransferProvider {
  final Map<String, String> _recipientCodesByAccount = <String, String>{};

  @override
  Future<SettlementTransferRecipientResult> createTransferRecipient({
    required String accountNumber,
    required String bankCode,
    required String name,
  }) async {
    final suffix = accountNumber.substring(accountNumber.length - 4);
    final code = bankCode == '058' ? 'rcpt_main_$suffix' : 'rcpt_save_$suffix';
    _recipientCodesByAccount[accountNumber] = code;
    return SettlementTransferRecipientResult(
      recipientCode: code,
      raw: <String, Object?>{'name': name, 'bank_code': bankCode},
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
        'recipient_code': recipientCode,
        'amount_minor': amountMinor,
        'reason': reason,
      },
    );
  }
}
