import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../infra/postgres_provider.dart';
import '../../infra/request_context.dart';
import 'admin_emergency_access_middleware.dart';
import '../http_utils.dart';

Middleware disabledUserMiddleware({
  required Database? db,
  PostgresProvider? postgresProvider,
}) {
  if (db == null && postgresProvider == null) {
    return (Handler innerHandler) => innerHandler;
  }

  return (Handler innerHandler) {
    return (Request request) async {
      if (requestUsedAdminToken(request)) {
        return innerHandler(request);
      }

      final userId = request.requestContext.userId?.trim() ?? '';
      if (userId.isEmpty) {
        return innerHandler(request);
      }

      final isDisabled = db != null
          ? await _isDisabledInSqlite(db, userId)
          : await _isDisabledInPostgres(postgresProvider, userId);
      if (!isDisabled) {
        return innerHandler(request);
      }

      return jsonErrorResponse(
        request,
        403,
        code: 'user_disabled',
        message: 'User account is disabled',
      );
    };
  };
}

Future<bool> _isDisabledInSqlite(Database db, String userId) async {
  try {
    final rows = await db.query(
      'users',
      columns: const <String>['disabled_at'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    final disabledAt = (rows.first['disabled_at'] as String?)?.trim() ?? '';
    return disabledAt.isNotEmpty;
  } on DatabaseException {
    return false;
  }
}

Future<bool> _isDisabledInPostgres(
  PostgresProvider? postgresProvider,
  String userId,
) async {
  if (postgresProvider == null) {
    return false;
  }
  try {
    final rows = await postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT disabled_at
        FROM users
        WHERE id = CAST(@id AS UUID)
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'id': userId},
      ),
    );
    if (rows.isEmpty) {
      return false;
    }
    return rows.first[0] is DateTime;
  } on PostgreSQLException {
    return false;
  }
}
