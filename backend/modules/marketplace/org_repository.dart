import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';

const Set<String> kOrgRoles = <String>{
  'owner',
  'admin',
  'billing',
  'member',
  'viewer',
};

const Set<String> kOrgMemberStatuses = <String>{
  'active',
  'invited',
  'suspended',
};

abstract class OrgRepository {
  Future<Map<String, Object?>> ensurePersonalOrg({required String userId});

  Future<List<Map<String, Object?>>> listUserOrgs(String userId);

  Future<List<String>> listActiveOrgIdsForUser(String userId);

  Future<Map<String, Object?>?> findOrgById(String orgId);

  Future<Map<String, Object?>?> findMembership({
    required String orgId,
    required String userId,
  });

  Future<List<Map<String, Object?>>> listMembers(String orgId);

  Future<Map<String, Object?>> createOrg({
    required String ownerUserId,
    required String name,
  });

  Future<Map<String, Object?>?> updateOrgName({
    required String orgId,
    required String name,
  });

  Future<void> upsertMember({
    required String orgId,
    required String userId,
    required String role,
    required String status,
  });

  Future<bool> removeMember({
    required String orgId,
    required String userId,
  });

  Future<bool> updateMemberRole({
    required String orgId,
    required String userId,
    required String role,
  });

  Future<Map<String, Object?>> createInvite({
    required String orgId,
    required String email,
    required String role,
    required String tokenHash,
    required DateTime expiresAtUtc,
  });

  Future<Map<String, Object?>?> findInviteByTokenHash(String tokenHash);

  Future<Map<String, Object?>?> findInviteByOrgAndEmail({
    required String orgId,
    required String email,
  });

  Future<void> markInviteAccepted({
    required String inviteId,
    required String acceptedByUserId,
    required DateTime acceptedAtUtc,
  });

  Future<List<Map<String, Object?>>> listInvitesByOrg(String orgId);
}

class PostgresOrgRepository implements OrgRepository {
  PostgresOrgRepository(this._provider, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final PostgresProvider _provider;
  final Uuid _uuid;

  @override
  Future<Map<String, Object?>> ensurePersonalOrg({required String userId}) async {
    final existing = await _findOwnedOrg(userId);
    if (existing != null) {
      await upsertMember(
        orgId: existing['id'] as String,
        userId: userId,
        role: 'owner',
        status: 'active',
      );
      return existing;
    }
    return createOrg(ownerUserId: userId, name: 'Personal Team');
  }

  @override
  Future<List<Map<String, Object?>>> listUserOrgs(String userId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          o.id,
          o.owner_user_id,
          o.name,
          o.slug,
          o.created_at,
          o.updated_at,
          m.role,
          m.status
        FROM org_members m
        INNER JOIN orgs o ON o.id = m.org_id
        WHERE m.user_id = @user_id
        ORDER BY o.created_at ASC
        ''',
        substitutionValues: <String, Object?>{'user_id': userId},
      ),
    );
    return rows.map(_orgWithMembershipFromRow).toList(growable: false);
  }

  @override
  Future<List<String>> listActiveOrgIdsForUser(String userId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT org_id
        FROM org_members
        WHERE user_id = @user_id AND status = 'active'
        ''',
        substitutionValues: <String, Object?>{'user_id': userId},
      ),
    );
    return rows
        .map((row) => row[0] as String)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> findOrgById(String orgId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, owner_user_id, name, slug, created_at, updated_at
        FROM orgs
        WHERE id = @id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'id': orgId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _orgFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findMembership({
    required String orgId,
    required String userId,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, org_id, user_id, role, status, created_at, updated_at
        FROM org_members
        WHERE org_id = @org_id AND user_id = @user_id
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'org_id': orgId,
          'user_id': userId,
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _memberFromRow(rows.first);
  }

  @override
  Future<List<Map<String, Object?>>> listMembers(String orgId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, org_id, user_id, role, status, created_at, updated_at
        FROM org_members
        WHERE org_id = @org_id
        ORDER BY created_at ASC
        ''',
        substitutionValues: <String, Object?>{'org_id': orgId},
      ),
    );
    return rows.map(_memberFromRow).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> createOrg({
    required String ownerUserId,
    required String name,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final orgId = _uuid.v4();
    final slug = await _uniqueSlug(_slugFromName(name, fallback: ownerUserId));
    await _provider.withTxn((txn) async {
      await txn.execute(
        '''
        INSERT INTO orgs(id, owner_user_id, name, slug, created_at, updated_at)
        VALUES(@id, @owner_user_id, @name, @slug, @created_at, @updated_at)
        ''',
        substitutionValues: <String, Object?>{
          'id': orgId,
          'owner_user_id': ownerUserId,
          'name': _normalizedOrgName(name),
          'slug': slug,
          'created_at': nowUtc,
          'updated_at': nowUtc,
        },
      );
      await txn.execute(
        '''
        INSERT INTO org_members(id, org_id, user_id, role, status, created_at, updated_at)
        VALUES(@id, @org_id, @user_id, 'owner', 'active', @created_at, @updated_at)
        ON CONFLICT (org_id, user_id)
        DO UPDATE SET role = 'owner', status = 'active', updated_at = EXCLUDED.updated_at
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'org_id': orgId,
          'user_id': ownerUserId,
          'created_at': nowUtc,
          'updated_at': nowUtc,
        },
      );
    });
    return (await findOrgById(orgId))!;
  }

  @override
  Future<Map<String, Object?>?> updateOrgName({
    required String orgId,
    required String name,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        UPDATE orgs
        SET name = @name, updated_at = NOW()
        WHERE id = @id
        RETURNING id, owner_user_id, name, slug, created_at, updated_at
        ''',
        substitutionValues: <String, Object?>{
          'id': orgId,
          'name': _normalizedOrgName(name),
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _orgFromRow(rows.first);
  }

  @override
  Future<void> upsertMember({
    required String orgId,
    required String userId,
    required String role,
    required String status,
  }) {
    final normalizedRole = _normalizedRole(role);
    final normalizedStatus = _normalizedMemberStatus(status);
    final nowUtc = DateTime.now().toUtc();
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        INSERT INTO org_members(id, org_id, user_id, role, status, created_at, updated_at)
        VALUES(@id, @org_id, @user_id, @role, @status, @created_at, @updated_at)
        ON CONFLICT (org_id, user_id)
        DO UPDATE SET role = EXCLUDED.role, status = EXCLUDED.status, updated_at = EXCLUDED.updated_at
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'org_id': orgId,
          'user_id': userId,
          'role': normalizedRole,
          'status': normalizedStatus,
          'created_at': nowUtc,
          'updated_at': nowUtc,
        },
      );
    });
  }

  @override
  Future<bool> removeMember({
    required String orgId,
    required String userId,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        DELETE FROM org_members
        WHERE org_id = @org_id AND user_id = @user_id
        RETURNING id
        ''',
        substitutionValues: <String, Object?>{
          'org_id': orgId,
          'user_id': userId,
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> updateMemberRole({
    required String orgId,
    required String userId,
    required String role,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        UPDATE org_members
        SET role = @role, updated_at = NOW()
        WHERE org_id = @org_id AND user_id = @user_id
        RETURNING id
        ''',
        substitutionValues: <String, Object?>{
          'org_id': orgId,
          'user_id': userId,
          'role': _normalizedRole(role),
        },
      ),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Map<String, Object?>> createInvite({
    required String orgId,
    required String email,
    required String role,
    required String tokenHash,
    required DateTime expiresAtUtc,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final inviteId = _uuid.v4();
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO org_invites(
          id,
          org_id,
          email,
          role,
          token_hash,
          expires_at,
          accepted_by_user_id,
          accepted_at,
          created_at
        )
        VALUES(
          @id,
          @org_id,
          @email,
          @role,
          @token_hash,
          @expires_at,
          NULL,
          NULL,
          @created_at
        )
        RETURNING id, org_id, email, role, token_hash, expires_at, accepted_by_user_id, accepted_at, created_at
        ''',
        substitutionValues: <String, Object?>{
          'id': inviteId,
          'org_id': orgId,
          'email': email.toLowerCase().trim(),
          'role': _normalizedRole(role),
          'token_hash': tokenHash,
          'expires_at': expiresAtUtc,
          'created_at': nowUtc,
        },
      ),
    );
    return _inviteFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findInviteByTokenHash(String tokenHash) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, org_id, email, role, token_hash, expires_at, accepted_by_user_id, accepted_at, created_at
        FROM org_invites
        WHERE token_hash = @token_hash
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'token_hash': tokenHash},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _inviteFromRow(rows.first);
  }

  @override
  Future<Map<String, Object?>?> findInviteByOrgAndEmail({
    required String orgId,
    required String email,
  }) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, org_id, email, role, token_hash, expires_at, accepted_by_user_id, accepted_at, created_at
        FROM org_invites
        WHERE org_id = @org_id AND email = @email
        ORDER BY created_at DESC
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'org_id': orgId,
          'email': email.toLowerCase().trim(),
        },
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _inviteFromRow(rows.first);
  }

  @override
  Future<void> markInviteAccepted({
    required String inviteId,
    required String acceptedByUserId,
    required DateTime acceptedAtUtc,
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        '''
        UPDATE org_invites
        SET accepted_by_user_id = @accepted_by_user_id, accepted_at = @accepted_at
        WHERE id = @id
        ''',
        substitutionValues: <String, Object?>{
          'id': inviteId,
          'accepted_by_user_id': acceptedByUserId,
          'accepted_at': acceptedAtUtc,
        },
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> listInvitesByOrg(String orgId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, org_id, email, role, token_hash, expires_at, accepted_by_user_id, accepted_at, created_at
        FROM org_invites
        WHERE org_id = @org_id
        ORDER BY created_at DESC
        ''',
        substitutionValues: <String, Object?>{'org_id': orgId},
      ),
    );
    return rows.map(_inviteFromRow).toList(growable: false);
  }

  Future<Map<String, Object?>?> _findOwnedOrg(String userId) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id, owner_user_id, name, slug, created_at, updated_at
        FROM orgs
        WHERE owner_user_id = @owner_user_id
        ORDER BY created_at ASC
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'owner_user_id': userId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _orgFromRow(rows.first);
  }

  Future<String> _uniqueSlug(String baseSlug) async {
    var candidate = baseSlug;
    var counter = 1;
    while (await _slugExists(candidate)) {
      candidate = '$baseSlug-$counter';
      counter += 1;
    }
    return candidate;
  }

  Future<bool> _slugExists(String slug) async {
    final rows = await _provider.withConnection(
      (connection) => connection.query(
        'SELECT 1 FROM orgs WHERE slug = @slug LIMIT 1',
        substitutionValues: <String, Object?>{'slug': slug},
      ),
    );
    return rows.isNotEmpty;
  }

  Map<String, Object?> _orgFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'owner_user_id': row[1] as String,
    'name': (row[2] as String?) ?? 'Team',
    'slug': (row[3] as String?) ?? '',
    'created_at': ((row[4] as DateTime?) ?? DateTime.now()).toUtc(),
    'updated_at': ((row[5] as DateTime?) ?? DateTime.now()).toUtc(),
  };

  Map<String, Object?> _orgWithMembershipFromRow(List<Object?> row) =>
      <String, Object?>{
        'id': row[0] as String,
        'owner_user_id': row[1] as String,
        'name': (row[2] as String?) ?? 'Team',
        'slug': (row[3] as String?) ?? '',
        'created_at': ((row[4] as DateTime?) ?? DateTime.now()).toUtc(),
        'updated_at': ((row[5] as DateTime?) ?? DateTime.now()).toUtc(),
        'role': (row[6] as String?) ?? 'viewer',
        'member_status': (row[7] as String?) ?? 'invited',
      };

  Map<String, Object?> _memberFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'org_id': row[1] as String,
    'user_id': row[2] as String,
    'role': (row[3] as String?) ?? 'member',
    'status': (row[4] as String?) ?? 'active',
    'created_at': ((row[5] as DateTime?) ?? DateTime.now()).toUtc(),
    'updated_at': ((row[6] as DateTime?) ?? DateTime.now()).toUtc(),
  };

  Map<String, Object?> _inviteFromRow(List<Object?> row) => <String, Object?>{
    'id': row[0] as String,
    'org_id': row[1] as String,
    'email': (row[2] as String?) ?? '',
    'role': (row[3] as String?) ?? 'member',
    'token_hash': (row[4] as String?) ?? '',
    'expires_at': ((row[5] as DateTime?) ?? DateTime.now()).toUtc(),
    'accepted_by_user_id': row[6] as String?,
    'accepted_at': (row[7] as DateTime?)?.toUtc(),
    'created_at': ((row[8] as DateTime?) ?? DateTime.now()).toUtc(),
  };
}

class InMemoryOrgRepository implements OrgRepository {
  InMemoryOrgRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final Map<String, Map<String, Object?>> _orgs = <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _membersByKey =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _invitesById =
      <String, Map<String, Object?>>{};
  final Map<String, String> _inviteIdByTokenHash = <String, String>{};

  @override
  Future<Map<String, Object?>> ensurePersonalOrg({required String userId}) async {
    for (final org in _orgs.values) {
      if (org['owner_user_id'] == userId) {
        await upsertMember(
          orgId: org['id'] as String,
          userId: userId,
          role: 'owner',
          status: 'active',
        );
        return Map<String, Object?>.from(org);
      }
    }
    return createOrg(ownerUserId: userId, name: 'Personal Team');
  }

  @override
  Future<List<Map<String, Object?>>> listUserOrgs(String userId) async {
    final rows = <Map<String, Object?>>[];
    for (final member in _membersByKey.values) {
      if (member['user_id'] != userId) {
        continue;
      }
      final org = _orgs[member['org_id']];
      if (org == null) {
        continue;
      }
      rows.add(<String, Object?>{
        ...org,
        'role': member['role'],
        'member_status': member['status'],
      });
    }
    rows.sort((a, b) {
      final left = (a['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = (b['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }

  @override
  Future<List<String>> listActiveOrgIdsForUser(String userId) async {
    final orgIds = <String>{};
    for (final member in _membersByKey.values) {
      if (member['user_id'] == userId && member['status'] == 'active') {
        orgIds.add(member['org_id'] as String);
      }
    }
    return orgIds.toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> findOrgById(String orgId) async {
    final org = _orgs[orgId];
    return org == null ? null : Map<String, Object?>.from(org);
  }

  @override
  Future<Map<String, Object?>?> findMembership({
    required String orgId,
    required String userId,
  }) async {
    final member = _membersByKey[_memberKey(orgId: orgId, userId: userId)];
    return member == null ? null : Map<String, Object?>.from(member);
  }

  @override
  Future<List<Map<String, Object?>>> listMembers(String orgId) async {
    final members = _membersByKey.values
        .where((row) => row['org_id'] == orgId)
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    members.sort((a, b) {
      final left = (a['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = (b['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
    return members;
  }

  @override
  Future<Map<String, Object?>> createOrg({
    required String ownerUserId,
    required String name,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final orgId = _uuid.v4();
    final slug = await _uniqueSlug(_slugFromName(name, fallback: ownerUserId));
    final org = <String, Object?>{
      'id': orgId,
      'owner_user_id': ownerUserId,
      'name': _normalizedOrgName(name),
      'slug': slug,
      'created_at': nowUtc,
      'updated_at': nowUtc,
    };
    _orgs[orgId] = org;
    await upsertMember(
      orgId: orgId,
      userId: ownerUserId,
      role: 'owner',
      status: 'active',
    );
    return Map<String, Object?>.from(org);
  }

  @override
  Future<Map<String, Object?>?> updateOrgName({
    required String orgId,
    required String name,
  }) async {
    final org = _orgs[orgId];
    if (org == null) {
      return null;
    }
    org['name'] = _normalizedOrgName(name);
    org['updated_at'] = DateTime.now().toUtc();
    return Map<String, Object?>.from(org);
  }

  @override
  Future<void> upsertMember({
    required String orgId,
    required String userId,
    required String role,
    required String status,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final key = _memberKey(orgId: orgId, userId: userId);
    final existing = _membersByKey[key];
    _membersByKey[key] = <String, Object?>{
      'id': existing?['id'] ?? _uuid.v4(),
      'org_id': orgId,
      'user_id': userId,
      'role': _normalizedRole(role),
      'status': _normalizedMemberStatus(status),
      'created_at': existing?['created_at'] ?? nowUtc,
      'updated_at': nowUtc,
    };
  }

  @override
  Future<bool> removeMember({
    required String orgId,
    required String userId,
  }) async {
    return _membersByKey.remove(_memberKey(orgId: orgId, userId: userId)) != null;
  }

  @override
  Future<bool> updateMemberRole({
    required String orgId,
    required String userId,
    required String role,
  }) async {
    final key = _memberKey(orgId: orgId, userId: userId);
    final existing = _membersByKey[key];
    if (existing == null) {
      return false;
    }
    existing['role'] = _normalizedRole(role);
    existing['updated_at'] = DateTime.now().toUtc();
    return true;
  }

  @override
  Future<Map<String, Object?>> createInvite({
    required String orgId,
    required String email,
    required String role,
    required String tokenHash,
    required DateTime expiresAtUtc,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final id = _uuid.v4();
    final invite = <String, Object?>{
      'id': id,
      'org_id': orgId,
      'email': email.toLowerCase().trim(),
      'role': _normalizedRole(role),
      'token_hash': tokenHash,
      'expires_at': expiresAtUtc,
      'accepted_by_user_id': null,
      'accepted_at': null,
      'created_at': nowUtc,
    };
    _invitesById[id] = invite;
    _inviteIdByTokenHash[tokenHash] = id;
    return Map<String, Object?>.from(invite);
  }

  @override
  Future<Map<String, Object?>?> findInviteByTokenHash(String tokenHash) async {
    final inviteId = _inviteIdByTokenHash[tokenHash];
    if (inviteId == null) {
      return null;
    }
    final invite = _invitesById[inviteId];
    return invite == null ? null : Map<String, Object?>.from(invite);
  }

  @override
  Future<Map<String, Object?>?> findInviteByOrgAndEmail({
    required String orgId,
    required String email,
  }) async {
    Map<String, Object?>? found;
    for (final invite in _invitesById.values) {
      if (invite['org_id'] == orgId &&
          (invite['email'] as String?) == email.toLowerCase().trim()) {
        if (found == null) {
          found = invite;
          continue;
        }
        final foundCreated = (found['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final inviteCreated = (invite['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (inviteCreated.isAfter(foundCreated)) {
          found = invite;
        }
      }
    }
    return found == null ? null : Map<String, Object?>.from(found);
  }

  @override
  Future<void> markInviteAccepted({
    required String inviteId,
    required String acceptedByUserId,
    required DateTime acceptedAtUtc,
  }) async {
    final invite = _invitesById[inviteId];
    if (invite == null) {
      return;
    }
    invite['accepted_by_user_id'] = acceptedByUserId;
    invite['accepted_at'] = acceptedAtUtc;
  }

  @override
  Future<List<Map<String, Object?>>> listInvitesByOrg(String orgId) async {
    final invites = _invitesById.values
        .where((invite) => invite['org_id'] == orgId)
        .map((invite) => Map<String, Object?>.from(invite))
        .toList(growable: false);
    invites.sort((a, b) {
      final left = (a['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = (b['created_at'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return invites;
  }

  Future<String> _uniqueSlug(String baseSlug) async {
    var candidate = baseSlug;
    var counter = 1;
    while (_orgs.values.any((org) => org['slug'] == candidate)) {
      candidate = '$baseSlug-$counter';
      counter += 1;
    }
    return candidate;
  }

  String _memberKey({required String orgId, required String userId}) =>
      '$orgId|$userId';
}

String _normalizedOrgName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Team';
  }
  return trimmed;
}

String _slugFromName(String raw, {required String fallback}) {
  final normalized = raw.toLowerCase().trim();
  final cleaned = normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+'), '')
      .replaceAll(RegExp(r'-+$'), '');
  if (cleaned.isNotEmpty) {
    return cleaned;
  }
  final fallbackRaw = fallback.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (fallbackRaw.isNotEmpty) {
    return 'team-$fallbackRaw';
  }
  return 'team';
}

String _normalizedRole(String role) {
  final normalized = role.trim().toLowerCase();
  if (kOrgRoles.contains(normalized)) {
    return normalized;
  }
  return 'member';
}

String _normalizedMemberStatus(String status) {
  final normalized = status.trim().toLowerCase();
  if (kOrgMemberStatuses.contains(normalized)) {
    return normalized;
  }
  return 'active';
}

String encodeInviteTokenPayload(Map<String, Object?> payload) {
  return base64Url.encode(utf8.encode(jsonEncode(payload)));
}

Map<String, Object?> decodeInviteTokenPayload(String token) {
  final decoded = utf8.decode(base64Url.decode(base64Url.normalize(token)));
  final raw = jsonDecode(decoded);
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value as Object?));
  }
  return <String, Object?>{};
}
