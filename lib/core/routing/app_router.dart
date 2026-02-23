import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_home.dart';
import '../../features/auth/login_screen.dart';
import '../../features/driver/driver_offer_screen.dart';
import '../../features/driver/driver_home.dart';
import '../../features/driver/driver_ride_ops_screen.dart';
import '../../features/driver/route_chain_screen.dart';
import '../../features/fleet/fleet_home.dart';
import '../../features/health/health_screen.dart';
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
    router = GoRouter(
      initialLocation: '/login',
      routes: <RouteBase>[
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              LoginScreen(apiClient: _apiClient, tokenStorage: _tokenStorage),
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
              path: '/rider',
              builder: (context, state) => const RiderHome(),
            ),
            GoRoute(
              path: '/rider/request',
              builder: (context, state) => RideRequestScreen(
                apiClient: _apiClient,
                tokenStorage: _tokenStorage,
              ),
            ),
            GoRoute(
              path: '/rider/next-of-kin',
              builder: (context, state) => NextOfKinScreen(
                apiClient: _apiClient,
                tokenStorage: _tokenStorage,
                returnTo:
                    state.uri.queryParameters['returnTo'] ?? '/rider/request',
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
                luggageCount:
                    int.tryParse(state.uri.queryParameters['luggage'] ?? '0') ??
                    0,
                charterMode: state.uri.queryParameters['charter'] == '1',
              ),
            ),
            GoRoute(
              path: '/rider/paywall/:rideId',
              builder: (context, state) => PaywallScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
                offerPriceMinor:
                    int.tryParse(
                      state.uri.queryParameters['offerPrice'] ?? '0',
                    ) ??
                    0,
                charterMode: state.uri.queryParameters['charter'] == '1',
                luggageCount:
                    int.tryParse(state.uri.queryParameters['luggage'] ?? '0') ??
                    0,
              ),
            ),
            GoRoute(
              path: '/rider/seats/:rideId',
              builder: (context, state) => SeatSelectionScreen(
                apiClient: _apiClient,
                rideId: state.pathParameters['rideId'] ?? '',
                offerPriceMinor:
                    int.tryParse(
                      state.uri.queryParameters['offerPrice'] ?? '0',
                    ) ??
                    0,
                charterMode: state.uri.queryParameters['charter'] == '1',
              ),
            ),
            GoRoute(
              path: '/driver',
              builder: (context, state) => const DriverHome(),
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
              path: '/driver/route-chain',
              builder: (context, state) => RouteChainScreen(
                apiClient: _apiClient,
                tokenStorage: _tokenStorage,
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
  late final GoRouter router;

  Future<String?> _handleRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final token = await _tokenStorage.readToken();
    final isAuthenticated = token != null && token.isNotEmpty;
    final path = state.uri.path;
    final isLoginPath = path == '/login';

    if (!isAuthenticated) {
      if (!isLoginPath) {
        return '/login';
      }
      return null;
    }

    if (isLoginPath) {
      return '/health';
    }

    final role = _normalizeRole(await _tokenStorage.readRole());
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
              context.go('/login');
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
  if (_isSelectedPath(path, '/rider/next-of-kin')) {
    return 'Next of Kin';
  }
  if (_isSelectedPath(path, '/rider/status')) {
    return 'Ride Status';
  }
  if (_isSelectedPath(path, '/rider/offers')) {
    return 'Marketplace Offers';
  }
  if (_isSelectedPath(path, '/rider/paywall')) {
    return 'Connection Fee';
  }
  if (_isSelectedPath(path, '/rider/seats')) {
    return 'Seat Selection';
  }
  if (_isSelectedPath(path, '/driver/offer')) {
    return 'Driver Offer';
  }
  if (_isSelectedPath(path, '/driver/route-chain')) {
    return 'Route Chain';
  }
  if (_isSelectedPath(path, '/driver/ride-ops')) {
    return 'Driver Ride Ops';
  }
  if (_isSelectedPath(path, '/rider')) {
    return 'Rider';
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
  if (_isSelectedPath(path, '/rider')) {
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
