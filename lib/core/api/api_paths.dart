class ApiPaths {
  static const health = '/health';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';

  static const ridesRequest = '/rides/request';
  static String rideSnapshot(String rideId) => '/rides/$rideId';
  static String rideAccept(String rideId) => '/rides/$rideId/accept';
  static String rideStart(String rideId) => '/rides/$rideId/start';
  static String rideCancel(String rideId) => '/rides/$rideId/cancel';
  static String rideComplete(String rideId) => '/rides/$rideId/complete';
}
