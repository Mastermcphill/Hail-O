import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

class PaymentWebhookStoredEvent {
  const PaymentWebhookStoredEvent({
    required this.provider,
    required this.eventId,
    required this.payload,
    required this.processingState,
    required this.attemptCount,
    required this.receivedAt,
    this.nextRetryAt,
    this.lastError,
    this.processedAt,
  });

  final String provider;
  final String eventId;
  final String payload;
  final String processingState;
  final int attemptCount;
  final DateTime receivedAt;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime? processedAt;

  bool get isProcessed => processingState == 'processed';
  bool get isFailed => processingState == 'failed';
}

abstract class PaymentWebhookEventRepository {
  Future<bool> recordEvent({
    required String provider,
    required String eventId,
    required String payload,
    DateTime? receivedAt,
  });

  Future<PaymentWebhookStoredEvent?> findEvent({
    required String provider,
    required String eventId,
  }) async {
    return null;
  }

  Future<void> markEventProcessed({
    required String provider,
    required String eventId,
    required DateTime processedAt,
  }) async {}

  Future<void> markEventPendingProcessing({
    required String provider,
    required String eventId,
    required String lastError,
    required DateTime nextRetryAt,
  }) async {}

  Future<void> markEventFailed({
    required String provider,
    required String eventId,
    required String lastError,
  }) async {}

  Future<List<PaymentWebhookStoredEvent>> listRetryableEvents({
    required DateTime nowUtc,
    int limit = 25,
  }) async {
    return const <PaymentWebhookStoredEvent>[];
  }
}

class InMemoryPaymentWebhookEventRepository
    implements PaymentWebhookEventRepository {
  final Map<String, PaymentWebhookStoredEvent> _eventsByDedupeKey =
      <String, PaymentWebhookStoredEvent>{};

  @override
  Future<bool> recordEvent({
    required String provider,
    required String eventId,
    required String payload,
    DateTime? receivedAt,
  }) async {
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedEventId = eventId.trim();
    final key = _dedupeKey(normalizedProvider, normalizedEventId);
    if (_eventsByDedupeKey.containsKey(key)) {
      return false;
    }
    _eventsByDedupeKey[key] = PaymentWebhookStoredEvent(
      provider: normalizedProvider,
      eventId: normalizedEventId,
      payload: payload.trim().isEmpty ? '{}' : payload,
      processingState: 'received',
      attemptCount: 0,
      receivedAt: (receivedAt ?? DateTime.now().toUtc()).toUtc(),
    );
    return true;
  }

  @override
  Future<PaymentWebhookStoredEvent?> findEvent({
    required String provider,
    required String eventId,
  }) async {
    final key = _dedupeKey(provider.trim().toLowerCase(), eventId.trim());
    return _eventsByDedupeKey[key];
  }

  @override
  Future<void> markEventProcessed({
    required String provider,
    required String eventId,
    required DateTime processedAt,
  }) async {
    final existing = await findEvent(provider: provider, eventId: eventId);
    if (existing == null) {
      return;
    }
    final key = _dedupeKey(existing.provider, existing.eventId);
    _eventsByDedupeKey[key] = PaymentWebhookStoredEvent(
      provider: existing.provider,
      eventId: existing.eventId,
      payload: existing.payload,
      processingState: 'processed',
      attemptCount: existing.attemptCount + 1,
      receivedAt: existing.receivedAt,
      processedAt: processedAt.toUtc(),
    );
  }

  @override
  Future<void> markEventPendingProcessing({
    required String provider,
    required String eventId,
    required String lastError,
    required DateTime nextRetryAt,
  }) async {
    final existing = await findEvent(provider: provider, eventId: eventId);
    if (existing == null) {
      return;
    }
    final key = _dedupeKey(existing.provider, existing.eventId);
    _eventsByDedupeKey[key] = PaymentWebhookStoredEvent(
      provider: existing.provider,
      eventId: existing.eventId,
      payload: existing.payload,
      processingState: 'pending_processing',
      attemptCount: existing.attemptCount + 1,
      receivedAt: existing.receivedAt,
      nextRetryAt: nextRetryAt.toUtc(),
      lastError: lastError.trim(),
      processedAt: existing.processedAt,
    );
  }

  @override
  Future<void> markEventFailed({
    required String provider,
    required String eventId,
    required String lastError,
  }) async {
    final existing = await findEvent(provider: provider, eventId: eventId);
    if (existing == null) {
      return;
    }
    final key = _dedupeKey(existing.provider, existing.eventId);
    _eventsByDedupeKey[key] = PaymentWebhookStoredEvent(
      provider: existing.provider,
      eventId: existing.eventId,
      payload: existing.payload,
      processingState: 'failed',
      attemptCount: existing.attemptCount + 1,
      receivedAt: existing.receivedAt,
      lastError: lastError.trim(),
      processedAt: existing.processedAt,
    );
  }

  @override
  Future<List<PaymentWebhookStoredEvent>> listRetryableEvents({
    required DateTime nowUtc,
    int limit = 25,
  }) async {
    final safeLimit = limit < 1
        ? 1
        : limit > 200
        ? 200
        : limit;
    final now = nowUtc.toUtc();
    final retryable =
        _eventsByDedupeKey.values
            .where((event) {
              if (event.processingState == 'received') {
                return true;
              }
              if (event.processingState != 'pending_processing') {
                return false;
              }
              final nextRetryAt = event.nextRetryAt;
              return nextRetryAt == null || !nextRetryAt.isAfter(now);
            })
            .toList(growable: false)
          ..sort((left, right) {
            final leftTime = left.nextRetryAt ?? left.receivedAt;
            final rightTime = right.nextRetryAt ?? right.receivedAt;
            return leftTime.compareTo(rightTime);
          });
    if (retryable.length <= safeLimit) {
      return retryable;
    }
    return retryable.take(safeLimit).toList(growable: false);
  }

  String _dedupeKey(String provider, String eventId) => '$provider::$eventId';
}

class PostgresPaymentWebhookEventRepository
    implements PaymentWebhookEventRepository {
  PostgresPaymentWebhookEventRepository(
    this._postgresProvider, {
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  @override
  Future<bool> recordEvent({
    required String provider,
    required String eventId,
    required String payload,
    DateTime? receivedAt,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO webhook_events(
          id,
          provider,
          event_id,
          payload,
          received_at,
          processing_state,
          attempt_count,
          next_retry_at,
          last_error,
          processed_at,
          updated_at
        )
        VALUES(
          @id,
          @provider,
          @event_id,
          CAST(@payload AS JSONB),
          @received_at,
          'received',
          0,
          NULL,
          NULL,
          NULL,
          @received_at
        )
        ON CONFLICT (provider, event_id)
        DO NOTHING
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'provider': provider.trim().toLowerCase(),
          'event_id': eventId.trim(),
          'payload': payload.trim().isEmpty ? '{}' : payload,
          'received_at': (receivedAt ?? _nowUtc()).toUtc(),
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<PaymentWebhookStoredEvent?> findEvent({
    required String provider,
    required String eventId,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          provider,
          event_id,
          payload::text,
          processing_state,
          attempt_count,
          next_retry_at,
          last_error,
          received_at,
          processed_at
        FROM webhook_events
        WHERE provider = @provider
          AND event_id = @event_id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'provider': provider.trim().toLowerCase(),
          'event_id': eventId.trim(),
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToStoredEvent(rows.first.toColumnMap());
  }

  @override
  Future<void> markEventProcessed({
    required String provider,
    required String eventId,
    required DateTime processedAt,
  }) async {
    final at = processedAt.toUtc();
    await _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        UPDATE webhook_events
        SET
          processing_state = 'processed',
          attempt_count = attempt_count + 1,
          next_retry_at = NULL,
          last_error = NULL,
          processed_at = @processed_at,
          updated_at = @processed_at
        WHERE provider = @provider
          AND event_id = @event_id
        ''',
        substitutionValues: <String, Object?>{
          'processed_at': at,
          'provider': provider.trim().toLowerCase(),
          'event_id': eventId.trim(),
        },
      ),
    );
  }

  @override
  Future<void> markEventPendingProcessing({
    required String provider,
    required String eventId,
    required String lastError,
    required DateTime nextRetryAt,
  }) async {
    final normalizedNow = _nowUtc();
    await _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        UPDATE webhook_events
        SET
          processing_state = 'pending_processing',
          attempt_count = attempt_count + 1,
          next_retry_at = @next_retry_at,
          last_error = @last_error,
          updated_at = @updated_at
        WHERE provider = @provider
          AND event_id = @event_id
        ''',
        substitutionValues: <String, Object?>{
          'next_retry_at': nextRetryAt.toUtc(),
          'last_error': _truncateError(lastError),
          'updated_at': normalizedNow,
          'provider': provider.trim().toLowerCase(),
          'event_id': eventId.trim(),
        },
      ),
    );
  }

  @override
  Future<void> markEventFailed({
    required String provider,
    required String eventId,
    required String lastError,
  }) async {
    final normalizedNow = _nowUtc();
    await _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        UPDATE webhook_events
        SET
          processing_state = 'failed',
          attempt_count = attempt_count + 1,
          next_retry_at = NULL,
          last_error = @last_error,
          updated_at = @updated_at
        WHERE provider = @provider
          AND event_id = @event_id
        ''',
        substitutionValues: <String, Object?>{
          'last_error': _truncateError(lastError),
          'updated_at': normalizedNow,
          'provider': provider.trim().toLowerCase(),
          'event_id': eventId.trim(),
        },
      ),
    );
  }

  @override
  Future<List<PaymentWebhookStoredEvent>> listRetryableEvents({
    required DateTime nowUtc,
    int limit = 25,
  }) async {
    final safeLimit = limit < 1
        ? 1
        : limit > 200
        ? 200
        : limit;
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          provider,
          event_id,
          payload::text,
          processing_state,
          attempt_count,
          next_retry_at,
          last_error,
          received_at,
          processed_at
        FROM webhook_events
        WHERE processing_state = 'received'
           OR (
             processing_state = 'pending_processing'
             AND (next_retry_at IS NULL OR next_retry_at <= @now_utc)
           )
        ORDER BY COALESCE(next_retry_at, received_at) ASC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'now_utc': nowUtc.toUtc(),
          'limit': safeLimit,
        },
      ),
    );
    return rows
        .map((row) => _rowToStoredEvent(row.toColumnMap()))
        .toList(growable: false);
  }

  PaymentWebhookStoredEvent _rowToStoredEvent(Map<String, dynamic> row) {
    final payloadRaw = row['payload'];
    final payload = payloadRaw is String ? payloadRaw : payloadRaw.toString();
    final processingState =
        (row['processing_state'] as String?)?.trim().toLowerCase() ??
        'received';
    final nextRetryAtRaw = row['next_retry_at'];
    final processedAtRaw = row['processed_at'];
    return PaymentWebhookStoredEvent(
      provider: (row['provider'] as String?)?.trim().toLowerCase() ?? '',
      eventId: (row['event_id'] as String?)?.trim() ?? '',
      payload: payload.trim().isEmpty ? '{}' : payload,
      processingState: processingState,
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      receivedAt: _asUtcDateTime(row['received_at']) ?? _nowUtc(),
      nextRetryAt: _asUtcDateTime(nextRetryAtRaw),
      lastError: (row['last_error'] as String?)?.trim(),
      processedAt: _asUtcDateTime(processedAtRaw),
    );
  }

  String _truncateError(String value) {
    final normalized = value.trim();
    if (normalized.length <= 512) {
      return normalized;
    }
    return normalized.substring(0, 512);
  }

  DateTime? _asUtcDateTime(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }
}
