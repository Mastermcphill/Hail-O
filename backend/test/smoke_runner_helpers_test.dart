import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../ops/smoke_runner_helpers.dart';

void main() {
  group('smoke runner helpers', () {
    test('buildSmokeUrl normalizes base and path slashes', () {
      expect(
        buildSmokeUrl('https://staging.example.com/', '/health'),
        'https://staging.example.com/health',
      );
      expect(
        buildSmokeUrl('https://staging.example.com', 'ready'),
        'https://staging.example.com/ready',
      );
    });

    test('parseSmokeJsonObject decodes object payload', () {
      final parsed = parseSmokeJsonObject('{"ok":true,"count":2}');
      expect(parsed['ok'], true);
      expect((parsed['count'] as num).toInt(), 2);
    });

    test('parseSmokeJsonObject rejects non-object payload', () {
      expect(
        () => parseSmokeJsonObject('["not","object"]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('writeSmokeArtifact persists formatted json', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'smoke_runner_helpers_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = await writeSmokeArtifact(
        runDir: tempDir,
        fileName: '01_health.json',
        payload: <String, Object?>{'ok': true, 'status': 200},
      );

      expect(await file.exists(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['ok'], true);
      expect(decoded['status'], 200);
    });
  });
}
