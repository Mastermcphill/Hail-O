import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/storage/token_storage.dart';
import 'features/auth/session/auth_session.dart';

class HailoCoreApp extends StatefulWidget {
  const HailoCoreApp({super.key});

  @override
  State<HailoCoreApp> createState() => _HailoCoreAppState();
}

class _HailoCoreAppState extends State<HailoCoreApp> {
  late final TokenStorage _tokenStorage;
  late final ApiClient _apiClient;
  late final AuthSession _authSession;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _tokenStorage = const TokenStorage();
    _apiClient = ApiClient(tokenStorage: _tokenStorage);
    _authSession = AuthSession(
      tokenStorage: _tokenStorage,
      apiClient: _apiClient,
    );
    _authSession.init();
    _appRouter = AppRouter(apiClient: _apiClient, authSession: _authSession);
  }

  @override
  void dispose() {
    _appRouter.dispose();
    _authSession.dispose();
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthSession>.value(
      value: _authSession,
      child: MaterialApp.router(
        title: 'Hail-O Core',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        routerConfig: _appRouter.router,
      ),
    );
  }
}
