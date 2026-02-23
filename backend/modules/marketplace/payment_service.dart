import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_metrics.dart';
import 'billing_ledger_repository.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_repository.dart';
import 'marketplace_timeline_service.dart';
import 'payment_provider.dart';

class PaymentWebhookOutcome {
  const PaymentWebhookOutcome({
    required this.statusCode,
    required this.success,
    required this.action,
    required this.message,
    required this.data,
  });

  final int statusCode;
  final bool success;
  final String action;
  final String message;
  final Map<String, Object?> data;
}

class PaymentService {
  PaymentService({
    required MarketplaceRepository marketplaceRepository,
    required BillingLedgerRepository billingLedgerRepository,
    required MarketplaceTimelineService timelineService,
    required MarketplaceEntitlementService entitlementService,
    required PaymentProvider paymentProvider,
    required RequestMetrics requestMetrics,
    Uuid? uuid,
  }) : _marketplaceRepository = marketplaceRepository,
       _billingLedgerRepository = billingLedgerRepository,
       _timelineService = timelineService,
       _entitlementService = entitlementService,
       _paymentProvider = paymentProvider,
       _requestMetrics = requestMetrics,
       _uuid = uuid ?? const Uuid();

  factory PaymentService.fromEnvironment({
    required Map<String, String> environment,
    required MarketplaceRepository marketplaceRepository,
    required BillingLedgerRepository billingLedgerRepository,
    required MarketplaceTimelineService timelineService,
    required MarketplaceEntitlementService entitlementService,
    required RequestMetrics requestMetrics,
  }) {
    final providerName = (environment['PAYMENT_PROVIDER'] ?? 'manual')
        .trim()
        .toLowerCase();
    final provider = switch (providerName) {
      'paystack' => PaystackPaymentProvider(),
      'stripe' => StripePaymentProvider(),
      _ => ManualPaymentProvider(
        webhookSecret: environment['PAYMENT_WEBHOOK_SECRET'],
      ),
    };
    return PaymentService(
      marketplaceRepository: marketplaceRepository,
      billingLedgerRepository: billingLedgerRepository,
      timelineService: timelineService,
      entitlementService: entitlementService,
      paymentProvider: provider,
      requestMetrics: requestMetrics,
    );
  }

  final MarketplaceRepository _marketplaceRepository;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceTimelineService _timelineService;
  final MarketplaceEntitlementService _entitlementService;
  final PaymentProvider _paymentProvider;
  final RequestMetrics _requestMetrics;
  final Uuid _uuid;

  Future<Map<String, Object?>> createCheckoutOrIntent({
    required Map<String, Object?> purchase,
  }) async {
    final purchaseId = (purchase['id'] as String?) ?? '';
    final userId = (purchase['user_id'] as String?) ?? '';
    if (purchaseId.isEmpty || userId.isEmpty) {
      return const <String, Object?>{
        'ok': false,
        'error': 'invalid_purchase_context',
      };
    }

    final checkout = await _paymentProvider.createCheckoutOrIntent(
      purchase: purchase,
    );
    final providerRef = checkout.providerRef.isEmpty
        ? 'missing-ref:$purchaseId'
        : checkout.providerRef;
    await _billingLedgerRepository.append(
      BillingLedgerEntryRecord(
        id: _uuid.v4(),
        purchaseId: purchaseId,
        userId: userId,
        entryType: checkout.success ? 'charge_authorized' : 'charge_failed',
        provider: _paymentProvider.providerName,
        providerRef: providerRef,
        amountMinor: checkout.amountMinor,
        currency: checkout.currency,
        metadata: checkout.metadata,
        occurredAtUtc: DateTime.now().toUtc(),
        createdAtUtc: DateTime.now().toUtc(),
      ),
    );

    if (checkout.success &&
        (checkout.status == 'captured' ||
            checkout.status == 'succeeded' ||
            checkout.status == 'paid')) {
      await _billingLedgerRepository.append(
        BillingLedgerEntryRecord(
          id: _uuid.v4(),
          purchaseId: purchaseId,
          userId: userId,
          entryType: 'charge_captured',
          provider: _paymentProvider.providerName,
          providerRef: providerRef,
          amountMinor: checkout.amountMinor,
          currency: checkout.currency,
          metadata: checkout.metadata,
          occurredAtUtc: DateTime.now().toUtc(),
          createdAtUtc: DateTime.now().toUtc(),
        ),
      );
      await _marketplaceRepository.updatePurchaseStatus(
        purchaseId: purchaseId,
        status: 'active',
        providerPaymentIntentId: providerRef,
      );
      final refreshed = await _marketplaceRepository.findPurchaseById(
        purchaseId,
      );
      if (refreshed != null) {
        await _entitlementService.syncPurchaseEntitlementsFromMap(
          purchase: refreshed,
        );
      }
      await _timelineService.appendEvent(
        purchaseId: purchaseId,
        type: 'payment_succeeded',
        data: <String, Object?>{
          'provider': _paymentProvider.providerName,
          'provider_ref': providerRef,
          'amount_minor': checkout.amountMinor,
          'currency': checkout.currency,
        },
      );
    } else {
      _requestMetrics.recordMarketplacePaymentFailure();
      await _marketplaceRepository.updatePurchaseStatus(
        purchaseId: purchaseId,
        status: 'past_due',
        providerPaymentIntentId: providerRef,
      );
      final refreshed = await _marketplaceRepository.findPurchaseById(
        purchaseId,
      );
      if (refreshed != null) {
        await _entitlementService.syncPurchaseEntitlementsFromMap(
          purchase: refreshed,
        );
      }
      await _timelineService.appendEvent(
        purchaseId: purchaseId,
        type: 'payment_failed',
        data: <String, Object?>{
          'provider': _paymentProvider.providerName,
          'provider_ref': providerRef,
          'amount_minor': checkout.amountMinor,
          'currency': checkout.currency,
        },
      );
    }

    return <String, Object?>{
      'ok': checkout.success,
      'provider': _paymentProvider.providerName,
      'provider_ref': providerRef,
      'status': checkout.status,
      'amount_minor': checkout.amountMinor,
      'currency': checkout.currency,
    };
  }

  Future<PaymentWebhookOutcome> handleWebhook(Request request) async {
    final verified = await _paymentProvider.verifyWebhook(request);
    if (!verified.verified) {
      _requestMetrics.recordMarketplaceWebhookVerificationFailure();
      return PaymentWebhookOutcome(
        statusCode: 400,
        success: false,
        action: 'rejected',
        message: verified.message ?? 'webhook_verification_failed',
        data: <String, Object?>{
          'provider': verified.provider,
          'provider_event_id': verified.providerEventId,
        },
      );
    }

    String? purchaseId = verified.purchaseId;
    if ((purchaseId ?? '').isEmpty &&
        (verified.providerRef ?? '').trim().isNotEmpty) {
      final purchase = await _marketplaceRepository.findPurchaseByProviderRef(
        provider: verified.provider,
        providerRef: verified.providerRef!.trim(),
      );
      purchaseId = purchase?['id'] as String?;
    }

    final isNewWebhook = await _marketplaceRepository.recordWebhookEvent(
      provider: verified.provider,
      providerEventId: verified.providerEventId,
      eventType: verified.eventType,
      payload: verified.payload,
      purchaseId: purchaseId,
    );
    if (!isNewWebhook) {
      _requestMetrics.recordMarketplaceWebhookEvent(
        provider: verified.provider,
        action: 'duplicate',
      );
      return PaymentWebhookOutcome(
        statusCode: 200,
        success: true,
        action: 'duplicate',
        message: 'already_processed',
        data: <String, Object?>{
          'provider': verified.provider,
          'provider_event_id': verified.providerEventId,
          'purchase_id': purchaseId,
        },
      );
    }

    if ((purchaseId ?? '').isEmpty) {
      _requestMetrics.recordMarketplaceWebhookEvent(
        provider: verified.provider,
        action: 'ignored',
      );
      await _marketplaceRepository.markWebhookProcessed(
        provider: verified.provider,
        providerEventId: verified.providerEventId,
      );
      return PaymentWebhookOutcome(
        statusCode: 202,
        success: true,
        action: 'ignored',
        message: 'purchase_not_resolved',
        data: <String, Object?>{
          'provider': verified.provider,
          'provider_event_id': verified.providerEventId,
        },
      );
    }

    final purchase = await _marketplaceRepository.findPurchaseById(purchaseId!);
    if (purchase == null) {
      _requestMetrics.recordMarketplaceWebhookEvent(
        provider: verified.provider,
        action: 'ignored',
      );
      await _marketplaceRepository.markWebhookProcessed(
        provider: verified.provider,
        providerEventId: verified.providerEventId,
      );
      return PaymentWebhookOutcome(
        statusCode: 202,
        success: true,
        action: 'ignored',
        message: 'purchase_not_found',
        data: <String, Object?>{
          'provider': verified.provider,
          'provider_event_id': verified.providerEventId,
          'purchase_id': purchaseId,
        },
      );
    }

    final normalizedEvent = verified.eventType.toLowerCase();
    final userId = (purchase['user_id'] as String?) ?? '';
    final providerRef =
        (verified.providerRef ??
            purchase['provider_payment_intent_id'] as String?) ??
        verified.providerEventId;
    final amountMinor =
        verified.amountMinor ?? (purchase['price_minor'] as num?)?.toInt() ?? 0;
    final currency =
        (verified.currency ?? purchase['currency'] as String? ?? 'NGN').trim();

    String action = 'processed';
    String status = (purchase['status'] as String?) ?? 'pending';
    String entryType = 'webhook_received';
    int amountToWrite = amountMinor;

    if (normalizedEvent == 'payment_succeeded' ||
        normalizedEvent == 'invoice_paid' ||
        normalizedEvent == 'charge_captured') {
      action = 'activate';
      status = 'active';
      entryType = normalizedEvent == 'invoice_paid'
          ? 'invoice_paid'
          : 'charge_captured';
    } else if (normalizedEvent == 'payment_failed') {
      action = 'past_due';
      status = 'past_due';
      entryType = 'charge_failed';
      _requestMetrics.recordMarketplacePaymentFailure();
    } else if (normalizedEvent == 'refund_succeeded' ||
        normalizedEvent == 'refund') {
      action = 'refund';
      status = 'refunded';
      entryType = 'refund_succeeded';
      amountToWrite = -amountMinor.abs();
    } else if (normalizedEvent == 'chargeback') {
      action = 'chargeback';
      status = 'refunded';
      entryType = 'chargeback';
      amountToWrite = -amountMinor.abs();
    } else if (normalizedEvent == 'subscription_canceled' ||
        normalizedEvent == 'subscription_cancelled') {
      action = 'cancel';
      status = 'canceled';
      entryType = 'invoice_created';
    }

    await _billingLedgerRepository.append(
      BillingLedgerEntryRecord(
        id: _uuid.v4(),
        purchaseId: purchaseId,
        userId: userId,
        entryType: entryType,
        provider: verified.provider,
        providerRef: providerRef,
        amountMinor: amountToWrite,
        currency: currency,
        metadata: verified.payload,
        occurredAtUtc: DateTime.now().toUtc(),
        createdAtUtc: DateTime.now().toUtc(),
      ),
    );
    await _marketplaceRepository.updatePurchaseStatus(
      purchaseId: purchaseId,
      status: status,
      providerPaymentIntentId: providerRef,
    );
    final refreshed = await _marketplaceRepository.findPurchaseById(purchaseId);
    if (refreshed != null) {
      await _entitlementService.syncPurchaseEntitlementsFromMap(
        purchase: refreshed,
      );
    }
    await _timelineService.appendEvent(
      purchaseId: purchaseId,
      type: normalizedEvent,
      data: <String, Object?>{
        'provider': verified.provider,
        'provider_event_id': verified.providerEventId,
        'provider_ref': providerRef,
        'status': status,
        'amount_minor': amountToWrite,
      },
    );
    await _marketplaceRepository.markWebhookProcessed(
      provider: verified.provider,
      providerEventId: verified.providerEventId,
    );

    _requestMetrics.recordMarketplaceWebhookEvent(
      provider: verified.provider,
      action: action,
    );
    return PaymentWebhookOutcome(
      statusCode: 200,
      success: true,
      action: action,
      message: 'processed',
      data: <String, Object?>{
        'provider': verified.provider,
        'provider_event_id': verified.providerEventId,
        'purchase_id': purchaseId,
        'status': status,
      },
    );
  }
}
