import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/purchase_receipt.dart';
import '../models/seat_selection.dart';
import '../state/marketplace_controller.dart';

class MarketplaceReceiptScreen extends StatefulWidget {
  const MarketplaceReceiptScreen({
    super.key,
    required this.purchaseId,
    this.fallbackOfferId,
    this.fallbackSeatCount,
    this.fallbackTotalPriceMinor,
  });

  final String purchaseId;
  final String? fallbackOfferId;
  final int? fallbackSeatCount;
  final int? fallbackTotalPriceMinor;

  @override
  State<MarketplaceReceiptScreen> createState() =>
      _MarketplaceReceiptScreenState();
}

class _MarketplaceReceiptScreenState extends State<MarketplaceReceiptScreen> {
  static final DateFormat _createdAtFormat = DateFormat('MMM d, y HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<MarketplaceController>().loadPurchaseReceipt(
        widget.purchaseId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        final receipt = _resolveReceipt(controller.activeReceipt);

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Receipt is not available yet.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      'purchase_id: ${widget.purchaseId}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          controller.loadPurchaseReceipt(widget.purchaseId),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final currentOfferId = receipt.offerId.isNotEmpty
            ? receipt.offerId
            : (widget.fallbackOfferId ?? '');

        return ListView(
          key: const Key('marketplace_receipt_list'),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Booking Receipt',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _row('Purchase ID', receipt.purchaseId),
                    _row('Offer', receipt.offerTitle),
                    _row('Seats', receipt.seatCount.toString()),
                    _row('Total', '${receipt.totalPriceMinor} minor units'),
                    _row('Status', receipt.status),
                    _row(
                      'Created',
                      _createdAtFormat.format(receipt.createdAt.toLocal()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('marketplace_receipt_timeline_button'),
              onPressed: () {
                context.push(
                  '/marketplace/timeline?purchaseId='
                  '${Uri.encodeQueryComponent(receipt.purchaseId)}',
                );
              },
              child: const Text('View timeline'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('marketplace_receipt_manage_seats_button'),
              onPressed: () {
                context.push(
                  '/marketplace/seats/manage/'
                  '${Uri.encodeComponent(receipt.purchaseId)}',
                );
              },
              child: const Text('Manage seats'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('marketplace_receipt_change_plan_button'),
              onPressed: currentOfferId.isEmpty
                  ? null
                  : () {
                      context.go(
                        '/marketplace/offers?purchaseId='
                        '${Uri.encodeQueryComponent(receipt.purchaseId)}'
                        '&currentOfferId=${Uri.encodeQueryComponent(currentOfferId)}',
                      );
                    },
              child: const Text('Change plan'),
            ),
          ],
        );
      },
    );
  }

  PurchaseReceipt? _resolveReceipt(PurchaseReceipt? activeReceipt) {
    if (activeReceipt != null &&
        activeReceipt.purchaseId == widget.purchaseId) {
      return activeReceipt;
    }
    if (widget.fallbackOfferId == null &&
        widget.fallbackSeatCount == null &&
        widget.fallbackTotalPriceMinor == null) {
      return null;
    }
    return PurchaseReceipt(
      purchaseId: widget.purchaseId,
      offerId: widget.fallbackOfferId ?? '',
      offerTitle: widget.fallbackOfferId ?? 'Offer',
      seatCount: widget.fallbackSeatCount ?? 1,
      totalPriceMinor: widget.fallbackTotalPriceMinor ?? 0,
      status: 'PENDING',
      createdAt: DateTime.now().toUtc(),
      assignments: const <SeatAssignment>[],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
