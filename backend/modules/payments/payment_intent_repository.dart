import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

const Set<String> kTerminalPaymentIntentStatuses = <String>{
  'failed',
  'canceled',
  'cancelled',
  'expired',
  'succeeded',
  'captured',
};

bool isTerminalPaymentIntentStatus(String status) {
  return kTerminalPaymentIntentStatuses.contains(status.trim().toLowerCase());
}

class PaymentIntentRecord {
  const PaymentIntentRecord({
    required this.id,
    required this.purchaseId,
    required this.userId,
    required this.provider,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.providerRef,
    required this.createdAt,
    this.clientSecret,
  });

  final String id;
  final String purchaseId;
  final String userId;
  final String provider;
  final String status;
  final int amountMinor;
  final String currency;
  final String providerRef;
  final String? clientSecret;
  final DateTime createdAt;
}

abstract class PaymentIntentRepository {
  Future<PaymentIntentRecord?> findActiveByPurchaseId({
    required String purchaseId,
  });

  Future<PaymentIntentRecord> createIntent({
    required String purchaseId,
    required String userId,
    required String provider,
    required String status,
    required int amountMinor,
    required String currency,
    required String providerRef,
    String? clientSecret,
  });

  Future<PaymentIntentRecord?> findByIdForUser({
    required String intentId,
    required String userId,
  });
}

class InMemoryPaymentIntentRepository implements PaymentIntentRepository {
  InMemoryPaymentIntentRepository({Uuid? uuid, DateTime Function()? nowUtc})
    : _uuid = uuid ?? const Uuid(),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final Map<String, PaymentIntentRecord> _intentsById =
      <String, PaymentIntentRecord>{};
  final Map<String, List<String>> _intentIdsByPurchase =
      <String, List<String>>{};

  @override
  Future<PaymentIntentRecord?> findActiveByPurchaseId({
    required String purchaseId,
  }) async {
    final ids = _intentIdsByPurchase[purchaseId] ?? const <String>[];
    for (var index = ids.length - 1; index >= 0; index--) {
      final id = ids[index];
      final intent = _intentsById[id];
      if (intent == null) {
        continue;
      }
      if (!isTerminalPaymentIntentStatus(intent.status)) {
        return intent;
      }
    }
    return null;
  }

  @override
  Future<PaymentIntentRecord> createIntent({
    required String purchaseId,
    required String userId,
    required String provider,
    required String status,
    required int amountMinor,
    required String currency,
    required String providerRef,
    String? clientSecret,
  }) async {
    final record = PaymentIntentRecord(
      id: _uuid.v4(),
      purchaseId: purchaseId.trim(),
      userId: userId.trim(),
      provider: provider.trim().toLowerCase(),
      status: status.trim().toLowerCase(),
      amountMinor: amountMinor,
      currency: currency.trim().isEmpty ? 'NGN' : currency.trim().toUpperCase(),
      providerRef: providerRef.trim(),
      clientSecret: _normalizeNullable(clientSecret),
      createdAt: _nowUtc(),
    );
    _intentsById[record.id] = record;
    _intentIdsByPurchase
        .putIfAbsent(record.purchaseId, () => <String>[])
        .add(record.id);
    return record;
  }

  @override
  Future<PaymentIntentRecord?> findByIdForUser({
    required String intentId,
    required String userId,
  }) async {
    final intent = _intentsById[intentId.trim()];
    if (intent == null) {
      return null;
    }
    if (intent.userId != userId.trim()) {
      return null;
    }
    return intent;
  }

  String? _normalizeNullable(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class PostgresPaymentIntentRepository implements PaymentIntentRepository {
  PostgresPaymentIntentRepository(
    this._postgresProvider, {
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  @override
  Future<PaymentIntentRecord?> findActiveByPurchaseId({
    required String purchaseId,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          provider,
          status,
          amount_minor,
          currency,
          provider_ref,
          client_secret,
          created_at
        FROM payment_intents
        WHERE purchase_id = CAST(@purchase_id AS UUID)
          AND LOWER(status) NOT IN ('failed', 'canceled', 'cancelled', 'expired', 'succeeded', 'captured')
        ORDER BY created_at DESC
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToRecord(rows.first);
  }

  @override
  Future<PaymentIntentRecord> createIntent({
    required String purchaseId,
    required String userId,
    required String provider,
    required String status,
    required int amountMinor,
    required String currency,
    required String providerRef,
    String? clientSecret,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO payment_intents(
          id,
          purchase_id,
          provider,
          status,
          amount_minor,
          currency,
          provider_ref,
          client_secret,
          created_at,
          updated_at
        )
        VALUES(
          @id,
          CAST(@purchase_id AS UUID),
          @provider,
          @status,
          @amount_minor,
          @currency,
          @provider_ref,
          @client_secret,
          @created_at,
          @updated_at
        )
        RETURNING
          id::text,
          purchase_id::text,
          provider,
          status,
          amount_minor,
          currency,
          provider_ref,
          client_secret,
          created_at
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'purchase_id': purchaseId.trim(),
          'provider': provider.trim().toLowerCase(),
          'status': status.trim().toLowerCase(),
          'amount_minor': amountMinor,
          'currency': currency.trim().isEmpty ? 'NGN' : currency.trim(),
          'provider_ref': providerRef.trim(),
          'client_secret': _normalizeNullable(clientSecret),
          'created_at': _nowUtc(),
          'updated_at': _nowUtc(),
        },
      ),
    );
    return _rowToRecord(rows.first, userId: userId);
  }

  @override
  Future<PaymentIntentRecord?> findByIdForUser({
    required String intentId,
    required String userId,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          i.id::text,
          i.purchase_id::text,
          i.provider,
          i.status,
          i.amount_minor,
          i.currency,
          i.provider_ref,
          i.client_secret,
          i.created_at,
          p.user_id
        FROM payment_intents i
        JOIN marketplace_purchases p
          ON p.id = i.purchase_id
        WHERE i.id = CAST(@intent_id AS UUID)
          AND p.user_id = @user_id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'intent_id': intentId.trim(),
          'user_id': userId.trim(),
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToRecord(rows.first, userId: rows.first[9] as String?);
  }

  PaymentIntentRecord _rowToRecord(List<Object?> row, {String? userId}) {
    return PaymentIntentRecord(
      id: _readString(row[0]),
      purchaseId: _readString(row[1]),
      userId: (userId ?? '').trim(),
      provider: _readString(row[2]),
      status: _readString(row[3]),
      amountMinor: (row[4] as num?)?.toInt() ?? 0,
      currency: _readString(row[5]),
      providerRef: _readString(row[6]),
      clientSecret: _normalizeNullable(row[7] as String?),
      createdAt: _readDateTime(row[8]),
    );
  }

  String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  String? _normalizeNullable(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  DateTime _readDateTime(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    return _nowUtc();
  }
}
