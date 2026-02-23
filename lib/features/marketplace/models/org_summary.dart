class MarketplaceOrgSummary {
  const MarketplaceOrgSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
    required this.memberStatus,
  });

  final String id;
  final String name;
  final String slug;
  final String role;
  final String memberStatus;

  bool get isActiveMember => memberStatus.toLowerCase() == 'active';

  bool get canManageBilling {
    final normalized = role.toLowerCase();
    return normalized == 'owner' ||
        normalized == 'admin' ||
        normalized == 'billing';
  }

  bool get canManageMembers {
    final normalized = role.toLowerCase();
    return normalized == 'owner' || normalized == 'admin';
  }

  factory MarketplaceOrgSummary.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrgSummary(
      id: (json['id'] ?? json['org_id'] ?? '').toString(),
      name: (json['name'] ?? json['org_name'] ?? 'Team').toString(),
      slug: (json['slug'] ?? '').toString(),
      role:
          (json['role'] ??
                  (json['membership'] is Map
                      ? (json['membership'] as Map)['role']
                      : null) ??
                  'viewer')
              .toString(),
      memberStatus:
          (json['member_status'] ??
                  (json['membership'] is Map
                      ? (json['membership'] as Map)['status']
                      : null) ??
                  'invited')
              .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'slug': slug,
      'role': role,
      'member_status': memberStatus,
    };
  }
}

class MarketplaceInviteResult {
  const MarketplaceInviteResult({
    required this.orgId,
    required this.email,
    required this.role,
    required this.token,
  });

  final String orgId;
  final String email;
  final String role;
  final String token;

  factory MarketplaceInviteResult.fromJson(Map<String, dynamic> json) {
    final inviteRaw = json['invite'];
    final invite = inviteRaw is Map
        ? inviteRaw.map(
            (key, value) => MapEntry<String, dynamic>(key.toString(), value),
          )
        : <String, dynamic>{};
    return MarketplaceInviteResult(
      orgId: (invite['org_id'] ?? json['org_id'] ?? '').toString(),
      email: (invite['email'] ?? json['email'] ?? '').toString(),
      role: (invite['role'] ?? json['role'] ?? 'member').toString(),
      token: (json['token'] ?? '').toString(),
    );
  }
}
