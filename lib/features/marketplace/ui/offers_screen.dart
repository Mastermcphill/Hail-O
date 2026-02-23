import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';

class MarketplaceOffersScreen extends StatefulWidget {
  const MarketplaceOffersScreen({
    super.key,
    this.currentPurchaseId,
    this.currentOfferId,
  });

  final String? currentPurchaseId;
  final String? currentOfferId;

  @override
  State<MarketplaceOffersScreen> createState() =>
      _MarketplaceOffersScreenState();
}

class _MarketplaceOffersScreenState extends State<MarketplaceOffersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<MarketplaceController>().loadOffers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        if (controller.loadingOffers && controller.offers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage != null && controller.offers.isEmpty) {
          return _ErrorState(
            message: controller.errorMessage!,
            onRetry: controller.loadOffers,
          );
        }

        if (controller.offers.isEmpty) {
          return _EmptyState(onRetry: controller.loadOffers);
        }

        return RefreshIndicator(
          onRefresh: controller.loadOffers,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: controller.offers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final offer = controller.offers[index];
              final isCurrentOffer = widget.currentOfferId == offer.id;
              final isPlanChange = (widget.currentPurchaseId ?? '').isNotEmpty;
              return Card(
                key: Key('marketplace_offer_card_$index'),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        offer.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (isCurrentOffer) ...<Widget>[
                        const SizedBox(height: 6),
                        const Chip(
                          label: Text('Current plan'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: <Widget>[
                          _InfoChip(label: offer.vehicleClass),
                          _InfoChip(
                            label: 'rating ${offer.rating.toStringAsFixed(1)}',
                          ),
                          _InfoChip(label: '${offer.etaMinutes} min ETA'),
                          _InfoChip(label: '${offer.seatsAvailable} seats'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final bullet in offer.highlights)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('- $bullet'),
                        ),
                      const SizedBox(height: 10),
                      Text('Price: ${offer.priceMinor} minor units'),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: Key('marketplace_offer_continue_$index'),
                          onPressed: isPlanChange && isCurrentOffer
                              ? null
                              : () {
                                  if (isPlanChange) {
                                    context.push(
                                      '/marketplace/upgrade?purchaseId='
                                      '${Uri.encodeQueryComponent(widget.currentPurchaseId!)}'
                                      '&currentOfferId=${Uri.encodeQueryComponent(widget.currentOfferId ?? '')}'
                                      '&newOfferId=${Uri.encodeQueryComponent(offer.id)}',
                                    );
                                    return;
                                  }
                                  context.push(
                                    '/marketplace/paywall?offerId='
                                    '${Uri.encodeQueryComponent(offer.id)}',
                                  );
                                },
                          child: Text(
                            isPlanChange
                                ? (isCurrentOffer
                                      ? 'Current plan'
                                      : 'Preview change')
                                : 'Continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'No marketplace offers available right now.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Could not load offers',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
