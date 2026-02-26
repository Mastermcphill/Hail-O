import 'dart:convert';
import 'dart:io';

String buildSmokeUrl(String baseUrl, String path) {
  final normalizedBase = baseUrl.trim();
  if (normalizedBase.isEmpty) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'base URL is required');
  }
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) {
    throw ArgumentError.value(path, 'path', 'path is required');
  }
  final baseNoTrailing = normalizedBase.endsWith('/')
      ? normalizedBase.substring(0, normalizedBase.length - 1)
      : normalizedBase;
  final pathWithLeading = normalizedPath.startsWith('/')
      ? normalizedPath
      : '/$normalizedPath';
  return '$baseNoTrailing$pathWithLeading';
}

Map<String, Object?> parseSmokeJsonObject(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(normalized);
  if (decoded is! Map) {
    throw const FormatException('json_payload_must_be_object');
  }
  return decoded.map(
    (Object? key, Object? value) => MapEntry(key.toString(), value),
  );
}

Future<File> writeSmokeArtifact({
  required Directory runDir,
  required String fileName,
  required Object payload,
}) async {
  final normalizedName = fileName.trim();
  if (normalizedName.isEmpty) {
    throw ArgumentError.value(fileName, 'fileName', 'file name is required');
  }
  await runDir.create(recursive: true);
  final file = File('${runDir.path}${Platform.pathSeparator}$normalizedName');
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(payload)}\n');
  return file;
}
