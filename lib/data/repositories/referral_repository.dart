import '../../domain/models/promo_event.dart';
import '../../domain/models/referral_code.dart';

abstract class ReferralRepository {
  Future<void> upsertCode(ReferralCode code);
  Future<ReferralCode?> getCode(String code);
  Future<void> recordPromoEvent(PromoEvent event);
  Future<List<PromoEvent>> listUserEvents(String userId);
}
