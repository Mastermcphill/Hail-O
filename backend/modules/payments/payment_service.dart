import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_metrics.dart';
import '../../infra/postgres_provider.dart';
import '../marketplace/billing_ledger_repository.dart';
import '../marketplace/marketplace_entitlement_service.dart';
import '../marketplace/marketplace_offer_repository.dart';
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

class PaymentWebhookSignatureException implements Exception {
  const PaymentWebhookSignatureException();
}

class PaymentService {
  PaymentService({
    required PaymentProvider provider,
    PostgresProvider? postgresProvider,
    BillingLedgerRepository? billingLedgerRepository,
    MarketplaceEntitlementService? entitlementService,
    RequestMetrics? metrics,
    void Function(String line)? logSink,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _provider = provider,
       _postgresProvider = postgresProvider,
       _billingLedgerRepository =
           billingLedgerRepository ?? InMemoryBillingLedgerRepository(),
       _entitlementService = entitlementService,
       _metrics = metrics,
       _logSink = logSink ?? print,
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  factory PaymentService.fromEnvironment({
    required PostgresProvider? postgresProvider,
    BillingLedgerRepository? billingLedgerRepository,
    MarketplaceEntitlementService? entitlementService,
    String? configuredProvider,
    String? paystackSecretKey,
    String? stripeWebhookSecret,
    RequestMetrics? metrics,
    void Function(String line)? logSink,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) {
    final providerName = (configuredProvider ?? 'manual').trim().toLowerCase();
    final provider = switch (providerName) {
      'paystack' => PaystackPaymentProvider(
        secretKey: (paystackSecretKey ?? '').trim(),
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
      entitlementService: entitlementService,
      metrics: metrics,
      logSink: logSink,
      uuid: uuid,
      nowUtc: nowUtc,
    );
  }

  final PaymentProvider _provider;
  final PostgresProvider? _postgresProvider;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceEntitlementService? _entitlementService;
  final RequestMetrics? _metrics;
  final void Function(String line) _logSink;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final Set<String> _memoryWebhookDedup = <String>{};
  final Set<String> _memoryActivatedPurchases = <String>{};
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  String get providerName => _provider.provider;

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

    final duplicate = await _recordWebhook(event: event, rawBody: rawBody);
    if (duplicate) {
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

    final action = await _applyWebhookEvent(event);
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
  }

  Future<void> _activatePurchase({
    required String purchaseId,
    required String providerPaymentIntentId,
  }) async {
    if (_postgresProvider == null || !_looksLikeUuid(purchaseId)) {
      _memoryActivatedPurchases.add(purchaseId);
      return;
    }

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

    if (_postgresProvider == null || purchaseId == null) {
      return eventType.isEmpty ? 'webhook_recorded' : eventType;
    }

    final timelineAction = await _postgresProvider.withTxn((txn) async {
      String? status;
      String timelineType;
      switch (eventType) {
        case 'payment_failed':
          status = 'PAST_DUE';
          timelineType = 'payment_failed';
          break;
        case 'subscription_canceled':
        case 'payment_canceled':
          status = 'CANCELED';
          timelineType = 'subscription_canceled';
          break;
        case 'payment_succeeded':
        default:
          status = 'ACTIVE';
          timelineType = 'payment_succeeded';
          break;
      }

      final updated = await txn.query(
        '''
        UPDATE marketplace_purchases
        SET
          status = @status,
          updated_at = @updated_at
        WHERE id = CAST(@purchase_id AS UUID)
        RETURNING id::text
        ''',
        substitutionValues: <String, Object?>{
          'status': status,
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
      return timelineType;
    });

    final entitlementService = _entitlementService;
    if (entitlementService != null) {
      if (timelineAction == 'payment_succeeded' ||
          timelineAction == 'invoice_paid') {
        await entitlementService.syncByPurchaseId(
          purchaseId: purchaseId,
          reason: 'payment_status_active',
        );
      } else if (timelineAction == 'payment_failed' ||
          timelineAction == 'subscription_canceled' ||
          timelineAction == 'chargeback' ||
          timelineAction == 'refund_succeeded') {
        await entitlementService.revokeByPurchaseId(
          purchaseId: purchaseId,
          reason: 'payment_status_$timelineAction',
        );
      }
    }
    return timelineAction;
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
