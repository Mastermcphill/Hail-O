import 'package:postgres/postgres.dart';

class PostgresProvider {
  PostgresProvider(this.databaseUrl);

  final String databaseUrl;
  PostgreSQLConnection? _connection;

  Future<PostgreSQLConnection> open() async {
    if (_connection != null && !(_connection?.isClosed ?? true)) {
      return _connection!;
    }

    final uri = Uri.parse(databaseUrl);
    final userInfoSeparator = uri.userInfo.indexOf(':');
    final username = userInfoSeparator < 0
        ? Uri.decodeComponent(uri.userInfo)
        : Uri.decodeComponent(uri.userInfo.substring(0, userInfoSeparator));
    final password = userInfoSeparator < 0
        ? ''
        : Uri.decodeComponent(uri.userInfo.substring(userInfoSeparator + 1));
    final databaseName = uri.pathSegments.isEmpty
        ? 'postgres'
        : uri.pathSegments.first;
    final sslMode = uri.queryParameters['sslmode']?.toLowerCase();
    final useSsl = sslMode == 'require' || sslMode == 'verify-full';

    final connection = PostgreSQLConnection(
      uri.host,
      uri.hasPort ? uri.port : 5432,
      databaseName,
      username: username,
      password: password,
      useSSL: useSsl,
    );
    await connection.open();
    _connection = connection;
    return connection;
  }

  Future<T> withTxn<T>(
    Future<T> Function(PostgreSQLExecutionContext ctx) action,
  ) async {
    final connection = await open();
    final result = await connection.transaction((ctx) => action(ctx));
    return result as T;
  }

  Future<void> close() async {
    final connection = _connection;
    if (connection != null && !connection.isClosed) {
      await connection.close();
    }
    _connection = null;
  }
}
