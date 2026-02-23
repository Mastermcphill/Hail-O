import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceOffersScreen extends StatefulWidget {
  const MarketplaceOffersScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  State<MarketplaceOffersScreen> createState() =>
      _MarketplaceOffersScreenState();
}

class _MarketplaceOffersScreenState extends State<MarketplaceOffersScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.initializeOffers();
      await widget.controller.startSyncLoop();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.stopSyncLoop();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                offer.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(offer.subtitle),
                              const SizedBox(height: 8),
                              Text(
                                '${offer.currency} ${offer.price} / ${offer.interval}',
                              ),
                              const SizedBox(height: 8),
                              if (offer.perks.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: offer.perks
                                      .map((perk) => Chip(label: Text(perk)))
                                      .toList(growable: false),
                                ),
                              const SizedBox(height: 10),
                              FilledButton(
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
                                  context.go(
                                    '/marketplace/paywall'
                                    '?offerId=${Uri.encodeQueryComponent(offer.id)}',
                                  );
                                },
                                child: const Text('Choose plan'),
                              ),
                            ],
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
