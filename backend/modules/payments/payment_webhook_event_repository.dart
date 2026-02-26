import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

abstract class PaymentWebhookEventRepository {
  Future<bool> recordEvent({
    required String provider,
    required String eventId,
    required String payload,
    DateTime? receivedAt,
  });
}

class InMemoryPaymentWebhookEventRepository
    implements PaymentWebhookEventRepository {
  final Set<String> _dedupeKeys = <String>{};

  @override
  Future<bool> recordEvent({
    required String provider,
    required String eventId,
    required String payload,
    DateTime? receivedAt,
  }) async {
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedEventId = eventId.trim();
    final key = '$normalizedProvider::$normalizedEventId';
    if (_dedupeKeys.contains(key)) {
      return false;
    }
    _dedupeKeys.add(key);
    return true;
  }
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
          received_at
        )
        VALUES(
          @id,
          @provider,
          @event_id,
          CAST(@payload AS JSONB),
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
}
