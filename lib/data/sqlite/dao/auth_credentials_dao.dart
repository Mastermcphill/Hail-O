import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/auth_credential.dart';
import '../table_names.dart';

class AuthCredentialsDao {
  const AuthCredentialsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(AuthCredential credential) async {
    await db.insert(
      TableNames.authCredentials,
      credential.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> upsert(AuthCredential credential) async {
    await db.insert(
      TableNames.authCredentials,
      credential.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AuthCredential?> findByEmail(String email) async {
    final rows = await db.query(
      TableNames.authCredentials,
      where: 'email = ?',
      whereArgs: <Object>[email.toLowerCase().trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AuthCredential.fromMap(rows.first);
  }

  Future<AuthCredential?> findByUserId(String userId) async {
    final rows = await db.query(
      TableNames.authCredentials,
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AuthCredential.fromMap(rows.first);
  }
}
