enum MarketplaceOutboxType {
  createPurchase('create_purchase'),
  updateSeats('update_seats'),
  updateAssignments('update_assignments'),
  changePlan('change_plan');

  const MarketplaceOutboxType(this.value);
  final String value;

  static MarketplaceOutboxType fromValue(String value) {
    for (final type in MarketplaceOutboxType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw ArgumentError('Unknown outbox type: $value');
  }
}

enum MarketplaceOutboxStatus {
  queued('queued'),
  sending('sending'),
  acked('acked'),
  failed('failed'),
  dead('dead');

  const MarketplaceOutboxStatus(this.value);
  final String value;

  static MarketplaceOutboxStatus fromValue(String value) {
    for (final status in MarketplaceOutboxStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError('Unknown outbox status: $value');
  }
}

class MarketplaceOutboxItem {
  const MarketplaceOutboxItem({
    required this.id,
    required this.type,
    required this.idempotencyKey,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.purchaseId,
    this.baseVersion,
    this.nextRetryAt,
    this.lastError,
  });

  final String id;
  final MarketplaceOutboxType type;
  final String? purchaseId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final int? baseVersion;
  final MarketplaceOutboxStatus status;
  final int attempts;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  final String? lastError;

  MarketplaceOutboxItem copyWith({
    String? id,
    MarketplaceOutboxType? type,
    String? purchaseId,
    String? idempotencyKey,
    Map<String, dynamic>? payload,
    int? baseVersion,
    MarketplaceOutboxStatus? status,
    int? attempts,
    DateTime? nextRetryAt,
    DateTime? createdAt,
    String? lastError,
  }) {
    return MarketplaceOutboxItem(
      id: id ?? this.id,
      type: type ?? this.type,
      purchaseId: purchaseId ?? this.purchaseId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      payload: payload ?? this.payload,
      baseVersion: baseVersion ?? this.baseVersion,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      createdAt: createdAt ?? this.createdAt,
      lastError: lastError ?? this.lastError,
    );
  }
}
