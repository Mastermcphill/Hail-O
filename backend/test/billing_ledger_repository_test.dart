import 'dart:convert';

import 'package:test/test.dart';

import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/payments/manual_payment_provider.dart';
import '../modules/payments/payment_service.dart';

void main() {
  group('Billing ledger repository', () {
    test(
      'in-memory append is deduped by provider+provider_ref+entry_type',
      () async {
        final repository = InMemoryBillingLedgerRepository();
        final inserted = await repository.appendEntry(
          purchaseId: '29efe8e2-ce58-4ea7-a8d0-e8e0f8a1280d',
          userId: 'user-a',
          entryType: 'charge_captured',
          provider: 'manual',
          providerRef: 'ref-1',
          amountMinor: 1000,
          currency: 'NGN',
          metadata: const <String, Object?>{'origin': 'test'},
        );
        final replayInserted = await repository.appendEntry(
          purchaseId: '29efe8e2-ce58-4ea7-a8d0-e8e0f8a1280d',
          userId: 'user-a',
          entryType: 'charge_captured',
          provider: 'manual',
          providerRef: 'ref-1',
          amountMinor: 1000,
          currency: 'NGN',
          metadata: const <String, Object?>{'origin': 'test'},
        );

        expect(inserted, isTrue);
        expect(replayInserted, isFalse);

        final entries = await repository.listByPurchase(
          purchaseId: '29efe8e2-ce58-4ea7-a8d0-e8e0f8a1280d',
        );
        expect(entries.length, 1);
        expect(entries.first.entryType, 'charge_captured');
      },
    );
  });

  group('PaymentService ledger mapping', () {
    test(
      'create checkout writes authorized + captured entries in manual mode',
      () async {
        final ledger = InMemoryBillingLedgerRepository();
        final service = PaymentService(
          provider: ManualPaymentProvider(),
          billingLedgerRepository: ledger,
        );
        final purchase = MarketplacePurchaseRecord(
          id: '688ac6bc-3e08-42f2-99f2-e11e8704cb9e',
          userId: 'user-ledger-1',
          offerId: 'offer_sedan_01',
          offerTitle: 'Budget Sedan',
          status: 'PENDING',
          currency: 'NGN',
          totalAmountMinor: 12600,
          seatCount: 3,
          idempotencyKey: 'idem-ledger-1',
          createdAt: DateTime.utc(2026, 2, 23),
          updatedAt: DateTime.utc(2026, 2, 23),
        );

        await service.createCheckoutOrIntent(purchase: purchase);
        final entries = await ledger.listByPurchase(purchaseId: purchase.id);
        expect(
          entries.map((entry) => entry.entryType),
          contains('charge_authorized'),
        );
        expect(
          entries.map((entry) => entry.entryType),
          contains('charge_captured'),
        );
      },
    );

    test('webhook replay does not duplicate captured ledger entry', () async {
      final ledger = InMemoryBillingLedgerRepository();
      final service = PaymentService(
        provider: ManualPaymentProvider(),
        billingLedgerRepository: ledger,
      );
      const purchaseId = '3f5720c3-fc3b-450d-9760-404f476fddf2';
      final body = jsonEncode(<String, Object?>{
        'provider_event_id': 'evt-ledger-1',
        'event_type': 'payment_succeeded',
        'purchase_id': purchaseId,
        'amount_minor': 4200,
        'currency': 'NGN',
      });

      final first = await service.handleWebhook(
        headers: const <String, String>{},
        rawBody: body,
      );
      final second = await service.handleWebhook(
        headers: const <String, String>{},
        rawBody: body,
      );

      expect(first.duplicate, isFalse);
      expect(second.duplicate, isTrue);
      final entries = await ledger.listByPurchase(purchaseId: purchaseId);
      final captured = entries
          .where((entry) => entry.entryType == 'charge_captured')
          .toList();
      expect(captured.length, 1);
    });
  });
}
