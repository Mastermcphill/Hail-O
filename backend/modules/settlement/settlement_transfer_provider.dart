import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../lib/services/payout_autosave_service.dart';

SettlementTransferProvider settlementTransferProviderFromEnvironment(
  Map<String, String> env, {
  http.Client? httpClient,
}) {
  final secretKey = (env['PAYSTACK_SECRET_KEY'] ?? '').trim();
  if (!secretKey.startsWith('sk_')) {
    return const DeterministicSettlementTransferProvider();
  }
  return PaystackSettlementTransferProvider(
    secretKey: secretKey,
    apiBaseUrl: (env['PAYSTACK_API_BASE_URL'] ?? '').trim(),
    httpClient: httpClient,
  );
}

class PaystackSettlementTransferProvider extends SettlementTransferProvider {
  PaystackSettlementTransferProvider({
    required String secretKey,
    String apiBaseUrl = 'https://api.paystack.co',
    http.Client? httpClient,
  }) : _secretKey = secretKey.trim(),
       _apiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl),
       _httpClient = httpClient ?? http.Client();

  final String _secretKey;
  final String _apiBaseUrl;
  final http.Client _httpClient;

  @override
  Future<SettlementTransferRecipientResult> createTransferRecipient({
    required String accountNumber,
    required String bankCode,
    required String name,
  }) async {
    final payload = await _post('/transferrecipient', <String, Object?>{
      'type': 'nuban',
      'name': name.trim(),
      'account_number': accountNumber.trim(),
      'bank_code': bankCode.trim(),
      'currency': 'NGN',
    });
    final data = _asMap(payload['data']);
    final recipientCode = _stringOrEmpty(data['recipient_code']);
    if (recipientCode.isEmpty) {
      throw StateError('paystack_transfer_recipient_missing_code');
    }
    return SettlementTransferRecipientResult(
      recipientCode: recipientCode,
      raw: payload,
    );
  }

  @override
  Future<SettlementTransferResult> initiateTransfer({
    required String recipientCode,
    required int amountMinor,
    required String reference,
    required String reason,
  }) async {
    final payload = await _post('/transfer', <String, Object?>{
      'source': 'balance',
      'amount': amountMinor,
      'recipient': recipientCode,
      'reference': reference,
      'reason': reason,
    });
    final data = _asMap(payload['data']);
    final transferCode = _stringOrEmpty(data['transfer_code']).isEmpty
        ? reference
        : _stringOrEmpty(data['transfer_code']);
    return SettlementTransferResult(
      transferCode: transferCode,
      status: _normalizeStatus(data['status']),
      raw: payload,
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$_apiBaseUrl$path'),
      headers: <String, String>{
        'authorization': 'Bearer $_secretKey',
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('paystack_transfer_http_${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('paystack_transfer_invalid_payload');
    }
    final payload = decoded.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
    if (payload['status'] != true) {
      throw StateError('paystack_transfer_rejected');
    }
    return payload;
  }

  static String _normalizeApiBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'https://api.paystack.co';
    }
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _normalizeStatus(Object? value) {
    final normalized = _stringOrEmpty(value).toLowerCase();
    if (normalized == 'success') {
      return 'SUCCESS';
    }
    if (normalized == 'failed') {
      return 'FAILED';
    }
    if (normalized == 'reversed') {
      return 'REVERSED';
    }
    return 'PENDING';
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry<String, Object?>(key.toString(), nestedValue),
      );
    }
    return const <String, Object?>{};
  }

  String _stringOrEmpty(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }
}
