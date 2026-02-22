import '../../domain/models/promo_event.dart';
import '../../domain/models/referral_code.dart';
import '../sqlite/dao/referrals_dao.dart';
import 'referral_repository.dart';

class SqliteReferralRepository implements ReferralRepository {
  const SqliteReferralRepository(this._dao);

  final ReferralsDao _dao;

  @override
  Future<ReferralCode?> getCode(String code) => _dao.findCode(code);

  @override
  Future<List<PromoEvent>> listUserEvents(String userId) =>
      _dao.listEventsByUser(userId);

  @override
  Future<void> recordPromoEvent(PromoEvent event) =>
      _dao.insertPromoEvent(event);

  @override
  Future<void> upsertCode(ReferralCode code) => _dao.upsertCode(code);
}
