class RuleRolloutService {
  const RuleRolloutService();

  bool isInRollout({
    required String subjectId,
    required int percent,
    required String salt,
  }) {
    if (percent <= 0) {
      return false;
    }
    if (percent >= 100) {
      return true;
    }
    final subject = subjectId.trim();
    if (subject.isEmpty) {
      return false;
    }
    final bucket = _bucketFor(subjectId: subject, salt: salt);
    return bucket < percent;
  }

  int bucketFor({required String subjectId, required String salt}) {
    return _bucketFor(subjectId: subjectId, salt: salt);
  }

  int _bucketFor({required String subjectId, required String salt}) {
    final input = '$salt|$subjectId';
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash % 100;
  }
}
