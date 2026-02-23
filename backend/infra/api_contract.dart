import 'dart:convert';

import 'package:crypto/crypto.dart';

const String apiContractVersion = 'v2';

const Map<String, Object?> _apiContractV2 = <String, Object?>{
  'version': apiContractVersion,
  'endpoints': <String, Object?>{
    'health': <String, Object?>{
      'required_keys': <String>['ok', 'service', 'db_mode', 'db_ok', 'build'],
      'field_types': <String, String>{
        'ok': 'bool',
        'service': 'string',
        'db_mode': 'string',
        'db_ok': 'bool',
        'build': 'object',
      },
    },
    'auth_register': <String, Object?>{
      'required_keys': <String>['ok', 'user_id', 'role'],
      'field_types': <String, String>{
        'ok': 'bool',
        'user_id': 'string',
        'role': 'string',
      },
    },
    'auth_login': <String, Object?>{
      'required_keys': <String>['ok', 'token', 'user_id', 'role'],
      'field_types': <String, String>{
        'ok': 'bool',
        'token': 'string',
        'user_id': 'string',
        'role': 'string',
      },
    },
    'error': <String, Object?>{
      'required_keys': <String>['ok', 'error_code', 'message', 'trace_id'],
      'field_types': <String, String>{
        'ok': 'bool',
        'error_code': 'string',
        'message': 'string',
        'trace_id': 'string',
      },
    },
  },
};

Map<String, Object?> apiContractGoldenSnapshot() {
  return _deepCopyMap(_apiContractV2);
}

String apiContractHash() {
  final canonical = jsonEncode(_canonicalize(_apiContractV2));
  return sha256.convert(utf8.encode(canonical)).toString();
}

Map<String, Object?> buildAdminContractPayload({
  required Map<String, Object?> buildInfo,
}) {
  return <String, Object?>{
    'ok': true,
    'contract': <String, Object?>{
      'version': apiContractVersion,
      'hash': apiContractHash(),
      'build_commit': buildInfo['commit'] ?? 'unknown',
      'db_schema': buildInfo['db_schema'] ?? 'unknown',
    },
  };
}

List<String> detectBreakingContractChanges({
  required Map<String, Object?> baseline,
  required Map<String, Object?> candidate,
}) {
  final findings = <String>[];
  final baselineEndpoints = _endpoints(baseline);
  final candidateEndpoints = _endpoints(candidate);

  for (final endpoint in baselineEndpoints.keys) {
    final baselineSpec = _endpointSpec(
      baselineEndpoints,
      endpoint,
      findings,
      source: 'baseline',
    );
    final candidateSpec = _endpointSpec(
      candidateEndpoints,
      endpoint,
      findings,
      source: 'candidate',
    );
    if (baselineSpec == null || candidateSpec == null) {
      if (!candidateEndpoints.containsKey(endpoint)) {
        findings.add('breaking: removed endpoint "$endpoint"');
      }
      continue;
    }

    final baselineRequired = _stringList(
      baselineSpec['required_keys'],
      findings,
      endpoint: endpoint,
      source: 'baseline',
    );
    final candidateRequired = _stringList(
      candidateSpec['required_keys'],
      findings,
      endpoint: endpoint,
      source: 'candidate',
    );
    if (baselineRequired != null && candidateRequired != null) {
      final candidateRequiredSet = candidateRequired.toSet();
      for (final field in baselineRequired) {
        if (!candidateRequiredSet.contains(field)) {
          findings.add(
            'breaking: endpoint "$endpoint" removed required field "$field"',
          );
        }
      }
    }

    final baselineTypes = _stringMap(
      baselineSpec['field_types'],
      findings,
      endpoint: endpoint,
      source: 'baseline',
      allowMissing: true,
    );
    final candidateTypes = _stringMap(
      candidateSpec['field_types'],
      findings,
      endpoint: endpoint,
      source: 'candidate',
      allowMissing: true,
    );
    if (baselineTypes != null && candidateTypes != null) {
      for (final entry in baselineTypes.entries) {
        final candidateType = candidateTypes[entry.key];
        if (candidateType == null) {
          findings.add(
            'breaking: endpoint "$endpoint" removed type for field "${entry.key}"',
          );
          continue;
        }
        if (candidateType != entry.value) {
          findings.add(
            'breaking: endpoint "$endpoint" changed type of "${entry.key}" from "${entry.value}" to "$candidateType"',
          );
        }
      }
    }
  }

  return findings;
}

List<String> detectNonBreakingContractChanges({
  required Map<String, Object?> baseline,
  required Map<String, Object?> candidate,
}) {
  final findings = <String>[];
  final baselineEndpoints = _endpoints(baseline);
  final candidateEndpoints = _endpoints(candidate);

  for (final endpoint in candidateEndpoints.keys) {
    if (!baselineEndpoints.containsKey(endpoint)) {
      findings.add('non_breaking: added endpoint "$endpoint"');
      continue;
    }

    final baselineSpec = _endpointSpec(
      baselineEndpoints,
      endpoint,
      findings,
      source: 'baseline',
    );
    final candidateSpec = _endpointSpec(
      candidateEndpoints,
      endpoint,
      findings,
      source: 'candidate',
    );
    if (baselineSpec == null || candidateSpec == null) {
      continue;
    }

    final baselineRequired = _stringList(
      baselineSpec['required_keys'],
      findings,
      endpoint: endpoint,
      source: 'baseline',
    );
    final candidateRequired = _stringList(
      candidateSpec['required_keys'],
      findings,
      endpoint: endpoint,
      source: 'candidate',
    );
    if (baselineRequired != null && candidateRequired != null) {
      final baselineRequiredSet = baselineRequired.toSet();
      for (final field in candidateRequired) {
        if (!baselineRequiredSet.contains(field)) {
          findings.add(
            'non_breaking: endpoint "$endpoint" added required field "$field"',
          );
        }
      }
    }

    final baselineTypes = _stringMap(
      baselineSpec['field_types'],
      findings,
      endpoint: endpoint,
      source: 'baseline',
      allowMissing: true,
    );
    final candidateTypes = _stringMap(
      candidateSpec['field_types'],
      findings,
      endpoint: endpoint,
      source: 'candidate',
      allowMissing: true,
    );
    if (baselineTypes != null && candidateTypes != null) {
      final baselineTypeKeys = baselineTypes.keys.toSet();
      for (final entry in candidateTypes.entries) {
        if (!baselineTypeKeys.contains(entry.key)) {
          findings.add(
            'non_breaking: endpoint "$endpoint" added type for field "${entry.key}"',
          );
        }
      }
    }
  }

  return findings;
}

Map<String, Object?> _endpoints(Map<String, Object?> spec) {
  final raw = spec['endpoints'];
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value as Object?));
  }
  return <String, Object?>{};
}

Map<String, Object?>? _endpointSpec(
  Map<String, Object?> endpoints,
  String endpoint,
  List<String> findings, {
  required String source,
}) {
  final raw = endpoints[endpoint];
  if (raw == null) {
    return null;
  }
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value as Object?));
  }
  findings.add(
    'breaking: endpoint "$endpoint" in $source is not an object contract',
  );
  return null;
}

List<String>? _stringList(
  Object? value,
  List<String> findings, {
  required String endpoint,
  required String source,
}) {
  if (value is! List) {
    findings.add(
      'breaking: endpoint "$endpoint" in $source has non-list required_keys',
    );
    return null;
  }
  final output = <String>[];
  for (final entry in value) {
    if (entry is! String) {
      findings.add(
        'breaking: endpoint "$endpoint" in $source has non-string required_keys value',
      );
      return null;
    }
    output.add(entry);
  }
  return output;
}

Map<String, String>? _stringMap(
  Object? value,
  List<String> findings, {
  required String endpoint,
  required String source,
  bool allowMissing = false,
}) {
  if (value == null && allowMissing) {
    return <String, String>{};
  }
  if (value is! Map) {
    findings.add(
      'breaking: endpoint "$endpoint" in $source has non-map field_types',
    );
    return null;
  }
  final output = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      findings.add(
        'breaking: endpoint "$endpoint" in $source has non-string field_types entry',
      );
      return null;
    }
    output[entry.key as String] = entry.value as String;
  }
  return output;
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = value.entries.toList()
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    return <String, Object?>{
      for (final entry in sorted)
        entry.key.toString(): _canonicalize(entry.value),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) {
  return _deepCopyValue(source) as Map<String, Object?>;
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopyValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}
