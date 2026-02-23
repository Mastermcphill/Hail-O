import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';
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
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _provider = provider,
       _postgresProvider = postgresProvider,
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  factory PaymentService.fromEnvironment({
    required PostgresProvider? postgresProvider,
    String? configuredProvider,
    String? paystackSecretKey,
    String? stripeWebhookSecret,
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
      uuid: uuid,
      nowUtc: nowUtc,
    );
  }

  final PaymentProvider _provider;
  final PostgresProvider? _postgresProvider;
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
    if (checkout.status.toUpperCase() == 'SUCCEEDED') {
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
      throw const PaymentWebhookSignatureException();
    }

    final duplicate = await _recordWebhook(event: event, rawBody: rawBody);
    if (duplicate) {
      return PaymentWebhookProcessResult(
        provider: event.provider,
        providerEventId: event.providerEventId,
        action: 'duplicate_ignored',
        duplicate: true,
        signatureValid: true,
      );
    }

    final action = await _applyWebhookEvent(event);
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
    return insertedRows.isEmpty;
  }

  Future<String> _applyWebhookEvent(PaymentWebhookEvent event) async {
    final eventType = event.eventType.trim().toLowerCase();
    final purchaseId = _looksLikeUuid(event.purchaseId)
        ? event.purchaseId
        : null;

    if (_postgresProvider == null || purchaseId == null) {
      return eventType.isEmpty ? 'webhook_recorded' : eventType;
    }

    return _postgresProvider.withTxn((txn) async {
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
}
