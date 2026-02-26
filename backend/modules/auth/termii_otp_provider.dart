import 'dart:convert';
import 'dart:io';

import 'otp_provider.dart';

class TermiiOtpProvider extends OtpProvider {
  TermiiOtpProvider({
    required String apiKey,
    required String senderId,
    String channel = 'generic',
    String apiBaseUrl = 'https://api.ng.termii.com',
    HttpClient? httpClient,
  }) : _apiKey = apiKey.trim(),
       _senderId = senderId.trim(),
       _channel = channel.trim().isEmpty ? 'generic' : channel.trim(),
       _apiBaseUrl = apiBaseUrl.trim().isEmpty
           ? 'https://api.ng.termii.com'
           : apiBaseUrl.trim(),
       _httpClient = httpClient ?? HttpClient() {
    if (_apiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'Termii API key is required');
    }
    if (_senderId.isEmpty) {
      throw ArgumentError.value(
        senderId,
        'senderId',
        'Termii sender id is required',
      );
    }
  }

  final String _apiKey;
  final String _senderId;
  final String _channel;
  final String _apiBaseUrl;
  final HttpClient _httpClient;

  @override
  String get providerName => 'termii';

  @override
  Future<void> sendOtp({
    required String phoneE164,
    required String code,
    required Duration ttl,
  }) async {
    final ttlMinutes = ttl.inMinutes > 0 ? ttl.inMinutes : 1;
    final message =
        'Your HAIL-O verification code is $code. '
        'It expires in $ttlMinutes minute${ttlMinutes == 1 ? '' : 's'}.';

    final payload = <String, Object?>{
      'to': phoneE164,
      'from': _senderId,
      'sms': message,
      'type': 'plain',
      'channel': _channel,
      'api_key': _apiKey,
    };

    final uri = Uri.parse('$_apiBaseUrl/api/sms/send');
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw StateError(
      'termii_send_failed_status_${response.statusCode}_body_${responseBody.trim()}',
    );
  }
}
