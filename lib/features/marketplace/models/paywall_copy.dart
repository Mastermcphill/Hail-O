class MarketplacePaywallCopy {
  const MarketplacePaywallCopy({
    required this.offerId,
    required this.headline,
    required this.subhead,
    required this.bullets,
    required this.legalText,
  });

  final String offerId;
  final String headline;
  final String subhead;
  final List<String> bullets;
  final String legalText;

  factory MarketplacePaywallCopy.fromJson(Map<String, dynamic> json) {
    return MarketplacePaywallCopy(
      offerId: (json['offerId'] ?? '').toString(),
      headline: (json['headline'] ?? '').toString(),
      subhead: (json['subhead'] ?? '').toString(),
      bullets: (json['bullets'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
      legalText: (json['legalText'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'offerId': offerId,
      'headline': headline,
      'subhead': subhead,
      'bullets': bullets,
      'legalText': legalText,
    };
  }
}
