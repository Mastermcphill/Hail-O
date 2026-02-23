import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceBillingScreen extends StatefulWidget {
  const MarketplaceBillingScreen({super.key, this.controller});

  final MarketplaceController? controller;

  @override
  State<MarketplaceBillingScreen> createState() =>
      _MarketplaceBillingScreenState();
}

class _MarketplaceBillingScreenState extends State<MarketplaceBillingScreen> {
  MarketplaceController _readController(BuildContext context) {
    return widget.controller ?? context.read<MarketplaceController>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final controller = _readController(context);
      await controller.loadOrgs();
      await controller.refreshActiveOrgPurchases();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller != null) {
      return AnimatedBuilder(
        animation: widget.controller!,
        builder: (context, _) => _buildBody(context, widget.controller!),
      );
    }
    return Consumer<MarketplaceController>(
      builder: (context, controller, _) => _buildBody(context, controller),
    );
  }

  Widget _buildBody(BuildContext context, MarketplaceController controller) {
    final numberFormat = NumberFormat.decimalPattern();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Team Billing',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          MarketplaceTeamSelector(controller: controller),
          const SizedBox(height: 12),
          if (!controller.canManageBilling)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text("You don't have billing permission"),
              ),
            ),
          if (controller.infoBanner != null &&
              controller.infoBanner!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              controller.infoBanner!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: controller.isLoadingBilling
                  ? null
                  : controller.refreshActiveOrgPurchases,
              child: const Text('Refresh purchases'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: !controller.canManageBilling
                ? ListView(
                    children: const <Widget>[
                      SizedBox(height: 120),
                      Center(
                        child: Text(
                          'Billing views are available for owner, admin, or billing roles.',
                        ),
                      ),
                    ],
                  )
                : controller.isLoadingBilling &&
                      controller.activeOrgPurchases.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : controller.activeOrgPurchases.isEmpty
                ? ListView(
                    children: const <Widget>[
                      SizedBox(height: 120),
                      Center(child: Text('No purchases for this team.')),
                    ],
                  )
                : ListView.separated(
                    itemCount: controller.activeOrgPurchases.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final purchase = controller.activeOrgPurchases[index];
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${purchase.offerId} | ${purchase.status}',
                          ),
                          subtitle: Text(
                            'purchaseId: ${purchase.purchaseId}\n'
                            'seats: ${purchase.seatCount}\n'
                            'total: ${purchase.currency} ${numberFormat.format(purchase.totalAmount)}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
