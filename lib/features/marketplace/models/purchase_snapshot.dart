class MarketplaceAssignment {
  const MarketplaceAssignment({
    required this.seatIndex,
    required this.name,
    required this.email,
  });

  final int seatIndex;
  final String name;
  final String email;

  factory MarketplaceAssignment.fromJson(Map<String, dynamic> json) {
    return MarketplaceAssignment(
      seatIndex: (json['seatIndex'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'seatIndex': seatIndex,
      'name': name,
      'email': email,
    };
  }
}

class MarketplacePurchaseSnapshot {
  const MarketplacePurchaseSnapshot({
    required this.purchaseId,
    required this.offerId,
    required this.seatCount,
    required this.status,
    required this.createdAt,
    required this.totalAmount,
    required this.currency,
    required this.version,
    required this.assignmentsVersion,
    required this.assignments,
    this.orgId,
    this.orgName,
    this.requesterRole,
    this.provider,
    this.providerRef,
  });

  final String purchaseId;
  final String offerId;
  final int seatCount;
  final String status;
  final DateTime? createdAt;
  final int totalAmount;
  final String currency;
  final int version;
  final int assignmentsVersion;
  final List<MarketplaceAssignment> assignments;
  final String? orgId;
  final String? orgName;
  final String? requesterRole;
  final String? provider;
  final String? providerRef;

  factory MarketplacePurchaseSnapshot.fromJson(Map<String, dynamic> json) {
    final purchaseId = _stringFromKeys(json, const <String>[
      'purchaseId',
      'purchase_id',
      'id',
    ]);
    final offerId = _stringFromKeys(json, const <String>[
      'offerId',
      'offer_id',
    ]);
    final seatCount = _intFromKeys(json, const <String>[
      'seatCount',
      'seats_total',
      'seatsTotal',
    ], fallback: 1);
    final totalAmount = _intFromKeys(json, const <String>[
      'totalAmount',
      'price_minor',
      'priceMinor',
    ], fallback: 0);
    final createdAtRaw = _stringFromKeys(json, const <String>[
      'createdAt',
      'created_at',
    ]);
    final version = _intFromKeys(json, const <String>[
      'version',
      'row_version',
    ], fallback: 1);
    final assignmentsVersion = _intFromKeys(json, const <String>[
      'assignments_version',
      'assignmentsVersion',
      'assignments_row_version',
    ], fallback: version);
    return MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: offerId,
      seatCount: seatCount,
      status: (json['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse(createdAtRaw),
      totalAmount: totalAmount,
      currency: (json['currency'] ?? 'NGN').toString(),
      version: version,
      assignmentsVersion: assignmentsVersion,
      assignments: (json['assignments'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) => MarketplaceAssignment.fromJson(
              item.map(
                (key, value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
      orgId: _optionalStringFromKeys(json, const <String>['org_id', 'orgId']),
      orgName: _optionalStringFromKeys(json, const <String>[
        'org_name',
        'orgName',
      ]),
      requesterRole: _optionalStringFromKeys(json, const <String>[
        'requester_role',
        'requesterRole',
      ]),
      provider: json['provider']?.toString(),
      providerRef:
          json['provider_ref']?.toString() ?? json['providerRef']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'purchaseId': purchaseId,
      'offerId': offerId,
      'seatCount': seatCount,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'totalAmount': totalAmount,
      'currency': currency,
      'version': version,
      'assignments_version': assignmentsVersion,
      'assignments': assignments.map((item) => item.toJson()).toList(),
      'org_id': orgId,
      'org_name': orgName,
      'requester_role': requesterRole,
      'provider': provider,
      'providerRef': providerRef,
    };
  }
}

String _stringFromKeys(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalStringFromKeys(json, keys);
  return value ?? '';
}

String? _optionalStringFromKeys(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) {
      continue;
    }
    final normalized = value.toString();
    if (normalized.trim().isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

int _intFromKeys(
  Map<String, dynamic> json,
  List<String> keys, {
  required int fallback,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return fallback;
}
