class TraceContext {
  const TraceContext({
    required this.traceId,
    this.idempotencyScope,
    this.idempotencyKey,
    this.rideId,
    this.escrowId,
    this.debugEnabled = false,
  });

  final String traceId;
  final String? idempotencyScope;
  final String? idempotencyKey;
  final String? rideId;
  final String? escrowId;
  final bool debugEnabled;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'trace_id': traceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'ride_id': rideId,
      'escrow_id': escrowId,
      'debug_enabled': debugEnabled,
    };
  }
}
