class MarketplacePaymentIntent {
  const MarketplacePaymentIntent({
    required this.id,
    required this.purchaseId,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.provider,
  });

  final String id;
  final String purchaseId;
  final String status;
  final int amountMinor;
  final String currency;
  final String provider;

  bool get isPending {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending' ||
        normalized == 'requires_action' ||
        normalized == 'processing';
  }

  factory MarketplacePaymentIntent.fromMap(
    Map<String, dynamic> map, {
    required String purchaseId,
  }) {
    return MarketplacePaymentIntent(
      id: _readString(map['id']),
      purchaseId: purchaseId.trim(),
      status: _readString(map['status'], fallback: 'pending'),
      amountMinor: _readInt(map['amount_minor']),
      currency: _readString(map['currency'], fallback: 'NGN'),
      provider: _readString(map['provider'], fallback: 'unknown'),
    );
  }
}

String _readString(Object? value, {String fallback = ''}) {
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return fallback;
}

int _readInt(Object? value, {int fallback = 0}) {
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
