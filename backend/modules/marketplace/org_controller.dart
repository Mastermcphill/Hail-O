import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import 'billing_ledger_repository.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_envelope.dart';
import 'marketplace_repository.dart';
import 'org_rbac.dart';
import 'org_repository.dart';

class OrgController {
  OrgController({
    required OrgRepository orgRepository,
    required MarketplaceRepository marketplaceRepository,
    required BillingLedgerRepository billingLedgerRepository,
    required MarketplaceEntitlementService entitlementService,
    Uuid? uuid,
  }) : _orgRepository = orgRepository,
       _marketplaceRepository = marketplaceRepository,
       _billingLedgerRepository = billingLedgerRepository,
       _entitlementService = entitlementService,
       _uuid = uuid ?? const Uuid();

  final OrgRepository _orgRepository;
  final MarketplaceRepository _marketplaceRepository;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceEntitlementService _entitlementService;
  final Uuid _uuid;

  Router get router {
    final router = Router();
    router.get('/', _listOrgs);
    router.get('/<orgId>', _getOrg);
    router.post('/', _createOrg);
    router.patch('/<orgId>', _renameOrg);

    router.get('/<orgId>/members', _listMembers);
    router.post('/<orgId>/invites', _createInvite);
    router.post('/invites/accept', _acceptInvite);
    router.delete('/<orgId>/members/<userId>', _removeMember);
    router.patch('/<orgId>/members/<userId>', _updateMemberRole);

    router.get('/<orgId>/billing/purchases', _billingPurchases);
    router.get('/<orgId>/billing/ledger', _billingLedger);
    router.get('/<orgId>/billing/entitlements', _billingEntitlements);
    return router;
  }

  Future<Response> _listOrgs(Request request) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final orgs = await _orgRepository.listUserOrgs(userId);
    return marketplaceOk(
      request,
      data: orgs.map(_jsonSafe).toList(growable: false),
    );
  }

  Future<Response> _getOrg(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final org = await _orgRepository.findOrgById(orgId);
    if (org == null) {
      return marketplaceError(
        request,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Organization not found',
      );
    }
    final membership = await _orgRepository.findMembership(
      orgId: orgId,
      userId: userId,
    );
    if (membership == null ||
        ((membership['status'] as String?)?.toLowerCase() != 'active')) {
      return forbiddenOrgRole(request);
    }
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org': _jsonSafe(org) as Map<String, Object?>,
        'membership': _jsonSafe(membership) as Map<String, Object?>,
      },
    );
  }

  Future<Response> _createOrg(Request request) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final body = await _readJsonBody(request);
    final name = (body['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'name is required',
      );
    }
    final created = await _orgRepository.createOrg(
      ownerUserId: userId,
      name: name,
    );
    final membership = await _orgRepository.findMembership(
      orgId: created['id'] as String,
      userId: userId,
    );
    return marketplaceOk(
      request,
      statusCode: 201,
      data: <String, Object?>{
        'org': _jsonSafe(created) as Map<String, Object?>,
        'membership': _jsonSafe(membership) as Map<String, Object?>,
      },
    );
  }

  Future<Response> _renameOrg(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final access = await requireAdminAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final body = await _readJsonBody(request);
    final name = (body['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'name is required',
      );
    }
    final org = await _orgRepository.updateOrgName(orgId: orgId, name: name);
    if (org == null) {
      return marketplaceError(
        request,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Organization not found',
      );
    }
    return marketplaceOk(
      request,
      data: <String, Object?>{'org': _jsonSafe(org) as Map<String, Object?>},
    );
  }

  Future<Response> _listMembers(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final membership = await _orgRepository.findMembership(
      orgId: orgId,
      userId: userId,
    );
    if (membership == null ||
        ((membership['status'] as String?)?.toLowerCase() != 'active')) {
      return forbiddenOrgRole(request);
    }
    final members = await _orgRepository.listMembers(orgId);
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'members': members.map(_jsonSafe).toList(growable: false),
      },
    );
  }

  Future<Response> _createInvite(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final access = await requireAdminAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final body = await _readJsonBody(request);
    final email = (body['email'] as String?)?.trim().toLowerCase() ?? '';
    final role = (body['role'] as String?)?.trim().toLowerCase() ?? 'member';
    if (email.isEmpty || !email.contains('@')) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'email is required',
      );
    }
    if (!kOrgRoles.contains(role)) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'role is invalid',
      );
    }
    final token = _uuid.v4();
    final tokenHash = _tokenHash(token);
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 7));
    final invite = await _orgRepository.createInvite(
      orgId: orgId,
      email: email,
      role: role,
      tokenHash: tokenHash,
      expiresAtUtc: expiresAt,
    );
    return marketplaceOk(
      request,
      statusCode: 201,
      data: <String, Object?>{
        'invite': _jsonSafe(invite) as Map<String, Object?>,
        'token': token,
      },
    );
  }

  Future<Response> _acceptInvite(Request request) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final body = await _readJsonBody(request);
    final token = (body['token'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'token is required',
      );
    }
    final invite = await _orgRepository.findInviteByTokenHash(_tokenHash(token));
    if (invite == null) {
      return marketplaceError(
        request,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Invite not found',
      );
    }
    final expiresAt = invite['expires_at'] as DateTime?;
    if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt.toUtc())) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'INVITE_EXPIRED',
        message: 'Invite has expired',
      );
    }

    final acceptedBy = (invite['accepted_by_user_id'] as String?)?.trim();
    final orgId = invite['org_id'] as String;
    final role = (invite['role'] as String?) ?? 'member';
    if (acceptedBy != null && acceptedBy.isNotEmpty && acceptedBy != userId) {
      return marketplaceError(
        request,
        statusCode: 409,
        errorCode: 'INVITE_ALREADY_ACCEPTED',
        message: 'Invite has already been accepted',
      );
    }

    await _orgRepository.upsertMember(
      orgId: orgId,
      userId: userId,
      role: role,
      status: 'active',
    );
    if (acceptedBy == null || acceptedBy.isEmpty) {
      await _orgRepository.markInviteAccepted(
        inviteId: invite['id'] as String,
        acceptedByUserId: userId,
        acceptedAtUtc: DateTime.now().toUtc(),
      );
    }
    final membership = await _orgRepository.findMembership(
      orgId: orgId,
      userId: userId,
    );
    final org = await _orgRepository.findOrgById(orgId);
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org': _jsonSafe(org) as Map<String, Object?>,
        'membership': _jsonSafe(membership) as Map<String, Object?>,
      },
    );
  }

  Future<Response> _removeMember(
    Request request,
    String orgId,
    String userId,
  ) async {
    final requesterId = _userId(request);
    if (requesterId == null) {
      return _unauthorized(request);
    }
    final access = await requireAdminAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: requesterId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final target = await _orgRepository.findMembership(orgId: orgId, userId: userId);
    if (target == null) {
      return marketplaceError(
        request,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Member not found',
      );
    }
    final targetRole = (target['role'] as String?)?.toLowerCase() ?? 'member';
    if (targetRole == 'owner') {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'Owner cannot be removed',
      );
    }
    await _orgRepository.removeMember(orgId: orgId, userId: userId);
    return marketplaceOk(
      request,
      data: <String, Object?>{'removed_user_id': userId, 'org_id': orgId},
    );
  }

  Future<Response> _updateMemberRole(
    Request request,
    String orgId,
    String userId,
  ) async {
    final requesterId = _userId(request);
    if (requesterId == null) {
      return _unauthorized(request);
    }
    final access = await requireAdminAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: requesterId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final body = await _readJsonBody(request);
    final role = (body['role'] as String?)?.trim().toLowerCase() ?? '';
    if (!kOrgRoles.contains(role)) {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'role is invalid',
      );
    }
    final target = await _orgRepository.findMembership(orgId: orgId, userId: userId);
    if (target == null) {
      return marketplaceError(
        request,
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Member not found',
      );
    }
    final targetRole = (target['role'] as String?)?.toLowerCase() ?? 'member';
    if (targetRole == 'owner' && role != 'owner') {
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'Owner role cannot be downgraded',
      );
    }
    await _orgRepository.updateMemberRole(orgId: orgId, userId: userId, role: role);
    final updated = await _orgRepository.findMembership(orgId: orgId, userId: userId);
    return marketplaceOk(
      request,
      data: <String, Object?>{'member': _jsonSafe(updated) as Map<String, Object?>},
    );
  }

  Future<Response> _billingPurchases(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final access = await requireBillingAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final purchases = await _marketplaceRepository.listPurchasesByOrg(orgId);
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'purchases': purchases.map(_jsonSafe).toList(growable: false),
      },
    );
  }

  Future<Response> _billingLedger(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final access = await requireBillingAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final purchases = await _marketplaceRepository.listPurchasesByOrg(orgId);
    final entries = <Map<String, Object?>>[];
    for (final purchase in purchases) {
      final purchaseId = (purchase['id'] as String?) ?? '';
      if (purchaseId.isEmpty) {
        continue;
      }
      final rows = await _billingLedgerRepository.listByPurchase(purchaseId);
      for (final row in rows) {
        entries.add(row.toMap());
      }
    }
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'entries': entries.map(_jsonSafe).toList(growable: false),
      },
    );
  }

  Future<Response> _billingEntitlements(Request request, String orgId) async {
    final userId = _userId(request);
    if (userId == null) {
      return _unauthorized(request);
    }
    final access = await requireBillingAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    if (access == null) {
      return forbiddenOrgRole(request);
    }
    final purchases = await _marketplaceRepository.listPurchasesByOrg(orgId);
    final rows = <Map<String, Object?>>[];
    for (final purchase in purchases) {
      final purchaseId = (purchase['id'] as String?) ?? '';
      if (purchaseId.isEmpty) {
        continue;
      }
      final entitlements = await _entitlementService.listByPurchase(purchaseId);
      for (final entitlement in entitlements) {
        rows.add(entitlement.toMap());
      }
    }
    return marketplaceOk(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'entitlements': rows.map(_jsonSafe).toList(growable: false),
      },
    );
  }

  Response _unauthorized(Request request) {
    return marketplaceError(
      request,
      statusCode: 401,
      errorCode: 'UNAUTHORIZED',
      message: 'Missing user context',
    );
  }

  String? _userId(Request request) {
    final userId = (request.requestContext.userId ?? '').trim();
    if (userId.isEmpty) {
      return null;
    }
    return userId;
  }

  Future<Map<String, Object?>> _readJsonBody(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value as Object?));
    }
    return <String, Object?>{};
  }

  String _tokenHash(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  Object? _jsonSafe(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _jsonSafe(item)));
    }
    if (value is List) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    return value;
  }
}
