import 'dart:collection';

import 'package:pool/pool.dart';
import 'package:postgres/postgres.dart';

class PostgresProvider {
  PostgresProvider(this.databaseUrl, {int poolSize = 4})
    : _poolSize = poolSize > 0 ? poolSize : 1;

  final String databaseUrl;
  final int _poolSize;
  late final Pool _pool = Pool(_poolSize);
  final Queue<PostgreSQLConnection> _connectionQueue =
      Queue<PostgreSQLConnection>();
  final List<PostgreSQLConnection> _allConnections = <PostgreSQLConnection>[];
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }

    final count = _poolSize;
    for (var index = 0; index < count; index++) {
      final connection = await _openConnection();
      _allConnections.add(connection);
      _connectionQueue.add(connection);
    }
    _initialized = true;
  }

  Future<PostgreSQLConnection> _openConnection() async {
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
    return connection;
  }

  Future<T> withConnection<T>(
    Future<T> Function(PostgreSQLConnection connection) action,
  ) async {
    await _initialize();
    return _pool.withResource(() async {
      final connection = _connectionQueue.removeFirst();
      try {
        return await action(connection);
      } finally {
        _connectionQueue.addLast(connection);
      }
    });
  }

  Future<PostgreSQLConnection> open() {
    return _openForReadiness();
  }

  Future<PostgreSQLConnection> _openForReadiness() async {
    await _initialize();
    return _allConnections.first;
  }

  Future<T> withTxn<T>(
    Future<T> Function(PostgreSQLExecutionContext ctx) action,
  ) {
    return withConnection<T>((connection) async {
      final result = await connection.transaction((ctx) => action(ctx));
      return result as T;
    });
  }

  Future<void> close() async {
    for (final connection in _allConnections) {
      if (!connection.isClosed) {
        await connection.close();
      }
    }
    _connectionQueue.clear();
    _allConnections.clear();
    _initialized = false;
    await _pool.close();
  }
}
