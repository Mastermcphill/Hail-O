import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/admin/admin_home.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/presentation/admin_login_screen.dart';
import '../../features/auth/presentation/boot_screen.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/session/auth_session.dart';
import '../../features/dispatch/data/dispatch_repository.dart';
import '../../features/dispatch/ui/dispatch_trip_create_screen.dart';
import '../../features/dispatch/ui/dispatch_trip_detail_screen.dart';
import '../../features/driver/driver_home.dart';
import '../../features/driver/driver_offer_screen.dart';
import '../../features/driver/driver_ride_ops_screen.dart';
import '../../features/driver/route_chain_screen.dart';
import '../../features/fleet/fleet_home.dart';
import '../../features/health/health_screen.dart';
import '../../features/marketplace/marketplace_module.dart';
import '../../features/marketplace/ui/billing_screen.dart';
import '../../features/marketplace/ui/invite_screen.dart';
import '../../features/marketplace/ui/manage_seats_screen.dart';
import '../../features/marketplace/ui/offers_screen.dart';
import '../../features/marketplace/ui/paywall_screen.dart';
import '../../features/marketplace/ui/plan_change_preview_screen.dart';
import '../../features/marketplace/ui/receipt_screen.dart';
import '../../features/marketplace/ui/seats_screen.dart';
import '../../features/marketplace/ui/timeline_screen.dart';
import '../../features/rider/documents_screen.dart';
import '../../features/rider/next_of_kin_screen.dart';
import '../../features/rider/offers_screen.dart';
import '../../features/rider/paywall_screen.dart';
import '../../features/rider/rider_home.dart';
import '../../features/rider/ride_request_screen.dart';
import '../../features/rider/ride_status_screen.dart';
import '../../features/rider/seat_selection_screen.dart';
import '../../features/rider/timeline_screen.dart';
import '../../features/rideshare/presentation/public_ride_preview_screen.dart';
import '../../features/rideshare/presentation/rider_map_screen.dart';
import '../../features/rideshare/presentation/rider_payments_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../api/api_client.dart';
import '../observability/app_observability.dart';
import 'role_routes.dart';

class AppRouter {
  AppRouter({required ApiClient apiClient, required AuthSession authSession})
    : _apiClient = apiClient,
      _authSession = authSession {
    _marketplaceModule = MarketplaceModule(apiClient: _apiClient);
    _dispatchRepository = DispatchRepository(apiClient: _apiClient);
    router = GoRouter(
      initialLocation: bootPath,
      refreshListenable: _authSession,
      routes: <RouteBase>[
        GoRoute(
          path: bootPath,
          builder: (context, state) => const BootScreen(),
        ),
        GoRoute(
          path: landingPath,
          builder: (context, state) => const LandingScreen(),
        ),
        GoRoute(
          path: previewResultsPath,
          builder: (context, state) => PublicRidePreviewScreen(
            draftEncoded: state.uri.queryParameters['draft'],
          ),
        ),
        GoRoute(
          path: loginPath,
          builder: (context, state) =>
              LoginScreen(nextPath: state.uri.queryParameters['next']),
        ),
        GoRoute(
          path: signupPath,
          builder: (context, state) => SignupScreen(
            nextPath: state.uri.queryParameters['next'],
            accountRole: PublicAccountRole.rider,
          ),
        ),
        GoRoute(
          path: driverApplicationPath,
          builder: (context, state) => SignupScreen(
            nextPath: state.uri.queryParameters['next'],
            accountRole: PublicAccountRole.driver,
          ),
        ),
        GoRoute(
          path: fleetRegistrationPath,
          builder: (context, state) => SignupScreen(
            nextPath: state.uri.queryParameters['next'],
            accountRole: PublicAccountRole.fleetOwner,
          ),
        ),
        GoRoute(
          path: internalAdminLoginPath,
          builder: (context, state) =>
              AdminLoginScreen(nextPath: state.uri.queryParameters['next']),
        ),
        ShellRoute(
          builder: (context, state, child) {
            return RoleNavigationScaffold(
              currentPath: state.uri.path,
              role: _authSession.roleNormalized,
              authSession: _authSession,
              child: child,
            );
          },
          routes: <RouteBase>[
            GoRoute(
              path: '/health',
              builder: (context, state) => HealthScreen(apiClient: _apiClient),
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) => const RiderHome(),
            ),
            GoRoute(
              path: '/rider',
              builder: (context, state) => const RiderHome(),
            ),
            GoRoute(
              path: '/rider/trips',
              builder: (context, state) => const RiderTripsScreen(),
            ),
            GoRoute(
              path: '/rider/safety',
              builder: (context, state) => const RiderSafetyScreen(),
            ),
            GoRoute(
              path: '/rider/profile',
              builder: (context, state) => const RiderProfileScreen(),
            ),
            GoRoute(
              path: '/rider/map',
              builder: (context, state) => const RiderMapScreen(),
            ),
            GoRoute(
              path: '/rider/payments',
              builder: (context, state) => const RiderPaymentsScreen(),
            ),
            GoRoute(
              path: '/rider/request',
              builder: (context, state) => RideRequestScreen(
                apiClient: _apiClient,
                draftEncoded: state.uri.queryParameters['draft'],
                autoSearch:
                    (state.uri.queryParameters['autosearch'] ?? '')
                        .toLowerCase() ==
                    '1',
              ),
            ),
            GoRoute(
              path: '/rider/status/:rideId',
              builder: (context, state) => RideStatusScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
              ),
            ),
            GoRoute(
              path: '/rider/offers/:rideId',
              builder: (context, state) => OffersScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
                initialLuggageCount: int.tryParse(
                  state.uri.queryParameters['luggage_count'] ?? '',
                ),
                charterMode:
                    (state.uri.queryParameters['charter_mode'] ?? '')
                        .toLowerCase() ==
                    'true',
                expired:
                    (state.uri.queryParameters['expired'] ?? '')
                        .toLowerCase() ==
                    'true',
                draftEncoded: state.uri.queryParameters['draft'],
              ),
            ),
            GoRoute(
              path: '/rider/paywall/:rideId',
              builder: (context, state) => PaywallScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
                charterMode:
                    (state.uri.queryParameters['charter_mode'] ?? '')
                        .toLowerCase() ==
                    'true',
                draftEncoded: state.uri.queryParameters['draft'],
                offerPriceMinor: int.tryParse(
                  state.uri.queryParameters['offer_price_minor'] ?? '',
                ),
                luggageCount: int.tryParse(
                  state.uri.queryParameters['luggage_count'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/rider/seats/:rideId',
              builder: (context, state) => SeatSelectionScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
                charterMode:
                    (state.uri.queryParameters['charter_mode'] ?? '')
                        .toLowerCase() ==
                    'true',
                draftEncoded: state.uri.queryParameters['draft'],
              ),
            ),
            GoRoute(
              path: '/rider/next-of-kin',
              builder: (context, state) => NextOfKinScreen(
                apiClient: _apiClient,
                returnTo: state.uri.queryParameters['return_to'],
              ),
            ),
            GoRoute(
              path: '/rider/documents',
              builder: (context, state) => RiderDocumentsScreen(
                apiClient: _apiClient,
                returnTo: state.uri.queryParameters['return_to'],
              ),
            ),
            GoRoute(
              path: '/rider/timeline/:purchaseId',
              builder: (context, state) => TimelineScreen(
                apiClient: _apiClient,
                purchaseId: state.pathParameters['purchaseId'] ?? '',
                rideId: state.uri.queryParameters['rideId'],
              ),
            ),
            GoRoute(
              path: '/dispatch/trips/new',
              builder: (context, state) =>
                  DispatchTripCreateScreen(repository: _dispatchRepository),
            ),
            GoRoute(
              path: '/dispatch/trips/:tripId',
              builder: (context, state) => DispatchTripDetailScreen(
                repository: _dispatchRepository,
                tripId: state.pathParameters['tripId'] ?? '',
              ),
            ),
            GoRoute(
              path: '/marketplace/offers',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceOffersScreen(
                  currentPurchaseId: state.uri.queryParameters['purchaseId'],
                  currentOfferId: state.uri.queryParameters['currentOfferId'],
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/paywall',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplacePaywallScreen(
                  offerId: state.uri.queryParameters['offerId'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/seats',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceSeatsScreen(
                  offerId: state.uri.queryParameters['offerId'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/receipt',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceReceiptScreen(
                  purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
                  fallbackOfferId: state.uri.queryParameters['offerId'],
                  fallbackSeatCount: int.tryParse(
                    state.uri.queryParameters['seatCount'] ?? '',
                  ),
                  fallbackTotalPriceMinor: int.tryParse(
                    state.uri.queryParameters['totalPriceMinor'] ?? '',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/seats/manage/:purchaseId',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceManageSeatsScreen(
                  purchaseId: state.pathParameters['purchaseId'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/upgrade',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplacePlanChangePreviewScreen(
                  purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
                  currentOfferId:
                      state.uri.queryParameters['currentOfferId'] ?? '',
                  newOfferId: state.uri.queryParameters['newOfferId'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/billing',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: const MarketplaceBillingScreen(),
              ),
            ),
            GoRoute(
              path: '/marketplace/invites',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceInviteScreen(
                  initialToken: state.uri.queryParameters['token'],
                ),
              ),
            ),
            GoRoute(
              path: '/marketplace/timeline',
              builder: (context, state) => ChangeNotifierProvider.value(
                value: _marketplaceModule.controller,
                child: MarketplaceTimelineScreen(
                  purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/driver',
              builder: (context, state) => const DriverHome(),
            ),
            GoRoute(
              path: '/driver/jobs',
              builder: (context, state) => const DriverJobsScreen(),
            ),
            GoRoute(
              path: '/driver/earnings',
              builder: (context, state) => const DriverEarningsScreen(),
            ),
            GoRoute(
              path: '/driver/profile',
              builder: (context, state) => const DriverProfileScreen(),
            ),
            GoRoute(
              path: '/driver/route-chain',
              builder: (context, state) =>
                  RouteChainScreen(apiClient: _apiClient),
            ),
            GoRoute(
              path: '/driver/offer',
              builder: (context, state) =>
                  DriverOfferScreen(apiClient: _apiClient),
            ),
            GoRoute(
              path: '/driver/offer/:rideId',
              builder: (context, state) => DriverOfferScreen(
                apiClient: _apiClient,
                initialRideId: state.pathParameters['rideId'],
              ),
            ),
            GoRoute(
              path: '/driver/ride-ops',
              builder: (context, state) =>
                  DriverRideOpsScreen(apiClient: _apiClient),
            ),
            GoRoute(
              path: '/driver/ride-ops/:rideId',
              builder: (context, state) => DriverRideOpsScreen(
                apiClient: _apiClient,
                initialRideId: state.pathParameters['rideId'],
              ),
            ),
            GoRoute(
              path: '/fleet',
              builder: (context, state) => const FleetHome(),
            ),
            GoRoute(
              path: '/fleet/vehicles',
              builder: (context, state) => const FleetVehiclesScreen(),
            ),
            GoRoute(
              path: '/fleet/drivers',
              builder: (context, state) => const FleetDriversScreen(),
            ),
            GoRoute(
              path: '/fleet/operations',
              builder: (context, state) => const FleetOperationsScreen(),
            ),
            GoRoute(
              path: '/admin',
              builder: (context, state) => const AdminHome(),
            ),
            GoRoute(
              path: '/settings/about',
              builder: (context, state) => const AboutScreen(),
            ),
          ],
        ),
      ],
      redirect: _handleRedirect,
    );
    router.routeInformationProvider.addListener(_handleRouteChange);
  }

  final ApiClient _apiClient;
  final AuthSession _authSession;
  late final MarketplaceModule _marketplaceModule;
  late final DispatchRepository _dispatchRepository;
  late final GoRouter router;
  bool _loggedFirstRouteDecision = false;
  bool _loggedSplashDismissed = false;

  void dispose() {
    router.routeInformationProvider.removeListener(_handleRouteChange);
    _marketplaceModule.dispose();
  }

  void _handleRouteChange() {
    if (_loggedSplashDismissed) {
      return;
    }
    final currentPath = router.routeInformationProvider.value.uri.path;
    if (currentPath == bootPath) {
      return;
    }
    _loggedSplashDismissed = true;
    unawaited(
      AppObservability.recordStartupStage(
        stage: 'splash dismissed',
        detail: 'route=$currentPath',
      ),
    );
  }

  String? _handleRedirect(BuildContext context, GoRouterState state) {
    final path = state.uri.path;

    if (!_authSession.isReady) {
      if (path == bootPath) {
        return _recordFirstRouteDecision(path, null);
      }
      return _recordFirstRouteDecision(path, bootPath);
    }

    if (!_authSession.isAuthenticated) {
      if (path == bootPath) {
        return _recordFirstRouteDecision(path, landingPath);
      }
      if (isPublicPath(path)) {
        return _recordFirstRouteDecision(path, null);
      }
      return _recordFirstRouteDecision(
        path,
        buildAuthRedirectPath(requestedPath: path, requestedUri: state.uri),
      );
    }

    final role = _authSession.roleNormalized;
    if (path == bootPath || path == '/home') {
      return _recordFirstRouteDecision(path, homeRouteForRole(role));
    }

    if (isPublicPath(path)) {
      final allowAuthenticatedPublicFlow =
          path == driverApplicationPath ||
          path == fleetRegistrationPath ||
          path == previewResultsPath;
      if (!allowAuthenticatedPublicFlow) {
        return _recordFirstRouteDecision(path, homeRouteForRole(role));
      }
    }

    if (isRoleRoute(path) && !isRoleAllowed(path, role)) {
      return _recordFirstRouteDecision(path, homeRouteForRole(role));
    }
    return _recordFirstRouteDecision(path, null);
  }

  String? _recordFirstRouteDecision(String path, String? redirectTarget) {
    if (_loggedFirstRouteDecision) {
      return redirectTarget;
    }
    _loggedFirstRouteDecision = true;
    final resolvedTarget = redirectTarget ?? path;
    unawaited(
      AppObservability.recordStartupStage(
        stage: 'first route decision made',
        detail: '$path -> $resolvedTarget',
      ),
    );
    return redirectTarget;
  }
}

class RoleNavigationScaffold extends StatelessWidget {
  const RoleNavigationScaffold({
    super.key,
    required this.currentPath,
    required this.role,
    required this.authSession,
    required this.child,
  });

  final String currentPath;
  final String role;
  final AuthSession authSession;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final normalizedRole = normalizeRole(role);
    final items = _navigationItemsForRole(normalizedRole);
    final sectionPath = _navigationSectionPath(currentPath, normalizedRole);
    final selectedIndex = _selectedIndexForPath(items, sectionPath);
    final isRootDestination = _isRootDestinationPath(
      currentPath,
      normalizedRole,
    );
    final showShellChrome =
        currentPath != '/settings/about' &&
        currentPath != '/rider' &&
        currentPath != '/home';
    final showBottomNavigation = showShellChrome && items.length > 1;

    return BrandBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: showShellChrome
            ? AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: 78,
                titleSpacing: HailoSpacing.lg,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _shellEyebrowForRole(normalizedRole),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.3,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_titleForPath(currentPath)),
                  ],
                ),
                leadingWidth: isRootDestination ? 0 : 76,
                leading: isRootDestination
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: HailoSpacing.md),
                        child: IconButton.filledTonal(
                          tooltip: 'Back',
                          onPressed: () => _handleBack(context, normalizedRole),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                actions: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: HailoSpacing.md),
                    child: PopupMenuButton<_ShellAction>(
                      tooltip: 'More',
                      position: PopupMenuPosition.under,
                      onSelected: (_ShellAction action) async {
                        switch (action) {
                          case _ShellAction.about:
                            context.go('/settings/about');
                            break;
                          case _ShellAction.signOut:
                            await authSession.logout();
                            if (!context.mounted) {
                              return;
                            }
                            context.go(landingPath);
                            break;
                        }
                      },
                      itemBuilder: (context) => <PopupMenuEntry<_ShellAction>>[
                        if (currentPath != '/settings/about')
                          const PopupMenuItem<_ShellAction>(
                            value: _ShellAction.about,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.info_outline_rounded),
                              title: Text('About HAIL-O'),
                            ),
                          ),
                        const PopupMenuItem<_ShellAction>(
                          value: _ShellAction.signOut,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.logout_rounded),
                            title: Text('Sign out'),
                          ),
                        ),
                      ],
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: HailoRadii.pill,
                          border: Border.all(
                            color: context.hailoTokens.outlineSoft,
                          ),
                        ),
                        child: const Icon(Icons.more_horiz_rounded),
                      ),
                    ),
                  ),
                ],
              )
            : null,
        body: SafeArea(top: false, child: child),
        bottomNavigationBar: showBottomNavigation
            ? SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  HailoSpacing.md,
                  0,
                  HailoSpacing.md,
                  HailoSpacing.md,
                ),
                child: PremiumPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HailoSpacing.xs,
                    vertical: HailoSpacing.xs,
                  ),
                  borderRadius: HailoRadii.xl,
                  child: NavigationBar(
                    height: 72,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) {
                      final target = items[index].path;
                      if (sectionPath == target) {
                        return;
                      }
                      context.go(target);
                    },
                    destinations: <NavigationDestination>[
                      for (final item in items)
                        NavigationDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon ?? item.icon),
                          label: item.label,
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }

  void _handleBack(BuildContext context, String normalizedRole) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    context.go(_fallbackBackPath(currentPath, normalizedRole));
  }
}

enum _ShellAction { about, signOut }

class _NavItem {
  const _NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
}

List<_NavItem> _navigationItemsForRole(String role) {
  switch (normalizeRole(role)) {
    case 'driver':
      return const <_NavItem>[
        _NavItem(
          path: '/driver',
          label: 'Home',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
        ),
        _NavItem(
          path: '/driver/jobs',
          label: 'Trips',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
        ),
        _NavItem(
          path: '/driver/earnings',
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
        ),
        _NavItem(
          path: '/driver/profile',
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ];
    case 'fleet_owner':
      return const <_NavItem>[
        _NavItem(
          path: '/fleet',
          label: 'Home',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
        ),
        _NavItem(
          path: '/fleet/vehicles',
          label: 'Vehicles',
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus_rounded,
        ),
        _NavItem(
          path: '/fleet/drivers',
          label: 'Drivers',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
        ),
        _NavItem(
          path: '/fleet/operations',
          label: 'Ops',
          icon: Icons.hub_outlined,
          selectedIcon: Icons.hub_rounded,
        ),
      ];
    case 'admin':
      return const <_NavItem>[
        _NavItem(
          path: '/admin',
          label: 'Admin',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
        ),
      ];
    case 'rider':
    default:
      return const <_NavItem>[
        _NavItem(
          path: '/rider',
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        _NavItem(
          path: '/rider/trips',
          label: 'Trips',
          icon: Icons.route_outlined,
          selectedIcon: Icons.route_rounded,
        ),
        _NavItem(
          path: '/rider/map',
          label: 'Map',
          icon: Icons.map_outlined,
          selectedIcon: Icons.map_rounded,
        ),
        _NavItem(
          path: '/rider/payments',
          label: 'Payments',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments_rounded,
        ),
        _NavItem(
          path: '/rider/profile',
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ];
  }
}

int _selectedIndexForPath(List<_NavItem> items, String currentPath) {
  for (var index = 0; index < items.length; index++) {
    if (isSelectedPath(currentPath, items[index].path)) {
      return index;
    }
  }
  return 0;
}

String _navigationSectionPath(String currentPath, String role) {
  switch (normalizeRole(role)) {
    case 'driver':
      if (isSelectedPath(currentPath, '/driver/offer') ||
          isSelectedPath(currentPath, '/driver/ride-ops') ||
          isSelectedPath(currentPath, '/driver/jobs')) {
        return '/driver/jobs';
      }
      if (isSelectedPath(currentPath, '/driver/earnings')) {
        return '/driver/earnings';
      }
      if (isSelectedPath(currentPath, '/driver/profile') ||
          isSelectedPath(currentPath, '/driver/route-chain')) {
        return '/driver/profile';
      }
      return '/driver';
    case 'fleet_owner':
      if (isSelectedPath(currentPath, '/fleet/vehicles')) {
        return '/fleet/vehicles';
      }
      if (isSelectedPath(currentPath, '/fleet/drivers')) {
        return '/fleet/drivers';
      }
      if (isSelectedPath(currentPath, '/fleet/operations')) {
        return '/fleet/operations';
      }
      return '/fleet';
    case 'admin':
      return '/admin';
    case 'rider':
    default:
      if (isSelectedPath(currentPath, '/rider/map')) {
        return '/rider/map';
      }
      if (isSelectedPath(currentPath, '/rider/payments')) {
        return '/rider/payments';
      }
      if (isSelectedPath(currentPath, '/rider/safety')) {
        return '/rider/profile';
      }
      if (isSelectedPath(currentPath, '/rider/profile') ||
          isSelectedPath(currentPath, '/rider/documents') ||
          isSelectedPath(currentPath, '/rider/next-of-kin')) {
        return '/rider/profile';
      }
      if (isSelectedPath(currentPath, '/rider/trips') ||
          isSelectedPath(currentPath, '/rider/request') ||
          isSelectedPath(currentPath, '/rider/status') ||
          isSelectedPath(currentPath, '/rider/offers') ||
          isSelectedPath(currentPath, '/rider/paywall') ||
          isSelectedPath(currentPath, '/rider/seats') ||
          isSelectedPath(currentPath, '/rider/timeline') ||
          isSelectedPath(currentPath, '/marketplace') ||
          isSelectedPath(currentPath, '/dispatch')) {
        return '/rider/trips';
      }
      return '/rider';
  }
}

bool _isRootDestinationPath(String currentPath, String role) {
  final sectionPath = _navigationSectionPath(currentPath, role);
  switch (normalizeRole(role)) {
    case 'driver':
      return sectionPath == currentPath &&
          <String>{
            '/driver',
            '/driver/jobs',
            '/driver/earnings',
            '/driver/profile',
          }.contains(currentPath);
    case 'fleet_owner':
      return sectionPath == currentPath &&
          <String>{
            '/fleet',
            '/fleet/vehicles',
            '/fleet/drivers',
            '/fleet/operations',
          }.contains(currentPath);
    case 'admin':
      return currentPath == '/admin';
    case 'rider':
    default:
      return sectionPath == currentPath &&
          <String>{
            '/rider',
            '/rider/trips',
            '/rider/map',
            '/rider/payments',
            '/rider/profile',
          }.contains(currentPath);
  }
}

String _fallbackBackPath(String currentPath, String role) {
  final normalizedRole = normalizeRole(role);
  if (currentPath == '/settings/about') {
    return homeRouteForRole(normalizedRole);
  }
  return _navigationSectionPath(currentPath, normalizedRole);
}

String _shellEyebrowForRole(String role) {
  switch (normalizeRole(role)) {
    case 'driver':
      return 'Driver workspace';
    case 'fleet_owner':
      return 'Fleet workspace';
    case 'admin':
      return 'Internal only';
    case 'rider':
    default:
      return 'Passenger workspace';
  }
}

String _titleForPath(String path) {
  if (isSelectedPath(path, '/rider/request')) {
    return 'Search rides';
  }
  if (isSelectedPath(path, '/rider/status')) {
    return 'Trip tracking';
  }
  if (isSelectedPath(path, '/rider/offers')) {
    return 'Ride matches';
  }
  if (isSelectedPath(path, '/rider/paywall')) {
    return 'Booking summary';
  }
  if (isSelectedPath(path, '/rider/seats')) {
    return 'Select seats';
  }
  if (isSelectedPath(path, '/rider/timeline')) {
    return 'Trip timeline';
  }
  if (isSelectedPath(path, '/rider/map')) {
    return 'Network map';
  }
  if (isSelectedPath(path, '/rider/payments')) {
    return 'Payments';
  }
  if (isSelectedPath(path, '/rider/next-of-kin')) {
    return 'Emergency contact';
  }
  if (isSelectedPath(path, '/rider/documents')) {
    return 'Travel documents';
  }
  if (isSelectedPath(path, '/dispatch/trips/new')) {
    return 'Create dispatch trip';
  }
  if (isSelectedPath(path, '/dispatch/trips')) {
    return 'Dispatch trip';
  }
  if (isSelectedPath(path, '/marketplace/offers')) {
    return 'Travel offers';
  }
  if (isSelectedPath(path, '/marketplace/paywall')) {
    return 'Upgrade options';
  }
  if (isSelectedPath(path, '/marketplace/seats/manage')) {
    return 'Manage seats';
  }
  if (isSelectedPath(path, '/marketplace/seats')) {
    return 'Seat planning';
  }
  if (isSelectedPath(path, '/marketplace/receipt')) {
    return 'Purchase receipt';
  }
  if (isSelectedPath(path, '/marketplace/upgrade')) {
    return 'Preview change';
  }
  if (isSelectedPath(path, '/marketplace/billing')) {
    return 'Billing';
  }
  if (isSelectedPath(path, '/marketplace/invites')) {
    return 'Seat invites';
  }
  if (isSelectedPath(path, '/marketplace/timeline')) {
    return 'Purchase timeline';
  }
  if (isSelectedPath(path, '/driver/offer')) {
    return 'Offer on a trip';
  }
  if (isSelectedPath(path, '/driver/ride-ops')) {
    return 'Trip operations';
  }
  if (isSelectedPath(path, '/driver/route-chain')) {
    return 'Route chain';
  }
  if (isSelectedPath(path, '/driver/earnings')) {
    return 'Earnings';
  }
  if (isSelectedPath(path, '/driver/profile')) {
    return 'Driver profile';
  }
  if (isSelectedPath(path, '/driver/jobs')) {
    return 'Driver trips';
  }
  if (isSelectedPath(path, '/fleet/vehicles')) {
    return 'Fleet vehicles';
  }
  if (isSelectedPath(path, '/fleet/drivers')) {
    return 'Fleet drivers';
  }
  if (isSelectedPath(path, '/fleet/operations')) {
    return 'Fleet operations';
  }
  if (isSelectedPath(path, '/health')) {
    return 'System health';
  }
  if (isSelectedPath(path, '/settings/about')) {
    return 'About HAIL-O';
  }
  if (isSelectedPath(path, '/admin')) {
    return 'Internal admin';
  }
  if (isSelectedPath(path, '/driver')) {
    return 'Driver command';
  }
  if (isSelectedPath(path, '/fleet')) {
    return 'Fleet command';
  }
  if (isSelectedPath(path, '/rider/profile')) {
    return 'Profile';
  }
  if (isSelectedPath(path, '/rider/safety')) {
    return 'Safety & support';
  }
  if (isSelectedPath(path, '/rider/trips')) {
    return 'Trips';
  }
  if (isSelectedPath(path, '/rider') || isSelectedPath(path, '/home')) {
    return 'Passenger home';
  }
  return 'HAIL-O';
}
