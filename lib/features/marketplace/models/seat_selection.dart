class SeatAssignment {
  const SeatAssignment({
    required this.seatNumber,
    required this.name,
    required this.email,
  });

  final int seatNumber;
  final String name;
  final String email;

  SeatAssignment copyWith({int? seatNumber, String? name, String? email}) {
    return SeatAssignment(
      seatNumber: seatNumber ?? this.seatNumber,
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'seat_number': seatNumber,
      'name': name,
      'email': email,
    };
  }
}

class SeatSelection {
  const SeatSelection({
    required this.offerId,
    required this.seatCount,
    required this.assignments,
  });

  final String offerId;
  final int seatCount;
  final List<SeatAssignment> assignments;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'offer_id': offerId,
      'seat_count': seatCount,
      'assignments': assignments
          .map((assignment) => assignment.toMap())
          .toList(growable: false),
    };
  }
}
