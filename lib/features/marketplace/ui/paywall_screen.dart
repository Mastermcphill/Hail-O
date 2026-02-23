import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/billing_invoice.dart';
import '../state/marketplace_controller.dart';

class MarketplacePaywallScreen extends StatefulWidget {
  const MarketplacePaywallScreen({super.key, required this.offerId});

  final String offerId;

  @override
  State<MarketplacePaywallScreen> createState() =>
      _MarketplacePaywallScreenState();
}

class _MarketplacePaywallScreenState extends State<MarketplacePaywallScreen> {
  static const List<String> _paymentIssueStatuses = <String>[
    'past_due',
    'failed',
    'open',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = context.read<MarketplaceController>();
      controller.loadPaywall(widget.offerId);
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
          onRefresh: () async {
            await controller.loadPaywall(widget.offerId);
          },
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
              FilledButton(
                key: const Key('marketplace_paywall_continue_button'),
                onPressed: controller.riskLocked
                    ? null
                    : () {
                        context.push(
                          '/marketplace/seats?offerId='
                          '${Uri.encodeQueryComponent(widget.offerId)}',
                        );
                      },
                child: Text(paywall.ctaLabel),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('marketplace_paywall_change_plan_button'),
                onPressed: () {
                  context.go(
                    '/marketplace/offers?currentOfferId='
                    '${Uri.encodeQueryComponent(widget.offerId)}',
                  );
                },
                child: const Text('Change plan'),
              ),
              const SizedBox(height: 8),
              if (controller.riskLocked) ...<Widget>[
                _RiskLockedBanner(message: controller.errorMessage),
                const SizedBox(height: 12),
              ],
              _PricingBreakdownCard(
                loading: controller.loadingPricing,
                baseMinor: controller.pricingBreakdown?.baseMinor,
                couponMinor: controller.pricingBreakdown?.couponDiscountMinor,
                referralMinor:
                    controller.pricingBreakdown?.referralDiscountMinor,
                creditsMinor: controller.pricingBreakdown?.creditsAppliedMinor,
                finalDueMinor: controller.pricingBreakdown?.finalDueMinor,
              ),
              const SizedBox(height: 10),
              _PromoCodeActions(
                couponDraft: controller.couponDraft,
                referralDraft: controller.referralDraft,
                busy: controller.pricingActionInFlight || controller.riskLocked,
                onCouponChanged: controller.updateCouponDraft,
                onReferralChanged: controller.updateReferralDraft,
                onApplyCoupon: (code) {
                  controller.applyCoupon(
                    offerId: widget.offerId,
                    couponCode: code,
                  );
                },
                onRemoveCoupon: () {
                  controller.removeCoupon(offerId: widget.offerId);
                },
                onApplyReferral: (code) {
                  controller.applyReferral(
                    offerId: widget.offerId,
                    referralCode: code,
                  );
                },
              ),
              const SizedBox(height: 10),
              _PaymentIssueBanner(
                invoice: _latestPaymentIssue(controller.invoices),
                retrying: controller.retryingInvoice,
                onRetry: (invoiceId) async {
                  await controller.retryInvoice(invoiceId);
                },
              ),
              const SizedBox(height: 10),
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

BillingInvoice? _latestPaymentIssue(List<BillingInvoice> invoices) {
  for (final invoice in invoices) {
    if (_MarketplacePaywallScreenState._paymentIssueStatuses.contains(
      invoice.status.toLowerCase(),
    )) {
      return invoice;
    }
  }
  return null;
}

class _PricingBreakdownCard extends StatelessWidget {
  const _PricingBreakdownCard({
    required this.loading,
    required this.baseMinor,
    required this.couponMinor,
    required this.referralMinor,
    required this.creditsMinor,
    required this.finalDueMinor,
  });

  final bool loading;
  final int? baseMinor;
  final int? couponMinor;
  final int? referralMinor;
  final int? creditsMinor;
  final int? finalDueMinor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Pricing breakdown',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (loading && finalDueMinor == null)
              const LinearProgressIndicator(minHeight: 3)
            else ...<Widget>[
              _line('Base', baseMinor ?? 0),
              _line('Coupon discount', -(couponMinor ?? 0)),
              _line('Referral discount', -(referralMinor ?? 0)),
              _line('Credits', -(creditsMinor ?? 0)),
              const Divider(height: 16),
              _line('Final due', finalDueMinor ?? 0, emphasize: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, int amountMinor, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: emphasize ? FontWeight.w600 : null),
            ),
          ),
          Text(
            '$amountMinor',
            style: TextStyle(fontWeight: emphasize ? FontWeight.w700 : null),
          ),
        ],
      ),
    );
  }
}

class _PromoCodeActions extends StatelessWidget {
  const _PromoCodeActions({
    required this.couponDraft,
    required this.referralDraft,
    required this.busy,
    required this.onCouponChanged,
    required this.onReferralChanged,
    required this.onApplyCoupon,
    required this.onRemoveCoupon,
    required this.onApplyReferral,
  });

  final String couponDraft;
  final String referralDraft;
  final bool busy;
  final ValueChanged<String> onCouponChanged;
  final ValueChanged<String> onReferralChanged;
  final ValueChanged<String> onApplyCoupon;
  final VoidCallback onRemoveCoupon;
  final ValueChanged<String> onApplyReferral;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          key: const Key('marketplace_coupon_field'),
          initialValue: couponDraft,
          onChanged: onCouponChanged,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Coupon code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonal(
                key: const Key('marketplace_apply_coupon_button'),
                onPressed: busy || couponDraft.trim().isEmpty
                    ? null
                    : () => onApplyCoupon(couponDraft.trim()),
                child: const Text('Apply coupon'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('marketplace_remove_coupon_button'),
                onPressed: busy ? null : onRemoveCoupon,
                child: const Text('Remove coupon'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('marketplace_referral_field'),
          initialValue: referralDraft,
          onChanged: onReferralChanged,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Referral code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('marketplace_apply_referral_button'),
          onPressed: busy || referralDraft.trim().isEmpty
              ? null
              : () => onApplyReferral(referralDraft.trim()),
          child: const Text('Apply referral'),
        ),
      ],
    );
  }
}

class _PaymentIssueBanner extends StatelessWidget {
  const _PaymentIssueBanner({
    required this.invoice,
    required this.retrying,
    required this.onRetry,
  });

  final BillingInvoice? invoice;
  final bool retrying;
  final Future<void> Function(String invoiceId) onRetry;

  @override
  Widget build(BuildContext context) {
    final item = invoice;
    if (item == null) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('marketplace_past_due_banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Payment issue detected',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Invoice ${item.invoiceId} is ${item.status}. '
              'Total due: ${item.totalDueMinor} ${item.currency}.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('marketplace_retry_invoice_button'),
              onPressed: retrying ? null : () => onRetry(item.invoiceId),
              child: retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Retry payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskLockedBanner extends StatelessWidget {
  const _RiskLockedBanner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('marketplace_risk_locked_banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message?.isNotEmpty == true
              ? message!
              : 'Marketplace mutations are temporarily locked for this account.',
        ),
      ),
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
