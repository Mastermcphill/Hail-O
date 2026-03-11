import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/routing/role_routes.dart';

void main() {
  group('role routes', () {
    test(
      'buildAuthRedirectPath routes admin paths to internal admin login',
      () {
        final redirect = buildAuthRedirectPath(
          requestedPath: '/admin/users',
          requestedUri: Uri.parse('/admin/users?tab=security'),
        );

        expect(redirect, startsWith('$internalAdminLoginPath?next='));
        expect(redirect, contains('admin%2Fusers'));
      },
    );

    test('buildAuthRedirectPath routes non-admin paths to login', () {
      final redirect = buildAuthRedirectPath(
        requestedPath: '/rider/request',
        requestedUri: Uri.parse('/rider/request'),
      );

      expect(redirect, startsWith('/login?next='));
    });

    test(
      'resolvePostLoginRoute falls back to role home for disallowed next',
      () {
        final route = resolvePostLoginRoute(
          role: 'rider',
          nextPath: Uri.encodeComponent('/admin'),
        );

        expect(route, '/rider');
      },
    );

    test('resolvePostLoginRoute returns safe role-allowed target', () {
      final route = resolvePostLoginRoute(
        role: 'admin',
        nextPath: Uri.encodeComponent('/admin?tab=users'),
      );

      expect(route, '/admin?tab=users');
    });

    test('role checks are normalized', () {
      expect(isRoleAllowed('/fleet', 'fleet'), isTrue);
      expect(isRoleAllowed('/admin', 'driver'), isFalse);
    });

    test('hidden admin auth path is not discoverable in public navigation', () {
      expect(isPublicPath(internalAdminLoginPath), isTrue);
      expect(isDiscoverablePublicPath(internalAdminLoginPath), isFalse);
    });

    test('preview results path stays public and discoverable', () {
      expect(isPublicPath(previewResultsPath), isTrue);
      expect(isDiscoverablePublicPath(previewResultsPath), isTrue);
    });

    test('fleet public role uses operator wording', () {
      expect(labelForPublicAccount(PublicAccountRole.fleetOwner), 'Fleet Operator');
    });
  });
}
