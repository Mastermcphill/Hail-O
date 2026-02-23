class MockBackendStore {
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
}
