class ApiPaths {
  static const health = '/health';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';

  static const meNextOfKin = '/me/next-of-kin';

  static const routesCreate = '/routes';
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
}
