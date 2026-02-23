import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceTimelineScreen extends StatefulWidget {
  const MarketplaceTimelineScreen({
    super.key,
    required this.purchaseId,
    this.controller,
  });

  final String purchaseId;
  final MarketplaceController? controller;

  @override
  State<MarketplaceTimelineScreen> createState() =>
      _MarketplaceTimelineScreenState();
}

class _MarketplaceTimelineScreenState extends State<MarketplaceTimelineScreen> {
  String _resolvedPurchaseId = '';

  MarketplaceController _readController(BuildContext context) {
    return widget.controller ?? context.read<MarketplaceController>();
  }

  @override
  void initState() {
    super.initState();
    _resolvedPurchaseId = widget.purchaseId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final controller = _readController(context);
      _resolvedPurchaseId = await controller.resolvePurchaseId(
        widget.purchaseId,
      );
      await controller.loadPurchase(_resolvedPurchaseId);
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _refresh(MarketplaceController controller) async {
    await controller.flushOutbox();
    await controller.loadPurchase(_resolvedPurchaseId);
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
    final events = controller.timeline;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Marketplace Timeline',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              if (controller.offlineMode)
                const Chip(label: Text('Offline mode')),
              if (controller.isSyncing)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('purchaseId: $_resolvedPurchaseId'),
          const SizedBox(height: 8),
          MarketplaceTeamSelector(
            controller: controller,
            onOpenInvites: () => context.go('/marketplace/invites'),
            onOpenBilling: () => context.go('/marketplace/billing'),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: () {
                  if (!controller.canManageBilling) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("You don't have billing permission"),
                      ),
                    );
                    return;
                  }
                  context.go(
                    '/marketplace/seats'
                    '?offerId=${Uri.encodeQueryComponent(controller.purchase?.offerId ?? '')}'
                    '&purchaseId=${Uri.encodeQueryComponent(_resolvedPurchaseId)}',
                  );
                },
                child: const Text('Manage seats'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  if (!controller.canManageBilling) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("You don't have billing permission"),
                      ),
                    );
                    return;
                  }
                  context.go('/marketplace/offers');
                },
                child: const Text('Change plan'),
              ),
              FilledButton.tonal(
                onPressed: controller.canManageBilling
                    ? () => context.go('/marketplace/billing')
                    : null,
                child: const Text('View billing'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(controller),
              child: events.isEmpty
                  ? ListView(
                      children: const <Widget>[
                        SizedBox(height: 120),
                        Center(child: Text('No timeline events yet.')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return ListTile(
                          key: Key('marketplace_timeline_event_$index'),
                          leading: Icon(
                            event.status == 'error'
                                ? Icons.error_outline
                                : event.status == 'warning'
                                ? Icons.warning_amber_outlined
                                : Icons.check_circle_outline,
                          ),
                          title: Text(event.title),
                          subtitle: Text(
                            '${event.description}\n${event.timestamp?.toLocal().toIso8601String() ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: event.cursor == null
                              ? null
                              : Text(event.cursor!),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
