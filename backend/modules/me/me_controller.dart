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
    router.get('/', _getProfile);
    router.patch('/', _patchProfile);
    router.get('/roles', _getRoles);
    router.get('/next-of-kin', _getNextOfKin);
    router.post('/next-of-kin', _upsertNextOfKin);
    router.get('/documents', _getDocuments);
    router.post('/documents', _upsertDocument);
    return router;
  }

  Future<Response> _getProfile(Request request) async {
    final userId = _requireUserId(request);
    final profile = await _loadProfile(userId);
    return jsonResponse(200, <String, Object?>{'ok': true, 'profile': profile});
  }

  Future<Response> _patchProfile(Request request) async {
    final userId = _requireUserId(request);
    final payload = await readJsonBody(request);
    final hasName =
        payload.containsKey('name') || payload.containsKey('display_name');
    final hasEmail = payload.containsKey('email');
    final hasAvatar = payload.containsKey('avatar_url');
    if (!hasName && !hasEmail && !hasAvatar) {
      throw const DomainInvariantError(code: 'profile_update_fields_required');
    }

    final existing = await _loadProfile(userId);
    var displayName = _normalizeStoredNullable(existing['display_name']);
    var email = _normalizeStoredNullable(existing['email']);
    var avatarUrl = _normalizeStoredNullable(existing['avatar_url']);

    if (hasName) {
      displayName = _normalizeProfileField(
        payload.containsKey('name') ? payload['name'] : payload['display_name'],
        errorCode: 'invalid_profile_name',
      );
    }
    if (hasEmail) {
      email = _normalizeProfileField(
        payload['email'],
        errorCode: 'invalid_profile_email',
      );
      if (email != null && !email.contains('@')) {
        throw const DomainInvariantError(code: 'invalid_profile_email');
      }
    }
    if (hasAvatar) {
      avatarUrl = _normalizeProfileField(
        payload['avatar_url'],
        errorCode: 'invalid_avatar_url',
      );
    }

    final nowIso = _nowUtc().toUtc().toIso8601String();
    final profileRow = <String, Object?>{
      'user_id': userId,
      'display_name': displayName,
      'email': email,
      'avatar_url': avatarUrl,
      'updated_at': nowIso,
    };

    final existingProfileRows = await db.query(
      'user_profiles',
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (existingProfileRows.isEmpty) {
      await db.insert(
        'user_profiles',
        profileRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await db.update(
        'user_profiles',
        profileRow,
        where: 'user_id = ?',
        whereArgs: <Object>[userId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    if (hasName || hasEmail) {
      final usersUpdate = <String, Object?>{'updated_at': nowIso};
      if (hasName) {
        usersUpdate['display_name'] = displayName;
      }
      if (hasEmail) {
        usersUpdate['email'] = email;
      }
      await db.update(
        'users',
        usersUpdate,
        where: 'id = ?',
        whereArgs: <Object>[userId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'profile': profileRow,
    });
  }

  Future<Response> _getRoles(Request request) async {
    final userId = _requireUserId(request);
    final roles = <String>{};

    final roleRows = await db.query(
      'user_roles',
      columns: <String>['role'],
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'role ASC',
    );
    for (final row in roleRows) {
      final mapped = _mapRole(
        (row['role'] as String?)?.trim().toLowerCase() ?? '',
      );
      if (_isSupportedRole(mapped)) {
        roles.add(mapped);
      }
    }

    final userRows = await db.query(
      'users',
      columns: <String>['role'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (userRows.isNotEmpty) {
      final mapped = _mapRole(
        (userRows.first['role'] as String?)?.trim().toLowerCase() ?? '',
      );
      if (_isSupportedRole(mapped)) {
        roles.add(mapped);
      }
    }

    final requestRole = _mapRole(
      request.requestContext.role?.trim().toLowerCase() ?? '',
    );
    if (_isSupportedRole(requestRole)) {
      roles.add(requestRole);
    }
    roles.add('user');

    final sorted = roles.toList(growable: false)..sort();
    for (final role in sorted) {
      await db.insert('user_roles', <String, Object?>{
        'user_id': userId,
        'role': role,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    return jsonResponse(200, <String, Object?>{'ok': true, 'roles': sorted});
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

  Future<Map<String, Object?>> _loadProfile(String userId) async {
    final profileRows = await db.query(
      'user_profiles',
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (profileRows.isNotEmpty) {
      final row = profileRows.first;
      return <String, Object?>{
        'user_id': userId,
        'display_name': _normalizeStoredNullable(row['display_name']),
        'email': _normalizeStoredNullable(row['email']),
        'avatar_url': _normalizeStoredNullable(row['avatar_url']),
        'updated_at':
            (_normalizeStoredNullable(row['updated_at']) ??
            _nowUtc().toUtc().toIso8601String()),
      };
    }

    final userRows = await db.query(
      'users',
      columns: <String>['display_name', 'email', 'updated_at'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      throw const DomainInvariantError(code: 'user_not_found');
    }
    final user = userRows.first;
    return <String, Object?>{
      'user_id': userId,
      'display_name': _normalizeStoredNullable(user['display_name']),
      'email': _normalizeStoredNullable(user['email']),
      'avatar_url': null,
      'updated_at':
          (_normalizeStoredNullable(user['updated_at']) ??
          _nowUtc().toUtc().toIso8601String()),
    };
  }

  String _mapRole(String role) {
    switch (role) {
      case 'admin':
        return 'admin';
      case 'driver':
        return 'driver';
      case 'inspector':
        return 'inspector';
      case 'merchant':
      case 'fleet_owner':
        return 'merchant';
      case 'user':
      case 'rider':
      default:
        return 'user';
    }
  }

  bool _isSupportedRole(String role) {
    return const <String>{
      'user',
      'admin',
      'merchant',
      'driver',
      'inspector',
    }.contains(role);
  }

  String? _normalizeStoredNullable(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeProfileField(Object? value, {required String errorCode}) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw DomainInvariantError(code: errorCode);
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
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
