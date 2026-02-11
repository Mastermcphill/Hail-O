import 'package:sqflite/sqflite.dart';

import '../models/ride_trip.dart';
import 'compliance_guard_service.dart';

enum BookingBlockedReason {
  nextOfKinRequired('next_of_kin_required'),
  crossBorderDocRequired('cross_border_doc_required'),
  crossBorderDocExpired('cross_border_doc_expired');

  const BookingBlockedReason(this.code);
  final String code;
}

class BookingBlockedException implements Exception {
  const BookingBlockedException(this.reason);

  final BookingBlockedReason reason;

  @override
  String toString() => 'BookingBlockedException(${reason.code})';
}

class RideBookingGuardService {
  RideBookingGuardService(
    this.db, {
    ComplianceGuardService? complianceGuardService,
  }) : _complianceGuardService =
           complianceGuardService ?? ComplianceGuardService(db);

  final DatabaseExecutor db;
  final ComplianceGuardService _complianceGuardService;

  Future<void> assertCanBookRide({
    required String riderUserId,
    required bool isCrossBorder,
    TripScope? tripScope,
    String? originCountry,
    String? destinationCountry,
  }) async {
    final scope =
        tripScope ??
        (isCrossBorder ? TripScope.crossCountry : TripScope.intraCity);
    try {
      await _complianceGuardService.assertEligibleForTrip(
        riderUserId: riderUserId,
        tripScope: scope,
        originCountry: originCountry,
        destinationCountry: destinationCountry,
      );
    } on ComplianceBlockedException catch (e) {
      if (e.reason == ComplianceBlockedReason.nextOfKinRequired) {
        throw const BookingBlockedException(
          BookingBlockedReason.nextOfKinRequired,
        );
      }
      if (e.reason == ComplianceBlockedReason.crossBorderDocExpired) {
        throw const BookingBlockedException(
          BookingBlockedReason.crossBorderDocExpired,
        );
      }
      throw const BookingBlockedException(
        BookingBlockedReason.crossBorderDocRequired,
      );
    }
  }
}
