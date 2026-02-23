import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/marketplace_controller.dart';

class MarketplaceSeatsScreen extends StatefulWidget {
  const MarketplaceSeatsScreen({super.key, required this.offerId});

  final String offerId;

  @override
  State<MarketplaceSeatsScreen> createState() => _MarketplaceSeatsScreenState();
}

class _MarketplaceSeatsScreenState extends State<MarketplaceSeatsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<MarketplaceController>().loadPendingCheckoutForOffer(
        widget.offerId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        return SingleChildScrollView(
          key: const Key('marketplace_seats_list'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Seat Selection',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                SelectableText('offer_id: ${widget.offerId}'),
                const SizedBox(height: 12),
                _SeatCountCard(
                  seatCount: controller.seatCount,
                  onDecrement: () =>
                      controller.setSeatCount(controller.seatCount - 1),
                  onIncrement: () =>
                      controller.setSeatCount(controller.seatCount + 1),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null) {
                      controller.setSeatCount(parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Optional passenger assignments',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (
                  var index = 0;
                  index < controller.assignments.length;
                  index++
                )
                  _AssignmentCard(index: index),
                const SizedBox(height: 12),
                if (controller.hasPendingCheckoutForOffer(
                  widget.offerId,
                )) ...<Widget>[
                  FilledButton.tonal(
                    key: const Key('marketplace_resume_purchase_button'),
                    onPressed: controller.submittingCheckout
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final router = GoRouter.of(context);
                            final purchaseId = await controller
                                .resumePendingCheckout(offerId: widget.offerId);
                            if (!mounted) {
                              return;
                            }
                            if (purchaseId == null || purchaseId.isEmpty) {
                              final message =
                                  controller.errorMessage ??
                                  'Unable to resume purchase.';
                              messenger.showSnackBar(
                                SnackBar(content: Text(message)),
                              );
                              return;
                            }
                            router.push(
                              '/marketplace/timeline?purchaseId='
                              '${Uri.encodeQueryComponent(purchaseId)}',
                            );
                          },
                    child: const Text('Resume purchase'),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton(
                  key: const Key('marketplace_confirm_seats_button'),
                  onPressed: controller.submittingCheckout
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final router = GoRouter.of(context);
                          final purchaseId = await controller.createCheckout(
                            offerId: widget.offerId,
                          );
                          if (!mounted) {
                            return;
                          }
                          if (purchaseId == null || purchaseId.isEmpty) {
                            final message =
                                controller.errorMessage ??
                                'Could not create checkout.';
                            messenger.showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                            return;
                          }
                          router.push(
                            '/marketplace/timeline?purchaseId='
                            '${Uri.encodeQueryComponent(purchaseId)}',
                          );
                        },
                  child: controller.submittingCheckout
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm'),
                ),
                if (controller.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    controller.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeatCountCard extends StatelessWidget {
  const _SeatCountCard({
    required this.seatCount,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
  });

  final int seatCount;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Seat count (1..50)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('marketplace_seat_count_decrement'),
                  onPressed: onDecrement,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 92,
                  child: TextFormField(
                    key: Key('marketplace_seat_count_field_$seatCount'),
                    initialValue: seatCount.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('marketplace_seat_count_increment'),
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<MarketplaceController>();
    final assignment = controller.assignments[index];

    return Card(
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
              key: Key('marketplace_assignment_name_$index'),
              initialValue: assignment.name,
              onChanged: (value) =>
                  controller.updateAssignmentName(index, value),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('marketplace_assignment_email_$index'),
              initialValue: assignment.email,
              onChanged: (value) =>
                  controller.updateAssignmentEmail(index, value),
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
