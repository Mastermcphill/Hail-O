import 'dart:convert';

import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../backend/infra/token_service.dart';
import '../../backend/server/app_server.dart';

class ApiTestHarness {
  ApiTestHarness._({required this.db, required this.handler});

  final Database db;
  final Handler handler;

  static Future<ApiTestHarness> create() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await HailODatabase().openInMemory();
    final tokenService = TokenService(secret: 'test-secret');
    final handler = AppServer(
      db: db,
      tokenService: tokenService,
    ).buildHandler();
    return ApiTestHarness._(db: db, handler: handler);
  }

  Future<void> close() async {
    await db.close();
  }

  Future<ApiResponse> postJson(
    String path, {
    Map<String, Object?> body = const <String, Object?>{},
    String? bearerToken,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (bearerToken != null) {
      headers['authorization'] = 'Bearer $bearerToken';
    }
    if (idempotencyKey != null) {
      headers['idempotency-key'] = idempotencyKey;
    }
    final request = Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    final response = await handler(request);
    return ApiResponse.fromResponse(response);
  }

  Future<ApiResponse> getJson(String path, {String? bearerToken}) async {
    final headers = <String, String>{};
    if (bearerToken != null) {
      headers['authorization'] = 'Bearer $bearerToken';
    }
    final request = Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: headers,
    );
    final response = await handler(request);
    return ApiResponse.fromResponse(response);
  }

  Future<AuthResult> registerAndLogin({
    required String role,
    required String email,
    required String password,
    required String registerIdempotencyKey,
  }) async {
    final registerBody = <String, Object?>{
      'email': email,
      'password': password,
      'role': role,
    };
    if (role == 'rider') {
      registerBody['next_of_kin'] = <String, Object?>{
        'full_name': 'Rider NOK',
        'phone': '+2348000000000',
        'relationship': 'family',
      };
    }
    final register = await postJson(
      '/auth/register',
      body: registerBody,
      idempotencyKey: registerIdempotencyKey,
    );
    final registerResponse = register.requireJsonMap();
    final userId = (registerResponse['user_id'] as String?) ?? '';
    final login = await postJson(
      '/auth/login',
      body: <String, Object?>{'email': email, 'password': password},
    );
    final loginBody = login.requireJsonMap();
    return AuthResult(
      userId: userId,
      token: (loginBody['token'] as String?) ?? '',
      role: (loginBody['role'] as String?) ?? '',
    );
  }
}

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.token,
    required this.role,
  });

  final String userId;
  final String token;
  final String role;
}

class ApiResponse {
  ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  static Future<ApiResponse> fromResponse(Response response) async {
    return ApiResponse(
      statusCode: response.statusCode,
      body: await response.readAsString(),
    );
  }

  Map<String, Object?> requireJsonMap() {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Expected JSON object body, got: $decoded');
    }
    return Map<String, Object?>.from(decoded);
  }
}
