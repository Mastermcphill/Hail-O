import '../../domain/models/user.dart';

abstract class UserRepository {
  Future<void> createUser(User user);
  Future<void> updateUser(User user);
  Future<User?> getUser(String userId);
  Future<List<User>> listUsers();
}
