import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';

class MarketplacePaywallScreen extends StatefulWidget {
  const MarketplacePaywallScreen({super.key, required this.offerId});

  final String offerId;

  @override
  State<MarketplacePaywallScreen> createState() =>
      _MarketplacePaywallScreenState();
}

class _MarketplacePaywallScreenState extends State<MarketplacePaywallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<MarketplaceController>().loadPaywall(widget.offerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        final paywall = controller.paywallCopy;

        if (controller.loadingPaywall && paywall == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage != null && paywall == null) {
          return _PaywallErrorState(
            message: controller.errorMessage!,
            onRetry: () => controller.loadPaywall(widget.offerId),
          );
        }

        if (paywall == null) {
          return _PaywallErrorState(
            message: 'Paywall copy is not available.',
            onRetry: () => controller.loadPaywall(widget.offerId),
          );
        }

        return RefreshIndicator(
          onRefresh: () => controller.loadPaywall(widget.offerId),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Connection Fee Paywall',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                paywall.headline,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Connection fee: ${paywall.connectionFeeMinor} minor units',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      for (final bullet in paywall.bullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('- $bullet'),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        paywall.legalText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('marketplace_paywall_continue_button'),
                onPressed: () {
                  context.push(
                    '/marketplace/seats?offerId='
                    '${Uri.encodeQueryComponent(widget.offerId)}',
                  );
                },
                child: Text(paywall.ctaLabel),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => controller.loadPaywall(widget.offerId),
                child: const Text('Refresh'),
              ),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PaywallErrorState extends StatelessWidget {
  const _PaywallErrorState({required this.message, required this.onRetry});

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
                'Could not load paywall',
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
