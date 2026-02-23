import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';
import 'marketplace_offer_repository.dart';

class PostgresMarketplaceOfferRepository implements MarketplaceOfferRepository {
  PostgresMarketplaceOfferRepository(
    this._postgresProvider, {
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  @override
  Future<MarketplaceOfferRecord?> findActiveOfferById(String offerId) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id,
          title,
          description,
          currency,
          price_minor,
          interval,
          features_json::text,
          sort_rank
        FROM marketplace_offers
        WHERE id = @offer_id
          AND is_active = TRUE
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'offer_id': offerId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToOffer(rows.first);
  }

  @override
  Future<List<MarketplaceOfferRecord>> listActiveOffers() async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query('''
        SELECT
          id,
          title,
          description,
          currency,
          price_minor,
          interval,
          features_json::text,
          sort_rank
        FROM marketplace_offers
        WHERE is_active = TRUE
        ORDER BY sort_rank ASC, created_at DESC
        '''),
    );
    return rows.map(_rowToOffer).toList(growable: false);
  }

  @override
  Future<MarketplacePurchaseRecord> createOrGetPurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
  }) async {
    return _postgresProvider.withTxn((txn) async {
      final offer = await _findOfferById(txn, offerId);
      if (offer == null) {
        throw const MarketplaceRepositoryStateException(
          code: 'offer_not_found',
        );
      }

      final now = _nowUtc();
      final purchaseId = _uuid.v4();
      final insertRows = await txn.query(
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
          @idempotency_key,
          @created_at,
          @updated_at
        )
        ON CONFLICT (user_id, idempotency_key)
        DO NOTHING
        RETURNING
          id::text,
          user_id,
          offer_id,
          status,
          currency,
          price_minor,
          seats_total,
          idempotency_key,
          created_at,
          updated_at
        ''',
        substitutionValues: <String, Object?>{
          'id': purchaseId,
          'user_id': userId,
          'offer_id': offer.id,
          'status': 'PENDING',
          'currency': offer.currency,
          'price_minor': offer.priceMinor * seatCount,
          'seats_total': seatCount,
          'provider': provider,
          'idempotency_key': idempotencyKey,
          'created_at': now,
          'updated_at': now,
        },
      );

      if (insertRows.isNotEmpty) {
        await _appendTimeline(
          txn,
          purchaseId: purchaseId,
          eventType: 'purchase_created',
          eventData: <String, Object?>{
            'offer_id': offer.id,
            'seat_count': seatCount,
            'status': 'PENDING',
            'idempotency_key': idempotencyKey,
          },
        );
        return _rowToPurchase(insertRows.first, offerTitle: offer.title);
      }

      final existing = await _findPurchaseByIdempotencyInternal(
        txn: txn,
        userId: userId,
        idempotencyKey: idempotencyKey,
      );
      if (existing == null) {
        throw const MarketplaceRepositoryStateException(
          code: 'purchase_replay_not_found',
        );
      }
      return existing;
    });
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseByIdempotencyKey({
    required String userId,
    required String idempotencyKey,
  }) {
    return _postgresProvider.withTxn(
      (txn) => _findPurchaseByIdempotencyInternal(
        txn: txn,
        userId: userId,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById({
    required String userId,
    required String purchaseId,
  }) async {
    final rows = await _postgresProvider.withConnection(
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
        JOIN marketplace_offers o
          ON o.id = p.offer_id
        WHERE p.id = CAST(@purchase_id AS UUID)
          AND p.user_id = @user_id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'user_id': userId,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToPurchase(rows.first, offerTitle: _readString(rows.first[10]));
  }

  Future<MarketplacePurchaseRecord?> _findPurchaseByIdempotencyInternal({
    required PostgreSQLExecutionContext txn,
    required String userId,
    required String idempotencyKey,
  }) async {
    final rows = await txn.query(
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
      JOIN marketplace_offers o
        ON o.id = p.offer_id
      WHERE p.user_id = @user_id
        AND p.idempotency_key = @idempotency_key
      LIMIT 1
      ''',
      substitutionValues: <String, Object?>{
        'user_id': userId,
        'idempotency_key': idempotencyKey,
      },
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToPurchase(rows.first, offerTitle: _readString(rows.first[10]));
  }

  Future<void> _appendTimeline(
    PostgreSQLExecutionContext txn, {
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) {
    return txn.execute(
      '''
      INSERT INTO marketplace_timeline_events(
        id,
        purchase_id,
        event_type,
        event_data,
        created_at
      )
      VALUES(
        @id,
        CAST(@purchase_id AS UUID),
        @event_type,
        CAST(@event_data AS JSONB),
        NOW()
      )
      ''',
      substitutionValues: <String, Object?>{
        'id': _uuid.v4(),
        'purchase_id': purchaseId,
        'event_type': eventType,
        'event_data': jsonEncode(eventData),
      },
    );
  }

  Future<MarketplaceOfferRecord?> _findOfferById(
    PostgreSQLExecutionContext txn,
    String offerId,
  ) async {
    final rows = await txn.query(
      '''
      SELECT
        id,
        title,
        description,
        currency,
        price_minor,
        interval,
        features_json::text,
        sort_rank
      FROM marketplace_offers
      WHERE id = @offer_id
        AND is_active = TRUE
      LIMIT 1
      ''',
      substitutionValues: <String, Object?>{'offer_id': offerId},
    );
    if (rows.isEmpty) {
      return null;
    }
    return _rowToOffer(rows.first);
  }

  MarketplaceOfferRecord _rowToOffer(List<Object?> row) {
    return MarketplaceOfferRecord(
      id: (row[0] as String?)?.trim() ?? '',
      title: (row[1] as String?)?.trim() ?? '',
      description: (row[2] as String?)?.trim() ?? '',
      currency: (row[3] as String?)?.trim().isNotEmpty == true
          ? (row[3] as String).trim()
          : 'NGN',
      priceMinor: (row[4] as num?)?.toInt() ?? 0,
      interval: (row[5] as String?)?.trim().isNotEmpty == true
          ? (row[5] as String).trim().replaceAll('_', ' ')
          : 'per trip',
      perks: _parsePerks(row[6]),
      sortRank: (row[7] as num?)?.toInt() ?? 0,
    );
  }

  MarketplacePurchaseRecord _rowToPurchase(
    List<Object?> row, {
    required String offerTitle,
  }) {
    return MarketplacePurchaseRecord(
      id: _readString(row[0]),
      userId: _readString(row[1]),
      offerId: _readString(row[2]),
      offerTitle: offerTitle,
      status: _readString(row[3]),
      currency: _readString(row[4]),
      totalAmountMinor: (row[5] as num?)?.toInt() ?? 0,
      seatCount: (row[6] as num?)?.toInt() ?? 0,
      idempotencyKey: _readString(row[7]),
      createdAt: _readDateTime(row[8]),
      updatedAt: _readDateTime(row[9]),
    );
  }

  List<String> _parsePerks(Object? raw) {
    if (raw is List) {
      return raw.map((entry) => entry.toString()).toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((entry) => entry.toString())
              .toList(growable: false);
        }
      } catch (_) {
        return <String>[];
      }
    }
    return <String>[];
  }

  String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
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
