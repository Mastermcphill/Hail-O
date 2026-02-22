abstract class LiquidationRepository {
  Future<void> recordLiquidationEvent({
    required String eventId,
    required String ownerId,
    required String reason,
    required int principalMinor,
    required int penaltyMinor,
    required String? harmedPartyId,
    required String status,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  });

  Future<List<Map<String, Object?>>> listLiquidationEvents(String ownerId);
}
