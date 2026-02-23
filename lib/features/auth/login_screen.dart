import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/storage/token_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.post(
        ApiPaths.authLogin,
        body: <String, dynamic>{
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );

      final token = (response['token'] as String?) ?? '';
      final role = _normalizeRole(response['role'] as String?);

      if (token.isEmpty) {
        throw Exception('Login response missing token');
      }

      await widget.tokenStorage.saveToken(token);
      await widget.tokenStorage.saveRole(role);

      if (!mounted) {
        return;
      }
      context.go(_homeRouteForRole(role));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _buildErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  onSubmitted: (_) => _isLoading ? null : _login(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _normalizeRole(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  if (normalized == 'fleet') {
    return 'fleet_owner';
  }
  if (normalized.isEmpty) {
    return 'rider';
  }
  return normalized;
}

String _buildErrorMessage(Object error) {
  return 'Login failed: ${formatApiError(error)}';
}

String _homeRouteForRole(String role) {
  switch (role) {
    case 'driver':
      return '/driver';
    case 'fleet_owner':
      return '/fleet';
    case 'admin':
      return '/admin';
    case 'rider':
    default:
      return '/rider';
  }
}
