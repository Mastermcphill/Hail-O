import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/purchase_receipt.dart';
import '../state/marketplace_controller.dart';

class MarketplaceManageSeatsScreen extends StatefulWidget {
  const MarketplaceManageSeatsScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  State<MarketplaceManageSeatsScreen> createState() =>
      _MarketplaceManageSeatsScreenState();
}

class _MarketplaceManageSeatsScreenState
    extends State<MarketplaceManageSeatsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = context.read<MarketplaceController>();
      controller.loadPurchaseReceipt(widget.purchaseId);
      controller.loadTimeline(widget.purchaseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        final receipt = _currentReceipt(controller.activeReceipt);
        final isBusy = controller.loadingReceipt || controller.updatingPurchase;

        if (controller.loadingReceipt && receipt == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (receipt == null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Could not load this purchase.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText('purchase_id: ${widget.purchaseId}'),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Manage Seats',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            SelectableText('purchase_id: ${receipt.purchaseId}'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      key: const Key('marketplace_manage_seat_count_decrement'),
                      onPressed: isBusy
                          ? null
                          : () => controller.setSeatCount(
                              controller.seatCount - 1,
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 96,
                      child: TextFormField(
                        key: Key(
                          'marketplace_manage_seat_count_${controller.seatCount}',
                        ),
                        initialValue: controller.seatCount.toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value.trim());
                          if (parsed != null) {
                            controller.setSeatCount(parsed);
                          }
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('marketplace_manage_seat_count_increment'),
                      onPressed: isBusy
                          ? null
                          : () => controller.setSeatCount(
                              controller.seatCount + 1,
                            ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('marketplace_manage_update_seats_button'),
                      onPressed: isBusy
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final updated = await controller
                                  .updatePurchaseSeatCount(
                                    purchaseId: widget.purchaseId,
                                    seatCount: controller.seatCount,
                                  );
                              if (!mounted || updated != null) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    controller.errorMessage ??
                                        'Unable to update seats.',
                                  ),
                                ),
                              );
                            },
                      child: const Text('Update seats'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Seat assignments',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (
              var index = 0;
              index < controller.assignments.length;
              index++
            ) ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Seat ${index + 1}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: Key('marketplace_manage_assignment_name_$index'),
                        initialValue: controller.assignments[index].name,
                        onChanged: (value) =>
                            controller.updateAssignmentName(index, value),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: Key('marketplace_manage_assignment_email_$index'),
                        initialValue: controller.assignments[index].email,
                        onChanged: (value) =>
                            controller.updateAssignmentEmail(index, value),
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('marketplace_manage_save_assignments_button'),
              onPressed: isBusy
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final updated = await controller
                          .updatePurchaseAssignments(
                            purchaseId: widget.purchaseId,
                          );
                      if (!mounted || updated != null) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            controller.errorMessage ??
                                'Unable to update assignments.',
                          ),
                        ),
                      );
                    },
              child: const Text('Save assignments'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                context.push(
                  '/marketplace/timeline?purchaseId='
                  '${Uri.encodeQueryComponent(widget.purchaseId)}',
                );
              },
              child: const Text('View timeline'),
            ),
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }

  PurchaseReceipt? _currentReceipt(PurchaseReceipt? activeReceipt) {
    if (activeReceipt != null &&
        activeReceipt.purchaseId == widget.purchaseId) {
      return activeReceipt;
    }
    return null;
  }
}
