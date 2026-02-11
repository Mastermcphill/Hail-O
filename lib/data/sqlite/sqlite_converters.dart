class SqliteConverters {
  static String toIso(DateTime value) => value.toUtc().toIso8601String();

  static DateTime fromIso(String value) => DateTime.parse(value).toUtc();

  static int boolToInt(bool value) => value ? 1 : 0;

  static bool intToBool(int value) => value == 1;

  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static String asString(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    return value.toString();
  }
}
