import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/ci/check_lcov.dart <lcov_path> <min_percent> [label]',
    );
    exitCode = 64;
    return;
  }

  final lcovPath = args[0];
  final minimumPercent = double.tryParse(args[1]);
  final label = args.length >= 3 ? args[2] : lcovPath;
  if (minimumPercent == null) {
    stderr.writeln('Invalid minimum percent: "${args[1]}"');
    exitCode = 64;
    return;
  }

  final file = File(lcovPath);
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: $lcovPath');
    exitCode = 66;
    return;
  }

  var totalLines = 0;
  var coveredLines = 0;
  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('DA:')) {
      continue;
    }
    final entry = line.substring(3).split(',');
    if (entry.length < 2) {
      continue;
    }
    final hitCount = int.tryParse(entry[1].trim()) ?? 0;
    totalLines += 1;
    if (hitCount > 0) {
      coveredLines += 1;
    }
  }

  if (totalLines == 0) {
    stderr.writeln('No DA lines found in coverage file: $lcovPath');
    exitCode = 65;
    return;
  }

  final percent = (coveredLines * 100) / totalLines;
  final formattedPercent = percent.toStringAsFixed(2);
  final formattedMinimum = minimumPercent.toStringAsFixed(2);
  stdout.writeln(
    '$label coverage: $formattedPercent% ($coveredLines/$totalLines) minimum=$formattedMinimum%',
  );

  if (percent < minimumPercent) {
    stderr.writeln('Coverage threshold not met for $label');
    exitCode = 1;
  }
}
