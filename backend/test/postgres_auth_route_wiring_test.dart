import 'dart:collection';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../lib/domain/services/auth_service.dart';
import '../infra/postgres_provider.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/auth/phone_auth_store.dart';
import '../server/app_server.dart';

void main() {
  test(
    'postgres app server mounts register/login and keeps otp routes available',
    () async {
      final postgresProvider = _InMemoryPostgresProvider();
      final handler = AppServer(
        db: null,
        tokenService: TokenService(secret: 'backend-test-secret'),
        dbMode: 'postgres',
        environment: 'test',
        requestMetrics: RequestMetrics(),
        dbHealthCheck: () async => true,
        buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
        runtimeConfigSnapshot: const <String, Object?>{
          'environment': 'test',
          'db_mode': 'postgres',
          'db_schema': 'public',
        },
        postgresProvider: postgresProvider,
        authCredentialsStore: _UnusedAuthCredentialsStore(),
        phoneAuthStore: _UnusedPhoneAuthStore(),
        environmentMap: const <String, String>{
          'ENV': 'test',
          'OTP_DEV_BYPASS': 'true',
        },
      ).buildHandler();

      final register = await _postJson(
        handler,
        '/auth/register',
        body: const <String, Object?>{
          'email': 'postgres.auth@example.com',
          'password': 'SuperSecret123',
          'role': 'rider',
        },
        idempotencyKey: 'postgres-register-1',
      );
      expect(register.statusCode, 201);
      final registerBody = await _decodeBody(register);
      expect(registerBody['ok'], true);
      expect(registerBody['role'], 'rider');
      expect((registerBody['user_id'] as String?)?.isNotEmpty, isTrue);

      final login = await _postJson(
        handler,
        '/auth/login',
        body: const <String, Object?>{
          'email': 'postgres.auth@example.com',
          'password': 'SuperSecret123',
        },
      );
      expect(login.statusCode, 200);
      final loginBody = await _decodeBody(login);
      expect(loginBody['email'], 'postgres.auth@example.com');
      expect((loginBody['token'] as String?)?.isNotEmpty, isTrue);

      final otpRequest = await _postJson(
        handler,
        '/auth/otp/request',
        body: const <String, Object?>{'phone_e164': ''},
      );
      expect(otpRequest.statusCode, isNot(404));
      final otpBody = await _decodeBody(otpRequest);
      expect(otpBody['error_code'], isNot('ROUTE_NOT_FOUND'));
    },
  );
}

Future<Response> _postJson(
  Handler handler,
  String path, {
  required Map<String, Object?> body,
  String? idempotencyKey,
}) {
  final headers = <String, String>{'content-type': 'application/json'};
  if (idempotencyKey != null) {
    headers['idempotency-key'] = idempotencyKey;
  }
  return Future<Response>.value(
    handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: headers,
        body: jsonEncode(body),
      ),
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _UnusedAuthCredentialsStore extends AuthCredentialsStore {
  @override
  Future<ExternalAuthCredentialRecord?> findByEmail(String email) async => null;

  @override
  Future<void> upsertCredential(ExternalAuthCredentialRecord record) async {}
}

class _UnusedPhoneAuthStore extends PhoneAuthStore {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected phone auth store call in postgres auth wiring test: ${invocation.memberName}',
    );
  }
}

class _InMemoryPostgresProvider extends PostgresProvider {
  _InMemoryPostgresProvider()
    : super('postgres://hailo:secret@localhost:5432/hailo');

  final Map<String, _AuthUserRecord> usersById = <String, _AuthUserRecord>{};
  final Map<String, String> userIdsByPhone = <String, String>{};
  final Map<String, _AuthCredentialRecord> credentialsByEmail =
      <String, _AuthCredentialRecord>{};
  final Map<String, _UserProfileRecord> profilesByUserId =
      <String, _UserProfileRecord>{};
  final Map<String, Set<String>> rolesByUserId = <String, Set<String>>{};

  @override
  Future<T> withConnection<T>(
    Future<T> Function(PostgreSQLConnection connection) action,
  ) async {
    return action(_InMemoryPostgreSQLConnection(this));
  }
}

class _InMemoryPostgreSQLConnection extends PostgreSQLConnection {
  _InMemoryPostgreSQLConnection(this._provider)
    : super('localhost', 5432, 'hailo');

  final _InMemoryPostgresProvider _provider;

  @override
  Future<PostgreSQLResult> query(
    String fmtString, {
    Map<String, dynamic>? substitutionValues,
    bool? allowReuse,
    int? timeoutInSeconds,
    bool? useSimpleQueryProtocol,
  }) async {
    final sql = _normalizeSql(fmtString);
    final values = substitutionValues ?? const <String, dynamic>{};

    if (sql.contains('from auth_credentials') &&
        sql.contains('where email =')) {
      final email = (values['email'] as String).trim().toLowerCase();
      final credential = _provider.credentialsByEmail[email];
      if (credential == null) {
        return _FakePostgreSQLResult.empty();
      }
      if (!sql.contains('password_hash')) {
        return _FakePostgreSQLResult.fromRows(
          columnNames: const <String>['user_id'],
          rows: <List<Object?>>[
            <Object?>[credential.userId],
          ],
        );
      }
      return _FakePostgreSQLResult.fromRows(
        columnNames: const <String>[
          'user_id',
          'email',
          'password_hash',
          'password_algo',
          'role',
          'created_at',
          'updated_at',
        ],
        rows: <List<Object?>>[
          <Object?>[
            credential.userId,
            credential.email,
            credential.passwordHash,
            credential.passwordAlgo,
            credential.role,
            credential.createdAt,
            credential.updatedAt,
          ],
        ],
      );
    }

    if (sql.contains('select disabled_at') && sql.contains('from users')) {
      final userId = (values['id'] as String).trim();
      final user = _provider.usersById[userId];
      if (user == null) {
        return _FakePostgreSQLResult.empty();
      }
      return _FakePostgreSQLResult.fromRows(
        columnNames: const <String>['disabled_at'],
        rows: <List<Object?>>[
          <Object?>[user.disabledAt],
        ],
      );
    }

    throw UnsupportedError('Unexpected postgres query: $fmtString');
  }

  @override
  Future<int> execute(
    String fmtString, {
    Map<String, dynamic>? substitutionValues,
    int? timeoutInSeconds,
  }) async {
    final sql = _normalizeSql(fmtString);
    final values = substitutionValues ?? const <String, dynamic>{};

    if (sql.startsWith('insert into users(')) {
      final userId = (values['id'] as String).trim();
      final phoneE164 = (values['phone_e164'] as String).trim();
      if (_provider.userIdsByPhone.containsKey(phoneE164)) {
        throw StateError('duplicate phone');
      }
      _provider.usersById[userId] = _AuthUserRecord(
        id: userId,
        phoneE164: phoneE164,
        createdAt: (values['created_at'] as DateTime).toUtc(),
        disabledAt: null,
      );
      _provider.userIdsByPhone[phoneE164] = userId;
      return 1;
    }

    if (sql.startsWith('insert into user_profiles(')) {
      final userId = (values['user_id'] as String).trim();
      _provider.profilesByUserId[userId] = _UserProfileRecord(
        userId: userId,
        displayName: values['display_name'] as String?,
        email: values['email'] as String?,
        updatedAt: (values['updated_at'] as DateTime).toUtc(),
      );
      return 1;
    }

    if (sql.startsWith('insert into user_roles(')) {
      final userId = (values['user_id'] as String).trim();
      final role = (values['role'] as String).trim();
      _provider.rolesByUserId.putIfAbsent(userId, () => <String>{}).add(role);
      return 1;
    }

    throw UnsupportedError('Unexpected postgres execute: $fmtString');
  }

  @override
  Future transaction(
    Future Function(PostgreSQLExecutionContext connection) queryBlock, {
    int? commitTimeoutInSeconds,
  }) async {
    final usersSnapshot = Map<String, _AuthUserRecord>.from(
      _provider.usersById,
    );
    final phonesSnapshot = Map<String, String>.from(_provider.userIdsByPhone);
    final credentialsSnapshot = Map<String, _AuthCredentialRecord>.from(
      _provider.credentialsByEmail,
    );
    final profilesSnapshot = Map<String, _UserProfileRecord>.from(
      _provider.profilesByUserId,
    );
    final rolesSnapshot = <String, Set<String>>{
      for (final entry in _provider.rolesByUserId.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final context = _InMemoryPostgreSQLTransactionContext(_provider);
    try {
      return await queryBlock(context);
    } catch (_) {
      _provider.usersById
        ..clear()
        ..addAll(usersSnapshot);
      _provider.userIdsByPhone
        ..clear()
        ..addAll(phonesSnapshot);
      _provider.credentialsByEmail
        ..clear()
        ..addAll(credentialsSnapshot);
      _provider.profilesByUserId
        ..clear()
        ..addAll(profilesSnapshot);
      _provider.rolesByUserId
        ..clear()
        ..addAll(rolesSnapshot);
      rethrow;
    }
  }
}

class _InMemoryPostgreSQLTransactionContext
    extends _InMemoryPostgreSQLConnection
    implements PostgreSQLExecutionContext {
  _InMemoryPostgreSQLTransactionContext(super.provider);

  @override
  Future<PostgreSQLResult> query(
    String fmtString, {
    Map<String, dynamic>? substitutionValues,
    bool? allowReuse,
    int? timeoutInSeconds,
    bool? useSimpleQueryProtocol,
  }) async {
    final sql = _normalizeSql(fmtString);
    final values = substitutionValues ?? const <String, dynamic>{};

    if (sql.startsWith('insert into auth_credentials(')) {
      final email = (values['email'] as String).trim().toLowerCase();
      if (_provider.credentialsByEmail.containsKey(email)) {
        return _FakePostgreSQLResult.empty();
      }
      final record = _AuthCredentialRecord(
        userId: (values['user_id'] as String).trim(),
        email: email,
        phone: values['phone'] as String?,
        passwordHash: values['password_hash'] as String,
        passwordAlgo: values['password_algo'] as String,
        role: values['role'] as String,
        createdAt: (values['created_at'] as DateTime).toUtc(),
        updatedAt: (values['updated_at'] as DateTime).toUtc(),
      );
      _provider.credentialsByEmail[email] = record;
      return _FakePostgreSQLResult.fromRows(
        columnNames: const <String>['user_id'],
        rows: <List<Object?>>[
          <Object?>[record.userId],
        ],
      );
    }
    return super.query(
      fmtString,
      substitutionValues: substitutionValues,
      allowReuse: allowReuse,
      timeoutInSeconds: timeoutInSeconds,
      useSimpleQueryProtocol: useSimpleQueryProtocol,
    );
  }
}

class _FakePostgreSQLResult extends ListBase<PostgreSQLResultRow>
    implements PostgreSQLResult {
  _FakePostgreSQLResult._(
    this._rows, {
    required this.columnDescriptions,
    required this.affectedRowCount,
  });

  factory _FakePostgreSQLResult.fromRows({
    required List<String> columnNames,
    required List<List<Object?>> rows,
  }) {
    final descriptions = columnNames
        .map<_FakeColumnDescription>((name) => _FakeColumnDescription(name))
        .toList(growable: false);
    return _FakePostgreSQLResult._(
      rows
          .map<PostgreSQLResultRow>(
            (row) => _FakePostgreSQLResultRow(
              row,
              columnNames: columnNames,
              columnDescriptions: descriptions,
            ),
          )
          .toList(growable: false),
      columnDescriptions: descriptions,
      affectedRowCount: rows.length,
    );
  }

  factory _FakePostgreSQLResult.empty() => _FakePostgreSQLResult._(
    const <PostgreSQLResultRow>[],
    columnDescriptions: const <ColumnDescription>[],
    affectedRowCount: 0,
  );

  final List<PostgreSQLResultRow> _rows;

  @override
  final int affectedRowCount;

  @override
  final List<ColumnDescription> columnDescriptions;

  @override
  int get length => _rows.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  PostgreSQLResultRow operator [](int index) => _rows[index];

  @override
  void operator []=(int index, PostgreSQLResultRow value) {
    throw UnsupportedError('immutable');
  }
}

class _FakePostgreSQLResultRow extends ListBase<dynamic>
    implements PostgreSQLResultRow {
  _FakePostgreSQLResultRow(
    this._values, {
    required List<String> columnNames,
    required this.columnDescriptions,
  }) : _columnNames = columnNames;

  final List<Object?> _values;
  final List<String> _columnNames;

  @override
  final List<ColumnDescription> columnDescriptions;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  dynamic operator [](int index) => _values[index];

  @override
  void operator []=(int index, dynamic value) {
    throw UnsupportedError('immutable');
  }

  @override
  Map<String, dynamic> toColumnMap() {
    final mapped = <String, dynamic>{};
    for (var index = 0; index < _columnNames.length; index += 1) {
      mapped[_columnNames[index]] = _values[index];
    }
    return mapped;
  }

  @override
  Map<String, Map<String, dynamic>> toTableColumnMap() {
    return <String, Map<String, dynamic>>{'result': toColumnMap()};
  }
}

class _FakeColumnDescription implements ColumnDescription {
  const _FakeColumnDescription(this.columnName);

  @override
  final String columnName;

  @override
  String get tableName => 'result';

  @override
  int get typeId => 0;
}

class _AuthUserRecord {
  const _AuthUserRecord({
    required this.id,
    required this.phoneE164,
    required this.createdAt,
    this.disabledAt,
  });

  final String id;
  final String phoneE164;
  final DateTime createdAt;
  final DateTime? disabledAt;
}

class _AuthCredentialRecord {
  const _AuthCredentialRecord({
    required this.userId,
    required this.email,
    required this.phone,
    required this.passwordHash,
    required this.passwordAlgo,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String email;
  final String? phone;
  final String passwordHash;
  final String passwordAlgo;
  final String role;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class _UserProfileRecord {
  const _UserProfileRecord({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.updatedAt,
  });

  final String userId;
  final String? displayName;
  final String? email;
  final DateTime updatedAt;
}

String _normalizeSql(String sql) {
  return sql.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
