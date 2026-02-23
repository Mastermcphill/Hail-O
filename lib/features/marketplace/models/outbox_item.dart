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

  factory MarketplaceOutboxItem.fromJson(Map<String, dynamic> json) {
    return MarketplaceOutboxItem(
      id: (json['id'] ?? '').toString(),
      type: MarketplaceOutboxType.fromValue(
        (json['type'] ?? 'create_purchase').toString(),
      ),
      purchaseId: json['purchase_id']?.toString(),
      idempotencyKey: (json['idempotency_key'] ?? '').toString(),
      payload: (json['payload'] is Map)
          ? (json['payload'] as Map).map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            )
          : const <String, dynamic>{},
      baseVersion: json['base_version'] is num
          ? (json['base_version'] as num).toInt()
          : int.tryParse((json['base_version'] ?? '').toString()),
      status: MarketplaceOutboxStatus.fromValue(
        (json['status'] ?? 'queued').toString(),
      ),
      attempts: json['attempts'] is num
          ? (json['attempts'] as num).toInt()
          : int.tryParse((json['attempts'] ?? '').toString()) ?? 0,
      nextRetryAt: _parseDateTime(json['next_retry_at']),
      createdAt:
          _parseDateTime(json['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastError: json['last_error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.value,
      'purchase_id': purchaseId,
      'idempotency_key': idempotencyKey,
      'payload': payload,
      'base_version': baseVersion,
      'status': status.value,
      'attempts': attempts,
      'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_error': lastError,
    };
  }

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
    bool clearNextRetryAt = false,
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
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      createdAt: createdAt ?? this.createdAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}
