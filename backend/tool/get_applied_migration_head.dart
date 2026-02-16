import 'dart:io';

import 'package:postgres/postgres.dart';

final RegExp _schemaPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

Future<void> main() async {
  final databaseUrl = (Platform.environment['DATABASE_URL'] ?? '').trim();
  if (databaseUrl.isEmpty) {
    stderr.writeln('DATABASE_URL is required.');
    exit(2);
  }

  final schema = (Platform.environment['DB_SCHEMA'] ?? 'hailo_staging').trim();
  if (!_schemaPattern.hasMatch(schema)) {
    stderr.writeln(
      'DB_SCHEMA must match ^[A-Za-z_][A-Za-z0-9_]*\$; got: $schema',
    );
    exit(2);
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
  try {
    final relationRows = await connection.query(
      'SELECT to_regclass(@relation_name)',
      substitutionValues: <String, Object?>{
        'relation_name': '$schema.schema_migrations',
      },
    );
    final relation = relationRows.isNotEmpty ? relationRows.first.first : null;
    if (relation == null) {
      stdout.writeln('0');
      return;
    }

    final quotedSchema = '"${schema.replaceAll('"', '""')}"';
    final rows = await connection.query(
      'SELECT COALESCE(MAX(version), 0)::int FROM $quotedSchema.schema_migrations',
    );
    final dynamic headValue = rows.isNotEmpty ? rows.first.first : 0;
    if (headValue is int) {
      stdout.writeln(headValue.toString());
      return;
    }
    if (headValue is num) {
      stdout.writeln(headValue.toInt().toString());
      return;
    }
    stdout.writeln('0');
  } finally {
    await connection.close();
  }
}
