class BillingInvoice {
  const BillingInvoice({
    required this.invoiceId,
    required this.orgId,
    required this.purchaseId,
    required this.currency,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.creditAppliedMinor,
    required this.totalDueMinor,
    required this.status,
    required this.createdAt,
  });

  final String invoiceId;
  final String orgId;
  final String purchaseId;
  final String currency;
  final int subtotalMinor;
  final int discountMinor;
  final int creditAppliedMinor;
  final int totalDueMinor;
  final String status;
  final DateTime createdAt;

  factory BillingInvoice.fromMap(Map<String, dynamic> map) {
    return BillingInvoice(
      invoiceId: _readString(map['invoice_id']),
      orgId: _readString(map['org_id']),
      purchaseId: _readString(map['purchase_id']),
      currency: _readString(map['currency']).isEmpty
          ? 'NGN'
          : _readString(map['currency']),
      subtotalMinor: _readInt(map['subtotal_minor']),
      discountMinor: _readInt(map['discount_minor']),
      creditAppliedMinor: _readInt(map['credit_applied_minor']),
      totalDueMinor: _readInt(map['total_due_minor']),
      status: _readString(map['status']).isEmpty
          ? 'open'
          : _readString(map['status']),
      createdAt: DateTime.tryParse(_readString(map['created_at']))?.toUtc() ??
          DateTime.now().toUtc(),
    );
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
