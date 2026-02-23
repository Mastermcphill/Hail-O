import 'dart:convert';
import 'dart:io';

import '../infra/postgres_provider.dart';
import '../infra/runtime_config.dart';
import '../modules/marketplace/marketplace_revenue_service.dart';

Future<void> main() async {
  final config = BackendRuntimeConfig.fromEnvironment();
  PostgresProvider? postgresProvider;
  final databaseUrl = config.databaseUrl?.trim() ?? '';
  if (config.usePostgres && databaseUrl.isNotEmpty) {
    postgresProvider = PostgresProvider(
      databaseUrl,
      dbSchema: config.dbSchema,
    );
  }

  final service = MarketplaceRevenueService(
    postgresProvider: postgresProvider,
  );
  final job = (Platform.environment['WORKER_JOB'] ?? 'all')
      .trim()
      .toLowerCase();

  try {
    final results = <String, Object?>{};
    if (job == 'dunning_runner' || job == 'all') {
      final runs = await service.runDunningRunner();
      results['dunning_runner'] = <String, Object?>{'processed': runs.length};
    }
    if (job == 'comms_sender' || job == 'all') {
      final sent = await service.runCommsSender();
      results['comms_sender'] = <String, Object?>{'processed': sent.length};
    }
    if (job == 'risk_aggregator' || job == 'all') {
      final aggregated = await service.runRiskAggregator();
      results['risk_aggregator'] = <String, Object?>{
        'processed': aggregated.length,
      };
    }
    if (job == 'usage_rollup_runner' || job == 'all') {
      final rollups = await service.runUsageRollupRunner();
      results['usage_rollup_runner'] = <String, Object?>{
        'processed': rollups.length,
      };
    }
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'event': 'worker_run_complete',
        'job': job,
        'results': results,
      }),
    );
  } finally {
    if (postgresProvider != null) {
      await postgresProvider.close();
    }
  }
}
