abstract class MarketplaceOfferRepository {
  Future<List<MarketplaceOfferRecord>> listActiveOffers();

  Future<MarketplaceOfferRecord?> findActiveOfferById(String offerId);

  Future<MarketplacePurchaseRecord> createOrGetPurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
    String? clientReference,
  });

  Future<MarketplacePurchaseRecord?> findPurchaseByIdempotencyKey({
    required String userId,
    required String idempotencyKey,
  });

  Future<MarketplacePurchaseRecord?> findPurchaseById({
    required String userId,
    required String purchaseId,
  });

  Future<MarketplacePurchaseRecord> updateSeatCount({
    required String userId,
    required String purchaseId,
    required int seatCount,
  });

  Future<MarketplacePurchaseRecord> replaceAssignments({
    required String userId,
    required String purchaseId,
    required List<MarketplaceSeatAssignmentInput> assignments,
  });

  Future<MarketplacePurchaseRecord> changePlan({
    required String userId,
    required String purchaseId,
    required String newOfferId,
  });

  Future<List<MarketplaceSeatAssignmentRecord>> listAssignments({
    required String userId,
    required String purchaseId,
  });

  Future<List<MarketplaceTimelineEventRecord>> listTimelineEvents({
    required String userId,
    required String purchaseId,
    int limit = 100,
  });
}

class MarketplaceOfferRecord {
  const MarketplaceOfferRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.currency,
    required this.priceMinor,
    required this.interval,
    required this.perks,
    required this.sortRank,
  });

  final String id;
  final String title;
  final String description;
  final String currency;
  final int priceMinor;
  final String interval;
  final List<String> perks;
  final int sortRank;
}

class MarketplacePurchaseRecord {
  const MarketplacePurchaseRecord({
    required this.id,
    required this.userId,
    required this.offerId,
    required this.offerTitle,
    required this.status,
    required this.currency,
    required this.totalAmountMinor,
    required this.seatCount,
    required this.idempotencyKey,
    required this.createdAt,
    required this.updatedAt,
    this.clientReference,
  });

  final String id;
  final String userId;
  final String offerId;
  final String offerTitle;
  final String status;
  final String currency;
  final int totalAmountMinor;
  final int seatCount;
  final String idempotencyKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? clientReference;
}

class MarketplaceSeatAssignmentRecord {
  const MarketplaceSeatAssignmentRecord({
    required this.id,
    required this.purchaseId,
    required this.seatIndex,
    required this.assigneeUserId,
    required this.role,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String purchaseId;
  final int seatIndex;
  final String assigneeUserId;
  final String role;
  final String name;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MarketplaceSeatAssignmentInput {
  const MarketplaceSeatAssignmentInput({
    required this.seatIndex,
    required this.name,
    required this.email,
  });

  final int seatIndex;
  final String name;
  final String email;
}

class MarketplaceTimelineEventRecord {
  const MarketplaceTimelineEventRecord({
    required this.id,
    required this.purchaseId,
    required this.eventType,
    required this.eventData,
    required this.createdAt,
  });

  final String id;
  final String purchaseId;
  final String eventType;
  final Map<String, Object?> eventData;
  final DateTime createdAt;
}

class MarketplaceRepositoryStateException implements Exception {
  const MarketplaceRepositoryStateException({required this.code});

  final String code;
}
