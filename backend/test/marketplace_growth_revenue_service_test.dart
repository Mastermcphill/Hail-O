import 'package:test/test.dart';

import '../modules/marketplace/marketplace_revenue_service.dart';

void main() {
  group('MarketplaceRevenueService', () {
    late MarketplaceRevenueService service;

    setUp(() {
      service = MarketplaceRevenueService();
    });

    test('coupon valid/expired/over-limit', () async {
      final valid = await service.applyCoupon(
        orgId: 'org-alpha',
        userId: 'user-1',
        couponCode: 'LAUNCH50',
        offerId: 'offer_sedan_01',
        seats: 2,
      );
      final validPreview = Map<String, Object?>.from(
        valid['pricing_preview'] as Map,
      );
      expect((validPreview['coupon_discount_minor'] as int?) ?? 0, greaterThan(0));

      expect(
        () => service.applyCoupon(
          orgId: 'org-alpha',
          userId: 'user-1',
          couponCode: 'EXPIRED1',
          offerId: 'offer_sedan_01',
          seats: 2,
        ),
        throwsA(
          isA<MarketplaceRevenueException>().having(
            (error) => error.code,
            'code',
            'COUPON_INVALID',
          ),
        ),
      );

      await service.applyCoupon(
        orgId: 'org-beta',
        userId: 'user-2',
        couponCode: 'LIMIT1',
        offerId: 'offer_sedan_01',
        seats: 1,
      );
      expect(
        () => service.applyCoupon(
          orgId: 'org-gamma',
          userId: 'user-3',
          couponCode: 'LIMIT1',
          offerId: 'offer_sedan_01',
          seats: 1,
        ),
        throwsA(
          isA<MarketplaceRevenueException>().having(
            (error) => error.code,
            'code',
            'COUPON_LIMIT_REACHED',
          ),
        ),
      );
    });

    test('coupon stacking + pricing order coupon -> referral -> credits', () async {
      await service.grantCredits(
        orgId: 'org-order',
        amountMinor: 500,
        reason: 'test_grant',
      );
      await service.applyCoupon(
        orgId: 'org-order',
        userId: 'user-order',
        couponCode: 'LAUNCH50',
        offerId: 'offer_sedan_01',
        seats: 2,
      );
      await service.applyReferral(
        orgId: 'org-order',
        userId: 'user-order',
        referralCode: 'FRIEND100',
        offerId: 'offer_sedan_01',
        seats: 2,
      );
      final preview = await service.pricingPreview(
        orgId: 'org-order',
        userId: 'user-order',
        offerId: 'offer_sedan_01',
        seats: 2,
      );

      expect(preview.baseMinor, 8400);
      expect(preview.couponMinor, 4200);
      expect(preview.referralMinor, 100);
      expect(preview.creditsMinor, 500);
      expect(preview.finalDueMinor, 3600);
    });

    test('referral self-referral rejected', () async {
      expect(
        () => service.applyReferral(
          orgId: 'org-self',
          userId: 'ref-owner-1',
          referralCode: 'FRIEND100',
          offerId: 'offer_sedan_01',
          seats: 1,
        ),
        throwsA(
          isA<MarketplaceRevenueException>().having(
            (error) => error.code,
            'code',
            'REFERRAL_SELF_REFERRAL',
          ),
        ),
      );
    });

    test('credits never go negative when pricing applies credits', () async {
      await service.grantCredits(
        orgId: 'org-credit',
        amountMinor: 100,
        reason: 'test_grant',
      );
      await service.createInvoice(
        orgId: 'org-credit',
        userId: 'user-credit',
        purchaseId: 'purchase-credit-1',
        offerId: 'offer_van_03',
        seats: 2,
      );

      final balance = await service.creditsBalance('org-credit');
      expect(balance['balance_minor'], greaterThanOrEqualTo(0));
    });

    test('dunning retry recovers invoice after second attempt', () async {
      final invoice = await service.createInvoice(
        orgId: 'org-dunning',
        userId: 'user-dunning',
        purchaseId: 'purchase-dunning-1',
        offerId: 'offer_van_03',
        seats: 2,
      );
      final invoiceId = (invoice['invoice_id'] as String?) ?? '';
      expect(invoiceId, isNotEmpty);
      expect(invoice['status'], anyOf('open', 'paid'));

      final first = await service.retryInvoice(
        orgId: 'org-dunning',
        invoiceId: invoiceId,
      );
      expect(first['status'], anyOf('failed', 'paid'));

      final second = await service.retryInvoice(
        orgId: 'org-dunning',
        invoiceId: invoiceId,
      );
      expect(second['status'], 'paid');
    });

    test('risk threshold blocks mutations but allows reads', () async {
      await service.recordRiskEvent(
        subjectType: 'org',
        subjectId: 'org-risk',
        eventType: 'failed_payment',
        scoreDelta: 80,
      );

      expect(
        () => service.assertMutationAllowed(
          userId: 'user-risk',
          orgId: 'org-risk',
          action: 'update_seats',
        ),
        throwsA(
          isA<MarketplaceRevenueException>().having(
            (error) => error.code,
            'code',
            'RISK_LOCKED',
          ),
        ),
      );

      await service.assertMutationAllowed(
        userId: 'user-risk',
        orgId: 'org-risk',
        action: 'read_purchase',
      );
    });

    test('comms outbox dedupe prevents spamming', () async {
      final first = await service.enqueueComms(
        channel: 'email',
        recipient: 'billing@org.local',
        templateId: 'invoice_failed_1',
        payload: const <String, Object?>{'invoice_id': 'inv_1'},
        dedupeKey: 'org-spam:invoice_failed_1:inv_1',
      );
      final second = await service.enqueueComms(
        channel: 'email',
        recipient: 'billing@org.local',
        templateId: 'invoice_failed_1',
        payload: const <String, Object?>{'invoice_id': 'inv_1'},
        dedupeKey: 'org-spam:invoice_failed_1:inv_1',
      );

      expect(first['deduped'], isNot(true));
      expect(second['deduped'], isTrue);
    });

    test('dunning admin controls resolve by case id and expose audit summary', () async {
      await service.createInvoice(
        orgId: 'org-admin-dunning',
        userId: 'user-admin-dunning',
        purchaseId: 'purchase-admin-dunning-1',
        offerId: 'offer_sedan_01',
        seats: 2,
      );
      final overview = await service.billingOverview('org-admin-dunning');
      final cases = (overview['dunning_cases'] as List?) ?? const <Object?>[];
      expect(cases, isNotEmpty);
      final firstCase = Map<String, Object?>.from(cases.first as Map);
      final caseId = (firstCase['id'] as String?) ?? '';
      expect(caseId, isNotEmpty);

      expect(await service.pauseDunningCase(caseId), isTrue);
      expect(await service.resumeDunningCase(caseId), isTrue);
      expect(await service.writeoffDunningCase(caseId), isTrue);

      final audit = await service.auditSummary('org-admin-dunning');
      expect(audit.containsKey('purchases'), isTrue);
      expect(audit.containsKey('timeline_summary'), isTrue);
      expect(audit.containsKey('comms_outbox'), isTrue);
    });
  });
}
