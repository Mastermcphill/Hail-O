import 'package:sqflite/sqflite.dart';

import '../../../domain/models/user.dart';
import '../table_names.dart';

class UsersDao {
  const UsersDao(this.db);

  final Database db;

  Future<void> insert(User user) async {
    await db.insert(
      TableNames.users,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(User user) async {
    await db.update(
      TableNames.users,
      user.toMap(),
      where: 'id = ?',
      whereArgs: <Object>[user.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<User?> findById(String userId) async {
    final rows = await db.query(
      TableNames.users,
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return User.fromMap(rows.first);
  }

  Future<List<User>> listAll() async {
    final rows = await db.query(TableNames.users, orderBy: 'created_at DESC');
    return rows.map(User.fromMap).toList(growable: false);
  }
}
