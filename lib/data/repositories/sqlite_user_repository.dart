import '../../domain/models/user.dart';
import '../sqlite/dao/users_dao.dart';
import 'user_repository.dart';

class SqliteUserRepository implements UserRepository {
  const SqliteUserRepository(this._usersDao);

  final UsersDao _usersDao;

  @override
  Future<void> createUser(User user) => _usersDao.insert(user);

  @override
  Future<User?> getUser(String userId) => _usersDao.findById(userId);

  @override
  Future<List<User>> listUsers() => _usersDao.listAll();

  @override
  Future<void> updateUser(User user) => _usersDao.update(user);
}
