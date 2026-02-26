import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../infra/analytics_event_store.dart';
import '../../infra/audit_log_store.dart';
import '../../infra/request_metrics.dart';
import '../../infra/postgres_provider.dart';
import '../marketplace/billing_ledger_repository.dart';
import '../marketplace/marketplace_entitlement_service.dart';
import '../marketplace/marketplace_offer_repository.dart';
import 'payment_intent_repository.dart';
import 'payment_webhook_event_repository.dart';
import 'manual_payment_provider.dart';
import 'paystack_payment_provider.dart';
import 'payment_provider.dart';
import 'stripe_payment_provider.dart';

class PaymentWebhookProcessResult {
  const PaymentWebhookProcessResult({
    required this.provider,
    required this.providerEventId,
    required this.action,
    required this.duplicate,
    required this.signatureValid,
  });

  final String provider;
  final String providerEventId;
  final String action;
  final bool duplicate;
  final bool signatureValid;
}

class PaymentWebhookRetryResult {
  const PaymentWebhookRetryResult({
    required this.scanned,
    required this.retried,
    required this.rescheduled,
    required this.failed,
    required this.skipped,
  });

  final int scanned;
  final int retried;
  final int rescheduled;
  final int failed;
  final int skipped;
}

class PaymentWebhookSignatureException implements Exception {
  const PaymentWebhookSignatureException();
}

class PaymentIntentPurchaseNotFoundException implements Exception {
  const PaymentIntentPurchaseNotFoundException();
}

class PaymentIntentPurchaseStateException implements Exception {
  const PaymentIntentPurchaseStateException({required this.currentStatus});

  final String currentStatus;
}

class PaymentService {
  PaymentService({
    required PaymentProvider provider,
    PostgresProvider? postgresProvider,
    BillingLedgerRepository? billingLedgerRepository,
    MarketplaceOfferRepository? offerRepository,
    PaymentIntentRepository? paymentIntentRepository,
    PaymentWebhookEventRepository? paymentWebhookEventRepository,
    MarketplaceEntitlementService? entitlementService,
    RequestMetrics? metrics,
    AuditLogStore? auditLogStore,
    AnalyticsEventStore? analyticsEventStore,
    void Function(String line)? logSink,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _provider = provider,
       _postgresProvider = postgresProvider,
       _billingLedgerRepository =
           billingLedgerRepository ?? InMemoryBillingLedgerRepository(),
       _offerRepository = offerRepository,
       _paymentIntentRepository =
           paymentIntentRepository ??
           (postgresProvider == null
               ? InMemoryPaymentIntentRepository(uuid: uuid, nowUtc: nowUtc)
               : PostgresPaymentIntentRepository(
                   postgresProvider,
                   uuid: uuid,
                   nowUtc: nowUtc,
                 )),
       _paymentWebhookEventRepository =
           paymentWebhookEventRepository ??
           (postgresProvider == null
               ? InMemoryPaymentWebhookEventRepository()
               : PostgresPaymentWebhookEventRepository(
                   postgresProvider,
                   uuid: uuid,
                   nowUtc: nowUtc,
                 )),
       _entitlementService = entitlementService,
       _metrics = metrics,
       _auditLogStore = auditLogStore,
       _analyticsEventStore = analyticsEventStore,
       _logSink = logSink ?? print,
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  factory PaymentService.fromEnvironment({
    required PostgresProvider? postgresProvider,
    BillingLedgerRepository? billingLedgerRepository,
    MarketplaceOfferRepository? offerRepository,
    PaymentIntentRepository? paymentIntentRepository,
    PaymentWebhookEventRepository? paymentWebhookEventRepository,
    MarketplaceEntitlementService? entitlementService,
    String? configuredProvider,
    String? paystackSecretKey,
    String? paystackWebhookSecret,
    String? paystackApiBaseUrl,
    String? paystackCallbackUrl,
    String? stripeWebhookSecret,
    RequestMetrics? metrics,
    AuditLogStore? auditLogStore,
    AnalyticsEventStore? analyticsEventStore,
    void Function(String line)? logSink,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) {
    final providerName = (configuredProvider ?? 'manual').trim().toLowerCase();
    final provider = switch (providerName) {
      'paystack' => PaystackPaymentProvider(
        secretKey: (paystackSecretKey ?? '').trim(),
        webhookSecret: (paystackWebhookSecret ?? '').trim(),
        apiBaseUrl: (paystackApiBaseUrl ?? '').trim().isEmpty
            ? PaystackPaymentProvider.defaultApiBaseUrl
            : (paystackApiBaseUrl ?? '').trim(),
        callbackUrl: (paystackCallbackUrl ?? '').trim(),
        uuid: uuid,
      ),
      'stripe' => StripePaymentProvider(
        webhookSecret: (stripeWebhookSecret ?? '').trim(),
        uuid: uuid,
      ),
      'manual' => ManualPaymentProvider(uuid: uuid),
      _ => ManualPaymentProvider(uuid: uuid),
    };
    return PaymentService(
      provider: provider,
      postgresProvider: postgresProvider,
      billingLedgerRepository: billingLedgerRepository,
      offerRepository: offerRepository,
      paymentIntentRepository: paymentIntentRepository,
      paymentWebhookEventRepository: paymentWebhookEventRepository,
      entitlementService: entitlementService,
      metrics: metrics,
      auditLogStore: auditLogStore,
      analyticsEventStore: analyticsEventStore,
      logSink: logSink,
      uuid: uuid,
      nowUtc: nowUtc,
    );
  }

  final PaymentProvider _provider;
  final PostgresProvider? _postgresProvider;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceOfferRepository? _offerRepository;
  final PaymentIntentRepository _paymentIntentRepository;
  final PaymentWebhookEventRepository _paymentWebhookEventRepository;
  final MarketplaceEntitlementService? _entitlementService;
  final RequestMetrics? _metrics;
  final AuditLogStore? _auditLogStore;
  final AnalyticsEventStore? _analyticsEventStore;
  final void Function(String line) _logSink;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final Set<String> _memoryWebhookDedup = <String>{};
  final Set<String> _memoryActivatedPurchases = <String>{};
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  static const int _maxWebhookRetryAttempts = 6;
  static const int _maxRetryBackoffSeconds = 900;

  String get providerName => _provider.provider;

  Future<PaymentIntentRecord> createPaymentIntent({
    required String userId,
    required String purchaseId,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedPurchaseId = purchaseId.trim();
    if (normalizedPurchaseId.isEmpty) {
      throw const FormatException('purchase_id is required');
    }
    final offerRepository = _offerRepository;
    if (offerRepository == null) {
      throw StateError('payment_intents_require_offer_repository');
    }

    final purchase = await offerRepository.findPurchaseById(
      userId: normalizedUserId,
      purchaseId: normalizedPurchaseId,
    );
    if (purchase == null) {
      throw const PaymentIntentPurchaseNotFoundException();
    }
    if (!_isPendingPaymentStatus(purchase.status)) {
      throw PaymentIntentPurchaseStateException(currentStatus: purchase.status);
    }

    final existing = await _paymentIntentRepository.findActiveByPurchaseId(
      purchaseId: purchase.id,
    );
    if (existing != null) {
      return existing;
    }

    final checkout = await _provider.createCheckoutOrIntent(purchase: purchase);
    final providerName = checkout.provider.trim().isEmpty
        ? _provider.provider
        : checkout.provider.trim().toLowerCase();
    final providerRef = _resolveProviderRefFromCheckout(
      checkout: checkout,
      purchaseId: purchase.id,
    );
    final intentStatus = _resolveIntentStatusFromCheckout(checkout.status);
    final clientSecret = _extractClientSecret(checkout.raw);
    PaymentIntentRecord intent;
    try {
      intent = await _paymentIntentRepository.createIntent(
        purchaseId: purchase.id,
        userId: purchase.userId,
        provider: providerName,
        status: intentStatus,
        amountMinor: purchase.totalAmountMinor,
        currency: purchase.currency,
        providerRef: providerRef,
        clientSecret: clientSecret,
      );
    } catch (_) {
      final concurrent = await _paymentIntentRepository.findActiveByPurchaseId(
        purchaseId: purchase.id,
      );
      if (concurrent != null) {
        return concurrent;
      }
      rethrow;
    }

    await _billingLedgerRepository.appendEntry(
      purchaseId: purchase.id,
      userId: purchase.userId,
      entryType: 'charge_authorized',
      provider: providerName,
      providerRef: providerRef,
      amountMinor: purchase.totalAmountMinor,
      currency: purchase.currency,
      metadata: <String, Object?>{
        'intent_id': intent.id,
        'intent_status': intent.status,
        'phase': 'authorization_pending',
        'checkout_status': checkout.status,
        ..._sanitizeCheckoutRaw(checkout.raw),
      },
      occurredAt: _nowUtc(),
    );
    return intent;
  }

  Future<PaymentIntentRecord?> getPaymentIntentForUser({
    required String userId,
    required String intentId,
  }) {
    return _paymentIntentRepository.findByIdForUser(
      intentId: intentId.trim(),
      userId: userId.trim(),
    );
  }

  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    final checkout = await _provider.createCheckoutOrIntent(purchase: purchase);
    final providerRef = checkout.providerPaymentIntentId.trim().isEmpty
        ? 'purchase_${purchase.id}'
        : checkout.providerPaymentIntentId.trim();
    await _billingLedgerRepository.appendEntry(
      purchaseId: purchase.id,
      userId: purchase.userId,
      entryType: 'charge_authorized',
      provider: checkout.provider,
      providerRef: providerRef,
      amountMinor: purchase.totalAmountMinor,
      currency: purchase.currency,
      metadata: <String, Object?>{
        'checkout_status': checkout.status,
        ...checkout.raw,
      },
      occurredAt: _nowUtc(),
    );
    if (checkout.status.toUpperCase() == 'SUCCEEDED') {
      await _billingLedgerRepository.appendEntry(
        purchaseId: purchase.id,
        userId: purchase.userId,
        entryType: 'charge_captured',
        provider: checkout.provider,
        providerRef: providerRef,
        amountMinor: purchase.totalAmountMinor,
        currency: purchase.currency,
        metadata: <String, Object?>{
          'checkout_status': checkout.status,
          ...checkout.raw,
        },
        occurredAt: _nowUtc(),
      );
      await _activatePurchase(
        purchaseId: purchase.id,
        providerPaymentIntentId: checkout.providerPaymentIntentId,
      );
    }
    return checkout;
  }

  Future<PaymentWebhookProcessResult> handleWebhook({
    required Map<String, String> headers,
    required String rawBody,
  }) {
    return acceptWebhook(
      headers: headers,
      rawBody: rawBody,
      processImmediately: true,
    );
  }

  Future<PaymentWebhookProcessResult> acceptWebhook({
    required Map<String, String> headers,
    required String rawBody,
    required bool processImmediately,
  }) async {
    final event = await _provider.verifyAndParseWebhook(
      headers: headers,
      rawBody: rawBody,
    );
    if (!event.signatureValid) {
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: 'signature_invalid',
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: false,
        action: 'signature_invalid',
      );
      throw const PaymentWebhookSignatureException();
    }

    await _analyticsEventStore?.emit(
      name: 'payments.webhook_received',
      properties: <String, Object?>{
        'provider': event.provider,
        'provider_event_id': event.providerEventId,
        'event_type': event.eventType,
        'has_purchase_id': (event.purchaseId ?? '').trim().isNotEmpty,
      },
    );

    final now = _nowUtc();
    final canonicalRecorded = await _recordCanonicalWebhookEvent(
      event: event,
      receivedAt: now,
    );
    final persistedEvent = await _paymentWebhookEventRepository.findEvent(
      provider: event.provider,
      eventId: event.providerEventId,
    );
    if (!canonicalRecorded && persistedEvent != null) {
      if (persistedEvent.isProcessed || persistedEvent.isFailed) {
        _metrics?.recordMarketplaceWebhookEvent(
          provider: event.provider,
          action: 'duplicate_ignored',
        );
        _logWebhookOutcome(
          provider: event.provider,
          providerEventId: event.providerEventId,
          verified: true,
          action: 'duplicate_ignored',
        );
        return PaymentWebhookProcessResult(
          provider: event.provider,
          providerEventId: event.providerEventId,
          action: 'duplicate_ignored',
          duplicate: true,
          signatureValid: true,
        );
      }
      if (persistedEvent.processingState == 'pending_processing') {
        final nextRetryAt = persistedEvent.nextRetryAt;
        if (nextRetryAt != null && nextRetryAt.isAfter(now)) {
          _metrics?.recordMarketplaceWebhookEvent(
            provider: event.provider,
            action: 'retry_scheduled',
          );
          _logWebhookOutcome(
            provider: event.provider,
            providerEventId: event.providerEventId,
            verified: true,
            action: 'retry_scheduled',
          );
          return PaymentWebhookProcessResult(
            provider: event.provider,
            providerEventId: event.providerEventId,
            action: 'retry_scheduled',
            duplicate: true,
            signatureValid: true,
          );
        }
      }
    }

    if (!processImmediately) {
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: canonicalRecorded ? 'webhook_enqueued' : 'duplicate_ignored',
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: true,
        action: canonicalRecorded ? 'webhook_enqueued' : 'duplicate_ignored',
      );
      return PaymentWebhookProcessResult(
        provider: event.provider,
        providerEventId: event.providerEventId,
        action: canonicalRecorded ? 'webhook_enqueued' : 'duplicate_ignored',
        duplicate: !canonicalRecorded,
        signatureValid: true,
      );
    }

    await _recordWebhook(event: event, rawBody: rawBody);

    try {
      final action = await _applyWebhookEvent(event);
      await _paymentWebhookEventRepository.markEventProcessed(
        provider: event.provider,
        eventId: event.providerEventId,
        processedAt: _nowUtc(),
      );
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: action,
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: true,
        action: action,
      );
      return PaymentWebhookProcessResult(
        provider: event.provider,
        providerEventId: event.providerEventId,
        action: action,
        duplicate: false,
        signatureValid: true,
      );
    } catch (error) {
      final exhausted = await _scheduleWebhookRetry(
        provider: event.provider,
        providerEventId: event.providerEventId,
        error: error,
      );
      final retryAction = exhausted ? 'retry_exhausted' : 'retry_scheduled';
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: retryAction,
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: true,
        action: retryAction,
      );
      rethrow;
    }
  }

  Future<PaymentWebhookProcessResult> processStoredWebhookEvent({
    required String provider,
    required String providerEventId,
  }) async {
    final storedEvent = await _paymentWebhookEventRepository.findEvent(
      provider: provider,
      eventId: providerEventId,
    );
    if (storedEvent == null) {
      throw StateError('webhook_event_not_found');
    }
    if (storedEvent.isProcessed || storedEvent.isFailed) {
      return PaymentWebhookProcessResult(
        provider: storedEvent.provider,
        providerEventId: storedEvent.eventId,
        action: 'duplicate_ignored',
        duplicate: true,
        signatureValid: true,
      );
    }
    final event = _decodeStoredWebhookEvent(storedEvent);
    if (event == null) {
      await _paymentWebhookEventRepository.markEventFailed(
        provider: storedEvent.provider,
        eventId: storedEvent.eventId,
        lastError: 'invalid_webhook_event_payload',
      );
      throw const FormatException('invalid_webhook_event_payload');
    }
    await _recordWebhook(event: event, rawBody: jsonEncode(event.payload));
    try {
      final action = await _applyWebhookEvent(event);
      await _paymentWebhookEventRepository.markEventProcessed(
        provider: event.provider,
        eventId: event.providerEventId,
        processedAt: _nowUtc(),
      );
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: 'retry_processed',
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: true,
        action: 'retry_processed',
      );
      return PaymentWebhookProcessResult(
        provider: event.provider,
        providerEventId: event.providerEventId,
        action: action,
        duplicate: false,
        signatureValid: true,
      );
    } catch (error) {
      final exhausted = await _scheduleWebhookRetry(
        provider: event.provider,
        providerEventId: event.providerEventId,
        error: error,
      );
      _metrics?.recordMarketplaceWebhookEvent(
        provider: event.provider,
        action: exhausted ? 'retry_exhausted' : 'retry_scheduled',
      );
      _logWebhookOutcome(
        provider: event.provider,
        providerEventId: event.providerEventId,
        verified: true,
        action: exhausted ? 'retry_exhausted' : 'retry_scheduled',
      );
      rethrow;
    }
  }

  Future<bool> _recordCanonicalWebhookEvent({
    required PaymentWebhookEvent event,
    required DateTime receivedAt,
  }) {
    final payload = jsonEncode(<String, Object?>{
      'provider': event.provider,
      'provider_event_id': event.providerEventId,
      'event_type': event.eventType,
      'purchase_id': event.purchaseId,
      'payload': event.payload,
    });
    return _paymentWebhookEventRepository.recordEvent(
      provider: event.provider,
      eventId: event.providerEventId,
      payload: payload,
      receivedAt: receivedAt,
    );
  }

  Future<PaymentWebhookRetryResult> retryPendingWebhooks({
    int limit = 25,
  }) async {
    final safeLimit = limit < 1
        ? 1
        : limit > 200
        ? 200
        : limit;
    final now = _nowUtc();
    final events = await _paymentWebhookEventRepository.listRetryableEvents(
      nowUtc: now,
      limit: safeLimit,
    );
    var retried = 0;
    var rescheduled = 0;
    var failed = 0;
    var skipped = 0;
    for (final storedEvent in events) {
      if (storedEvent.isProcessed || storedEvent.isFailed) {
        skipped += 1;
        continue;
      }
      final event = _decodeStoredWebhookEvent(storedEvent);
      if (event == null) {
        await _paymentWebhookEventRepository.markEventFailed(
          provider: storedEvent.provider,
          eventId: storedEvent.eventId,
          lastError: 'invalid_webhook_event_payload',
        );
        failed += 1;
        continue;
      }
      try {
        await _recordWebhook(event: event, rawBody: jsonEncode(event.payload));
        await _applyWebhookEvent(event);
        await _paymentWebhookEventRepository.markEventProcessed(
          provider: event.provider,
          eventId: event.providerEventId,
          processedAt: _nowUtc(),
        );
        _metrics?.recordMarketplaceWebhookEvent(
          provider: event.provider,
          action: 'retry_processed',
        );
        _logWebhookOutcome(
          provider: event.provider,
          providerEventId: event.providerEventId,
          verified: true,
          action: 'retry_processed',
        );
        retried += 1;
      } catch (error) {
        final exhausted = await _scheduleWebhookRetry(
          provider: event.provider,
          providerEventId: event.providerEventId,
          error: error,
        );
        if (exhausted) {
          failed += 1;
          _metrics?.recordMarketplaceWebhookEvent(
            provider: event.provider,
            action: 'retry_exhausted',
          );
          _logWebhookOutcome(
            provider: event.provider,
            providerEventId: event.providerEventId,
            verified: true,
            action: 'retry_exhausted',
          );
        } else {
          rescheduled += 1;
          _metrics?.recordMarketplaceWebhookEvent(
            provider: event.provider,
            action: 'retry_scheduled',
          );
          _logWebhookOutcome(
            provider: event.provider,
            providerEventId: event.providerEventId,
            verified: true,
            action: 'retry_scheduled',
          );
        }
      }
    }
    return PaymentWebhookRetryResult(
      scanned: events.length,
      retried: retried,
      rescheduled: rescheduled,
      failed: failed,
      skipped: skipped,
    );
  }

  Future<List<PaymentWebhookStoredEvent>> listRetryableWebhookEvents({
    int limit = 25,
  }) {
    final safeLimit = limit < 1
        ? 1
        : limit > 200
        ? 200
        : limit;
    return _paymentWebhookEventRepository.listRetryableEvents(
      nowUtc: _nowUtc(),
      limit: safeLimit,
    );
  }

  PaymentWebhookEvent? _decodeStoredWebhookEvent(
    PaymentWebhookStoredEvent storedEvent,
  ) {
    try {
      final decoded = jsonDecode(storedEvent.payload);
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
      final provider = (map['provider'] as String?)?.trim().toLowerCase();
      final providerEventId =
          (map['provider_event_id'] as String?)?.trim() ?? storedEvent.eventId;
      final eventType = (map['event_type'] as String?)?.trim().toLowerCase();
      final purchaseId = (map['purchase_id'] as String?)?.trim();
      final payloadRaw = map['payload'];
      Map<String, Object?> payload = <String, Object?>{};
      if (payloadRaw is Map) {
        payload = payloadRaw.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        );
      }
      final resolvedProvider = (provider == null || provider.isEmpty)
          ? storedEvent.provider
          : provider;
      final resolvedEventType = (eventType == null || eventType.isEmpty)
          ? (payload['event_type'] as String?)?.trim().toLowerCase() ?? ''
          : eventType;
      if (resolvedProvider.trim().isEmpty ||
          providerEventId.trim().isEmpty ||
          resolvedEventType.trim().isEmpty) {
        return null;
      }
      return PaymentWebhookEvent(
        provider: resolvedProvider,
        providerEventId: providerEventId,
        eventType: resolvedEventType,
        signatureValid: true,
        purchaseId: (purchaseId?.isEmpty ?? true) ? null : purchaseId,
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _scheduleWebhookRetry({
    required String provider,
    required String providerEventId,
    required Object error,
  }) async {
    final storedEvent = await _paymentWebhookEventRepository.findEvent(
      provider: provider,
      eventId: providerEventId,
    );
    final attemptCount = storedEvent?.attemptCount ?? 0;
    final safeErrorMessage = _safeErrorMessage(error);
    if (attemptCount + 1 >= _maxWebhookRetryAttempts) {
      await _paymentWebhookEventRepository.markEventFailed(
        provider: provider,
        eventId: providerEventId,
        lastError: safeErrorMessage,
      );
      return true;
    }
    final delay = _retryBackoffDuration(attemptCount + 1);
    await _paymentWebhookEventRepository.markEventPendingProcessing(
      provider: provider,
      eventId: providerEventId,
      lastError: safeErrorMessage,
      nextRetryAt: _nowUtc().add(delay),
    );
    return false;
  }

  Duration _retryBackoffDuration(int attempt) {
    if (attempt <= 1) {
      return const Duration(seconds: 15);
    }
    var seconds = 15;
    for (var index = 1; index < attempt; index++) {
      seconds *= 2;
      if (seconds >= _maxRetryBackoffSeconds) {
        seconds = _maxRetryBackoffSeconds;
        break;
      }
    }
    return Duration(seconds: seconds);
  }

  String _safeErrorMessage(Object error) {
    final normalized = error.toString().trim();
    if (normalized.isEmpty) {
      return 'unknown_webhook_processing_error';
    }
    if (normalized.length <= 512) {
      return normalized;
    }
    return normalized.substring(0, 512);
  }

  Future<void> _activatePurchase({
    required String purchaseId,
    required String providerPaymentIntentId,
  }) async {
    if (_postgresProvider == null || !_looksLikeUuid(purchaseId)) {
      _memoryActivatedPurchases.add(purchaseId);
      return;
    }

    var purchaseActivated = false;
    await _postgresProvider.withTxn((txn) async {
      final rows = await txn.query(
        '''
        UPDATE marketplace_purchases
        SET
          status = @status,
          provider_payment_intent_id = COALESCE(provider_payment_intent_id, @provider_payment_intent_id),
          updated_at = @updated_at
        WHERE id = CAST(@purchase_id AS UUID)
          AND status <> @status
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'status': 'ACTIVE',
          'provider_payment_intent_id': providerPaymentIntentId,
          'updated_at': _nowUtc(),
          'purchase_id': purchaseId,
        },
      );
      if (rows.isNotEmpty) {
        purchaseActivated = true;
        await _appendTimeline(
          txn,
          purchaseId: purchaseId,
          eventType: 'payment_succeeded',
          eventData: <String, Object?>{
            'provider': _provider.provider,
            'provider_payment_intent_id': providerPaymentIntentId,
          },
        );
      }
    });
    if (purchaseActivated) {
      await _auditLogStore?.record(
        actorType: 'user',
        actorUserId: null,
        action: 'payments.purchase.status_transition',
        resourceType: 'marketplace_purchase',
        resourceId: purchaseId,
        metadata: <String, Object?>{
          'from_status': 'unknown',
          'to_status': 'ACTIVE',
          'provider': _provider.provider,
          'provider_payment_intent_id': providerPaymentIntentId,
        },
      );
      await _analyticsEventStore?.emit(
        name: 'payments.succeeded',
        properties: <String, Object?>{
          'provider': _provider.provider,
          'event_type': 'checkout_succeeded',
          'purchase_id': purchaseId,
          'provider_payment_intent_id': providerPaymentIntentId,
        },
      );
    }
    final entitlementService = _entitlementService;
    if (entitlementService != null) {
      await entitlementService.syncByPurchaseId(
        purchaseId: purchaseId,
        reason: 'payment_capture',
      );
    }
  }

  Future<bool> _recordWebhook({
    required PaymentWebhookEvent event,
    required String rawBody,
  }) async {
    final dedupeKey = '${event.provider}::${event.providerEventId}';
    if (_postgresProvider == null) {
      if (_memoryWebhookDedup.contains(dedupeKey)) {
        return true;
      }
      _memoryWebhookDedup.add(dedupeKey);
      return false;
    }

    final purchaseId = _looksLikeUuid(event.purchaseId)
        ? event.purchaseId
        : null;
    final watch = Stopwatch()..start();
    final insertedRows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO marketplace_webhook_events(
          id,
          provider,
          provider_event_id,
          purchase_id,
          event_type,
          payload,
          signature_valid,
          processed,
          created_at,
          processed_at
        )
        VALUES(
          @id,
          @provider,
          @provider_event_id,
          CAST(@purchase_id AS UUID),
          @event_type,
          CAST(@payload AS JSONB),
          @signature_valid,
          FALSE,
          @created_at,
          NULL
        )
        ON CONFLICT (provider, provider_event_id)
        DO NOTHING
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'provider': event.provider,
          'provider_event_id': event.providerEventId,
          'purchase_id': purchaseId,
          'event_type': event.eventType,
          'payload': rawBody.trim().isEmpty
              ? jsonEncode(event.payload)
              : rawBody,
          'signature_valid': event.signatureValid,
          'created_at': _nowUtc(),
        },
      ),
    );
    watch.stop();
    _metrics?.recordMarketplaceDbQueryLatency(
      op: 'insert_webhook_event',
      latencyMs: watch.elapsedMilliseconds,
    );
    return insertedRows.isEmpty;
  }

  Future<String> _applyWebhookEvent(PaymentWebhookEvent event) async {
    final eventType = event.eventType.trim().toLowerCase();
    final purchaseId = _looksLikeUuid(event.purchaseId)
        ? event.purchaseId
        : null;
    final financialContext = await _resolveFinancialContext(
      purchaseId: purchaseId,
      payload: event.payload,
    );
    final isPaymentSucceeded =
        eventType == 'payment_succeeded' || eventType == 'invoice_paid';
    final isPaymentFailed = eventType == 'payment_failed';

    if (isPaymentSucceeded) {
      await _appendEscrowTransferLedgerEntries(
        event: event,
        purchaseId: purchaseId,
        financialContext: financialContext,
      );
    } else {
      final mappedEntryType = _mapLedgerEntryType(eventType);
      final mappedAmount = _mapLedgerAmount(
        entryType: mappedEntryType,
        amountMinor: financialContext.amountMinor,
      );
      await _billingLedgerRepository.appendEntry(
        purchaseId: purchaseId,
        userId: financialContext.userId,
        entryType: mappedEntryType,
        provider: event.provider,
        providerRef: event.providerEventId,
        amountMinor: mappedAmount,
        currency: financialContext.currency,
        metadata: <String, Object?>{
          'event_type': event.eventType,
          ...event.payload,
        },
        occurredAt: _nowUtc(),
      );
    }

    if (purchaseId != null) {
      if (isPaymentSucceeded) {
        await _paymentIntentRepository.updateLatestByPurchaseId(
          purchaseId: purchaseId,
          status: 'succeeded',
        );
      } else if (isPaymentFailed) {
        await _paymentIntentRepository.updateLatestByPurchaseId(
          purchaseId: purchaseId,
          status: 'failed',
        );
      }
    }

    if (_postgresProvider == null || purchaseId == null) {
      await _emitPaymentOutcomeAnalytics(
        event: event,
        userId: financialContext.userId,
        purchaseId: purchaseId ?? event.purchaseId,
        outcomeStatus: isPaymentSucceeded
            ? 'succeeded'
            : isPaymentFailed
            ? 'failed'
            : null,
      );
      return eventType.isEmpty ? 'webhook_recorded' : eventType;
    }

    final timelineMutation = await _postgresProvider.withTxn((txn) async {
      late final String status;
      late final String timelineType;
      switch (eventType) {
        case 'payment_failed':
          status = 'pending_payment';
          timelineType = 'payment_failed';
          break;
        case 'subscription_canceled':
        case 'payment_canceled':
          status = 'canceled';
          timelineType = 'subscription_canceled';
          break;
        case 'chargeback':
          status = 'refunded';
          timelineType = 'chargeback';
          break;
        case 'refund':
        case 'refund_succeeded':
          status = 'refunded';
          timelineType = 'refund_succeeded';
          break;
        case 'invoice_paid':
          status = 'paid';
          timelineType = 'invoice_paid';
          break;
        case 'payment_succeeded':
        default:
          status = 'paid';
          timelineType = 'payment_succeeded';
          break;
      }

      final updated = await txn.query(
        '''
        UPDATE marketplace_purchases
        SET
          status = @status,
          provider_payment_intent_id = COALESCE(provider_payment_intent_id, @provider_payment_intent_id),
          updated_at = @updated_at
        WHERE id = CAST(@purchase_id AS UUID)
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'status': status,
          'provider_payment_intent_id': _resolveProviderPaymentIntentId(event),
          'updated_at': _nowUtc(),
          'purchase_id': purchaseId,
        },
      );

      if (updated.isNotEmpty) {
        await _appendTimeline(
          txn,
          purchaseId: purchaseId,
          eventType: timelineType,
          eventData: <String, Object?>{
            'provider': event.provider,
            'provider_event_id': event.providerEventId,
            ...event.payload,
          },
        );
      }

      await txn.execute(
        '''
        UPDATE marketplace_webhook_events
        SET processed = TRUE, processed_at = @processed_at
        WHERE provider = @provider
          AND provider_event_id = @provider_event_id
        ''',
        substitutionValues: <String, Object?>{
          'provider': event.provider,
          'provider_event_id': event.providerEventId,
          'processed_at': _nowUtc(),
        },
      );
      return _WebhookTimelineMutation(
        action: timelineType,
        toStatus: status,
        purchaseUpdated: updated.isNotEmpty,
      );
    });
    if (timelineMutation.purchaseUpdated) {
      await _auditLogStore?.record(
        actorType: 'user',
        actorUserId: null,
        action: 'payments.purchase.status_transition',
        resourceType: 'marketplace_purchase',
        resourceId: purchaseId,
        metadata: <String, Object?>{
          'from_status': 'unknown',
          'to_status': timelineMutation.toStatus,
          'provider': event.provider,
          'provider_event_id': event.providerEventId,
          'event_type': event.eventType,
        },
      );
    }

    final entitlementService = _entitlementService;
    if (entitlementService != null) {
      if (timelineMutation.action == 'payment_succeeded' ||
          timelineMutation.action == 'invoice_paid') {
        await entitlementService.syncByPurchaseId(
          purchaseId: purchaseId,
          reason: 'payment_status_paid',
        );
      } else if (timelineMutation.action == 'subscription_canceled' ||
          timelineMutation.action == 'chargeback' ||
          timelineMutation.action == 'refund_succeeded') {
        await entitlementService.revokeByPurchaseId(
          purchaseId: purchaseId,
          reason: 'payment_status_${timelineMutation.action}',
        );
      }
    }
    await _emitPaymentOutcomeAnalytics(
      event: event,
      userId: financialContext.userId,
      purchaseId: purchaseId,
      outcomeStatus: timelineMutation.toStatus,
    );
    return timelineMutation.action;
  }

  Future<void> _emitPaymentOutcomeAnalytics({
    required PaymentWebhookEvent event,
    required String? userId,
    required String? purchaseId,
    required String? outcomeStatus,
  }) async {
    final eventType = event.eventType.trim().toLowerCase();
    final isSuccess =
        eventType == 'payment_succeeded' || eventType == 'invoice_paid';
    final isFailure = eventType == 'payment_failed';
    if (!isSuccess && !isFailure) {
      return;
    }
    await _analyticsEventStore?.emit(
      name: isSuccess ? 'payments.succeeded' : 'payments.failed',
      userId: _looksLikeUuid(userId) ? userId?.trim() : null,
      properties: <String, Object?>{
        'provider': event.provider,
        'provider_event_id': event.providerEventId,
        'event_type': event.eventType,
        if ((purchaseId ?? '').trim().isNotEmpty)
          'purchase_id': purchaseId!.trim(),
        if ((outcomeStatus ?? '').trim().isNotEmpty)
          'status': outcomeStatus!.trim(),
      },
    );
  }

  Future<void> _appendEscrowTransferLedgerEntries({
    required PaymentWebhookEvent event,
    required String? purchaseId,
    required _FinancialContext financialContext,
  }) async {
    final amountMinor = financialContext.amountMinor.abs();
    final metadata = <String, Object?>{
      'event_type': event.eventType,
      ...event.payload,
    };
    await _billingLedgerRepository.appendEntry(
      purchaseId: purchaseId,
      userId: financialContext.userId,
      entryType: 'charge_captured',
      provider: event.provider,
      providerRef: '${event.providerEventId}:escrow_debit',
      amountMinor: amountMinor,
      currency: financialContext.currency,
      metadata: <String, Object?>{
        ...metadata,
        'ledger_leg': 'user_escrow_debit',
      },
      occurredAt: _nowUtc(),
    );
    await _billingLedgerRepository.appendEntry(
      purchaseId: purchaseId,
      userId: financialContext.userId,
      entryType: 'invoice_paid',
      provider: event.provider,
      providerRef: '${event.providerEventId}:escrow_credit',
      amountMinor: amountMinor,
      currency: financialContext.currency,
      metadata: <String, Object?>{
        ...metadata,
        'ledger_leg': 'platform_escrow_credit',
      },
      occurredAt: _nowUtc(),
    );
  }

  String _resolveProviderPaymentIntentId(PaymentWebhookEvent event) {
    final payloadRef = event.payload['provider_payment_intent_id']
        ?.toString()
        .trim();
    if (payloadRef != null && payloadRef.isNotEmpty) {
      return payloadRef;
    }
    final nestedRef =
        _nestedValue(event.payload, const <String>[
          'data',
          'id',
        ])?.toString().trim() ??
        '';
    if (nestedRef.isNotEmpty) {
      return nestedRef;
    }
    return event.providerEventId;
  }

  Future<_FinancialContext> _resolveFinancialContext({
    required String? purchaseId,
    required Map<String, Object?> payload,
  }) async {
    final payloadAmount =
        _toInt(payload['amount_minor']) ??
        _toInt(payload['amount']) ??
        _toInt(_nestedValue(payload, const <String>['data', 'amount_minor'])) ??
        _toInt(_nestedValue(payload, const <String>['data', 'amount'])) ??
        0;
    final payloadCurrency =
        (_nestedValue(payload, const <String>['data', 'currency']) ??
                payload['currency'])
            ?.toString()
            .trim() ??
        '';
    final defaultCurrency = payloadCurrency.isEmpty ? 'NGN' : payloadCurrency;
    if (_postgresProvider == null || purchaseId == null) {
      return _FinancialContext(
        userId: _extractUserIdFromPayload(payload) ?? 'unknown',
        amountMinor: payloadAmount,
        currency: defaultCurrency,
      );
    }

    final watch = Stopwatch()..start();
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT user_id, price_minor, currency
        FROM marketplace_purchases
        WHERE id = CAST(@purchase_id AS UUID)
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    watch.stop();
    _metrics?.recordMarketplaceDbQueryLatency(
      op: 'lookup_purchase_financials',
      latencyMs: watch.elapsedMilliseconds,
    );
    if (rows.isEmpty) {
      return _FinancialContext(
        userId: _extractUserIdFromPayload(payload) ?? 'unknown',
        amountMinor: payloadAmount,
        currency: defaultCurrency,
      );
    }
    final row = rows.first;
    return _FinancialContext(
      userId: (row[0] as String?)?.trim().isNotEmpty == true
          ? (row[0] as String).trim()
          : (_extractUserIdFromPayload(payload) ?? 'unknown'),
      amountMinor: (row[1] as num?)?.toInt() ?? payloadAmount,
      currency: (row[2] as String?)?.trim().isNotEmpty == true
          ? (row[2] as String).trim()
          : defaultCurrency,
    );
  }

  String _mapLedgerEntryType(String eventType) {
    switch (eventType.trim().toLowerCase()) {
      case 'payment_failed':
        return 'charge_failed';
      case 'subscription_canceled':
      case 'payment_canceled':
        return 'refund_succeeded';
      case 'chargeback':
        return 'chargeback';
      case 'invoice_created':
        return 'invoice_created';
      case 'invoice_paid':
        return 'invoice_paid';
      case 'payment_succeeded':
      default:
        return 'charge_captured';
    }
  }

  int _mapLedgerAmount({required String entryType, required int amountMinor}) {
    if (entryType == 'refund_succeeded' || entryType == 'chargeback') {
      return amountMinor > 0 ? -amountMinor : amountMinor;
    }
    return amountMinor;
  }

  String? _extractUserIdFromPayload(Map<String, Object?> payload) {
    final direct = payload['user_id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final nested = _nestedValue(payload, const <String>[
      'data',
      'user_id',
    ])?.toString().trim();
    if (nested != null && nested.isNotEmpty) {
      return nested;
    }
    return null;
  }

  Object? _nestedValue(Map<String, Object?> payload, List<String> path) {
    Object? current = payload;
    for (final key in path) {
      if (current is! Map) {
        return null;
      }
      current = current[key];
    }
    return current;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Future<void> _appendTimeline(
    PostgreSQLExecutionContext txn, {
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) {
    return txn.execute(
      '''
      INSERT INTO marketplace_timeline_events(
        id,
        purchase_id,
        event_type,
        event_data,
        created_at
      )
      VALUES(
        @id,
        CAST(@purchase_id AS UUID),
        @event_type,
        CAST(@event_data AS JSONB),
        NOW()
      )
      ''',
      substitutionValues: <String, Object?>{
        'id': _uuid.v4(),
        'purchase_id': purchaseId,
        'event_type': eventType,
        'event_data': jsonEncode(eventData),
      },
    );
  }

  bool _looksLikeUuid(String? value) {
    if (value == null) {
      return false;
    }
    return _uuidPattern.hasMatch(value.trim());
  }

  bool _isPendingPaymentStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending' || normalized == 'pending_payment';
  }

  String _resolveProviderRefFromCheckout({
    required PaymentCheckoutResult checkout,
    required String purchaseId,
  }) {
    final provided = checkout.providerPaymentIntentId.trim();
    if (provided.isNotEmpty) {
      return provided;
    }
    return '${checkout.provider.trim().isEmpty ? _provider.provider : checkout.provider.trim()}_${purchaseId.trim()}';
  }

  String _resolveIntentStatusFromCheckout(String checkoutStatus) {
    final normalized = checkoutStatus.trim().toLowerCase();
    switch (normalized) {
      case 'failed':
        return 'failed';
      case 'canceled':
      case 'cancelled':
        return 'canceled';
      case 'processing':
        return 'processing';
      case 'requires_action':
        return 'requires_action';
      case 'pending':
      case 'succeeded':
      case 'captured':
      default:
        // Intent creation remains pre-settlement; final state changes on webhook.
        return 'pending';
    }
  }

  String? _extractClientSecret(Map<String, Object?> raw) {
    final directClientSecret = _trimString(raw['client_secret']);
    if (directClientSecret != null) {
      return directClientSecret;
    }
    final authorizationUrl = _trimString(raw['authorization_url']);
    if (authorizationUrl != null) {
      return authorizationUrl;
    }
    final checkoutUrl = _trimString(raw['checkout_url']);
    if (checkoutUrl != null) {
      return checkoutUrl;
    }
    final accessCode = _trimString(raw['access_code']);
    if (accessCode != null) {
      return accessCode;
    }
    return null;
  }

  Map<String, Object?> _sanitizeCheckoutRaw(Map<String, Object?> raw) {
    final sanitized = <String, Object?>{};
    final reference = _trimString(raw['reference']);
    final authorizationUrl = _trimString(raw['authorization_url']);
    final accessCode = _trimString(raw['access_code']);
    final initMode = _trimString(raw['init_mode']);
    if (reference != null) {
      sanitized['reference'] = reference;
    }
    if (authorizationUrl != null) {
      sanitized['authorization_url'] = authorizationUrl;
    }
    if (accessCode != null) {
      sanitized['access_code'] = accessCode;
    }
    if (initMode != null) {
      sanitized['init_mode'] = initMode;
    }
    return sanitized;
  }

  String? _trimString(Object? value) {
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  void _logWebhookOutcome({
    required String provider,
    required String providerEventId,
    required bool verified,
    required String action,
  }) {
    _logSink(
      jsonEncode(<String, Object?>{
        'component': 'payment_webhook',
        'provider': provider,
        'provider_event_id': providerEventId,
        'verified': verified,
        'action': action,
      }),
    );
  }
}

class _FinancialContext {
  const _FinancialContext({
    required this.userId,
    required this.amountMinor,
    required this.currency,
  });

  final String userId;
  final int amountMinor;
  final String currency;
}

class _WebhookTimelineMutation {
  const _WebhookTimelineMutation({
    required this.action,
    required this.toStatus,
    required this.purchaseUpdated,
  });

  final String action;
  final String toStatus;
  final bool purchaseUpdated;
}
