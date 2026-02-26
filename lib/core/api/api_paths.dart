class ApiPaths {
  static const health = '/health';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const meNextOfKin = '/me/next-of-kin';
  static const meDocuments = '/me/documents';
  static const nextOfKin = meNextOfKin;

  static const routesCreate = '/routes';
  static const routes = routesCreate;
  static String routesMatch({required String from, required String to}) =>
      '/routes/match?from=${Uri.encodeQueryComponent(from)}'
      '&to=${Uri.encodeQueryComponent(to)}';

  static const ridesRequest = '/rides/request';
  static String rideSnapshot(String rideId) => '/rides/$rideId';
  static String rideAccept(String rideId) => '/rides/$rideId/accept';
  static String rideStart(String rideId) => '/rides/$rideId/start';
  static String rideCancel(String rideId) => '/rides/$rideId/cancel';
  static String rideComplete(String rideId) => '/rides/$rideId/complete';
  static String rideOffers(String rideId) => '/rides/$rideId/offers';
  static String rideAcceptOffer(String rideId) => '/rides/$rideId/accept-offer';
  static String ridePaywallOpen(String rideId) => '/rides/$rideId/paywall/open';
  static String ridePaywallPay(String rideId) => '/rides/$rideId/paywall/pay';
  static String rideSeats(String rideId) => '/rides/$rideId/seats';
  static String rideSeatsSelect(String rideId) => '/rides/$rideId/seats/select';

  static const marketplaceOffers = '/marketplace/offers';
  static String marketplaceOfferPaywall(String offerId) =>
      '/marketplace/offers/${Uri.encodeComponent(offerId)}/paywall';
  static const marketplacePurchases = '/marketplace/purchases';
  static String marketplacePurchase(String purchaseId) =>
      '/marketplace/purchases/${Uri.encodeComponent(purchaseId)}';
  static String marketplacePurchaseRestore(String idempotencyKey) =>
      '/marketplace/purchases/restore'
      '?idempotencyKey=${Uri.encodeQueryComponent(idempotencyKey)}';
  static String marketplacePurchaseSeats(String purchaseId) =>
      '${marketplacePurchase(purchaseId)}/seats';
  static String marketplacePurchaseAssignments(String purchaseId) =>
      '${marketplacePurchase(purchaseId)}/assignments';
  static String marketplacePurchaseChangePlan(String purchaseId) =>
      '${marketplacePurchase(purchaseId)}/change-plan';
  static String marketplacePurchaseTimeline(
    String purchaseId, {
    DateTime? sinceUtc,
    int? limit,
  }) {
    final query = <String, String>{};
    if (sinceUtc != null) {
      query['since'] = sinceUtc.toIso8601String();
    }
    if (limit != null) {
      query['limit'] = '$limit';
    }
    final base = '${marketplacePurchase(purchaseId)}/timeline';
    if (query.isEmpty) {
      return base;
    }
    return '$base?${Uri(queryParameters: query).query}';
  }

  static const dispatchQuote = '/dispatch/quote';
  static const dispatchTrips = '/dispatch/trips';
  static String dispatchTrip(String tripId) =>
      '$dispatchTrips/${Uri.encodeComponent(tripId)}';
  static String dispatchTripStatus(String tripId) =>
      '${dispatchTrip(tripId)}/status';
  static String dispatchTripAssign(String tripId) =>
      '${dispatchTrip(tripId)}/assign';
  static String dispatchNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 5,
    int limit = 20,
  }) {
    final query = Uri(
      queryParameters: <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius_km': radiusKm.toString(),
        'limit': '$limit',
      },
    ).query;
    return '/dispatch/drivers/nearby?$query';
  }
}
