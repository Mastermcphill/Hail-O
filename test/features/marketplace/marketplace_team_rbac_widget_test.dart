import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/marketplace/models/org_summary.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/billing_screen.dart';
import 'package:hailo_core/features/marketplace/ui/invite_screen.dart';
import 'package:hailo_core/features/marketplace/ui/timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_marketplace_repository.dart';
import 'memory_marketplace_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String uniqueNamespace(String suffix) {
    return 'marketplace_team_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  MarketplacePurchaseSnapshot purchase({
    required String purchaseId,
    required String offerId,
    required String orgId,
    required String role,
  }) {
    return MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: offerId,
      seatCount: 2,
      status: 'active',
      createdAt: DateTime.utc(2026, 3, 1, 10, 0, 0),
      totalAmount: 12000,
      currency: 'NGN',
      version: 1,
      assignmentsVersion: 1,
      assignments: const <MarketplaceAssignment>[],
      orgId: orgId,
      requesterRole: role,
    );
  }

  test(
    'team selection persists in SharedPreferences across controller restart',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repo = FakeMarketplaceRepository()
        ..orgs = const <MarketplaceOrgSummary>[
          MarketplaceOrgSummary(
            id: 'org-a',
            name: 'Alpha Team',
            slug: 'alpha-team',
            role: 'owner',
            memberStatus: 'active',
          ),
          MarketplaceOrgSummary(
            id: 'org-b',
            name: 'Beta Team',
            slug: 'beta-team',
            role: 'billing',
            memberStatus: 'active',
          ),
        ];
      final controllerA = MarketplaceController(
        repository: repo,
        localStore: MemoryMarketplaceLocalStore(
          namespace: uniqueNamespace('a'),
        ),
      );
      await controllerA.loadOrgs();
      expect(controllerA.activeOrgId, 'org-a');

      await controllerA.selectOrg('org-b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MarketplaceController.activeOrgPrefsKey), 'org-b');
      controllerA.dispose();

      final controllerB = MarketplaceController(
        repository: repo,
        localStore: MemoryMarketplaceLocalStore(
          namespace: uniqueNamespace('b'),
        ),
      );
      await controllerB.loadOrgs();
      expect(controllerB.activeOrgId, 'org-b');
      controllerB.dispose();
    },
  );

  testWidgets('member role cannot use billing actions from timeline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MarketplaceController.activeOrgPrefsKey: 'org-readonly',
    });
    final repo = FakeMarketplaceRepository()
      ..orgs = const <MarketplaceOrgSummary>[
        MarketplaceOrgSummary(
          id: 'org-readonly',
          name: 'Read Only',
          slug: 'read-only',
          role: 'member',
          memberStatus: 'active',
        ),
      ]
      ..purchases['purchase-readonly'] = purchase(
        purchaseId: 'purchase-readonly',
        offerId: 'starter_monthly',
        orgId: 'org-readonly',
        role: 'member',
      );
    final controller = MarketplaceController(
      repository: repo,
      localStore: MemoryMarketplaceLocalStore(
        namespace: uniqueNamespace('readonly'),
      ),
    );
    await controller.loadOrgs();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarketplaceTimelineScreen(
            controller: controller,
            purchaseId: 'purchase-readonly',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Manage seats'));
    await tester.pump();

    expect(find.text("You don't have billing permission"), findsOneWidget);

    controller.stopSyncLoop();
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invite flow submits and accepts token', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = FakeMarketplaceRepository()
      ..orgs = const <MarketplaceOrgSummary>[
        MarketplaceOrgSummary(
          id: 'org-owner',
          name: 'Owner Team',
          slug: 'owner-team',
          role: 'owner',
          memberStatus: 'active',
        ),
      ];
    final controller = MarketplaceController(
      repository: repo,
      localStore: MemoryMarketplaceLocalStore(
        namespace: uniqueNamespace('invite'),
      ),
    );
    await controller.loadOrgs();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketplaceInviteScreen(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'new@hailo.dev',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send invite'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Invite token:'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept invite'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.activeOrgId, 'org-owner');
    expect(controller.infoBanner, isNull);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching team changes visible org purchases', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = FakeMarketplaceRepository()
      ..orgs = const <MarketplaceOrgSummary>[
        MarketplaceOrgSummary(
          id: 'org-a',
          name: 'Alpha Team',
          slug: 'alpha-team',
          role: 'billing',
          memberStatus: 'active',
        ),
        MarketplaceOrgSummary(
          id: 'org-b',
          name: 'Beta Team',
          slug: 'beta-team',
          role: 'billing',
          memberStatus: 'active',
        ),
      ]
      ..purchasesByOrg['org-a'] = <MarketplacePurchaseSnapshot>[
        purchase(
          purchaseId: 'purchase-alpha',
          offerId: 'starter_monthly',
          orgId: 'org-a',
          role: 'billing',
        ),
      ]
      ..purchasesByOrg['org-b'] = <MarketplacePurchaseSnapshot>[
        purchase(
          purchaseId: 'purchase-beta',
          offerId: 'pro_monthly',
          orgId: 'org-b',
          role: 'billing',
        ),
      ];
    final controller = MarketplaceController(
      repository: repo,
      localStore: MemoryMarketplaceLocalStore(
        namespace: uniqueNamespace('switch'),
      ),
    );
    await controller.loadOrgs();
    await controller.refreshActiveOrgPurchases();
    expect(controller.activeOrgId, 'org-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketplaceBillingScreen(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('purchase-alpha'), findsOneWidget);
    expect(find.textContaining('purchase-beta'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Team').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('purchase-beta'), findsOneWidget);
    expect(find.textContaining('purchase-alpha'), findsNothing);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
