import '../../../lib/data/sqlite/dao/auth_credentials_dao.dart';
import '../../../lib/data/sqlite/dao/users_dao.dart';
import '../../../lib/domain/models/auth_credential.dart';
import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import 'auth_credentials_store.dart';

class SqliteAuthCredentialsStore extends AuthCredentialsStore {
  const SqliteAuthCredentialsStore(this.db);

  final DatabaseExecutor db;

  @override
  Future<ExternalAuthCredentialRecord?> findByEmail(String email) async {
    final credential = await AuthCredentialsDao(db).findByEmail(email);
    if (credential == null) {
      return null;
    }
    final user = await UsersDao(db).findById(credential.userId);
    return ExternalAuthCredentialRecord(
      userId: credential.userId,
      email: credential.email,
      passwordHash: credential.passwordHash,
      passwordAlgo: credential.passwordAlgo,
      role: user?.role.dbValue ?? UserRole.rider.dbValue,
      createdAt: credential.createdAt,
      updatedAt: credential.updatedAt,
    );
  }

  @override
  Future<void> upsertCredential(ExternalAuthCredentialRecord record) async {
    await AuthCredentialsDao(db).upsert(
      AuthCredential(
        userId: record.userId,
        email: record.email.toLowerCase().trim(),
        passwordHash: record.passwordHash,
        passwordAlgo: record.passwordAlgo,
        createdAt: record.createdAt.toUtc(),
        updatedAt: record.updatedAt.toUtc(),
      ),
    );
  }
}
