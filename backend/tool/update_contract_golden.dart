import 'dart:convert';
import 'dart:io';

void main() {
  final golden = <String, Object?>{
    'version': 'v1',
    'endpoints': <String, Object?>{
      'health': <String, Object?>{
        'required_keys': <String>['ok', 'service', 'db_mode', 'db_ok', 'build'],
      },
      'auth_register': <String, Object?>{
        'required_keys': <String>['ok', 'user_id', 'role'],
      },
      'auth_login': <String, Object?>{
        'required_keys': <String>['ok', 'token', 'user_id', 'role'],
      },
      'error': <String, Object?>{
        'required_keys': <String>['ok', 'code', 'message', 'trace_id'],
      },
    },
  };

  final file = File('test/golden/api_contract_v1.json');
  file.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(golden)}\n');
  stdout.writeln('Updated ${file.path}');
}
