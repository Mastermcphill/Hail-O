class DisputeRecord {
  const DisputeRecord({
    required this.id,
    required this.rideId,
    required this.openedBy,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.resolvedAt,
    this.resolverUserId,
    this.resolutionNote,
    this.refundMinorTotal = 0,
  });

  final String id;
  final String rideId;
  final String openedBy;
  final String status;
  final String reason;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolverUserId;
  final String? resolutionNote;
  final int refundMinorTotal;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'opened_by': openedBy,
      'status': status,
      'reason': reason,
      'created_at': createdAt.toUtc().toIso8601String(),
      'resolved_at': resolvedAt?.toUtc().toIso8601String(),
      'resolver_user_id': resolverUserId,
      'resolution_note': resolutionNote,
      'refund_minor_total': refundMinorTotal,
    };
  }

  factory DisputeRecord.fromMap(Map<String, Object?> map) {
    DateTime? parseNullable(String key) {
      final raw = map[key] as String?;
      return raw == null ? null : DateTime.parse(raw).toUtc();
    }

    return DisputeRecord(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      openedBy: map['opened_by'] as String,
      status: map['status'] as String,
      reason: map['reason'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      resolvedAt: parseNullable('resolved_at'),
      resolverUserId: map['resolver_user_id'] as String?,
      resolutionNote: map['resolution_note'] as String?,
      refundMinorTotal: (map['refund_minor_total'] as num?)?.toInt() ?? 0,
    );
  }
}
