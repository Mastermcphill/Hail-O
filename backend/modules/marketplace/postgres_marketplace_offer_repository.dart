import 'dart:convert';

import '../../infra/postgres_provider.dart';
import 'marketplace_offer_repository.dart';

class PostgresMarketplaceOfferRepository implements MarketplaceOfferRepository {
  PostgresMarketplaceOfferRepository(this._postgresProvider);

  final PostgresProvider _postgresProvider;

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
}
