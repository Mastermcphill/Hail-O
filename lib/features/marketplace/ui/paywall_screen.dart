import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplacePaywallScreen extends StatefulWidget {
  const MarketplacePaywallScreen({
    super.key,
    required this.controller,
    required this.offerId,
  });

  final MarketplaceController controller;
  final String offerId;

  @override
  State<MarketplacePaywallScreen> createState() =>
      _MarketplacePaywallScreenState();
}

class _MarketplacePaywallScreenState extends State<MarketplacePaywallScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadPaywall(widget.offerId);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
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
    final paywall = controller.paywallCopy;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'Paywall',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      if (controller.offlineMode)
                        const Chip(label: Text('Offline mode')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MarketplaceTeamSelector(
                    controller: controller,
                    onOpenInvites: () => context.go('/marketplace/invites'),
                    onOpenBilling: () => context.go('/marketplace/billing'),
                  ),
                  const SizedBox(height: 10),
                  Text(paywall?.headline ?? 'Loading paywall...'),
                  const SizedBox(height: 6),
                  Text(paywall?.subhead ?? ''),
                  const SizedBox(height: 10),
                  for (final bullet in paywall?.bullets ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('- $bullet'),
                    ),
                  const SizedBox(height: 10),
                  Text(paywall?.legalText ?? ''),
                  if (controller.infoBanner != null &&
                      controller.infoBanner!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      controller.infoBanner!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: controller.isLoadingPaywall
                        ? null
                        : () {
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
                              '/marketplace/seats'
                              '?offerId=${Uri.encodeQueryComponent(widget.offerId)}',
                            );
                          },
                    child: controller.isLoadingPaywall
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue to Seats'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
