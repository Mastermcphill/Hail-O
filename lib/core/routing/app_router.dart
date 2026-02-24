import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/admin/admin_home.dart';
import '../../features/auth/presentation/admin_login_screen.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/driver/driver_offer_screen.dart';
import '../../features/driver/driver_home.dart';
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
import '../../features/rider/next_of_kin_screen.dart';
import '../../features/rider/offers_screen.dart';
import '../../features/rider/paywall_screen.dart';
import '../../features/rider/rider_home.dart';
import '../../features/rider/ride_request_screen.dart';
import '../../features/rider/seat_selection_screen.dart';
import '../../features/rider/ride_status_screen.dart';
import '../api/api_client.dart';
import '../storage/token_storage.dart';

class AppRouter {
  AppRouter({required ApiClient apiClient, required TokenStorage tokenStorage})
    : _apiClient = apiClient,
      _tokenStorage = tokenStorage {
    _marketplaceModule = MarketplaceModule(apiClient: _apiClient);
    router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              LoginScreen(apiClient: _apiClient, tokenStorage: _tokenStorage),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) =>
              SignupScreen(apiClient: _apiClient, tokenStorage: _tokenStorage),
        ),
        GoRoute(
          path: '/admin-login',
          builder: (context, state) => AdminLoginScreen(
            apiClient: _apiClient,
            tokenStorage: _tokenStorage,
          ),
        ),
        ShellRoute(
          builder: (context, state, child) {
            return FutureBuilder<String?>(
              future: _tokenStorage.readRole(),
              builder: (context, snapshot) {
                final role = _normalizeRole(snapshot.data);
                return RoleNavigationScaffold(
                  currentPath: state.uri.path,
                  role: role,
                  tokenStorage: _tokenStorage,
                  child: child,
                );
              },
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
          ],
        ),
      ],
      redirect: _handleRedirect,
    );
  }

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  late final MarketplaceModule _marketplaceModule;
  late final GoRouter router;

  void dispose() {
    _marketplaceModule.dispose();
  }

  Future<String?> _handleRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final token = await _tokenStorage.readToken();
    final isAuthenticated = token != null && token.isNotEmpty;
    final path = state.uri.path;
    final isPublicPath = _publicPaths.contains(path);

    if (!isAuthenticated) {
      if (!isPublicPath) {
        return '/';
      }
      return null;
    }

    final role = _normalizeRole(await _tokenStorage.readRole());

    if (path == '/home') {
      return _homeRouteForRole(role);
    }

    if (isPublicPath) {
      return _homeRouteForRole(role);
    }

    if (_isRoleRoute(path) && !_isRoleAllowed(path, role)) {
      return _homeRouteForRole(role);
    }
    return null;
  }
}

class RoleNavigationScaffold extends StatelessWidget {
  const RoleNavigationScaffold({
    super.key,
    required this.currentPath,
    required this.role,
    required this.tokenStorage,
    required this.child,
  });

  final String currentPath;
  final String role;
  final TokenStorage tokenStorage;
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
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await tokenStorage.clearAuth();
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
          if (_isSelectedPath(currentPath, target)) {
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

const Set<String> _publicPaths = <String>{
  '/',
  '/login',
  '/signup',
  '/admin-login',
};

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

List<_NavItem> _navigationItemsForRole(String role) {
  final items = <_NavItem>[
    const _NavItem(
      path: '/health',
      label: 'Health',
      icon: Icons.health_and_safety_outlined,
    ),
  ];

  switch (_normalizeRole(role)) {
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
    if (_isSelectedPath(currentPath, items[i].path)) {
      return i;
    }
  }
  return 0;
}

bool _isSelectedPath(String currentPath, String itemPath) {
  return currentPath == itemPath || currentPath.startsWith('$itemPath/');
}

bool _isRoleRoute(String path) {
  return _roleFromPath(path) != null;
}

bool _isRoleAllowed(String path, String role) {
  final routeRole = _roleFromPath(path);
  if (routeRole == null) {
    return true;
  }
  return _normalizeRole(role) == routeRole;
}

String _homeRouteForRole(String role) {
  switch (_normalizeRole(role)) {
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

String _titleForPath(String path) {
  if (_isSelectedPath(path, '/health')) {
    return 'Health Check';
  }
  if (_isSelectedPath(path, '/rider/request')) {
    return 'Request Ride';
  }
  if (_isSelectedPath(path, '/rider/offers')) {
    return 'Ride Offers';
  }
  if (_isSelectedPath(path, '/rider/paywall')) {
    return 'Paywall';
  }
  if (_isSelectedPath(path, '/rider/seats')) {
    return 'Seat Selection';
  }
  if (_isSelectedPath(path, '/rider/status')) {
    return 'Ride Status';
  }
  if (_isSelectedPath(path, '/rider/next-of-kin')) {
    return 'Next-of-kin';
  }
  if (_isSelectedPath(path, '/driver/ride-ops')) {
    return 'Driver Ride Ops';
  }
  if (_isSelectedPath(path, '/driver/route-chain')) {
    return 'Route Chain';
  }
  if (_isSelectedPath(path, '/driver/offer')) {
    return 'Driver Offer';
  }
  if (_isSelectedPath(path, '/home')) {
    return 'Rider';
  }
  if (_isSelectedPath(path, '/rider')) {
    return 'Rider';
  }
  if (_isSelectedPath(path, '/marketplace/offers')) {
    return 'Marketplace Offers';
  }
  if (_isSelectedPath(path, '/marketplace/paywall')) {
    return 'Marketplace Paywall';
  }
  if (_isSelectedPath(path, '/marketplace/seats')) {
    return 'Marketplace Seats';
  }
  if (_isSelectedPath(path, '/marketplace/billing')) {
    return 'Marketplace Billing';
  }
  if (_isSelectedPath(path, '/marketplace/invites')) {
    return 'Marketplace Invites';
  }
  if (_isSelectedPath(path, '/marketplace/timeline')) {
    return 'Marketplace Timeline';
  }
  if (_isSelectedPath(path, '/driver')) {
    return 'Driver';
  }
  if (_isSelectedPath(path, '/fleet')) {
    return 'Fleet';
  }
  if (_isSelectedPath(path, '/admin')) {
    return 'Admin';
  }
  return 'Hail-O Core';
}

String? _roleFromPath(String path) {
  if (_isSelectedPath(path, '/home')) {
    return 'rider';
  }
  if (_isSelectedPath(path, '/rider')) {
    return 'rider';
  }
  if (_isSelectedPath(path, '/marketplace')) {
    return 'rider';
  }
  if (_isSelectedPath(path, '/driver')) {
    return 'driver';
  }
  if (_isSelectedPath(path, '/fleet')) {
    return 'fleet_owner';
  }
  if (_isSelectedPath(path, '/admin')) {
    return 'admin';
  }
  return null;
}
