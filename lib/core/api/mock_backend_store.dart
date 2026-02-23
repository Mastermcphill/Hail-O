class MockBackendStore {
  static final List<Map<String, dynamic>> routeChains =
      <Map<String, dynamic>>[];
  static final Map<String, List<Map<String, dynamic>>> offersByRideId =
      <String, List<Map<String, dynamic>>>{};
  static final Map<String, Map<String, dynamic>> acceptedOfferByRideId =
      <String, Map<String, dynamic>>{};
  static final Map<String, Map<String, dynamic>> paywallByRideId =
      <String, Map<String, dynamic>>{};
  static final Map<String, List<Map<String, dynamic>>> seatsByRideId =
      <String, List<Map<String, dynamic>>>{};
  static final Map<String, List<String>> selectedSeatIdsByRideId =
      <String, List<String>>{};
  static final Map<String, Map<String, dynamic>> purchasesById =
      <String, Map<String, dynamic>>{};
}
