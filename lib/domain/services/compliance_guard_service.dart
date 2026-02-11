import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/documents_dao.dart';
import '../../data/sqlite/dao/next_of_kin_dao.dart';
import '../models/ride_trip.dart';

enum ComplianceBlockedReason {
  nextOfKinRequired('next_of_kin_required'),
  crossBorderDocRequired('cross_border_doc_required'),
  crossBorderDocExpired('cross_border_doc_expired');

  const ComplianceBlockedReason(this.code);
  final String code;
}

class ComplianceBlockedException implements Exception {
  const ComplianceBlockedException(this.reason);

  final ComplianceBlockedReason reason;

  @override
  String toString() => 'ComplianceBlockedException(${reason.code})';
}

class ComplianceGuardService {
  ComplianceGuardService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final DatabaseExecutor db;
  final DateTime Function() _nowUtc;

  Future<void> assertEligibleForTrip({
    required String riderUserId,
    required TripScope tripScope,
    String? originCountry,
    String? destinationCountry,
  }) async {
    final nextOfKinExists = await NextOfKinDao(db).existsForUser(riderUserId);
    if (!nextOfKinExists) {
      throw const ComplianceBlockedException(
        ComplianceBlockedReason.nextOfKinRequired,
      );
    }

    final isCrossBorder =
        tripScope == TripScope.crossCountry ||
        tripScope == TripScope.international;
    if (!isCrossBorder) {
      return;
    }

    final requiredCountry = _resolveRequiredCountry(
      tripScope: tripScope,
      originCountry: originCountry,
      destinationCountry: destinationCountry,
    );

    final validDoc = await DocumentsDao(db).hasValidCrossBorderDocument(
      riderUserId,
      nowUtc: _nowUtc(),
      requiredCountry: requiredCountry,
    );
    if (!validDoc) {
      final hasAnyCrossBorderDoc = await DocumentsDao(
        db,
      ).hasCrossBorderDocument(riderUserId);
      throw ComplianceBlockedException(
        hasAnyCrossBorderDoc
            ? ComplianceBlockedReason.crossBorderDocExpired
            : ComplianceBlockedReason.crossBorderDocRequired,
      );
    }
  }

  String? _resolveRequiredCountry({
    required TripScope tripScope,
    String? originCountry,
    String? destinationCountry,
  }) {
    final origin = originCountry?.trim().toUpperCase();
    final destination = destinationCountry?.trim().toUpperCase();
    if (tripScope == TripScope.international && destination != null) {
      return destination;
    }
    if (tripScope == TripScope.crossCountry && origin != null) {
      return origin;
    }
    return destination ?? origin;
  }
}
