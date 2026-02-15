import 'package:hail_o_finance_core/sqlite_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import '../infra/token_service.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/error_middleware.dart';
import 'middleware/idempotency_middleware.dart';
import 'middleware/trace_middleware.dart';
import 'router.dart';

class AppServer {
  const AppServer({required this.db, required this.tokenService});

  final Database db;
  final TokenService tokenService;

  Handler buildHandler() {
    final router = buildApiRouter(db: db, tokenService: tokenService);
    return Pipeline()
        .addMiddleware(errorMiddleware())
        .addMiddleware(traceMiddleware())
        .addMiddleware(corsHeaders())
        .addMiddleware(idempotencyMiddleware())
        .addMiddleware(authMiddleware(tokenService))
        .addHandler(router);
  }
}
