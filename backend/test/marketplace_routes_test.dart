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

  test('marketplace endpoints and admin debug/reconcile are wired', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = AppServer(
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

    final riderToken = await _registerAndLogin(
      handler,
      email: 'market.rider@example.com',
      role: 'rider',
      idSuffix: 'market-rider',
    );
    final adminToken = await _registerAndLogin(
      handler,
      email: 'market.admin@example.com',
      role: 'admin',
      idSuffix: 'market-admin',
    );

    final offersResponse = await _request(
      handler,
      method: 'GET',
      path: '/marketplace/offers',
      token: riderToken,
    );
    expect(offersResponse.statusCode, 200);
    final offersBody = await _decodeBody(offersResponse);
    expect(offersBody['ok'], true);
    expect((offersBody['trace_id'] as String?)?.isNotEmpty, isTrue);
    final offers = (offersBody['data'] as List?) ?? const <Object?>[];
    expect(offers, isNotEmpty);
    final offer = Map<String, Object?>.from(offers.first as Map);
    final offerId = (offer['id'] as String?) ?? '';
    expect(offerId.isNotEmpty, isTrue);

    final createPurchase = await _request(
      handler,
      method: 'POST',
      path: '/marketplace/purchases',
      token: riderToken,
      idempotencyKey: 'marketplace-purchase-idem-1',
      body: <String, Object?>{'offerId': offerId, 'seatCount': 3},
    );
    expect(createPurchase.statusCode, 201);
    final createBody = await _decodeBody(createPurchase);
    expect(createBody['ok'], true);
    final createdData = Map<String, Object?>.from(
      createBody['data'] as Map<String, Object?>,
    );
    final purchaseId = (createdData['purchaseId'] as String?) ?? '';
    expect(purchaseId.isNotEmpty, isTrue);

    final replayPurchase = await _request(
      handler,
      method: 'POST',
      path: '/marketplace/purchases',
      token: riderToken,
      idempotencyKey: 'marketplace-purchase-idem-1',
      body: <String, Object?>{'offerId': offerId, 'seatCount': 3},
    );
    expect(replayPurchase.statusCode, 200);
    final replayBody = await _decodeBody(replayPurchase);
    final replayData = Map<String, Object?>.from(
      replayBody['data'] as Map<String, Object?>,
    );
    expect(replayData['purchaseId'], purchaseId);
    expect(replayData['replayed'], true);

    final riderDebug = await _request(
      handler,
      method: 'GET',
      path: '/admin/marketplace/purchases/$purchaseId/debug',
      token: riderToken,
    );
    expect(riderDebug.statusCode, 403);

    final debugResponse = await _request(
      handler,
      method: 'GET',
      path: '/admin/marketplace/purchases/$purchaseId/debug',
      token: adminToken,
    );
    expect(debugResponse.statusCode, 200);
    final debugBody = await _decodeBody(debugResponse);
    expect(debugBody['ok'], true);
    final debugData = Map<String, Object?>.from(debugBody['data'] as Map);
    expect(debugData.containsKey('purchase'), isTrue);
    expect(debugData.containsKey('entitlements'), isTrue);
    expect(debugData.containsKey('ledger_entries'), isTrue);
    expect(debugData.containsKey('timeline'), isTrue);
    expect(debugData.containsKey('reconciliation'), isTrue);

    final reconcileResponse = await _request(
      handler,
      method: 'POST',
      path: '/admin/marketplace/purchases/$purchaseId/reconcile',
      token: adminToken,
      idempotencyKey: 'admin-reconcile-1',
      body: const <String, Object?>{},
    );
    expect(reconcileResponse.statusCode, 200);
    final reconcileBody = await _decodeBody(reconcileResponse);
    expect(reconcileBody['ok'], true);
    final reconcileData = Map<String, Object?>.from(
      reconcileBody['data'] as Map,
    );
    final reconciliation = Map<String, Object?>.from(
      reconcileData['reconciliation'] as Map,
    );
    expect(reconciliation['purchase_id'], purchaseId);
  });
}

Future<String> _registerAndLogin(
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
  return token;
}

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
    headers['idempotency-key'] = idempotencyKey;
  }
  final response = await handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body == null ? '' : jsonEncode(body),
    ),
  );
  return response;
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
