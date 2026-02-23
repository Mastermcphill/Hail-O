import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../state/marketplace_controller.dart';

class MarketplacePlanChangePreviewScreen extends StatefulWidget {
  const MarketplacePlanChangePreviewScreen({
    super.key,
    required this.purchaseId,
    required this.currentOfferId,
    required this.newOfferId,
  });

  final String purchaseId;
  final String currentOfferId;
  final String newOfferId;

  @override
  State<MarketplacePlanChangePreviewScreen> createState() =>
      _MarketplacePlanChangePreviewScreenState();
}

class _MarketplacePlanChangePreviewScreenState
    extends State<MarketplacePlanChangePreviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = context.read<MarketplaceController>();
      if (controller.offers.isEmpty) {
        controller.loadOffers();
      }
      controller.loadPurchaseReceipt(widget.purchaseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        final seatCount =
            controller.activeReceipt?.purchaseId == widget.purchaseId
            ? controller.activeReceipt!.seatCount
            : controller.seatCount;
        final currentOffer = _findOffer(controller, widget.currentOfferId);
        final newOffer = _findOffer(controller, widget.newOfferId);

        if (controller.loadingOffers &&
            currentOffer == null &&
            newOffer == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (currentOffer == null || newOffer == null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Could not load plan details.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: controller.loadOffers,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final currentTotal = currentOffer.priceMinor * seatCount;
        final newTotal = newOffer.priceMinor * seatCount;
        final delta = newTotal - currentTotal;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Upgrade Preview',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _line('Current plan', currentOffer.title),
                    _line('New plan', newOffer.title),
                    _line('Seats', '$seatCount'),
                    _line('Current total', '$currentTotal minor units'),
                    _line('New total', '$newTotal minor units'),
                    _line(
                      'Price delta',
                      '${delta >= 0 ? '+' : ''}$delta minor units',
                    ),
                    _line('Effective date', 'Immediately after confirmation'),
                    _line(
                      'Seat implications',
                      'Existing seat count is preserved ($seatCount).',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('marketplace_confirm_plan_change_button'),
              onPressed: controller.changingPlan
                  ? null
                  : () async {
                      final router = GoRouter.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      final newPurchaseId = await controller.changePlan(
                        purchaseId: widget.purchaseId,
                        newOfferId: widget.newOfferId,
                      );
                      if (!mounted) {
                        return;
                      }
                      if (newPurchaseId == null || newPurchaseId.isEmpty) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              controller.errorMessage ??
                                  'Unable to change plan right now.',
                            ),
                          ),
                        );
                        return;
                      }
                      router.push(
                        '/marketplace/receipt?purchaseId='
                        '${Uri.encodeQueryComponent(newPurchaseId)}',
                      );
                    },
              child: controller.changingPlan
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirm plan change'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                context.pop();
              },
              child: const Text('Back'),
            ),
          ],
        );
      },
    );
  }

  Offer? _findOffer(MarketplaceController controller, String offerId) {
    return controller.offerById(offerId);
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
