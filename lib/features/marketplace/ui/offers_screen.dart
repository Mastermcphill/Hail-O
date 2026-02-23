import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceOffersScreen extends StatefulWidget {
  const MarketplaceOffersScreen({
    super.key,
    this.controller,
    this.currentPurchaseId,
    this.currentOfferId,
  });

  final MarketplaceController? controller;
  final String? currentPurchaseId;
  final String? currentOfferId;

  @override
  State<MarketplaceOffersScreen> createState() =>
      _MarketplaceOffersScreenState();
}

class _MarketplaceOffersScreenState extends State<MarketplaceOffersScreen> {
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
      await controller.initializeOffers();
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Marketplace Offers',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              if (controller.isSyncing)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          MarketplaceTeamSelector(
            controller: controller,
            onOpenInvites: () => context.go('/marketplace/invites'),
            onOpenBilling: () => context.go('/marketplace/billing'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (controller.offlineMode)
                const Chip(label: Text('Offline mode')),
              if (controller.pendingOutboxCount > 0)
                Chip(label: Text('Queued: ${controller.pendingOutboxCount}')),
              if (!controller.canManageBilling)
                const Chip(label: Text('Read-only role')),
            ],
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
              onPressed: controller.isLoadingOffers
                  ? null
                  : controller.refreshOffers,
              child: const Text('Refresh'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: controller.isLoadingOffers && controller.offers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : controller.offers.isEmpty
                ? const Center(child: Text('No offers cached yet.'))
                : ListView.separated(
                    itemCount: controller.offers.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final offer = controller.offers[index];
                      return Card(
                        child: ListTile(
                          title: Text(offer.title),
                          subtitle: Text(
                            '${offer.currency} ${offer.price} / ${offer.interval}',
                          ),
                          trailing: FilledButton(
                            key: Key('marketplace_offer_continue_$index'),
                            onPressed: () {
                              if (!controller.canManageBilling) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "You don't have billing permission",
                                    ),
                                  ),
                                );
                                return;
                              }
                              final purchaseId =
                                  widget.currentPurchaseId?.trim() ?? '';
                              final currentOfferId =
                                  widget.currentOfferId?.trim() ?? '';
                              if (purchaseId.isNotEmpty &&
                                  currentOfferId.isNotEmpty &&
                                  currentOfferId != offer.id) {
                                context.go(
                                  '/marketplace/upgrade'
                                  '?purchaseId=${Uri.encodeQueryComponent(purchaseId)}'
                                  '&currentOfferId=${Uri.encodeQueryComponent(currentOfferId)}'
                                  '&newOfferId=${Uri.encodeQueryComponent(offer.id)}',
                                );
                                return;
                              }
                              context.go(
                                '/marketplace/paywall'
                                '?offerId=${Uri.encodeQueryComponent(offer.id)}',
                              );
                            },
                            child: const Text('Choose'),
                          ),
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
