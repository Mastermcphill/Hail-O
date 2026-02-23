import 'package:test/test.dart';

import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_repository_memory.dart';

void main() {
  test('entitlement service rotates seat entitlement when seats change', () async {
    final repository = InMemoryMarketplaceRepository();
    final entitlementRepository = InMemoryMarketplaceEntitlementRepository();
    final entitlementService = MarketplaceEntitlementService(
      entitlementRepository: entitlementRepository,
    );

    final purchase = await repository.createOrReusePurchase(
      userId: 'user-entitlement',
      offerId: 'starter_monthly',
      seatCount: 2,
      idempotencyKey: 'entitlement-idem-1',
      provider: 'manual',
    );
    await repository.updatePurchaseStatus(
      purchaseId: purchase['id'] as String,
      status: 'active',
    );
    final activePurchase = await repository.findPurchaseById(
      purchase['id'] as String,
    );
    await entitlementService.syncPurchaseEntitlements(activePurchase!);

    final updatedPurchase = await repository.updatePurchaseSeats(
      purchaseId: purchase['id'] as String,
      seatCount: 6,
    );
    await entitlementService.syncPurchaseEntitlements(updatedPurchase);

    final seatRows = (await entitlementService.listByPurchase(
      purchase['id'] as String,
    ))
        .where((row) => row.entitlementType == 'seats')
        .toList(growable: false);
    expect(seatRows.length, greaterThanOrEqualTo(2));
    expect(seatRows.any((row) => row.effectiveToUtc != null), isTrue);
    final active = seatRows.firstWhere((row) => row.effectiveToUtc == null);
    expect((active.valueJson['seats_total'] as num?)?.toInt(), 6);
  });
}
