import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

class BillingLedgerEntryRecord {
  const BillingLedgerEntryRecord({
    required this.id,
    required this.userId,
    required this.entryType,
    required this.provider,
    required this.providerRef,
    required this.amountMinor,
    required this.currency,
    required this.metadata,
    required this.occurredAtUtc,
    required this.createdAtUtc,
    this.purchaseId,
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
  final DateTime occurredAtUtc;
  final DateTime createdAtUtc;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'purchase_id': purchaseId,
      'user_id': userId,
      'entry_type': entryType,
      'provider': provider,
      'provider_ref': providerRef,
      'amount_minor': amountMinor,
      'currency': currency,
      'metadata': metadata,
      'occurred_at': occurredAtUtc.toIso8601String(),
      'created_at': createdAtUtc.toIso8601String(),
    };
  }
}

abstract class BillingLedgerRepository {
  Future<bool> append(BillingLedgerEntryRecord record);

  Future<List<BillingLedgerEntryRecord>> listByPurchase(String purchaseId);
}

class PostgresBillingLedgerRepository implements BillingLedgerRepository {
  PostgresBillingLedgerRepository(this._provider, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final PostgresProvider _provider;
  final Uuid _uuid;

  @override
  Future<bool> append(BillingLedgerEntryRecord record) async {
    final rows = await _provider.withConnection(
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
          @purchase_id,
          @user_id,
          @entry_type,
          @provider,
          @provider_ref,
          @amount_minor,
          @currency,
          @metadata,
          @occurred_at,
          @created_at
        )
        ON CONFLICT (provider, provider_ref, entry_type) DO NOTHING
        RETURNING id
        ''',
        substitutionValues: <String, Object?>{
          'id': record.id.isEmpty ? _uuid.v4() : record.id,
          'purchase_id': record.purchaseId,
          'user_id': record.userId,
          'entry_type': record.entryType,
          'provider': record.provider,
          'provider_ref': record.providerRef,
          'amount_minor': record.amountMinor,
          'currency': record.currency,
          'metadata': jsonEncode(record.metadata),
          'occurred_at': record.occurredAtUtc,
          'created_at': record.createdAtUtc,
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByPurchase(
    String purchaseId,
  ) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
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
        FROM billing_ledger_entries
        WHERE purchase_id = @purchase_id
        ORDER BY occurred_at ASC, created_at ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map(_rowToRecord).toList(growable: false);
  }

  BillingLedgerEntryRecord _rowToRecord(List<Object?> row) {
    return BillingLedgerEntryRecord(
      id: row[0] as String,
      purchaseId: row[1] as String?,
      userId: row[2] as String,
      entryType: row[3] as String,
      provider: row[4] as String,
      providerRef: (row[5] as String?) ?? '',
      amountMinor: (row[6] as num?)?.toInt() ?? 0,
      currency: (row[7] as String?) ?? 'NGN',
      metadata: _decodeMetadata(row[8]),
      occurredAtUtc: ((row[9] as DateTime?) ?? DateTime.now()).toUtc(),
      createdAtUtc: ((row[10] as DateTime?) ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> _decodeMetadata(Object? raw) {
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          return decoded;
        }
      } catch (_) {}
    }
    return <String, Object?>{};
  }
}

class InMemoryBillingLedgerRepository implements BillingLedgerRepository {
  InMemoryBillingLedgerRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final List<BillingLedgerEntryRecord> _records = <BillingLedgerEntryRecord>[];
  final Set<String> _dedupe = <String>{};

  @override
  Future<bool> append(BillingLedgerEntryRecord record) async {
    final key = '${record.provider}|${record.providerRef}|${record.entryType}';
    if (_dedupe.contains(key)) {
      return false;
    }
    _dedupe.add(key);
    _records.add(
      BillingLedgerEntryRecord(
        id: record.id.isEmpty ? _uuid.v4() : record.id,
        purchaseId: record.purchaseId,
        userId: record.userId,
        entryType: record.entryType,
        provider: record.provider,
        providerRef: record.providerRef,
        amountMinor: record.amountMinor,
        currency: record.currency,
        metadata: Map<String, Object?>.from(record.metadata),
        occurredAtUtc: record.occurredAtUtc,
        createdAtUtc: record.createdAtUtc,
      ),
    );
    return true;
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByPurchase(
    String purchaseId,
  ) async {
    return _records
        .where((record) => record.purchaseId == purchaseId)
        .toList(growable: false);
  }
}
