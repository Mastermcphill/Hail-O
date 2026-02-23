class PaywallCopy {
  const PaywallCopy({
    required this.offerId,
    required this.headline,
    required this.bullets,
    required this.legalText,
    this.subhead = '',
    this.ctaLabel = 'Continue',
    this.connectionFeeMinor = 0,
  });

  final String offerId;
  final String headline;
  final String subhead;
  final List<String> bullets;
  final String legalText;
  final String ctaLabel;
  final int connectionFeeMinor;

  factory PaywallCopy.fromMap(Map<String, dynamic> map) {
    return PaywallCopy(
      offerId: _string(map['offer_id'], fallback: _string(map['offerId'])),
      headline: _string(map['headline']),
      subhead: _string(map['subhead']),
      bullets: _stringList(map['bullets']),
      legalText: _string(
        map['legal_text'],
        fallback: _string(map['legalText']),
      ),
      ctaLabel: _string(
        map['cta_label'],
        fallback: _string(map['ctaLabel'], fallback: 'Continue'),
      ),
      connectionFeeMinor: _int(
        map['connection_fee_minor'],
        fallback: _int(map['connectionFeeMinor']),
      ),
    );
  }

  factory PaywallCopy.fromJson(Map<String, dynamic> json) => PaywallCopy.fromMap(json);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'offer_id': offerId,
      'headline': headline,
      'subhead': subhead,
      'bullets': bullets,
      'legal_text': legalText,
      'cta_label': ctaLabel,
      'connection_fee_minor': connectionFeeMinor,
    };
  }

  Map<String, dynamic> toJson() => toMap();
}

typedef MarketplacePaywallCopy = PaywallCopy;

String _string(Object? value, {String fallback = ''}) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return fallback;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const <String>[];
}
