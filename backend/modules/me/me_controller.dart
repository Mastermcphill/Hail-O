import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../lib/data/sqlite/dao/documents_dao.dart';
import '../../../lib/data/sqlite/dao/next_of_kin_dao.dart';
import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/models/document_record.dart';
import '../../../lib/domain/models/next_of_kin.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class MeController {
  MeController(this.db, {Uuid? uuid, DateTime Function()? nowUtc})
    : _uuid = uuid ?? const Uuid(),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  Router get router {
    final router = Router();
    router.get('/next-of-kin', _getNextOfKin);
    router.post('/next-of-kin', _upsertNextOfKin);
    router.get('/documents', _getDocuments);
    router.post('/documents', _upsertDocument);
    return router;
  }

  Future<Response> _getNextOfKin(Request request) async {
    final userId = _requireUserId(request);
    final nextOfKin = await NextOfKinDao(db).findByUser(userId);
    if (nextOfKin == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'next_of_kin_not_set',
        message: 'Next-of-kin not set',
      );
    }
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'next_of_kin': nextOfKin.toMap(),
    });
  }

  Future<Response> _upsertNextOfKin(Request request) async {
    final userId = _requireUserId(request);
    final payload = await readJsonBody(request);
    final fullName = (payload['full_name'] as String?)?.trim() ?? '';
    final phone = (payload['phone'] as String?)?.trim() ?? '';
    if (fullName.isEmpty || phone.isEmpty) {
      throw const DomainInvariantError(
        code: 'next_of_kin_full_name_and_phone_required',
      );
    }
    final now = _nowUtc();
    final nextOfKin = NextOfKin(
      userId: userId,
      fullName: fullName,
      phone: phone,
      relationship: (payload['relationship'] as String?)?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await NextOfKinDao(db).upsert(nextOfKin);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'next_of_kin': nextOfKin.toMap(),
    });
  }

  Future<Response> _getDocuments(Request request) async {
    final userId = _requireUserId(request);
    final validFor = (request.url.queryParameters['valid_for'] ?? '')
        .trim()
        .toLowerCase();
    if (validFor == 'international' || validFor == 'cross_country') {
      final hasValidCrossBorder = await DocumentsDao(
        db,
      ).hasValidCrossBorderDocument(userId, nowUtc: _nowUtc());
      return jsonResponse(200, <String, Object?>{
        'ok': true,
        'has_valid_cross_border_document': hasValidCrossBorder,
      });
    }
    final docs = await DocumentsDao(db).listByUser(userId);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'documents': docs.map((doc) => doc.toMap()).toList(growable: false),
    });
  }

  Future<Response> _upsertDocument(Request request) async {
    final userId = _requireUserId(request);
    final payload = await readJsonBody(request);

    final docTypeRaw = (payload['doc_type'] as String?)?.trim() ?? '';
    final fileRef = (payload['file_ref'] as String?)?.trim() ?? '';
    if (docTypeRaw.isEmpty || fileRef.isEmpty) {
      throw const DomainInvariantError(
        code: 'document_type_and_file_ref_required',
      );
    }
    final docType = _parseDocumentType(docTypeRaw);
    final now = _nowUtc();
    final expiresAtRaw = (payload['expires_at'] as String?)?.trim();
    final expiresAt = (expiresAtRaw == null || expiresAtRaw.isEmpty)
        ? null
        : DateTime.tryParse(expiresAtRaw)?.toUtc();
    final verified = (payload['verified'] as bool?) ?? true;
    final country = (payload['country'] as String?)?.trim().toUpperCase();

    final record = DocumentRecord(
      id: (payload['id'] as String?)?.trim().isNotEmpty == true
          ? (payload['id'] as String).trim()
          : _uuid.v4(),
      userId: userId,
      docType: docType,
      fileRef: fileRef,
      verified: verified,
      status: verified ? 'verified' : 'pending',
      country: country,
      expiresAt: expiresAt,
      verifiedAt: verified ? now : null,
      createdAt: now,
      updatedAt: now,
    );
    await DocumentsDao(db).upsert(record);
    return jsonResponse(201, <String, Object?>{
      'ok': true,
      'document': record.toMap(),
    });
  }

  String _requireUserId(Request request) {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
    return userId;
  }

  DocumentType _parseDocumentType(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final type in DocumentType.values) {
      if (type.dbValue == normalized) {
        return type;
      }
    }
    throw const DomainInvariantError(code: 'invalid_document_type');
  }
}
