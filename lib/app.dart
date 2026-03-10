import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/api/server_warmup_notifier.dart';
import 'core/connectivity/connectivity_notifier.dart';
import 'core/observability/app_observability.dart';
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
    _serverWarmupNotifier = ServerWarmupNotifier();
    _connectivityNotifier = ConnectivityNotifier();
    unawaited(
      AppObservability.recordStartupStage(
        stage: 'services initialized',
        detail: 'api, auth, warmup, and connectivity services created',
      ),
    );
    _apiClient.setAuthFailureHandler(() => _authSession.logout());
    _authSession.init();
    if (widget.enableStartupWarmup) {
      _serverWarmupNotifier.start(_apiClient);
      _connectivityNotifier.start();
    }
    _appRouter = AppRouter(apiClient: _apiClient, authSession: _authSession);
    unawaited(AppObservability.recordStartupStage(stage: 'router ready'));
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
          final authSession = context.watch<AuthSession>();
          final warming = context.watch<ServerWarmupNotifier>().isWarming;
          final offline = context.watch<ConnectivityNotifier>().isOffline;
          final startupNotice = authSession.startupNotice;
          return Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              if (startupNotice != null)
                _StartupRecoveryBanner(
                  message: startupNotice,
                  onDismiss: authSession.dismissStartupNotice,
                ),
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

class _StartupRecoveryBanner extends StatelessWidget {
  const _StartupRecoveryBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: colorScheme.onTertiaryContainer),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onTertiaryContainer,
                  ),
                  onPressed: onDismiss,
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
