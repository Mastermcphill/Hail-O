import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/models/billing_invoice.dart';
import 'package:hailo_core/features/marketplace/models/pricing_breakdown.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/paywall_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('paywall shows pricing breakdown and persists applied coupon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = MarketplaceRepositoryMock();

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _routerFor(repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pricing breakdown'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('marketplace_coupon_field')),
      'SAVE500',
    );
    await tester.pump();
    final applyCouponButton = find.byKey(
      const Key('marketplace_apply_coupon_button'),
    );
    await tester.tap(applyCouponButton);
    await tester.pumpAndSettle();

    expect(find.text('-500'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _routerFor(MarketplaceRepositoryMock())),
    );
    await tester.pumpAndSettle();

    final couponField = tester.widget<TextFormField>(
      find.byKey(const Key('marketplace_coupon_field')),
    );
    expect(couponField.initialValue, 'SAVE500');
  });

  testWidgets('past due banner renders and retry payment clears banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _PastDueMarketplaceRepository();

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _routerFor(repository)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('marketplace_past_due_banner')),
      findsOneWidget,
    );

    final retryButton = find.byKey(
      const Key('marketplace_retry_invoice_button'),
    );
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('marketplace_past_due_banner')), findsNothing);
  });

  testWidgets('risk lock disables paywall mutation controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _RiskLockedMarketplaceRepository();

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _routerFor(repository)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('marketplace_coupon_field')),
      'SAVE500',
    );
    await tester.pump();
    final applyCouponButton = find.byKey(
      const Key('marketplace_apply_coupon_button'),
    );
    await tester.tap(applyCouponButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('marketplace_risk_locked_banner')),
      findsOneWidget,
    );
    final continueButton = tester.widget<FilledButton>(
      find.byKey(const Key('marketplace_paywall_continue_button')),
    );
    expect(continueButton.onPressed, isNull);
  });
}

GoRouter _routerFor(MarketplaceRepository repository) {
  return GoRouter(
    initialLocation: '/marketplace/paywall?offerId=offer_sedan_01',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) {
          return ChangeNotifierProvider<MarketplaceController>(
            create: (_) => MarketplaceController(repository: repository),
            child: Scaffold(body: child),
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/marketplace/paywall',
            builder: (context, state) => MarketplacePaywallScreen(
              offerId: state.uri.queryParameters['offerId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/marketplace/seats',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ],
  );
}

class _PastDueMarketplaceRepository extends MarketplaceRepositoryMock {
  BillingInvoice _invoice = BillingInvoice(
    invoiceId: 'inv_past_due_1',
    orgId: 'org_demo',
    purchaseId: 'purchase_demo_1',
    currency: 'NGN',
    subtotalMinor: 5200,
    discountMinor: 0,
    creditAppliedMinor: 0,
    totalDueMinor: 5200,
    status: 'past_due',
    createdAt: DateTime.now().toUtc(),
  );

  @override
  Future<List<BillingInvoice>> fetchInvoices(String orgId) async {
    return <BillingInvoice>[_invoice];
  }

  @override
  Future<BillingInvoice?> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    _invoice = BillingInvoice(
      invoiceId: _invoice.invoiceId,
      orgId: _invoice.orgId,
      purchaseId: _invoice.purchaseId,
      currency: _invoice.currency,
      subtotalMinor: _invoice.subtotalMinor,
      discountMinor: _invoice.discountMinor,
      creditAppliedMinor: _invoice.creditAppliedMinor,
      totalDueMinor: _invoice.totalDueMinor,
      status: 'paid',
      createdAt: _invoice.createdAt,
    );
    return _invoice;
  }
}

class _RiskLockedMarketplaceRepository extends MarketplaceRepositoryMock {
  @override
  Future<PricingBreakdown> applyCoupon({
    required String orgId,
    required String couponCode,
    required String offerId,
    required int seats,
  }) {
    throw const MarketplaceRepositoryException(
      'RISK_LOCKED: account restricted',
      code: 'RISK_LOCKED',
    );
  }
}
