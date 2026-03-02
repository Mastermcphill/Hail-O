import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../server/router.dart';

void main() {
  test(
    'legacy wallet and moneybox routes return 410 disabled envelope',
    () async {
      final handler = buildApiRouter(
        db: null,
        tokenService: TokenService(secret: 'test-secret'),
        dbMode: 'sqlite',
        dbHealthCheck: () async => true,
        buildInfo: const <String, Object?>{'migration_head': 27},
        requestMetrics: RequestMetrics(),
        runtimeConfigSnapshot: const <String, Object?>{},
      );

      final walletResponse = await handler(
        Request('GET', Uri.parse('http://localhost/api/wallet/status')),
      );
      final walletPayload =
          jsonDecode(await walletResponse.readAsString()) as Map;
      expect(walletResponse.statusCode, 410);
      expect(walletPayload['error_code'], 'WALLET_CUSTODY_DISABLED');
      expect(walletPayload['trace_id'], isNotNull);

      final moneyboxResponse = await handler(
        Request('POST', Uri.parse('http://localhost/api/moneybox/configure')),
      );
      final moneyboxPayload =
          jsonDecode(await moneyboxResponse.readAsString()) as Map;
      expect(moneyboxResponse.statusCode, 410);
      expect(moneyboxPayload['error_code'], 'WALLET_CUSTODY_DISABLED');
      expect(moneyboxPayload['trace_id'], isNotNull);
    },
  );
}
