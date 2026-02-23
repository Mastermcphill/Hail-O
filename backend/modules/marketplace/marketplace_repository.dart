import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

abstract class MarketplaceRepository {
  Future<List<Map<String, Object?>>> listOffers();

  Future<Map<String, Object?>?> findOfferById(String offerId);

  Future<Map<String, Object?>> createOrReusePurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
    String? orgId,
    List<Map<String, Object?>> assignments,
  });

  Future<Map<String, Object?>?> findPurchaseById(String purchaseId);

  Future<Map<String, Object?>?> findPurchaseByIdempotency({
    required String userId,
    required String idempotencyKey,
  });

  Future<Map<String, Object?>?> findPurchaseByIdempotencyAccessible({
    required String userId,
    required String idempotencyKey,
    required List<String> orgIds,
  });

  Future<Map<String, Object?>?> findPurchaseByProviderRef({
    required String provider,
    required String providerRef,
  });

  Future<List<Map<String, Object?>>> listPurchasesByOrg(String orgId);

  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
    String? providerCustomerId,
    String? providerSubscriptionId,
    String? providerPaymentIntentId,
  });

  Future<Map<String, Object?>> updatePurchaseSeats({
    required String purchaseId,
    required int seatCount,
  });

  Future<Map<String, Object?>> updatePurchasePlan({
    required String purchaseId,
    required String offerId,
  });

  Future<List<Map<String, Object?>>> listAssignments(String purchaseId);

  Future<void> replaceAssignments({
    required String purchaseId,
    required List<Map<String, Object?>> assignments,
    bool bumpPurchaseVersion,
  });

  Future<void> appendTimelineEvent({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
    DateTime? createdAtUtc,
  });

  Future<List<Map<String, Object?>>> listTimelineEvents(
    String purchaseId, {
    int limit,
    DateTime? sinceUtc,
  });

  Future<bool> recordWebhookEvent({
    required String provider,
    required String providerEventId,
    required String eventType,
    required Map<String, Object?> payload,
    String? purchaseId,
  });

  Future<void> markWebhookProcessed({
    required String provider,
    required String providerEventId,
  });

  Future<List<Map<String, Object?>>> listWebhookEvents(String purchaseId);
}

class PostgresMarketplaceRepository implements MarketplaceRepository {
  PostgresMarketplaceRepository(this._provider, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final PostgresProvider _provider;
  final Uuid _uuid;

  @override
  Future<List<Map<String, Object?>>> listOffers() async {
    final rows = await _provider.withConnection(
      (connection) => connection.query('''
        SELECT
          id,
          title,
          description,
          currency,
          price_minor,
          interval,
          features_json,
          seat_policy_json,
          is_active,
          sort_rank,
          created_at,
          updated_at
        FROM marketplace_offers
        WHERE is_active = TRUE
        ORDER BY sort_rank ASC, created_at ASC
        '''),
    );
    return rows.map(_offerFromRow).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> findOfferById(String offerId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          title,
          description,
          currency,
          price_minor,
          interval,
          features_json,
          seat_policy_json,
          is_active,
          sort_rank,
          created_at,
          updated_at
        FROM marketplace_offers
        WHERE id = @id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'id': offerId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _offerFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>> createOrReusePurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
    String? orgId,
    List<Map<String, Object?>> assignments = const <Map<String, Object?>>[],
  }) async {
    final offer = await findOfferById(offerId);
    if (offer == null) {
      throw StateError('offer_not_found');
    }
    final nowUtc = DateTime.now().toUtc();
    final purchaseId = _uuid.v4();
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO marketplace_purchases(
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          org_id,
          idempotency_key,
          created_at,
          updated_at
        )
        VALUES(
          @id,
          @user_id,
          @offer_id,
          @status,
          @currency,
          @price_minor,
          @seats_total,
          @provider,
          @org_id,
          @idempotency_key,
          @created_at,
          @updated_at
        )
        ON CONFLICT (user_id, idempotency_key) DO NOTHING
        RETURNING
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        ''',
        substitutionValues: <String, Object?>{
          'id': purchaseId,
          'user_id': userId,
          'offer_id': offerId,
          'status': 'pending',
          'currency': offer['currency'],
          'price_minor': offer['price_minor'],
          'seats_total': seatCount,
          'provider': provider,
          'org_id': orgId,
          'idempotency_key': idempotencyKey,
          'created_at': nowUtc,
          'updated_at': nowUtc,
        },
      ),
    );
    if (rows.isEmpty) {
      final existing = await findPurchaseByIdempotency(
        userId: userId,
        idempotencyKey: idempotencyKey,
      );
      if (existing == null) {
        throw StateError('purchase_replay_missing');
      }
      return <String, Object?>{...existing, '_replayed': true};
    }
    final purchase = _purchaseFromRow(rows.first);
    final initialAssignments = assignments.isEmpty
        ? <Map<String, Object?>>[
            <String, Object?>{
              'seat_index': 1,
              'assignee_user_id': userId,
              'role': 'admin',
            },
          ]
        : assignments;
    await replaceAssignments(
      purchaseId: purchase['id'] as String,
      assignments: initialAssignments,
    );
    return <String, Object?>{...purchase, '_replayed': false};
  }

  @override
  Future<Map<String, Object?>?> findPurchaseById(String purchaseId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        FROM marketplace_purchases
        WHERE id = @id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'id': purchaseId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findPurchaseByIdempotency({
    required String userId,
    required String idempotencyKey,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        FROM marketplace_purchases
        WHERE user_id = @user_id AND idempotency_key = @idempotency_key
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'user_id': userId,
          'idempotency_key': idempotencyKey,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findPurchaseByIdempotencyAccessible({
    required String userId,
    required String idempotencyKey,
    required List<String> orgIds,
  }) async {
    final normalizedOrgIds = orgIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final orgIdsCsv = normalizedOrgIds.join(',');
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        FROM marketplace_purchases
        WHERE idempotency_key = @idempotency_key
          AND (
            user_id = @user_id
            OR (
              @org_ids_csv <> ''
              AND org_id IS NOT NULL
              AND org_id::text = ANY(string_to_array(@org_ids_csv, ','))
            )
          )
        ORDER BY created_at DESC
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'user_id': userId,
          'idempotency_key': idempotencyKey,
          'org_ids_csv': orgIdsCsv,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findPurchaseByProviderRef({
    required String provider,
    required String providerRef,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        FROM marketplace_purchases
        WHERE provider = @provider AND provider_payment_intent_id = @provider_ref
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'provider': provider,
          'provider_ref': providerRef,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<List<Map<String, Object?>>> listPurchasesByOrg(String orgId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        FROM marketplace_purchases
        WHERE org_id = @org_id
        ORDER BY created_at DESC
        ''',
        substitutionValues: <String, Object?>{'org_id': orgId},
      ),
    );
    return rows.map(_purchaseFromRow).toList(growable: false);
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
    String? providerCustomerId,
    String? providerSubscriptionId,
    String? providerPaymentIntentId,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        UPDATE marketplace_purchases
        SET
          status = @status,
          provider_customer_id = COALESCE(@provider_customer_id, provider_customer_id),
          provider_subscription_id = COALESCE(@provider_subscription_id, provider_subscription_id),
          provider_payment_intent_id = COALESCE(@provider_payment_intent_id, provider_payment_intent_id),
          updated_at = NOW(),
          row_version = row_version + 1
        WHERE id = @id
        ''',
        substitutionValues: <String, Object?>{
          'id': purchaseId,
          'status': status,
          'provider_customer_id': providerCustomerId,
          'provider_subscription_id': providerSubscriptionId,
          'provider_payment_intent_id': providerPaymentIntentId,
        },
      );
    });
  }

  @override
  Future<Map<String, Object?>> updatePurchaseSeats({
    required String purchaseId,
    required int seatCount,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        UPDATE marketplace_purchases
        SET
          seats_total = @seats_total,
          updated_at = NOW(),
          row_version = row_version + 1
        WHERE id = @id
        RETURNING
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        ''',
        substitutionValues: <String, Object?>{
          'id': purchaseId,
          'seats_total': seatCount,
        },
      ),
    );
    if (rows.isEmpty) {
      throw StateError('purchase_not_found');
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>> updatePurchasePlan({
    required String purchaseId,
    required String offerId,
  }) async {
    final offer = await findOfferById(offerId);
    if (offer == null) {
      throw StateError('offer_not_found');
    }
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        UPDATE marketplace_purchases
        SET
          offer_id = @offer_id,
          currency = @currency,
          price_minor = @price_minor,
          updated_at = NOW(),
          row_version = row_version + 1
        WHERE id = @id
        RETURNING
          id,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          provider,
          provider_customer_id,
          provider_subscription_id,
          provider_payment_intent_id,
          idempotency_key,
          created_at,
          updated_at,
          org_id,
          row_version
        ''',
        substitutionValues: <String, Object?>{
          'id': purchaseId,
          'offer_id': offerId,
          'currency': offer['currency'],
          'price_minor': offer['price_minor'],
        },
      ),
    );
    if (rows.isEmpty) {
      throw StateError('purchase_not_found');
    }
    return _purchaseFromRow(rows.first);
  }

  @override
  Future<List<Map<String, Object?>>> listAssignments(String purchaseId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          purchase_id,
          seat_index,
          assignee_user_id,
          role,
          created_at,
          updated_at,
          row_version
        FROM marketplace_seat_assignments
        WHERE purchase_id = @purchase_id
        ORDER BY seat_index ASC, created_at ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map((row) => _assignmentFromRow(row)).toList(growable: false);
  }

  @override
  Future<void> replaceAssignments({
    required String purchaseId,
    required List<Map<String, Object?>> assignments,
    bool bumpPurchaseVersion = false,
  }) async {
    await _provider.withTxn((txn) async {
      final purchaseRows = await txn.query(
        '''
        UPDATE marketplace_purchases
        SET
          updated_at = NOW(),
          row_version = CASE
            WHEN @bump_version THEN row_version + 1
            ELSE row_version
          END
        WHERE id = @purchase_id
        RETURNING row_version
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'bump_version': bumpPurchaseVersion,
        },
      );
      if (purchaseRows.isEmpty) {
        throw StateError('purchase_not_found');
      }
      final assignmentRowVersion =
          (purchaseRows.first[0] as num?)?.toInt() ?? 1;

      await txn.execute(
        'DELETE FROM marketplace_seat_assignments WHERE purchase_id = @purchase_id',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      );
      final seen = <String>{};
      for (var i = 0; i < assignments.length; i++) {
        final row = assignments[i];
        final assignee =
            (row['assignee_user_id'] as String?)?.trim() ??
            (row['email'] as String?)?.trim() ??
            (row['name'] as String?)?.trim() ??
            '';
        if (assignee.isEmpty || seen.contains(assignee)) {
          continue;
        }
        seen.add(assignee);
        final seatIndex = ((row['seat_index'] as num?)?.toInt() ?? (i + 1));
        await txn.execute(
          '''
          INSERT INTO marketplace_seat_assignments(
            id,
            purchase_id,
            seat_index,
            assignee_user_id,
            role,
            created_at,
            updated_at,
            row_version
          )
          VALUES(
            @id,
            @purchase_id,
            @seat_index,
            @assignee_user_id,
            @role,
            @created_at,
            @updated_at,
            @row_version
          )
          ''',
          substitutionValues: <String, Object?>{
            'id': _uuid.v4(),
            'purchase_id': purchaseId,
            'seat_index': seatIndex <= 0 ? 1 : seatIndex,
            'assignee_user_id': assignee,
            'role':
                ((row['role'] as String?)?.trim().toLowerCase() ?? 'member'),
            'created_at': DateTime.now().toUtc(),
            'updated_at': DateTime.now().toUtc(),
            'row_version': assignmentRowVersion,
          },
        );
      }
    });
  }

  @override
  Future<void> appendTimelineEvent({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
    DateTime? createdAtUtc,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        INSERT INTO marketplace_timeline_events(id, purchase_id, event_type, event_data, created_at)
        VALUES(@id, @purchase_id, @event_type, @event_data, @created_at)
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'purchase_id': purchaseId,
          'event_type': eventType,
          'event_data': jsonEncode(eventData),
          'created_at': (createdAtUtc ?? DateTime.now().toUtc()),
        },
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> listTimelineEvents(
    String purchaseId, {
    int limit = 50,
    DateTime? sinceUtc,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, purchase_id, event_type, event_data, created_at, event_seq
        FROM marketplace_timeline_events
        WHERE purchase_id = @purchase_id
          AND (@since_utc::timestamptz IS NULL OR created_at > @since_utc)
        ORDER BY created_at ASC, event_seq ASC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'since_utc': sinceUtc,
          'limit': limit <= 0 ? 50 : limit,
        },
      ),
    );
    return rows.map((row) => _timelineFromRow(row)).toList(growable: false);
  }

  @override
  Future<bool> recordWebhookEvent({
    required String provider,
    required String providerEventId,
    required String eventType,
    required Map<String, Object?> payload,
    String? purchaseId,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO marketplace_webhook_events(
          id, provider, provider_event_id, purchase_id, event_type, payload_json, processed, created_at
        )
        VALUES(
          @id, @provider, @provider_event_id, @purchase_id, @event_type, @payload_json, FALSE, NOW()
        )
        ON CONFLICT (provider, provider_event_id) DO NOTHING
        RETURNING id
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'provider': provider,
          'provider_event_id': providerEventId,
          'purchase_id': purchaseId,
          'event_type': eventType,
          'payload_json': jsonEncode(payload),
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markWebhookProcessed({
    required String provider,
    required String providerEventId,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        UPDATE marketplace_webhook_events
        SET processed = TRUE, processed_at = NOW()
        WHERE provider = @provider AND provider_event_id = @provider_event_id
        ''',
        substitutionValues: <String, Object?>{
          'provider': provider,
          'provider_event_id': providerEventId,
        },
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> listWebhookEvents(
    String purchaseId,
  ) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, provider, provider_event_id, purchase_id, event_type, payload_json, processed, created_at, processed_at
        FROM marketplace_webhook_events
        WHERE purchase_id = @purchase_id
        ORDER BY created_at ASC
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    return rows.map((row) => _webhookFromRow(row)).toList(growable: false);
  }

  Map<String, Object?> _offerFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'title': row[1] as String,
    'description': (row[2] as String?) ?? '',
    'currency': (row[3] as String?) ?? 'NGN',
    'price_minor': (row[4] as num?)?.toInt() ?? 0,
    'interval': (row[5] as String?) ?? 'month',
    'features_json': _decodeJson(row[6], fallback: const <Object?>[]),
    'seat_policy_json': _decodeJson(
      row[7],
      fallback: const <String, Object?>{},
    ),
    'is_active': row[8] == true,
    'sort_rank': (row[9] as num?)?.toInt() ?? 0,
    'created_at': ((row[10] as DateTime?) ?? DateTime.now()).toUtc(),
    'updated_at': ((row[11] as DateTime?) ?? DateTime.now()).toUtc(),
  };

  Map<String, Object?> _purchaseFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'user_id': row[1] as String,
    'offer_id': row[2] as String,
    'status': (row[3] as String?) ?? 'pending',
    'currency': (row[4] as String?) ?? 'NGN',
    'price_minor': (row[5] as num?)?.toInt() ?? 0,
    'seats_total': (row[6] as num?)?.toInt() ?? 1,
    'provider': (row[7] as String?) ?? 'manual',
    'provider_customer_id': row[8] as String?,
    'provider_subscription_id': row[9] as String?,
    'provider_payment_intent_id': row[10] as String?,
    'idempotency_key': row[11] as String,
    'created_at': ((row[12] as DateTime?) ?? DateTime.now()).toUtc(),
    'updated_at': ((row[13] as DateTime?) ?? DateTime.now()).toUtc(),
    'org_id': row[14] as String?,
    'row_version': (row[15] as num?)?.toInt() ?? 1,
  };

  Map<String, Object?> _assignmentFromRow(List<Object?> row) =>
      <String, Object?>{
        'id': row[0] as String,
        'purchase_id': row[1] as String,
        'seat_index': (row[2] as num?)?.toInt() ?? 1,
        'assignee_user_id': row[3] as String,
        'role': (row[4] as String?) ?? 'member',
        'created_at': ((row[5] as DateTime?) ?? DateTime.now()).toUtc(),
        'updated_at': ((row[6] as DateTime?) ?? DateTime.now()).toUtc(),
        'row_version': (row[7] as num?)?.toInt() ?? 1,
      };

  Map<String, Object?> _timelineFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'purchase_id': row[1] as String,
    'event_type': row[2] as String,
    'event_data': _decodeJson(row[3], fallback: const <String, Object?>{}),
    'created_at': ((row[4] as DateTime?) ?? DateTime.now()).toUtc(),
    'event_seq': (row[5] as num?)?.toInt() ?? 0,
  };

  Map<String, Object?> _webhookFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'provider': row[1] as String,
    'provider_event_id': row[2] as String,
    'purchase_id': row[3] as String?,
    'event_type': row[4] as String,
    'payload_json': _decodeJson(row[5], fallback: const <String, Object?>{}),
    'processed': row[6] == true,
    'created_at': ((row[7] as DateTime?) ?? DateTime.now()).toUtc(),
    'processed_at': (row[8] as DateTime?)?.toUtc(),
  };

  Object _decodeJson(Object? value, {required Object fallback}) {
    if (value == null) {
      return fallback;
    }
    if (value is Map<String, Object?> || value is List<Object?>) {
      return value;
    }
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return fallback;
      }
    }
    return fallback;
  }
}
