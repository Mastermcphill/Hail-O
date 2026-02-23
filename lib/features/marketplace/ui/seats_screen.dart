import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/purchase_snapshot.dart';
import '../state/marketplace_controller.dart';
import 'team_selector.dart';

class MarketplaceSeatsScreen extends StatefulWidget {
  const MarketplaceSeatsScreen({
    super.key,
    required this.controller,
    required this.offerId,
    this.purchaseId,
  });

  final MarketplaceController controller;
  final String offerId;
  final String? purchaseId;

  @override
  State<MarketplaceSeatsScreen> createState() => _MarketplaceSeatsScreenState();
}

class _MarketplaceSeatsScreenState extends State<MarketplaceSeatsScreen> {
  late int _seatCount;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _seatCount = 1;
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.purchaseId != null && widget.purchaseId!.trim().isNotEmpty) {
        await widget.controller.loadPurchase(widget.purchaseId!);
        final purchase = widget.controller.purchase;
        if (purchase != null) {
          setState(() {
            _seatCount = purchase.seatCount.clamp(1, 50);
          });
          final first = purchase.assignments.isNotEmpty
              ? purchase.assignments.first
              : null;
          _nameController.text = first?.name ?? '';
          _emailController.text = first?.email ?? '';
        }
      }
      await widget.controller.startSyncLoop(purchaseId: widget.purchaseId);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  List<MarketplaceAssignment> _buildAssignments() {
    final assignments = <MarketplaceAssignment>[
      MarketplaceAssignment(
        seatIndex: 1,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
      ),
    ];
    for (var i = 2; i <= _seatCount; i++) {
      assignments.add(
        MarketplaceAssignment(
          seatIndex: i,
          name: 'seat-$i',
          email: 'seat-$i@pending.local',
        ),
      );
    }
    return assignments;
  }

  Future<void> _confirm() async {
    final controller = widget.controller;
    if (!controller.canManageBilling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You don't have billing permission")),
      );
      return;
    }
    final existingPurchase = controller.purchase;
    final assignments = _buildAssignments();

    if (widget.purchaseId != null &&
        widget.purchaseId!.trim().isNotEmpty &&
        existingPurchase != null) {
      await controller.enqueueSeatUpdate(
        purchaseId: widget.purchaseId!,
        seatCount: _seatCount,
        baseVersion: existingPurchase.version,
      );
      await controller.enqueueAssignmentsUpdate(
        purchaseId: widget.purchaseId!,
        assignments: assignments,
        baseVersion: existingPurchase.version,
      );
      if (!mounted) {
        return;
      }
      context.go(
        '/marketplace/timeline'
        '?purchaseId=${Uri.encodeQueryComponent(widget.purchaseId!)}',
      );
      return;
    }

    final purchaseId = await controller.submitSeats(
      offerId: widget.offerId,
      seatCount: _seatCount,
      assignments: assignments,
    );
    if (!mounted) {
      return;
    }
    context.go(
      '/marketplace/timeline'
      '?purchaseId=${Uri.encodeQueryComponent(purchaseId)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Seat Selection',
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
              const SizedBox(height: 10),
              MarketplaceTeamSelector(
                controller: controller,
                onOpenInvites: () => context.go('/marketplace/invites'),
                onOpenBilling: () => context.go('/marketplace/billing'),
              ),
              const SizedBox(height: 10),
              Text('offerId: ${widget.offerId}'),
              if (widget.purchaseId != null)
                Text('purchaseId: ${widget.purchaseId}'),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('Seats'),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: !controller.canManageBilling || _seatCount <= 1
                        ? null
                        : () {
                            setState(() {
                              _seatCount = (_seatCount - 1).clamp(1, 50);
                            });
                          },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_seatCount'),
                  IconButton(
                    onPressed: !controller.canManageBilling || _seatCount >= 50
                        ? null
                        : () {
                            setState(() {
                              _seatCount = (_seatCount + 1).clamp(1, 50);
                            });
                          },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                enabled: controller.canManageBilling,
                decoration: const InputDecoration(
                  labelText: 'Primary seat name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                enabled: controller.canManageBilling,
                decoration: const InputDecoration(
                  labelText: 'Primary seat email',
                  border: OutlineInputBorder(),
                ),
              ),
              if (controller.infoBanner != null &&
                  controller.infoBanner!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  controller.infoBanner!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: controller.isSubmittingSeats ? null : _confirm,
                child: controller.isSubmittingSeats
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm'),
              ),
              const SizedBox(height: 8),
              Text(
                controller.pendingOutboxCount > 0
                    ? 'Pending sync operations: ${controller.pendingOutboxCount}'
                    : 'No pending sync operations.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
