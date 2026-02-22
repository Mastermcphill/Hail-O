import 'dart:convert';
import 'dart:io';

import '../infra/api_contract.dart';

void main() {
  final file = File('test/golden/api_contract_v1.json');
  if (!file.existsSync()) {
    stderr.writeln('Missing golden contract file at ${file.path}');
    exitCode = 1;
    return;
  }

  final baselineRaw = file.readAsStringSync();
  final baseline = Map<String, Object?>.from(
    jsonDecode(baselineRaw) as Map<String, dynamic>,
  );
  final candidate = apiContractGoldenSnapshot();
  final breaking = detectBreakingContractChanges(
    baseline: baseline,
    candidate: candidate,
  );
  final nonBreaking = detectNonBreakingContractChanges(
    baseline: baseline,
    candidate: candidate,
  );

  stdout.writeln('Contract version: ${candidate['version']}');
  stdout.writeln('Contract hash: ${apiContractHash()}');
  stdout.writeln('Breaking changes detected: ${breaking.length}');
  for (final finding in breaking) {
    stdout.writeln('- $finding');
  }
  stdout.writeln('Non-breaking changes detected: ${nonBreaking.length}');
  for (final finding in nonBreaking) {
    stdout.writeln('- $finding');
  }

  if (breaking.isNotEmpty) {
    stderr.writeln(
      'Breaking API contract changes detected. '
      'If intentional, version the contract (e.g. api_contract_v2.json).',
    );
    exitCode = 1;
    return;
  }
}
