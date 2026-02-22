import 'dart:convert';

import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/compliance_requirements_dao.dart';
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
  ComplianceGuardService(
    this.db, {
    DateTime Function()? nowUtc,
    ComplianceRequirementsDao? complianceRequirementsDao,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _providedRequirementsDao = complianceRequirementsDao;

  final DatabaseExecutor db;
  final DateTime Function() _nowUtc;
  ComplianceRequirementsDao get _requirementsDao =>
      _providedRequirementsDao ?? ComplianceRequirementsDao(db);
  final ComplianceRequirementsDao? _providedRequirementsDao;

  Future<void> assertEligibleForTrip({
    required String riderUserId,
    required TripScope tripScope,
    String? originCountry,
    String? destinationCountry,
  }) async {
    final isCrossBorder =
        tripScope == TripScope.crossCountry ||
        tripScope == TripScope.international;
    final requiredCountry = _resolveRequiredCountry(
      tripScope: tripScope,
      originCountry: originCountry,
      destinationCountry: destinationCountry,
    );
    final rule = await _requirementsDao.findApplicableRequirement(
      scope: tripScope.dbValue,
      fromCountry: originCountry,
      toCountry: destinationCountry,
    );
    final policy = rule == null
        ? (isCrossBorder
              ? _CompliancePolicy.defaultCrossBorder()
              : _CompliancePolicy.intraCityDefault())
        : _CompliancePolicy.fromJson(rule.requiredDocsJson);
    if (policy.requiresNextOfKin) {
      final nextOfKinExists = await NextOfKinDao(db).existsForUser(riderUserId);
      if (!nextOfKinExists) {
        throw const ComplianceBlockedException(
          ComplianceBlockedReason.nextOfKinRequired,
        );
      }
    }

    if (!policy.enforcesDocuments) {
      return;
    }
    final docTypes = policy.allowedDocTypes;
    final validDoc = await DocumentsDao(db).hasValidDocumentForTypes(
      riderUserId,
      docTypes: docTypes,
      nowUtc: _nowUtc(),
      requiredCountry: requiredCountry,
      requireVerified: policy.requiresVerified,
      requireNotExpired: policy.requiresNotExpired,
    );
    if (!validDoc) {
      final hasAnyCrossBorderDoc = await DocumentsDao(db)
          .hasValidDocumentForTypes(
            riderUserId,
            docTypes: docTypes,
            requireVerified: false,
            requireNotExpired: false,
          );
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

class _CompliancePolicy {
  const _CompliancePolicy({
    required this.requiresNextOfKin,
    required this.allowedDocTypes,
    required this.requiresVerified,
    required this.requiresNotExpired,
  });

  final bool requiresNextOfKin;
  final List<String> allowedDocTypes;
  final bool requiresVerified;
  final bool requiresNotExpired;

  bool get enforcesDocuments => allowedDocTypes.isNotEmpty;

  factory _CompliancePolicy.defaultCrossBorder() {
    return const _CompliancePolicy(
      requiresNextOfKin: true,
      allowedDocTypes: <String>['passport', 'ecowas_id'],
      requiresVerified: true,
      requiresNotExpired: true,
    );
  }

  factory _CompliancePolicy.intraCityDefault() {
    return const _CompliancePolicy(
      requiresNextOfKin: true,
      allowedDocTypes: <String>[],
      requiresVerified: true,
      requiresNotExpired: true,
    );
  }

  factory _CompliancePolicy.fromJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return _CompliancePolicy.defaultCrossBorder();
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return _CompliancePolicy.defaultCrossBorder();
    }
    final docs = (decoded['allowed_doc_types'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic value) => value.toString().trim().toLowerCase())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    return _CompliancePolicy(
      requiresNextOfKin: decoded['requires_next_of_kin'] as bool? ?? true,
      allowedDocTypes: docs,
      requiresVerified: decoded['requires_verified'] as bool? ?? true,
      requiresNotExpired: decoded['requires_not_expired'] as bool? ?? true,
    );
  }
}
