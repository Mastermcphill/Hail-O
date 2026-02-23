class PricingBreakdown {
  const PricingBreakdown({
    required this.orgId,
    required this.offerId,
    required this.seats,
    required this.currency,
    required this.baseMinor,
    required this.couponDiscountMinor,
    required this.referralDiscountMinor,
    required this.creditsAppliedMinor,
    required this.finalDueMinor,
    this.appliedCoupon,
    this.appliedReferral,
  });

  final String orgId;
  final String offerId;
  final int seats;
  final String currency;
  final int baseMinor;
  final int couponDiscountMinor;
  final int referralDiscountMinor;
  final int creditsAppliedMinor;
  final int finalDueMinor;
  final String? appliedCoupon;
  final String? appliedReferral;

  factory PricingBreakdown.fromMap(Map<String, dynamic> map) {
    return PricingBreakdown(
      orgId: _readString(map['org_id']),
      offerId: _readString(map['offer_id']),
      seats: _readInt(map['seats']),
      currency: _readString(map['currency']).isEmpty
          ? 'NGN'
          : _readString(map['currency']),
      baseMinor: _readInt(map['base_minor']),
      couponDiscountMinor: _readInt(map['coupon_discount_minor']),
      referralDiscountMinor: _readInt(map['referral_discount_minor']),
      creditsAppliedMinor: _readInt(map['credits_applied_minor']),
      finalDueMinor: _readInt(map['final_due_minor']),
      appliedCoupon: _nullableString(map['applied_coupon']),
      appliedReferral: _nullableString(map['applied_referral']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'org_id': orgId,
      'offer_id': offerId,
      'seats': seats,
      'currency': currency,
      'base_minor': baseMinor,
      'coupon_discount_minor': couponDiscountMinor,
      'referral_discount_minor': referralDiscountMinor,
      'credits_applied_minor': creditsAppliedMinor,
      'final_due_minor': finalDueMinor,
      'applied_coupon': appliedCoupon,
      'applied_referral': appliedReferral,
    };
  }
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

String? _nullableString(Object? value) {
  final normalized = _readString(value);
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}
