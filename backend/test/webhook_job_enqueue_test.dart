import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import '../infra/redis_client.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../jobs/job.dart';
import '../jobs/job_processor.dart';
import '../jobs/job_registry.dart';
import '../modules/auth/sqlite_auth_credentials_store.dart';
import '../modules/rides/sqlite_operational_record_store.dart';
import '../modules/rides/sqlite_ride_request_metadata_store.dart';
import '../server/app_server.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'webhook requests enqueue process_webhook_event job when queue is wired',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      final redisClient = InMemoryRedisClient();
      final registry = QueueJobRegistry();
      final processor = QueueJobProcessor(
        redisClient: redisClient,
        registry: registry,
      );
      final handler = AppServer(
        db: db,
        tokenService: TokenService(secret: 'backend-test-secret'),
        dbMode: 'sqlite',
        environment: 'test',
        requestMetrics: RequestMetrics(),
        dbHealthCheck: () async => true,
        buildInfo: const <String, Object?>{'commit': 'webhook-queue-test'},
        authCredentialsStore: SqliteAuthCredentialsStore(db),
        rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
        operationalRecordStore: const SqliteOperationalRecordStore(),
        environmentMap: const <String, String>{
          'ENV': 'staging',
          'REDIS_URL': 'redis://localhost:6379/0',
        },
        redisClient: redisClient,
        queueJobRegistry: registry,
        queueJobProcessor: processor,
      ).buildHandler();

      final response = await handler(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider_event_id': 'evt_queue_1',
            'event_type': 'payment_succeeded',
          }),
        ),
      );
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(body['data'] as Map);
      expect(data['action'], 'webhook_enqueued');

      final jobPayload = await redisClient.dequeue(QueueNames.jobs);
      expect(jobPayload, isNotNull);
      final decoded = jsonDecode(jobPayload!) as Map<String, dynamic>;
      expect(decoded['type'], QueueJobTypes.processWebhookEvent);
      final payload = Map<String, dynamic>.from(decoded['payload'] as Map);
      expect(payload['provider'], 'manual');
      expect(payload['provider_event_id'], 'evt_queue_1');
    },
  );
}
