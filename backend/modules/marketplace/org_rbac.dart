import 'package:shelf/shelf.dart';

import 'marketplace_envelope.dart';
import 'org_repository.dart';

const Set<String> kOrgBillingRoles = <String>{'owner', 'admin', 'billing'};
const Set<String> kOrgAdminRoles = <String>{'owner', 'admin'};

Future<Map<String, Object?>?> requireOrgRole({
  required Request request,
  required OrgRepository orgRepository,
  required String orgId,
  required String userId,
  required Set<String> allowedRoles,
}) async {
  final membership = await orgRepository.findMembership(
    orgId: orgId,
    userId: userId,
  );
  if (membership == null) {
    return null;
  }
  final status = (membership['status'] as String?)?.toLowerCase() ?? 'invited';
  final role = (membership['role'] as String?)?.toLowerCase() ?? 'viewer';
  if (status != 'active' || !allowedRoles.contains(role)) {
    return null;
  }
  return membership;
}

Future<Map<String, Object?>?> requireBillingAccess({
  required Request request,
  required OrgRepository orgRepository,
  required String orgId,
  required String userId,
}) {
  return requireOrgRole(
    request: request,
    orgRepository: orgRepository,
    orgId: orgId,
    userId: userId,
    allowedRoles: kOrgBillingRoles,
  );
}

Future<Map<String, Object?>?> requireAdminAccess({
  required Request request,
  required OrgRepository orgRepository,
  required String orgId,
  required String userId,
}) {
  return requireOrgRole(
    request: request,
    orgRepository: orgRepository,
    orgId: orgId,
    userId: userId,
    allowedRoles: kOrgAdminRoles,
  );
}

Response forbiddenOrgRole(Request request) {
  return marketplaceError(
    request,
    statusCode: 403,
    errorCode: 'FORBIDDEN',
    message: 'You do not have permission for this organization',
  );
}
