import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/promo_event.dart';
import '../../../domain/models/referral_code.dart';
import '../table_names.dart';

class ReferralsDao {
  const ReferralsDao(this.db);

  final Database db;

  Future<void> upsertCode(ReferralCode code) async {
    await db.insert(
      TableNames.referralCodes,
      code.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ReferralCode?> findCode(String code) async {
    final rows = await db.query(
      TableNames.referralCodes,
      where: 'code = ?',
      whereArgs: <Object>[code],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ReferralCode.fromMap(rows.first);
  }

  Future<void> insertPromoEvent(PromoEvent event) async {
    await db.insert(
      TableNames.promoEvents,
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PromoEvent>> listEventsByUser(String userId) async {
    final rows = await db.query(
      TableNames.promoEvents,
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(PromoEvent.fromMap).toList(growable: false);
  }
}
