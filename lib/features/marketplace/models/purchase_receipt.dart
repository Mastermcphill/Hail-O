import 'seat_selection.dart';

class PurchaseReceipt {
  const PurchaseReceipt({
    required this.purchaseId,
    required this.offerId,
    required this.offerTitle,
    required this.seatCount,
    required this.totalPriceMinor,
    required this.status,
    required this.createdAt,
    required this.assignments,
  });

  final String purchaseId;
  final String offerId;
  final String offerTitle;
  final int seatCount;
  final int totalPriceMinor;
  final String status;
  final DateTime createdAt;
  final List<SeatAssignment> assignments;

  PurchaseReceipt copyWith({
    String? purchaseId,
    String? offerId,
    String? offerTitle,
    int? seatCount,
    int? totalPriceMinor,
    String? status,
    DateTime? createdAt,
    List<SeatAssignment>? assignments,
  }) {
    return PurchaseReceipt(
      purchaseId: purchaseId ?? this.purchaseId,
      offerId: offerId ?? this.offerId,
      offerTitle: offerTitle ?? this.offerTitle,
      seatCount: seatCount ?? this.seatCount,
      totalPriceMinor: totalPriceMinor ?? this.totalPriceMinor,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      assignments: assignments ?? this.assignments,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'purchase_id': purchaseId,
      'offer_id': offerId,
      'offer_title': offerTitle,
      'seat_count': seatCount,
      'total_price_minor': totalPriceMinor,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'assignments': assignments
          .map((assignment) => assignment.toMap())
          .toList(growable: false),
    };
  }

  factory PurchaseReceipt.fromMap(Map<String, dynamic> map) {
    final purchaseMap = _readMap(map['purchase']);
    final source = purchaseMap.isEmpty ? map : purchaseMap;
    final createdAtRaw = _readString(source['created_at']);
    final offerMap = _readMap(source['offer']);
    final offerId = _readString(source['offer_id']).isNotEmpty
        ? _readString(source['offer_id'])
        : _readString(offerMap['id']);
    final offerTitle = _readString(source['offer_title']).isNotEmpty
        ? _readString(source['offer_title'])
        : _readString(offerMap['title']);

    return PurchaseReceipt(
      purchaseId: _readString(source['purchase_id']).isNotEmpty
          ? _readString(source['purchase_id'])
          : _readString(source['id']),
      offerId: offerId,
      offerTitle: offerTitle,
      seatCount: _readInt(source['seat_count']),
      totalPriceMinor: _readInt(source['total_price_minor']),
      status: _readString(source['status']).isEmpty
          ? 'PENDING'
          : _readString(source['status']),
      createdAt:
          DateTime.tryParse(createdAtRaw)?.toUtc() ?? DateTime.now().toUtc(),
      assignments: _readAssignments(source['assignments']),
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

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

List<SeatAssignment> _readAssignments(Object? value) {
  if (value is! List) {
    return const <SeatAssignment>[];
  }
  final assignments = <SeatAssignment>[];
  for (final entry in value) {
    final map = _readMap(entry);
    assignments.add(
      SeatAssignment(
        seatNumber: _readInt(map['seat_number']),
        name: _readString(map['name']),
        email: _readString(map['email']),
      ),
    );
  }
  return assignments;
}
