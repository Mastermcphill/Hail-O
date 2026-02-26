import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/api/server_warmup_notifier.dart';
import 'core/connectivity/connectivity_notifier.dart';
import 'core/routing/app_router.dart';
import 'core/storage/token_storage.dart';
import 'features/auth/session/auth_session.dart';
import 'theme/brand_theme.dart';

class HailoCoreApp extends StatefulWidget {
  const HailoCoreApp({super.key, this.enableStartupWarmup = true});

  final bool enableStartupWarmup;

  @override
  State<HailoCoreApp> createState() => _HailoCoreAppState();
}

class _HailoCoreAppState extends State<HailoCoreApp> {
  late final TokenStorage _tokenStorage;
  late final ApiClient _apiClient;
  late final AuthSession _authSession;
  late final ServerWarmupNotifier _serverWarmupNotifier;
  late final ConnectivityNotifier _connectivityNotifier;
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
    _apiClient.setAuthFailureHandler(() => _authSession.logout());
    _authSession.init();
    _serverWarmupNotifier = ServerWarmupNotifier();
    _connectivityNotifier = ConnectivityNotifier();
    if (widget.enableStartupWarmup) {
      _serverWarmupNotifier.start(_apiClient);
      _connectivityNotifier.start();
    }
    _appRouter = AppRouter(apiClient: _apiClient, authSession: _authSession);
  }

  @override
  void dispose() {
    _appRouter.dispose();
    _serverWarmupNotifier.dispose();
    _connectivityNotifier.dispose();
    _authSession.dispose();
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthSession>.value(value: _authSession),
        ChangeNotifierProvider<ServerWarmupNotifier>.value(
          value: _serverWarmupNotifier,
        ),
        ChangeNotifierProvider<ConnectivityNotifier>.value(
          value: _connectivityNotifier,
        ),
      ],
      child: MaterialApp.router(
        title: 'Hail-O Core',
        debugShowCheckedModeBanner: false,
        theme: BrandTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en')],
        routerConfig: _appRouter.router,
        builder: (context, child) {
          final warming = context.watch<ServerWarmupNotifier>().isWarming;
          final offline = context.watch<ConnectivityNotifier>().isOffline;
          return Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              if (offline) const _OfflineBanner(message: 'Offline mode'),
              if (warming) const _WarmupBanner(message: 'Waking server...'),
            ],
          );
        },
      ),
    );
  }
}

class _WarmupBanner extends StatelessWidget {
  const _WarmupBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.inverseSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onInverseSurface,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  message,
                  style: TextStyle(color: colorScheme.onInverseSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.wifi_off_rounded,
                  size: 16,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Text(
                  message,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
