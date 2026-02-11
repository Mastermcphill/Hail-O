import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/documents_dao.dart';
import '../../data/sqlite/dao/next_of_kin_dao.dart';

enum BookingBlockedReason {
  nextOfKinRequired('next_of_kin_required'),
  crossBorderDocRequired('cross_border_doc_required');

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
  const RideBookingGuardService(this.db);

  final Database db;

  Future<void> assertCanBookRide({
    required String riderUserId,
    required bool isCrossBorder,
  }) async {
    final nextOfKinExists = await NextOfKinDao(db).existsForUser(riderUserId);
    if (!nextOfKinExists) {
      throw const BookingBlockedException(
        BookingBlockedReason.nextOfKinRequired,
      );
    }

    if (isCrossBorder) {
      final hasDocument = await DocumentsDao(
        db,
      ).hasCrossBorderDocument(riderUserId);
      if (!hasDocument) {
        throw const BookingBlockedException(
          BookingBlockedReason.crossBorderDocRequired,
        );
      }
    }
  }
}
