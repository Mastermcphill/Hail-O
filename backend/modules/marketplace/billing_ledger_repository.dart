import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

class BillingLedgerEntryRecord {
  const BillingLedgerEntryRecord({
    required this.id,
    required this.purchaseId,
    required this.userId,
    required this.entryType,
    required this.provider,
    required this.providerRef,
    required this.amountMinor,
    required this.currency,
    required this.metadata,
    required this.occurredAt,
    required this.createdAt,
  });

  final String id;
  final String? purchaseId;
  final String userId;
  final String entryType;
  final String provider;
  final String providerRef;
  final int amountMinor;
  final String currency;
  final Map<String, Object?> metadata;
  final DateTime occurredAt;
  final DateTime createdAt;
}

abstract class BillingLedgerRepository {
  Future<bool> appendEntry({
    required String? purchaseId,
    required String userId,
    required String entryType,
    required String provider,
    required String providerRef,
    required int amountMinor,
    required String currency,
    required Map<String, Object?> metadata,
    DateTime? occurredAt,
  });

  Future<List<BillingLedgerEntryRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  });

  Future<List<BillingLedgerEntryRecord>> listByUser({
    required String userId,
    int limit = 200,
  });
}

class InMemoryBillingLedgerRepository implements BillingLedgerRepository {
  InMemoryBillingLedgerRepository({Uuid? uuid, DateTime Function()? nowUtc})
    : _uuid = uuid ?? const Uuid(),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final List<BillingLedgerEntryRecord> _entries = <BillingLedgerEntryRecord>[];
  final Set<String> _dedupeKeys = <String>{};

  @override
  Future<bool> appendEntry({
    required String? purchaseId,
    required String userId,
    required String entryType,
    required String provider,
    required String providerRef,
    required int amountMinor,
    required String currency,
    required Map<String, Object?> metadata,
    DateTime? occurredAt,
  }) async {
    final dedupeKey =
        '${provider.trim().toLowerCase()}::${providerRef.trim()}::${entryType.trim().toLowerCase()}';
    if (_dedupeKeys.contains(dedupeKey)) {
      return false;
    }
    _dedupeKeys.add(dedupeKey);
    final now = _nowUtc();
    _entries.add(
      BillingLedgerEntryRecord(
        id: _uuid.v4(),
        purchaseId: purchaseId?.trim().isEmpty == true ? null : purchaseId,
        userId: userId.trim(),
        entryType: entryType.trim().toLowerCase(),
        provider: provider.trim().toLowerCase(),
        providerRef: providerRef.trim(),
        amountMinor: amountMinor,
        currency: currency.trim().isEmpty ? 'NGN' : currency.trim(),
        metadata: Map<String, Object?>.from(metadata),
        occurredAt: (occurredAt ?? now).toUtc(),
        createdAt: now,
      ),
    );
    return true;
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    return _entries
        .where((entry) => entry.purchaseId == purchaseId)
        .toList(growable: false)
        .reversed
        .take(safeLimit)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByUser({
    required String userId,
    int limit = 200,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    return _entries
        .where((entry) => entry.userId == userId)
        .toList(growable: false)
        .reversed
        .take(safeLimit)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }
}

class PostgresBillingLedgerRepository implements BillingLedgerRepository {
  PostgresBillingLedgerRepository(
    this._postgresProvider, {
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  @override
  Future<bool> appendEntry({
    required String? purchaseId,
    required String userId,
    required String entryType,
    required String provider,
    required String providerRef,
    required int amountMinor,
    required String currency,
    required Map<String, Object?> metadata,
    DateTime? occurredAt,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO billing_ledger_entries(
          id,
          purchase_id,
          user_id,
          entry_type,
          provider,
          provider_ref,
          amount_minor,
          currency,
          metadata,
          occurred_at,
          created_at
        )
        VALUES(
          @id,
          CAST(@purchase_id AS UUID),
          @user_id,
          @entry_type,
          @provider,
          @provider_ref,
          @amount_minor,
          @currency,
          CAST(@metadata AS JSONB),
          @occurred_at,
          @created_at
        )
        ON CONFLICT (provider, provider_ref, entry_type)
        DO NOTHING
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'purchase_id': _normalizePurchaseId(purchaseId),
          'user_id': userId.trim(),
          'entry_type': entryType.trim().toLowerCase(),
          'provider': provider.trim().toLowerCase(),
          'provider_ref': providerRef.trim(),
          'amount_minor': amountMinor,
          'currency': currency.trim().isEmpty ? 'NGN' : currency.trim(),
          'metadata': jsonEncode(metadata),
          'occurred_at': (occurredAt ?? _nowUtc()).toUtc(),
          'created_at': _nowUtc(),
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          user_id,
          entry_type,
          provider,
          provider_ref,
          amount_minor,
          currency,
          metadata::text,
          occurred_at,
          created_at
        FROM billing_ledger_entries
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY occurred_at DESC, created_at DESC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'limit': safeLimit,
        },
      ),
    );
    return rows.map(_rowToRecord).toList(growable: false);
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByUser({
    required String userId,
    int limit = 200,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          user_id,
          entry_type,
          provider,
          provider_ref,
          amount_minor,
          currency,
          metadata::text,
          occurred_at,
          created_at
        FROM billing_ledger_entries
        WHERE user_id = @user_id
        ORDER BY occurred_at DESC, created_at DESC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'user_id': userId,
          'limit': safeLimit,
        },
      ),
    );
    return rows.map(_rowToRecord).toList(growable: false);
  }

  BillingLedgerEntryRecord _rowToRecord(List<Object?> row) {
    return BillingLedgerEntryRecord(
      id: (row[0] as String?)?.trim() ?? '',
      purchaseId: (row[1] as String?)?.trim(),
      userId: (row[2] as String?)?.trim() ?? '',
      entryType: (row[3] as String?)?.trim() ?? '',
      provider: (row[4] as String?)?.trim() ?? '',
      providerRef: (row[5] as String?)?.trim() ?? '',
      amountMinor: (row[6] as num?)?.toInt() ?? 0,
      currency: (row[7] as String?)?.trim() ?? 'NGN',
      metadata: _parseMetadata(row[8]),
      occurredAt: _readDateTime(row[9]),
      createdAt: _readDateTime(row[10]),
    );
  }

  String? _normalizePurchaseId(String? purchaseId) {
    final trimmed = (purchaseId ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, Object?> _parseMetadata(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return <String, Object?>{};
      }
    }
    return <String, Object?>{};
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
