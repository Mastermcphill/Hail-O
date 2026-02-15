import 'dart:io';

import '../infra/migrator.dart';
import '../infra/postgres_provider.dart';
import '../infra/runtime_config.dart';

Future<void> main() async {
  final config = BackendRuntimeConfig.fromEnvironment();
  if (!config.usePostgres) {
    stdout.writeln('Skipping Postgres migrations: BACKEND_DB_MODE=sqlite');
    return;
  }
  final databaseUrl = config.databaseUrl?.trim() ?? '';
  if (databaseUrl.isEmpty) {
    throw StateError(
      'DATABASE_URL is required when BACKEND_DB_MODE is postgres',
    );
  }

  final provider = PostgresProvider(databaseUrl);
  try {
    await BackendPostgresMigrator(
      postgresProvider: provider,
    ).runPendingMigrations();
    stdout.writeln('Postgres migrations applied successfully');
  } finally {
    await provider.close();
  }
}
