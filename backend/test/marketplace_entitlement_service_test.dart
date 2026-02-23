import 'package:test/test.dart';

import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';

void main() {
  group('MarketplaceEntitlementService', () {
    test(
      'capture/active purchase grants plan and seats entitlements',
      () async {
        final repository = InMemoryMarketplaceEntitlementRepository();
        final service = MarketplaceEntitlementService(repository: repository);
        final purchase = _purchase(
          status: 'ACTIVE',
          seatCount: 3,
          offerId: 'offer_sedan_01',
        );

        await service.syncPurchaseEntitlements(
          purchase: purchase,
          reason: 'payment_capture',
        );

        final active = await repository.listActiveByPurchase(
          purchaseId: purchase.id,
        );
        expect(active.length, 2);
        final seats = active.firstWhere(
          (row) => row.entitlementType == 'seats',
        );
        final plan = active.firstWhere((row) => row.entitlementType == 'plan');
        expect(seats.value['seats_total'], 3);
        expect(plan.value['plan'], 'offer_sedan_01');
      },
    );

    test('refund/canceled purchase revokes active entitlements', () async {
      final repository = InMemoryMarketplaceEntitlementRepository();
      final service = MarketplaceEntitlementService(repository: repository);
      final purchase = _purchase(
        status: 'ACTIVE',
        seatCount: 2,
        offerId: 'offer_suv_02',
      );
      await service.syncPurchaseEntitlements(
        purchase: purchase,
        reason: 'payment_capture',
      );

      await service.syncPurchaseEntitlements(
        purchase: _purchase(
          status: 'CANCELED',
          seatCount: 2,
          offerId: 'offer_suv_02',
          purchaseId: purchase.id,
          userId: purchase.userId,
        ),
        reason: 'refund',
      );

      final active = await repository.listActiveByPurchase(
        purchaseId: purchase.id,
      );
      expect(active, isEmpty);

      final all = await repository.listByPurchase(purchaseId: purchase.id);
      expect(all.where((row) => row.status == 'revoked').length, 2);
    });

    test('seat count changes rotate seats entitlement row', () async {
      final repository = InMemoryMarketplaceEntitlementRepository();
      final service = MarketplaceEntitlementService(repository: repository);
      final purchase = _purchase(
        status: 'ACTIVE',
        seatCount: 1,
        offerId: 'offer_van_03',
      );
      await service.syncPurchaseEntitlements(
        purchase: purchase,
        reason: 'initial',
      );
      await service.syncPurchaseEntitlements(
        purchase: _purchase(
          status: 'ACTIVE',
          seatCount: 4,
          offerId: 'offer_van_03',
          purchaseId: purchase.id,
          userId: purchase.userId,
        ),
        reason: 'seats_changed',
      );

      final all = await repository.listByPurchase(purchaseId: purchase.id);
      final seats = all
          .where((row) => row.entitlementType == 'seats')
          .toList(growable: false);
      final plans = all
          .where((row) => row.entitlementType == 'plan')
          .toList(growable: false);
      expect(seats.length, 2);
      expect(plans.length, 1, reason: 'plan entitlement should not rotate');
      expect(
        seats
            .where((row) => row.status == 'active')
            .single
            .value['seats_total'],
        4,
      );
      expect(
        seats.where((row) => row.status == 'revoked').single.effectiveTo,
        isNotNull,
      );
    });
  });
}

MarketplacePurchaseRecord _purchase({
  required String status,
  required int seatCount,
  required String offerId,
  String? purchaseId,
  String? userId,
}) {
  return MarketplacePurchaseRecord(
    id: purchaseId ?? '74d50de3-688d-4f7c-a79e-6f7fcf74addf',
    userId: userId ?? 'user-entitlement-1',
    offerId: offerId,
    offerTitle: 'Offer Title',
    status: status,
    currency: 'NGN',
    totalAmountMinor: 1000 * seatCount,
    seatCount: seatCount,
    idempotencyKey: 'idem-entitlement',
    createdAt: DateTime.utc(2026, 2, 23),
    updatedAt: DateTime.utc(2026, 2, 23),
  );
}
