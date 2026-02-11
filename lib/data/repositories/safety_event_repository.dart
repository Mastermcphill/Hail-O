abstract class SafetyEventRepository {
  Future<void> insertEvent({
    required String id,
    required String rideId,
    required String eventType,
    required String payloadJson,
    required DateTime createdAt,
  });

  Future<List<Map<String, Object?>>> listEventsByRide(String rideId);
}
