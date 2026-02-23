import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';
import 'marketplace_repository.dart';

class MarketplaceEntitlementRecord {
  const MarketplaceEntitlementRecord({
    required this.id,
    required this.purchaseId,
    required this.userId,
    required this.entitlementType,
    required this.valueJson,
    required this.status,
    required this.effectiveFromUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.effectiveToUtc,
  });

  final String id;
  final String purchaseId;
  final String userId;
  final String entitlementType;
  final Map<String, Object?> valueJson;
  final String status;
  final DateTime effectiveFromUtc;
  final DateTime? effectiveToUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'purchase_id': purchaseId,
      'user_id': userId,
      'entitlement_type': entitlementType,
      'value_json': valueJson,
      'status': status,
      'effective_from': effectiveFromUtc.toIso8601String(),
      'effective_to': effectiveToUtc?.toIso8601String(),
      'created_at': createdAtUtc.toIso8601String(),
      'updated_at': updatedAtUtc.toIso8601String(),
    };
  }
}

abstract class MarketplaceEntitlementRepository {
  Future<List<MarketplaceEntitlementRecord>> listByPurchase(String purchaseId);

  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase(
    String purchaseId,
  );

  Future<MarketplaceEntitlementRecord?> findActiveByType({
    required String purchaseId,
    required String entitlementType,
  });

  Future<void> closeActiveByType({
    required String purchaseId,
    required String entitlementType,
    required DateTime effectiveToUtc,
  });

  Future<void> closeAllActive({
    required String purchaseId,
    required DateTime effectiveToUtc,
  });

  Future<void> insert(MarketplaceEntitlementRecord record);
}

class PostgresMarketplaceEntitlementRepository
    implements MarketplaceEntitlementRepository {
  PostgresMarketplaceEntitlementRepository(this._provider, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final PostgresProvider _provider;
  final Uuid _uuid;

  @override
  Future<List<MarketplaceEntitlementRecord>> listByPurchase(
    String purchaseId,
  ) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          purchase_id,
          user_id,
          entitlement_type,
          value_json,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = @purchase_id
        ORDER BY effective_from ASC, created_at ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase(
    String purchaseId,
  ) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          purchase_id,
          user_id,
          entitlement_type,
          value_json,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = @purchase_id
          AND effective_to IS NULL
        ORDER BY effective_from ASC, created_at ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<MarketplaceEntitlementRecord?> findActiveByType({
    required String purchaseId,
    required String entitlementType,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          purchase_id,
          user_id,
          entitlement_type,
          value_json,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = @purchase_id
          AND entitlement_type = @entitlement_type
          AND effective_to IS NULL
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'entitlement_type': entitlementType,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  @override
  Future<void> closeActiveByType({
    required String purchaseId,
    required String entitlementType,
    required DateTime effectiveToUtc,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        UPDATE marketplace_entitlements
        SET
          effective_to = @effective_to,
          status = 'revoked',
          updated_at = NOW()
        WHERE purchase_id = @purchase_id
          AND entitlement_type = @entitlement_type
          AND effective_to IS NULL
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'entitlement_type': entitlementType,
          'effective_to': effectiveToUtc,
        },
      );
    });
  }

  @override
  Future<void> closeAllActive({
    required String purchaseId,
    required DateTime effectiveToUtc,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        UPDATE marketplace_entitlements
        SET
          effective_to = @effective_to,
          status = 'revoked',
          updated_at = NOW()
        WHERE purchase_id = @purchase_id
          AND effective_to IS NULL
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'effective_to': effectiveToUtc,
        },
      );
    });
  }

  @override
  Future<void> insert(MarketplaceEntitlementRecord record) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        INSERT INTO marketplace_entitlements(
          id,
          purchase_id,
          user_id,
          entitlement_type,
          value_json,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        )
        VALUES(
          @id,
          @purchase_id,
          @user_id,
          @entitlement_type,
          @value_json,
          @status,
          @effective_from,
          @effective_to,
          @created_at,
          @updated_at
        )
        ''',
        substitutionValues: <String, Object?>{
          'id': record.id.isEmpty ? _uuid.v4() : record.id,
          'purchase_id': record.purchaseId,
          'user_id': record.userId,
          'entitlement_type': record.entitlementType,
          'value_json': jsonEncode(record.valueJson),
          'status': record.status,
          'effective_from': record.effectiveFromUtc,
          'effective_to': record.effectiveToUtc,
          'created_at': record.createdAtUtc,
          'updated_at': record.updatedAtUtc,
        },
      );
    });
  }

  MarketplaceEntitlementRecord _fromRow(List<Object?> row) {
    return MarketplaceEntitlementRecord(
      id: row[0] as String,
      purchaseId: row[1] as String,
      userId: row[2] as String,
      entitlementType: row[3] as String,
      valueJson: _decodeMap(row[4]),
      status: (row[5] as String?) ?? 'pending',
      effectiveFromUtc: ((row[6] as DateTime?) ?? DateTime.now()).toUtc(),
      effectiveToUtc: (row[7] as DateTime?)?.toUtc(),
      createdAtUtc: ((row[8] as DateTime?) ?? DateTime.now()).toUtc(),
      updatedAtUtc: ((row[9] as DateTime?) ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> _decodeMap(Object? raw) {
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

class InMemoryMarketplaceEntitlementRepository
    implements MarketplaceEntitlementRepository {
  InMemoryMarketplaceEntitlementRepository({Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final List<MarketplaceEntitlementRecord> _records =
      <MarketplaceEntitlementRecord>[];

  @override
  Future<List<MarketplaceEntitlementRecord>> listByPurchase(
    String purchaseId,
  ) async {
    return _records
        .where((record) => record.purchaseId == purchaseId)
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase(
    String purchaseId,
  ) async {
    return _records
        .where(
          (record) =>
              record.purchaseId == purchaseId && record.effectiveToUtc == null,
        )
        .toList(growable: false);
  }

  @override
  Future<MarketplaceEntitlementRecord?> findActiveByType({
    required String purchaseId,
    required String entitlementType,
  }) async {
    for (final record in _records) {
      if (record.purchaseId == purchaseId &&
          record.entitlementType == entitlementType &&
          record.effectiveToUtc == null) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> closeActiveByType({
    required String purchaseId,
    required String entitlementType,
    required DateTime effectiveToUtc,
  }) async {
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      if (record.purchaseId == purchaseId &&
          record.entitlementType == entitlementType &&
          record.effectiveToUtc == null) {
        _records[i] = MarketplaceEntitlementRecord(
          id: record.id,
          purchaseId: record.purchaseId,
          userId: record.userId,
          entitlementType: record.entitlementType,
          valueJson: record.valueJson,
          status: 'revoked',
          effectiveFromUtc: record.effectiveFromUtc,
          effectiveToUtc: effectiveToUtc,
          createdAtUtc: record.createdAtUtc,
          updatedAtUtc: effectiveToUtc,
        );
      }
    }
  }

  @override
  Future<void> closeAllActive({
    required String purchaseId,
    required DateTime effectiveToUtc,
  }) async {
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      if (record.purchaseId == purchaseId && record.effectiveToUtc == null) {
        _records[i] = MarketplaceEntitlementRecord(
          id: record.id,
          purchaseId: record.purchaseId,
          userId: record.userId,
          entitlementType: record.entitlementType,
          valueJson: record.valueJson,
          status: 'revoked',
          effectiveFromUtc: record.effectiveFromUtc,
          effectiveToUtc: effectiveToUtc,
          createdAtUtc: record.createdAtUtc,
          updatedAtUtc: effectiveToUtc,
        );
      }
    }
  }

  @override
  Future<void> insert(MarketplaceEntitlementRecord record) async {
    _records.add(
      MarketplaceEntitlementRecord(
        id: record.id.isEmpty ? _uuid.v4() : record.id,
        purchaseId: record.purchaseId,
        userId: record.userId,
        entitlementType: record.entitlementType,
        valueJson: Map<String, Object?>.from(record.valueJson),
        status: record.status,
        effectiveFromUtc: record.effectiveFromUtc,
        effectiveToUtc: record.effectiveToUtc,
        createdAtUtc: record.createdAtUtc,
        updatedAtUtc: record.updatedAtUtc,
      ),
    );
  }
}

class MarketplaceEntitlementService {
  MarketplaceEntitlementService({
    required MarketplaceEntitlementRepository entitlementRepository,
    Uuid? uuid,
  }) : _repository = entitlementRepository,
       _uuid = uuid ?? const Uuid();

  final MarketplaceEntitlementRepository _repository;
  final Uuid _uuid;

  Future<List<MarketplaceEntitlementRecord>> listByPurchase(String purchaseId) {
    return _repository.listByPurchase(purchaseId);
  }

  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase(
    String purchaseId,
  ) {
    return _repository.listActiveByPurchase(purchaseId);
  }

  Future<void> syncPurchaseEntitlements(Map<String, Object?> purchase) async {
    final status =
        (purchase['status'] as String?)?.trim().toLowerCase() ?? 'pending';
    final purchaseId = (purchase['id'] as String?) ?? '';
    final userId = (purchase['user_id'] as String?) ?? '';
    if (purchaseId.isEmpty || userId.isEmpty) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    if (_isRevokedStatus(status)) {
      await _repository.closeAllActive(
        purchaseId: purchaseId,
        effectiveToUtc: nowUtc,
      );
      return;
    }

    final planValue = <String, Object?>{
      'plan': (purchase['offer_id'] as String?) ?? 'unknown',
    };
    final seatsValue = <String, Object?>{
      'seats_total': (purchase['seats_total'] as num?)?.toInt() ?? 1,
    };

    final targetStatus = status == 'active' ? 'active' : 'pending';
    await _rotate(
      purchaseId: purchaseId,
      userId: userId,
      entitlementType: 'plan',
      valueJson: planValue,
      status: targetStatus,
      nowUtc: nowUtc,
    );
    await _rotate(
      purchaseId: purchaseId,
      userId: userId,
      entitlementType: 'seats',
      valueJson: seatsValue,
      status: targetStatus,
      nowUtc: nowUtc,
    );
  }

  Future<void> revokeByPurchaseId(String purchaseId) {
    return _repository.closeAllActive(
      purchaseId: purchaseId,
      effectiveToUtc: DateTime.now().toUtc(),
    );
  }

  Future<void> syncByPurchaseId({
    required String purchaseId,
    required MarketplaceRepository marketplaceRepository,
  }) async {
    final purchase = await marketplaceRepository.findPurchaseById(purchaseId);
    if (purchase == null) {
      return;
    }
    await syncPurchaseEntitlements(purchase);
  }

  Future<void> _rotate({
    required String purchaseId,
    required String userId,
    required String entitlementType,
    required Map<String, Object?> valueJson,
    required String status,
    required DateTime nowUtc,
  }) async {
    final active = await _repository.findActiveByType(
      purchaseId: purchaseId,
      entitlementType: entitlementType,
    );
    if (active != null &&
        _mapEquals(active.valueJson, valueJson) &&
        active.status == status) {
      return;
    }
    if (active != null) {
      await _repository.closeActiveByType(
        purchaseId: purchaseId,
        entitlementType: entitlementType,
        effectiveToUtc: nowUtc,
      );
    }
    await _repository.insert(
      MarketplaceEntitlementRecord(
        id: _uuid.v4(),
        purchaseId: purchaseId,
        userId: userId,
        entitlementType: entitlementType,
        valueJson: valueJson,
        status: status,
        effectiveFromUtc: nowUtc,
        effectiveToUtc: null,
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      ),
    );
  }

  bool _isRevokedStatus(String status) {
    return status == 'canceled' ||
        status == 'cancelled' ||
        status == 'refunded' ||
        status == 'past_due';
  }

  bool _mapEquals(Map<String, Object?> left, Map<String, Object?> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
