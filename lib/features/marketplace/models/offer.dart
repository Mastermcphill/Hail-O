class MarketplaceOffer {
  const MarketplaceOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.currency,
    required this.interval,
    required this.perks,
  });

  final String id;
  final String title;
  final String subtitle;
  final int price;
  final String currency;
  final String interval;
  final List<String> perks;

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    return MarketplaceOffer(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      price: (json['price'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'NGN').toString(),
      interval: (json['interval'] ?? 'month').toString(),
      perks: (json['perks'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'price': price,
      'currency': currency,
      'interval': interval,
      'perks': perks,
    };
  }
}
