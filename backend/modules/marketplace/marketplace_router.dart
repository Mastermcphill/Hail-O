import 'package:shelf_router/shelf_router.dart';

import 'marketplace_handlers.dart';

class MarketplaceRouter {
  MarketplaceRouter({MarketplaceHandlers? handlers})
    : _handlers = handlers ?? MarketplaceHandlers();

  final MarketplaceHandlers _handlers;

  Router get router {
    final router = Router();
    router.get('/offers', _handlers.listOffers);
    router.get('/offers/<offerId>/paywall', _handlers.getOfferPaywall);
    router.post('/purchases', _handlers.createPurchase);
    router.get('/purchases/restore', _handlers.restorePurchase);
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
}
