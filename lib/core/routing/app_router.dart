import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../observability/app_observability.dart';
import '../../features/admin/admin_home.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/presentation/admin_login_screen.dart';
import '../../features/auth/presentation/boot_screen.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/session/auth_session.dart';
import '../../features/driver/driver_home.dart';
import '../../features/driver/driver_offer_screen.dart';
import '../../features/driver/driver_ride_ops_screen.dart';
import '../../features/driver/route_chain_screen.dart';
import '../../features/dispatch/data/dispatch_repository.dart';
import '../../features/dispatch/ui/dispatch_trip_create_screen.dart';
import '../../features/dispatch/ui/dispatch_trip_detail_screen.dart';
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
import '../../features/rider/next_of_kin_screen.dart';
import '../../features/rider/offers_screen.dart';
import '../../features/rider/paywall_screen.dart';
import '../../features/rider/rider_home.dart';
import '../../features/rider/ride_request_screen.dart';
import '../../features/rider/ride_status_screen.dart';
import '../../features/rider/seat_selection_screen.dart';
import '../../features/rider/timeline_screen.dart';
import '../../features/rider/documents_screen.dart';
import '../../features/settings/about_screen.dart';
import '../api/api_client.dart';
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
        GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              LoginScreen(nextPath: state.uri.queryParameters['next']),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) =>
              SignupScreen(nextPath: state.uri.queryParameters['next']),
        ),
        GoRoute(
          path: '/admin-login',
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
              path: '/rider/request',
              builder: (context, state) =>
                  RideRequestScreen(apiClient: _apiClient),
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
              builder: (context, state) => DriverHome(apiClient: _apiClient),
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
        return _recordFirstRouteDecision(path, '/');
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
      return _recordFirstRouteDecision(path, homeRouteForRole(role));
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
    final items = _navigationItemsForRole(role);
    final selectedIndex = _selectedIndexForPath(items, currentPath);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForPath(currentPath)),
        actions: <Widget>[
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.go('/settings/about'),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authSession.logout();
              if (!context.mounted) {
                return;
              }
              context.go('/');
            },
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final target = items[index].path;
          if (isSelectedPath(currentPath, target)) {
            return;
          }
          context.go(target);
        },
        destinations: <NavigationDestination>[
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.path, required this.label, required this.icon});

  final String path;
  final String label;
  final IconData icon;
}

List<_NavItem> _navigationItemsForRole(String role) {
  final items = <_NavItem>[
    const _NavItem(
      path: '/health',
      label: 'Health',
      icon: Icons.health_and_safety_outlined,
    ),
  ];

  switch (normalizeRole(role)) {
    case 'driver':
      items.add(
        const _NavItem(
          path: '/driver',
          label: 'Driver',
          icon: Icons.local_taxi_outlined,
        ),
      );
      break;
    case 'fleet_owner':
      items.add(
        const _NavItem(
          path: '/fleet',
          label: 'Fleet',
          icon: Icons.directions_bus_outlined,
        ),
      );
      break;
    case 'admin':
      items.add(
        const _NavItem(
          path: '/admin',
          label: 'Admin',
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
      break;
    case 'rider':
    default:
      items.add(
        const _NavItem(
          path: '/rider',
          label: 'Rider',
          icon: Icons.person_outline,
        ),
      );
      break;
  }
  return items;
}

int _selectedIndexForPath(List<_NavItem> items, String currentPath) {
  for (var i = 0; i < items.length; i++) {
    if (isSelectedPath(currentPath, items[i].path)) {
      return i;
    }
  }
  return 0;
}

String _titleForPath(String path) {
  if (isSelectedPath(path, '/health')) {
    return 'Health Check';
  }
  if (isSelectedPath(path, '/rider/request')) {
    return 'Request Ride';
  }
  if (isSelectedPath(path, '/rider/offers')) {
    return 'Ride Offers';
  }
  if (isSelectedPath(path, '/rider/paywall')) {
    return 'Paywall';
  }
  if (isSelectedPath(path, '/rider/seats')) {
    return 'Seat Selection';
  }
  if (isSelectedPath(path, '/rider/status')) {
    return 'Ride Status';
  }
  if (isSelectedPath(path, '/rider/next-of-kin')) {
    return 'Next-of-kin';
  }
  if (isSelectedPath(path, '/rider/documents')) {
    return 'Documents';
  }
  if (isSelectedPath(path, '/rider/timeline')) {
    return 'Timeline';
  }
  if (isSelectedPath(path, '/dispatch/trips/new')) {
    return 'Dispatch Create';
  }
  if (isSelectedPath(path, '/dispatch/trips')) {
    return 'Dispatch Trip';
  }
  if (isSelectedPath(path, '/driver/ride-ops')) {
    return 'Driver Ride Ops';
  }
  if (isSelectedPath(path, '/driver/route-chain')) {
    return 'Route Chain';
  }
  if (isSelectedPath(path, '/driver/offer')) {
    return 'Driver Offer';
  }
  if (isSelectedPath(path, '/home')) {
    return 'Rider';
  }
  if (isSelectedPath(path, '/rider')) {
    return 'Rider';
  }
  if (isSelectedPath(path, '/marketplace/offers')) {
    return 'Marketplace Offers';
  }
  if (isSelectedPath(path, '/marketplace/paywall')) {
    return 'Marketplace Paywall';
  }
  if (isSelectedPath(path, '/marketplace/seats')) {
    return 'Marketplace Seats';
  }
  if (isSelectedPath(path, '/marketplace/billing')) {
    return 'Marketplace Billing';
  }
  if (isSelectedPath(path, '/marketplace/invites')) {
    return 'Marketplace Invites';
  }
  if (isSelectedPath(path, '/marketplace/timeline')) {
    return 'Marketplace Timeline';
  }
  if (isSelectedPath(path, '/driver')) {
    return 'Driver';
  }
  if (isSelectedPath(path, '/fleet')) {
    return 'Fleet';
  }
  if (isSelectedPath(path, '/admin')) {
    return 'Admin';
  }
  if (isSelectedPath(path, '/settings/about')) {
    return 'About';
  }
  return 'Hail-O Core';
}
