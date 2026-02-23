import 'dart:convert';
import 'dart:io';

import '../infra/api_contract.dart';

void main() {
  final golden = apiContractGoldenSnapshot();

  final file = File('test/golden/api_contract_v2.json');
  file.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(golden)}\n');
  stdout.writeln('Updated ${file.path}');
}
