import 'marketplace_repository.dart';

class MarketplaceTimelineService {
  const MarketplaceTimelineService(this._repository);

  final MarketplaceRepository _repository;

  Future<void> appendEvent({
    required String purchaseId,
    required String type,
    required Map<String, Object?> data,
    DateTime? createdAtUtc,
  }) {
    return _repository.appendTimelineEvent(
      purchaseId: purchaseId,
      eventType: type,
      eventData: data,
      createdAtUtc: createdAtUtc,
    );
  }

  Future<List<Map<String, Object?>>> listEvents(
    String purchaseId, {
    int limit = 100,
    DateTime? sinceUtc,
  }) {
    return _repository.listTimelineEvents(
      purchaseId,
      limit: limit,
      sinceUtc: sinceUtc,
    );
  }
}
