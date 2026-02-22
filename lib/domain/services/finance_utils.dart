String isoNowUtc([DateTime? value]) =>
    (value ?? DateTime.now().toUtc()).toIso8601String();

DateTime lagosFromUtc(DateTime utc) =>
    utc.toUtc().add(const Duration(hours: 1));

int percentOf(int amountMinor, int percent) {
  if (amountMinor <= 0 || percent <= 0) {
    return 0;
  }
  return (amountMinor * percent) ~/ 100;
}
