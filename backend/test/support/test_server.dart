import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../lib/data/sqlite/hailo_database.dart';
import '../../infra/request_metrics.dart';
import '../../infra/token_service.dart';
import '../../server/app_server.dart';
import 'test_client.dart';

class BackendTestServer {
  BackendTestServer._({required this.db, required this.handler});

  static bool _sqliteReady = false;

  final Database db;
  final Handler handler;

  static Future<BackendTestServer> create({
    Map<String, String> environmentMap = const <String, String>{'ENV': 'test'},
  }) async {
    _ensureSqliteReady();
    final db = await HailODatabase().openInMemory();
    final handler = AppServer(
      db: db,
      tokenService: TokenService(secret: 'backend-test-secret'),
      dbMode: 'sqlite',
      environment: environmentMap['ENV'] ?? 'test',
      requestMetrics: RequestMetrics(),
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{
        'commit': 'test',
        'runtime': 'test',
        'migration_head': 27,
      },
      runtimeConfigSnapshot: const <String, Object?>{},
      environmentMap: environmentMap,
      rateLimitEnabled: false,
    ).buildHandler();
    return BackendTestServer._(db: db, handler: handler);
  }

  Future<void> seedUser({
    required String userId,
    required String role,
    bool isBlocked = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('users', <String, Object?>{
      'id': userId,
      'role': role,
      'is_blocked': isBlocked ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BackendTestClient> createDriverClient({
    String userId = 'driver_http_smoke',
    String traceId = 'trace-autosave-smoke',
  }) async {
    await seedUser(userId: userId, role: 'driver');
    return BackendTestClient(
      handler: handler,
      userId: userId,
      role: 'driver',
      traceId: traceId,
    );
  }

  Future<void> close() async {
    await db.close();
  }

  static void _ensureSqliteReady() {
    if (_sqliteReady) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _sqliteReady = true;
  }
}
