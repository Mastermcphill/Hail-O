import 'package:test/test.dart';

import 'support/test_client.dart';
import 'support/test_server.dart';

void main() {
  group('autosave HTTP smoke', () {
    late BackendTestServer server;
    late BackendTestClient client;

    setUp(() async {
      server = await BackendTestServer.create();
      addTearDown(server.close);
      client = await server.createDriverClient();
    });

    test('status returns not configured initially', () async {
      final response = await client.get('/api/settlement/autosave/status');

      expect(response.statusCode, 200);
      expect(response.json['ok'], true);
      expect(response.json['configured'], false);
      expect(response.json['status'], 'NOT_CONFIGURED');
      expect(response.json['bonus_eligible'], false);

      final totals = Map<String, Object?>.from(response.json['totals'] as Map);
      expect(totals['total_autosaved_minor'], 0);
      expect(totals['total_bonus_minor'], 0);
      expect(totals['total_exit_fees_minor'], 0);
    });

    test('configure creates active plan with masked destinations', () async {
      final response = await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-1',
        body: _configurePayload(),
      );

      expect(response.statusCode, 200);
      expect(response.json['ok'], true);
      expect(response.json['configured'], true);
      expect(response.json['status'], 'ACTIVE');
      expect(response.json['tier'], 1);
      expect(response.json['autosave_percent'], 5);

      final destinations = Map<String, Object?>.from(
        response.json['masked_destinations'] as Map,
      );
      final main = Map<String, Object?>.from(destinations['main'] as Map);
      final savings = Map<String, Object?>.from(destinations['savings'] as Map);

      expect(main['masked_account_number'], '****2223');
      expect(main.containsKey('account_number'), isFalse);
      expect(savings['masked_account_number'], '****6667');
      expect(savings.containsKey('account_number'), isFalse);
    });

    test('ledger contains a plan configuration entry', () async {
      await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-ledger',
        body: _configurePayload(),
      );

      final response = await client.get(
        '/api/settlement/autosave/ledger?limit=50',
      );

      expect(response.statusCode, 200);
      expect(response.json['ok'], true);

      final ledger = List<Map<String, Object?>>.from(
        (response.json['ledger'] as List).map(
          (entry) => Map<String, Object?>.from(entry as Map),
        ),
      );
      expect(ledger, isNotEmpty);

      final planEntry = ledger.firstWhere(
        (entry) =>
            entry['entry_type'] == 'PLAN_OPEN' ||
            entry['entry_type'] == 'PLAN_CHANGE',
      );
      expect((planEntry['reference'] as String).isNotEmpty, true);
      expect((planEntry['created_at'] as String).isNotEmpty, true);
    });

    test('disable early pauses plan and records exit fee entry', () async {
      await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-disable',
        body: _configurePayload(),
      );

      final disable = await client.post(
        '/api/settlement/autosave/disable',
        idempotencyKey: 'autosave-disable-1',
        body: const <String, Object?>{'reason': 'need flexibility'},
      );

      expect(disable.statusCode, 200);
      expect(disable.json['ok'], true);
      expect(disable.json['status'], 'PAUSED');
      expect(disable.json['bonus_eligible'], false);

      final ledgerResponse = await client.get(
        '/api/settlement/autosave/ledger?limit=50',
      );
      final ledger = List<Map<String, Object?>>.from(
        (ledgerResponse.json['ledger'] as List).map(
          (entry) => Map<String, Object?>.from(entry as Map),
        ),
      );
      final exitFeeEntries = ledger
          .where((entry) => entry['entry_type'] == 'EXIT_FEE')
          .toList(growable: false);

      expect(exitFeeEntries, isNotEmpty);
    });

    test('configure retries do not duplicate plan open entries', () async {
      final first = await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-idempotent',
        body: _configurePayload(),
      );
      final second = await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-idempotent',
        body: _configurePayload(),
      );
      final third = await client.post(
        '/api/settlement/autosave/configure',
        idempotencyKey: 'autosave-configure-idempotent',
        body: _configurePayload(),
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(third.statusCode, 200);
      expect(third.json['status'], 'ACTIVE');

      final ledgerResponse = await client.get(
        '/api/settlement/autosave/ledger?limit=50',
      );
      final ledger = List<Map<String, Object?>>.from(
        (ledgerResponse.json['ledger'] as List).map(
          (entry) => Map<String, Object?>.from(entry as Map),
        ),
      );
      final planOpenCount = ledger
          .where((entry) => entry['entry_type'] == 'PLAN_OPEN')
          .length;
      final planChangeCount = ledger
          .where((entry) => entry['entry_type'] == 'PLAN_CHANGE')
          .length;

      expect(planOpenCount, 1);
      expect(planChangeCount, lessThanOrEqualTo(1));
    });
  });
}

Map<String, Object?> _configurePayload() {
  return const <String, Object?>{
    'autosave_enabled': true,
    'tier': 1,
    'autosave_percent': 5,
    'main_bank': <String, Object?>{
      'account_number': '0001112223',
      'bank_code': '058',
      'name': 'Main Destination',
    },
    'savings_bank': <String, Object?>{
      'account_number': '4445556667',
      'bank_code': '033',
      'name': 'Savings Destination',
    },
  };
}
