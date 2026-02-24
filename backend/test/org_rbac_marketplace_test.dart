import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/sqlite_auth_credentials_store.dart';
import '../modules/rides/sqlite_operational_record_store.dart';
import '../modules/rides/sqlite_ride_request_metadata_store.dart';
import '../server/app_server.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('member cannot change seats but billing role can change plan', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final owner = await _registerAndLogin(
      handler,
      email: 'org-owner@example.com',
      role: 'rider',
      idSuffix: 'org-owner',
    );
    final member = await _registerAndLogin(
      handler,
      email: 'org-member@example.com',
      role: 'rider',
      idSuffix: 'org-member',
    );
    final billing = await _registerAndLogin(
      handler,
      email: 'org-billing@example.com',
      role: 'rider',
      idSuffix: 'org-billing',
    );

    final createOrg = await _request(
      handler,
      method: 'POST',
      path: '/api/orgs',
      token: owner.token,
      idempotencyKey: 'create-org-1',
      body: <String, Object?>{'name': 'Alpha Team'},
    );
    expect(createOrg.statusCode, 201);
    final createOrgBody = await _decodeBody(createOrg);
    final orgData = Map<String, Object?>.from(createOrgBody['data'] as Map);
    final org = Map<String, Object?>.from(orgData['org'] as Map);
    final orgId = (org['id'] as String?) ?? '';
    expect(orgId.isNotEmpty, isTrue);

    final memberInvite = await _request(
      handler,
      method: 'POST',
      path: '/api/orgs/$orgId/invites',
      token: owner.token,
      idempotencyKey: 'invite-member-1',
      body: <String, Object?>{
        'email': 'org-member@example.com',
        'role': 'member',
      },
    );
    expect(memberInvite.statusCode, 201);
    final memberInviteBody = await _decodeBody(memberInvite);
    final memberInviteData = Map<String, Object?>.from(
      memberInviteBody['data'] as Map,
    );
    final memberInviteToken = (memberInviteData['token'] as String?) ?? '';
    expect(memberInviteToken.isNotEmpty, isTrue);

    final memberAccept = await _request(
      handler,
      method: 'POST',
      path: '/api/orgs/invites/accept',
      token: member.token,
      idempotencyKey: 'accept-member-1',
      body: <String, Object?>{'token': memberInviteToken},
    );
    expect(memberAccept.statusCode, 200);

    final billingInvite = await _request(
      handler,
      method: 'POST',
      path: '/api/orgs/$orgId/invites',
      token: owner.token,
      idempotencyKey: 'invite-billing-1',
      body: <String, Object?>{
        'email': 'org-billing@example.com',
        'role': 'billing',
      },
    );
    expect(billingInvite.statusCode, 201);
    final billingInviteBody = await _decodeBody(billingInvite);
    final billingInviteData = Map<String, Object?>.from(
      billingInviteBody['data'] as Map,
    );
    final billingInviteToken = (billingInviteData['token'] as String?) ?? '';
    expect(billingInviteToken.isNotEmpty, isTrue);

    final billingAccept = await _request(
      handler,
      method: 'POST',
      path: '/api/orgs/invites/accept',
      token: billing.token,
      idempotencyKey: 'accept-billing-1',
      body: <String, Object?>{'token': billingInviteToken},
    );
    expect(billingAccept.statusCode, 200);

    final offers = await _request(
      handler,
      method: 'GET',
      path: '/marketplace/offers',
      token: owner.token,
    );
    expect(offers.statusCode, 200);
    final offersBody = await _decodeBody(offers);
    final offersList = (offersBody['data'] as List?) ?? const <Object?>[];
    expect(offersList, isNotEmpty);
    final starterOffer = Map<String, Object?>.from(offersList.first as Map);
    final starterOfferId = (starterOffer['id'] as String?) ?? '';
    expect(starterOfferId, isNotEmpty);
    final nextOffer = offersList.length > 1
        ? Map<String, Object?>.from(offersList[1] as Map)
        : starterOffer;
    final nextOfferId = (nextOffer['id'] as String?) ?? starterOfferId;

    final createPurchase = await _request(
      handler,
      method: 'POST',
      path: '/marketplace/purchases',
      token: owner.token,
      idempotencyKey: 'org-purchase-idem-1',
      body: <String, Object?>{
        'offerId': starterOfferId,
        'seatCount': 3,
        'orgId': orgId,
      },
    );
    expect(createPurchase.statusCode, anyOf(200, 201));
    final createPurchaseBody = await _decodeBody(createPurchase);
    final purchaseData = Map<String, Object?>.from(
      createPurchaseBody['data'] as Map,
    );
    final purchaseId = (purchaseData['purchaseId'] as String?) ?? '';
    final purchaseVersion = (purchaseData['version'] as num?)?.toInt() ?? 1;
    expect(purchaseId.isNotEmpty, isTrue);
    expect((purchaseData['org_id'] as String?) ?? '', orgId);

    final memberSeatUpdate = await _request(
      handler,
      method: 'PATCH',
      path: '/marketplace/purchases/$purchaseId/seats',
      token: member.token,
      extraHeaders: <String, String>{'if-match-version': '$purchaseVersion'},
      body: <String, Object?>{'seatCount': 2},
    );
    expect(memberSeatUpdate.statusCode, 403);
    final memberSeatBody = await _decodeBody(memberSeatUpdate);
    expect(memberSeatBody['error_code'], 'FORBIDDEN');

    final billingChangePlan = await _request(
      handler,
      method: 'POST',
      path: '/marketplace/purchases/$purchaseId/change-plan',
      token: billing.token,
      idempotencyKey: 'billing-change-plan-1',
      extraHeaders: <String, String>{'if-match-version': '$purchaseVersion'},
      body: <String, Object?>{'offerId': nextOfferId},
    );
    expect(billingChangePlan.statusCode, 200);
    final billingBody = await _decodeBody(billingChangePlan);
    final billingData = Map<String, Object?>.from(billingBody['data'] as Map);
    expect((billingData['offerId'] as String?) ?? '', nextOfferId);
  });

  test(
    'cannot assign seat to non-member, invite accept activates membership, and restore works via org access',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      final handler = _buildHandler(db);

      final owner = await _registerAndLogin(
        handler,
        email: 'rbac-owner@example.com',
        role: 'rider',
        idSuffix: 'rbac-owner',
      );
      final member = await _registerAndLogin(
        handler,
        email: 'rbac-member@example.com',
        role: 'rider',
        idSuffix: 'rbac-member',
      );

      final createOrg = await _request(
        handler,
        method: 'POST',
        path: '/api/orgs',
        token: owner.token,
        idempotencyKey: 'create-org-2',
        body: <String, Object?>{'name': 'Beta Team'},
      );
      expect(createOrg.statusCode, 201);
      final createOrgBody = await _decodeBody(createOrg);
      final orgData = Map<String, Object?>.from(createOrgBody['data'] as Map);
      final org = Map<String, Object?>.from(orgData['org'] as Map);
      final orgId = (org['id'] as String?) ?? '';
      expect(orgId.isNotEmpty, isTrue);

      final invite = await _request(
        handler,
        method: 'POST',
        path: '/api/orgs/$orgId/invites',
        token: owner.token,
        idempotencyKey: 'invite-rbac-member-1',
        body: <String, Object?>{
          'email': 'rbac-member@example.com',
          'role': 'member',
        },
      );
      expect(invite.statusCode, 201);
      final inviteBody = await _decodeBody(invite);
      final inviteData = Map<String, Object?>.from(inviteBody['data'] as Map);
      final inviteToken = (inviteData['token'] as String?) ?? '';
      expect(inviteToken.isNotEmpty, isTrue);

      final acceptInvite = await _request(
        handler,
        method: 'POST',
        path: '/api/orgs/invites/accept',
        token: member.token,
        idempotencyKey: 'accept-rbac-member-1',
        body: <String, Object?>{'token': inviteToken},
      );
      expect(acceptInvite.statusCode, 200);

      final membersResponse = await _request(
        handler,
        method: 'GET',
        path: '/api/orgs/$orgId/members',
        token: owner.token,
      );
      expect(membersResponse.statusCode, 200);
      final membersBody = await _decodeBody(membersResponse);
      final membersData = Map<String, Object?>.from(membersBody['data'] as Map);
      final members = (membersData['members'] as List?) ?? const <Object?>[];
      final memberRow = members
          .whereType<Map>()
          .map((entry) => Map<String, Object?>.from(entry))
          .firstWhere((entry) => entry['user_id'] == member.userId);
      expect(memberRow['status'], 'active');

      final offers = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/offers',
        token: owner.token,
      );
      expect(offers.statusCode, 200);
      final offersBody = await _decodeBody(offers);
      final offerId =
          (((offersBody['data'] as List).first as Map)['id'] as String?) ?? '';
      expect(offerId.isNotEmpty, isTrue);

      final createPurchase = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        token: owner.token,
        idempotencyKey: 'org-purchase-idem-2',
        body: <String, Object?>{
          'offerId': offerId,
          'seatCount': 2,
          'orgId': orgId,
        },
      );
      expect(createPurchase.statusCode, anyOf(200, 201));
      final createPurchaseBody = await _decodeBody(createPurchase);
      final purchaseData = Map<String, Object?>.from(
        createPurchaseBody['data'] as Map,
      );
      final purchaseId = (purchaseData['purchaseId'] as String?) ?? '';
      final purchaseVersion = (purchaseData['version'] as num?)?.toInt() ?? 1;
      expect(purchaseId.isNotEmpty, isTrue);

      final badAssignments = await _request(
        handler,
        method: 'PATCH',
        path: '/marketplace/purchases/$purchaseId/assignments',
        token: owner.token,
        extraHeaders: <String, String>{'if-match-version': '$purchaseVersion'},
        body: <String, Object?>{
          'assignments': <Map<String, Object?>>[
            <String, Object?>{'seat_index': 1, 'user_id': 'not-a-member-user'},
          ],
        },
      );
      expect(badAssignments.statusCode, 400);
      final badAssignmentsBody = await _decodeBody(badAssignments);
      expect(badAssignmentsBody['error_code'], 'INVALID_ASSIGNEE');

      final restoreByMember = await _request(
        handler,
        method: 'GET',
        path:
            '/marketplace/purchases/restore?idempotencyKey=${Uri.encodeQueryComponent('org-purchase-idem-2')}',
        token: member.token,
      );
      expect(restoreByMember.statusCode, 200);
      final restoreBody = await _decodeBody(restoreByMember);
      final restoreData = Map<String, Object?>.from(restoreBody['data'] as Map);
      expect((restoreData['purchaseId'] as String?) ?? '', purchaseId);
      expect((restoreData['org_id'] as String?) ?? '', orgId);
    },
  );
}

class _AuthUser {
  const _AuthUser({
    required this.userId,
    required this.token,
    required this.email,
  });

  final String userId;
  final String token;
  final String email;
}

Handler _buildHandler(dynamic db) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'sqlite',
    environment: 'test',
    requestMetrics: RequestMetrics(),
    dbHealthCheck: () async => true,
    buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
    environmentMap: const <String, String>{
      'PAYMENT_PROVIDER': 'manual',
      'PAYMENT_WEBHOOK_SECRET': 'manual-secret',
    },
  ).buildHandler();
}

Future<_AuthUser> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String idSuffix,
}) async {
  final register = await _request(
    handler,
    method: 'POST',
    path: '/auth/register',
    idempotencyKey: 'register-$idSuffix',
    body: <String, Object?>{
      'email': email,
      'password': 'SuperSecret123',
      'role': role,
    },
  );
  expect(register.statusCode, 201);
  final registerBody = await _decodeBody(register);
  final userId = (registerBody['user_id'] as String?) ?? '';
  expect(userId.isNotEmpty, isTrue);

  final login = await _request(
    handler,
    method: 'POST',
    path: '/auth/login',
    body: <String, Object?>{'email': email, 'password': 'SuperSecret123'},
  );
  expect(login.statusCode, 200);
  final loginBody = await _decodeBody(login);
  final token = (loginBody['token'] as String?) ?? '';
  expect(token.isNotEmpty, isTrue);
  return _AuthUser(userId: userId, token: token, email: email);
}

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, String>? extraHeaders,
  Map<String, Object?>? body,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
    headers['idempotency-key'] = idempotencyKey;
  }
  if (extraHeaders != null && extraHeaders.isNotEmpty) {
    headers.addAll(extraHeaders);
  }
  return handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body == null ? '' : jsonEncode(body),
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final raw = await response.readAsString();
  if (raw.trim().isEmpty) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
