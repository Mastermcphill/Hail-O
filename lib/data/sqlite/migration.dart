abstract class Migration {
  const Migration();

  int get version;
  String get name;
  String get checksum;
  List<String> get upSql;
}
