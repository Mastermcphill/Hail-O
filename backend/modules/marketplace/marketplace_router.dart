import 'package:shelf_router/shelf_router.dart';

import 'marketplace_handlers.dart';

class MarketplaceRouter {
  MarketplaceRouter({required MarketplaceHandlers handlers})
    : _handlers = handlers;

  final MarketplaceHandlers _handlers;

  Router get router {
    final router = Router();
    router.get('/offers', _handlers.listOffers);
    router.get('/timeline', _handlers.listTimeline);
    router.get('/offers/<offerId>/paywall', _handlers.getOfferPaywall);
    router.get('/pricing/preview', _handlers.pricingPreview);
    router.post('/apply-coupon', _handlers.applyCoupon);
    router.delete('/remove-coupon', _handlers.removeCoupon);
    router.post('/apply-referral', _handlers.applyReferral);
    router.post('/purchases', _handlers.createPurchase);
    router.get('/purchases/restore', _handlers.restorePurchase);
    router.post('/purchases/restore', _handlers.restorePurchasePost);
    router.get('/purchases/<purchaseId>', _handlers.getPurchase);
    router.patch('/purchases/<purchaseId>/seats', _handlers.updateSeats);
    router.patch(
      '/purchases/<purchaseId>/assignments',
      _handlers.updateAssignments,
    );
    router.post('/purchases/<purchaseId>/change-plan', _handlers.changePlan);
    router.get('/purchases/<purchaseId>/timeline', _handlers.getTimeline);
    return router;
  }

  Router get orgRouter {
    final router = Router();
    router.get('/<orgId>/credits', _handlers.getOrgCredits);
    router.get('/<orgId>/credits/ledger', _handlers.getOrgCreditsLedger);
    router.get('/<orgId>/billing/invoices', _handlers.getOrgInvoices);
    router.get(
      '/<orgId>/billing/invoices/<invoiceId>',
      _handlers.getOrgInvoice,
    );
    router.post(
      '/<orgId>/billing/payment-method',
      _handlers.setOrgPaymentMethod,
    );
    router.post(
      '/<orgId>/billing/retry/<invoiceId>',
      _handlers.retryOrgInvoice,
    );
    router.get('/<orgId>/usage', _handlers.listOrgUsage);
    router.get('/<orgId>/usage/rollups', _handlers.listOrgUsageRollups);
    return router;
  }
}
