import 'dart:collection';

import 'package:pool/pool.dart';
import 'package:postgres/postgres.dart';

class PostgresProvider {
  PostgresProvider(
    this.databaseUrl, {
    int poolSize = 4,
    String dbSchema = 'hailo_prod',
    int statementTimeoutMs = 10000,
  }) : _poolSize = poolSize > 0 ? poolSize : 1,
       dbSchema = _normalizeSchema(dbSchema),
       statementTimeoutMs = statementTimeoutMs > 0 ? statementTimeoutMs : 10000;

  final String databaseUrl;
  final String dbSchema;
  final int statementTimeoutMs;
  final int _poolSize;
  late final Pool _pool = Pool(_poolSize);
  final Queue<PostgreSQLConnection> _connectionQueue =
      Queue<PostgreSQLConnection>();
  final List<PostgreSQLConnection> _allConnections = <PostgreSQLConnection>[];
  bool _initialized = false;
  static final RegExp _schemaPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static String _normalizeSchema(String schema) {
    final trimmed = schema.trim();
    if (trimmed.isEmpty || !_schemaPattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
        schema,
        'dbSchema',
        'Schema must match ^[A-Za-z_][A-Za-z0-9_]*\$',
      );
    }
    return trimmed;
  }

  String get _quotedSchema => '"${dbSchema.replaceAll('"', '""')}"';

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
        await connection.execute(
          'SET statement_timeout TO @timeout_ms',
          substitutionValues: <String, Object?>{
            'timeout_ms': statementTimeoutMs,
          },
        );
        await connection.execute('SET search_path TO $_quotedSchema, public');
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
