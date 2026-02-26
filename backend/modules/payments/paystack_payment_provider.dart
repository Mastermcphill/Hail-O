import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../marketplace/marketplace_offer_repository.dart';
import 'payment_provider.dart';

class PaystackPaymentProvider implements PaymentProvider {
  PaystackPaymentProvider({
    required String secretKey,
    String apiBaseUrl = defaultApiBaseUrl,
    String callbackUrl = '',
    http.Client? httpClient,
    Duration initializeTimeout = const Duration(seconds: 8),
    Uuid? uuid,
  }) : _secretKey = secretKey.trim(),
       _apiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl),
       _callbackUrl = callbackUrl.trim(),
       _httpClient = httpClient ?? http.Client(),
       _initializeTimeout = initializeTimeout,
       _uuid = uuid ?? const Uuid();

  static const String defaultApiBaseUrl = 'https://api.paystack.co';

  final String _secretKey;
  final String _apiBaseUrl;
  final String _callbackUrl;
  final http.Client _httpClient;
  final Duration _initializeTimeout;
  final Uuid _uuid;

  @override
  String get provider => 'paystack';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    if (!_shouldCallPaystackApi()) {
      return _fallbackCheckoutResult(
        purchase: purchase,
        reason: 'paystack_api_disabled_or_unconfigured',
      );
    }
    final fallbackReference = _fallbackReference(purchase.id);
    final requestBody = <String, Object?>{
      'email': _resolveCustomerEmail(purchase.userId),
      'amount': purchase.totalAmountMinor,
      'currency': purchase.currency.trim().isEmpty
          ? 'NGN'
          : purchase.currency.trim().toUpperCase(),
      'reference': fallbackReference,
      'metadata': <String, Object?>{
        'purchase_id': purchase.id,
        'user_id': purchase.userId,
      },
      if (_callbackUrl.isNotEmpty) 'callback_url': _callbackUrl,
    };

    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_apiBaseUrl/transaction/initialize'),
            headers: <String, String>{
              'authorization': 'Bearer $_secretKey',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(_initializeTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallbackCheckoutResult(
          purchase: purchase,
          reason: 'paystack_initialize_http_${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _fallbackCheckoutResult(
          purchase: purchase,
          reason: 'paystack_initialize_invalid_payload',
        );
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (payload['status'] != true) {
        return _fallbackCheckoutResult(
          purchase: purchase,
          reason: 'paystack_initialize_rejected',
        );
      }
      final data = _asMap(payload['data']);
      final providerRef = _stringOrEmpty(data['reference']).isNotEmpty
          ? _stringOrEmpty(data['reference'])
          : fallbackReference;
      final authorizationUrl = _stringOrEmpty(data['authorization_url']);
      final accessCode = _stringOrEmpty(data['access_code']);

      return PaymentCheckoutResult(
        provider: provider,
        status: 'PENDING',
        providerPaymentIntentId: providerRef,
        raw: <String, Object?>{
          'purchase_id': purchase.id,
          'provider': provider,
          'status': 'PENDING',
          'reference': providerRef,
          if (authorizationUrl.isNotEmpty)
            'authorization_url': authorizationUrl,
          if (accessCode.isNotEmpty) 'access_code': accessCode,
          'init_mode': 'paystack_api',
        },
      );
    } catch (_) {
      return _fallbackCheckoutResult(
        purchase: purchase,
        reason: 'paystack_initialize_exception',
      );
    }
  }

  PaymentCheckoutResult _fallbackCheckoutResult({
    required MarketplacePurchaseRecord purchase,
    required String reason,
  }) {
    final providerRef = _fallbackReference(purchase.id);
    return PaymentCheckoutResult(
      provider: provider,
      status: 'PENDING',
      providerPaymentIntentId: providerRef,
      raw: <String, Object?>{
        'purchase_id': purchase.id,
        'provider': provider,
        'status': 'PENDING',
        'reference': providerRef,
        'init_mode': 'fallback',
        'reason': reason,
      },
    );
  }

  @override
  Future<PaymentWebhookEvent> verifyAndParseWebhook({
    required Map<String, String> headers,
    required String rawBody,
  }) async {
    final payload = _decodeBody(rawBody);
    final signature = (headers['x-paystack-signature'] ?? '').trim();
    final signatureValid = _verifySignature(
      rawBody: rawBody,
      signature: signature,
    );
    final rawEventType = (payload['event'] as String?)?.trim() ?? '';
    final eventType = _normalizeEventType(rawEventType);
    final data = payload['data'];
    final purchaseId = _extractPurchaseId(data);
    final headerEventId = (headers['x-paystack-event-id'] ?? '').trim();
    final providerEventId =
        _extractEventId(data) ??
        (headerEventId.isNotEmpty ? headerEventId : _uuid.v4());

    return PaymentWebhookEvent(
      provider: provider,
      providerEventId: providerEventId,
      eventType: eventType,
      signatureValid: signatureValid,
      purchaseId: purchaseId,
      payload: payload,
    );
  }

  bool _verifySignature({required String rawBody, required String signature}) {
    if (signature.isEmpty || _secretKey.isEmpty) {
      return false;
    }
    final digest = Hmac(
      sha512,
      utf8.encode(_secretKey),
    ).convert(utf8.encode(rawBody)).toString();
    return digest.toLowerCase() == signature.toLowerCase();
  }

  Map<String, Object?> _decodeBody(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('webhook_body_must_be_json_object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _extractPurchaseId(Object? data) {
    if (data is! Map) {
      return null;
    }
    final metadata = data['metadata'];
    if (metadata is Map) {
      final value = (metadata['purchase_id'] ?? metadata['purchaseId'])
          ?.toString()
          .trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final direct = data['purchase_id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    return null;
  }

  String? _extractEventId(Object? data) {
    if (data is! Map) {
      return null;
    }
    final id = data['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      return id;
    }
    return null;
  }

  String _normalizeEventType(String rawEventType) {
    final normalized = rawEventType.trim().toLowerCase();
    switch (normalized) {
      case 'charge.success':
        return 'payment_succeeded';
      case 'charge.failed':
        return 'payment_failed';
      default:
        return normalized.isEmpty ? 'payment_succeeded' : normalized;
    }
  }

  String _fallbackReference(String purchaseId) {
    final normalizedPurchaseId = purchaseId.trim().isEmpty
        ? _uuid.v4()
        : purchaseId.trim();
    return 'paystack_$normalizedPurchaseId';
  }

  bool _shouldCallPaystackApi() {
    if (_secretKey.isEmpty) {
      return false;
    }
    // Keep local/unit tests deterministic when non-Paystack formatted keys are used.
    return _secretKey.startsWith('sk_');
  }

  String _resolveCustomerEmail(String userId) {
    final normalized = userId.trim();
    if (normalized.contains('@') &&
        normalized.contains('.') &&
        normalized.indexOf('@') > 0) {
      return normalized;
    }
    final localPart = normalized.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'),
      '',
    );
    final safeLocalPart = localPart.isEmpty ? 'hailo_user' : localPart;
    return '$safeLocalPart@hailo.local';
  }

  static String _normalizeApiBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return defaultApiBaseUrl;
    }
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, nestedValue) {
        return MapEntry<String, Object?>(key.toString(), nestedValue);
      });
    }
    return <String, Object?>{};
  }

  String _stringOrEmpty(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }
}
