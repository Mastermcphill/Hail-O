import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallets_dao.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/models/wallet_ledger_entry.dart';

import 'api_test_harness.dart';

void main() {
  test('admin reversal endpoint is replay safe', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    final admin = await harness.registerAndLogin(
      role: 'admin',
      email: 'admin.reversal@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-admin-reversal',
    );
    final driver = await harness.registerAndLogin(
      role: 'driver',
      email: 'driver.reversal@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-driver-reversal',
    );

    final now = DateTime.now().toUtc();
    await WalletsDao(harness.db).upsert(
      Wallet(
        ownerId: driver.userId,
        walletType: WalletType.driverA,
        balanceMinor: 20000,
        reservedMinor: 0,
        currency: 'NGN',
        updatedAt: now,
        createdAt: now,
      ),
      viaOrchestrator: true,
    );

    final originalLedgerId = await WalletLedgerDao(harness.db).append(
      WalletLedgerEntry(
        ownerId: driver.userId,
        walletType: WalletType.driverA,
        direction: LedgerDirection.credit,
        amountMinor: 20000,
        balanceAfterMinor: 20000,
        kind: 'test_credit',
        referenceId: 'test_ref',
        idempotencyScope: 'test.seed',
        idempotencyKey: 'test.seed.ledger.1',
        createdAt: now,
      ),
      viaOrchestrator: true,
    );

    const key = 'admin-reversal-1';
    final first = await harness.postJson(
      '/admin/reversal',
      bearerToken: admin.token,
      idempotencyKey: key,
      body: <String, Object?>{
        'original_ledger_id': originalLedgerId,
        'reason': 'test_reversal',
      },
    );
    expect(first.statusCode, 200);
    final firstBody = first.requireJsonMap();
    expect(firstBody['ok'], true);

    final replay = await harness.postJson(
      '/admin/reversal',
      bearerToken: admin.token,
      idempotencyKey: key,
      body: <String, Object?>{
        'original_ledger_id': originalLedgerId,
        'reason': 'test_reversal',
      },
    );
    expect(replay.statusCode, 200);
    final replayBody = replay.requireJsonMap();
    expect(replayBody['replayed'], true);
  });
}
