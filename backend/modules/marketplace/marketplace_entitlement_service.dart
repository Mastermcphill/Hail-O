import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';
import 'marketplace_offer_repository.dart';

class MarketplaceEntitlementRecord {
  const MarketplaceEntitlementRecord({
    required this.id,
    required this.purchaseId,
    required this.userId,
    required this.entitlementType,
    required this.value,
    required this.status,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String purchaseId;
  final String userId;
  final String entitlementType;
  final Map<String, Object?> value;
  final String status;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract class MarketplaceEntitlementRepository {
  Future<List<MarketplaceEntitlementRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  });

  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase({
    required String purchaseId,
  });

  Future<void> rotateEntitlement({
    required String purchaseId,
    required String userId,
    required String entitlementType,
    required Map<String, Object?> value,
    DateTime? effectiveFrom,
  });

  Future<void> revokeActiveEntitlements({
    required String purchaseId,
    DateTime? effectiveTo,
    String reason = 'status_changed',
  });
}

class InMemoryMarketplaceEntitlementRepository
    implements MarketplaceEntitlementRepository {
  InMemoryMarketplaceEntitlementRepository({
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final Map<String, List<MarketplaceEntitlementRecord>> _byPurchase =
      <String, List<MarketplaceEntitlementRecord>>{};

  @override
  Future<List<MarketplaceEntitlementRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    final all =
        _byPurchase[purchaseId] ?? const <MarketplaceEntitlementRecord>[];
    if (all.length <= safeLimit) {
      return List<MarketplaceEntitlementRecord>.from(all);
    }
    return List<MarketplaceEntitlementRecord>.from(
      all.sublist(all.length - safeLimit),
    );
  }

  @override
  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase({
    required String purchaseId,
  }) async {
    final all =
        _byPurchase[purchaseId] ?? const <MarketplaceEntitlementRecord>[];
    return all
        .where((row) => row.status == 'active' && row.effectiveTo == null)
        .toList(growable: false);
  }

  @override
  Future<void> rotateEntitlement({
    required String purchaseId,
    required String userId,
    required String entitlementType,
    required Map<String, Object?> value,
    DateTime? effectiveFrom,
  }) async {
    final now = (effectiveFrom ?? _nowUtc()).toUtc();
    final rows = _byPurchase.putIfAbsent(
      purchaseId,
      () => <MarketplaceEntitlementRecord>[],
    );
    for (var index = 0; index < rows.length; index++) {
      final existing = rows[index];
      if (existing.entitlementType == entitlementType &&
          existing.status == 'active' &&
          existing.effectiveTo == null) {
        rows[index] = MarketplaceEntitlementRecord(
          id: existing.id,
          purchaseId: existing.purchaseId,
          userId: existing.userId,
          entitlementType: existing.entitlementType,
          value: existing.value,
          status: 'revoked',
          effectiveFrom: existing.effectiveFrom,
          effectiveTo: now,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
      }
    }

    rows.add(
      MarketplaceEntitlementRecord(
        id: _uuid.v4(),
        purchaseId: purchaseId,
        userId: userId,
        entitlementType: entitlementType,
        value: Map<String, Object?>.from(value),
        status: 'active',
        effectiveFrom: now,
        effectiveTo: null,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<void> revokeActiveEntitlements({
    required String purchaseId,
    DateTime? effectiveTo,
    String reason = 'status_changed',
  }) async {
    final now = (effectiveTo ?? _nowUtc()).toUtc();
    final rows = _byPurchase[purchaseId];
    if (rows == null || rows.isEmpty) {
      return;
    }
    for (var index = 0; index < rows.length; index++) {
      final existing = rows[index];
      if (existing.status == 'active' && existing.effectiveTo == null) {
        rows[index] = MarketplaceEntitlementRecord(
          id: existing.id,
          purchaseId: existing.purchaseId,
          userId: existing.userId,
          entitlementType: existing.entitlementType,
          value: <String, Object?>{...existing.value, 'revoked_reason': reason},
          status: 'revoked',
          effectiveFrom: existing.effectiveFrom,
          effectiveTo: now,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
      }
    }
  }
}

class PostgresMarketplaceEntitlementRepository
    implements MarketplaceEntitlementRepository {
  PostgresMarketplaceEntitlementRepository(
    this._postgresProvider, {
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  @override
  Future<List<MarketplaceEntitlementRecord>> listByPurchase({
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
          entitlement_type,
          value_json::text,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY effective_from ASC, created_at ASC
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
  Future<List<MarketplaceEntitlementRecord>> listActiveByPurchase({
    required String purchaseId,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          user_id,
          entitlement_type,
          value_json::text,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = CAST(@purchase_id AS UUID)
          AND status = 'active'
          AND effective_to IS NULL
        ORDER BY effective_from ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map(_rowToRecord).toList(growable: false);
  }

  @override
  Future<void> rotateEntitlement({
    required String purchaseId,
    required String userId,
    required String entitlementType,
    required Map<String, Object?> value,
    DateTime? effectiveFrom,
  }) async {
    final effectiveAt = (effectiveFrom ?? _nowUtc()).toUtc();
    await _postgresProvider.withTxn((txn) async {
      await txn.execute(
        '''
        UPDATE marketplace_entitlements
        SET
          status = 'revoked',
          effective_to = @effective_to,
          updated_at = @updated_at
        WHERE purchase_id = CAST(@purchase_id AS UUID)
          AND entitlement_type = @entitlement_type
          AND status = 'active'
          AND effective_to IS NULL
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'entitlement_type': entitlementType,
          'effective_to': effectiveAt,
          'updated_at': _nowUtc(),
        },
      );
      await txn.execute(
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
          CAST(@purchase_id AS UUID),
          @user_id,
          @entitlement_type,
          CAST(@value_json AS JSONB),
          'active',
          @effective_from,
          NULL,
          @created_at,
          @updated_at
        )
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'purchase_id': purchaseId,
          'user_id': userId,
          'entitlement_type': entitlementType,
          'value_json': jsonEncode(value),
          'effective_from': effectiveAt,
          'created_at': _nowUtc(),
          'updated_at': _nowUtc(),
        },
      );
    });
  }

  @override
  Future<void> revokeActiveEntitlements({
    required String purchaseId,
    DateTime? effectiveTo,
    String reason = 'status_changed',
  }) async {
    final now = (effectiveTo ?? _nowUtc()).toUtc();
    await _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        UPDATE marketplace_entitlements
        SET
          status = 'revoked',
          effective_to = @effective_to,
          value_json = value_json || CAST(@reason_patch AS JSONB),
          updated_at = @updated_at
        WHERE purchase_id = CAST(@purchase_id AS UUID)
          AND status = 'active'
          AND effective_to IS NULL
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'effective_to': now,
          'reason_patch': jsonEncode(<String, Object?>{
            'revoked_reason': reason,
          }),
          'updated_at': _nowUtc(),
        },
      ),
    );
  }

  MarketplaceEntitlementRecord _rowToRecord(List<Object?> row) {
    return MarketplaceEntitlementRecord(
      id: (row[0] as String?)?.trim() ?? '',
      purchaseId: (row[1] as String?)?.trim() ?? '',
      userId: (row[2] as String?)?.trim() ?? '',
      entitlementType: (row[3] as String?)?.trim() ?? '',
      value: _decodeMap(row[4]),
      status: (row[5] as String?)?.trim() ?? '',
      effectiveFrom: _readDateTime(row[6]),
      effectiveTo: row[7] == null ? null : _readDateTime(row[7]),
      createdAt: _readDateTime(row[8]),
      updatedAt: _readDateTime(row[9]),
    );
  }

  Map<String, Object?> _decodeMap(Object? raw) {
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

class MarketplaceEntitlementService {
  MarketplaceEntitlementService({
    required MarketplaceEntitlementRepository repository,
    PostgresProvider? postgresProvider,
  }) : _repository = repository,
       _postgresProvider = postgresProvider;

  final MarketplaceEntitlementRepository _repository;
  final PostgresProvider? _postgresProvider;

  Future<void> syncPurchaseEntitlements({
    required MarketplacePurchaseRecord purchase,
    String reason = 'purchase_state_sync',
    DateTime? effectiveFrom,
  }) async {
    if (purchase.status.trim().toUpperCase() != 'ACTIVE') {
      await _repository.revokeActiveEntitlements(
        purchaseId: purchase.id,
        effectiveTo: effectiveFrom,
        reason: reason,
      );
      return;
    }

    final active = await _repository.listActiveByPurchase(
      purchaseId: purchase.id,
    );
    final activeByType = <String, MarketplaceEntitlementRecord>{
      for (final row in active) row.entitlementType: row,
    };
    final seatValue = <String, Object?>{'seats_total': purchase.seatCount};
    final currentSeat = activeByType['seats'];
    if (currentSeat == null ||
        !_jsonEquivalent(
          currentSeat.value['seats_total'],
          purchase.seatCount,
        )) {
      await _repository.rotateEntitlement(
        purchaseId: purchase.id,
        userId: purchase.userId,
        entitlementType: 'seats',
        value: seatValue,
        effectiveFrom: effectiveFrom,
      );
    }

    final planValue = <String, Object?>{'plan': purchase.offerId};
    final currentPlan = activeByType['plan'];
    if (currentPlan == null ||
        !_jsonEquivalent(currentPlan.value['plan'], purchase.offerId)) {
      await _repository.rotateEntitlement(
        purchaseId: purchase.id,
        userId: purchase.userId,
        entitlementType: 'plan',
        value: planValue,
        effectiveFrom: effectiveFrom,
      );
    }
  }

  Future<void> syncByPurchaseId({
    required String purchaseId,
    String reason = 'purchase_state_sync',
  }) async {
    final postgresProvider = _postgresProvider;
    if (postgresProvider == null) {
      return;
    }
    final rows = await postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          p.id::text,
          p.user_id,
          p.offer_id,
          p.status,
          p.currency,
          p.price_minor,
          p.seats_total,
          p.idempotency_key,
          p.created_at,
          p.updated_at,
          o.title
        FROM marketplace_purchases p
        JOIN marketplace_offers o ON o.id = p.offer_id
        WHERE p.id = CAST(@purchase_id AS UUID)
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    if (rows.isEmpty) {
      return;
    }
    final row = rows.first;
    final purchase = MarketplacePurchaseRecord(
      id: (row[0] as String?)?.trim() ?? '',
      userId: (row[1] as String?)?.trim() ?? '',
      offerId: (row[2] as String?)?.trim() ?? '',
      status: (row[3] as String?)?.trim() ?? '',
      currency: (row[4] as String?)?.trim() ?? 'NGN',
      totalAmountMinor: (row[5] as num?)?.toInt() ?? 0,
      seatCount: (row[6] as num?)?.toInt() ?? 0,
      idempotencyKey: (row[7] as String?)?.trim() ?? '',
      createdAt: _readDateTime(row[8]),
      updatedAt: _readDateTime(row[9]),
      offerTitle: (row[10] as String?)?.trim() ?? '',
    );
    await syncPurchaseEntitlements(purchase: purchase, reason: reason);
  }

  Future<void> revokeByPurchaseId({
    required String purchaseId,
    String reason = 'status_changed',
  }) {
    return _repository.revokeActiveEntitlements(
      purchaseId: purchaseId,
      reason: reason,
    );
  }

  Future<List<MarketplaceEntitlementRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  }) {
    return _repository.listByPurchase(purchaseId: purchaseId, limit: limit);
  }

  bool _jsonEquivalent(Object? left, Object? right) {
    if (left == null && right == null) {
      return true;
    }
    if (left is num && right is num) {
      return left.toInt() == right.toInt();
    }
    return left?.toString() == right?.toString();
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
    return DateTime.now().toUtc();
  }
}
