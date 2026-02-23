class PaywallCopy {
  const PaywallCopy({
    required this.offerId,
    required this.headline,
    required this.bullets,
    required this.legalText,
    required this.ctaLabel,
    required this.connectionFeeMinor,
  });

  final String offerId;
  final String headline;
  final List<String> bullets;
  final String legalText;
  final String ctaLabel;
  final int connectionFeeMinor;

  factory PaywallCopy.fromMap(Map<String, dynamic> map) {
    return PaywallCopy(
      offerId: _readString(map['offer_id']),
      headline: _readString(map['headline']),
      bullets: _readStringList(map['bullets']),
      legalText: _readString(map['legal_text']),
      ctaLabel: _readString(map['cta_label']),
      connectionFeeMinor: _readInt(map['connection_fee_minor']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'offer_id': offerId,
      'headline': headline,
      'bullets': bullets,
      'legal_text': legalText,
      'cta_label': ctaLabel,
      'connection_fee_minor': connectionFeeMinor,
    };
  }
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
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

List<String> _readStringList(Object? value) {
  if (value is List) {
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  return <String>[];
}
