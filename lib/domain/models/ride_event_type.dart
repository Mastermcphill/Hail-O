enum RideEventType {
  rideBooked('RIDE_BOOKED'),
  driverAccepted('DRIVER_ACCEPTED'),
  rideStarted('RIDE_STARTED'),
  rideCompleted('RIDE_COMPLETED'),
  rideCancelled('RIDE_CANCELLED'),
  settled('SETTLED'),
  disputeOpened('DISPUTE_OPENED'),
  disputeResolved('DISPUTE_RESOLVED');

  const RideEventType(this.dbValue);

  final String dbValue;

  static RideEventType fromDbValue(String value) {
    return RideEventType.values.firstWhere(
      (event) => event.dbValue == value,
      orElse: () => RideEventType.rideBooked,
    );
  }
}
