import 'dart:async';
import 'dart:io';

import 'api_errors.dart';

enum ApiErrorKind {
  timeout,
  network,
  unauthorized,
  forbidden,
  server,
  client,
  unknown,
}

class ApiErrorEnvelope {
  const ApiErrorEnvelope({
    required this.kind,
    required this.friendlyMessage,
    required this.technicalMessage,
    this.statusCode,
    this.code,
    this.requestId,
  });

  final ApiErrorKind kind;
  final int? statusCode;
  final String? code;
  final String friendlyMessage;
  final String technicalMessage;
  final String? requestId;

  factory ApiErrorEnvelope.fromException(Object error, {String? requestId}) {
    if (error is ApiException) {
      final code = (error.code ?? '').toLowerCase();
      if (code == 'request_timeout' ||
          error.message.toLowerCase().contains('timed out')) {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.timeout,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage:
              'Server is taking too long to respond. Please try again.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
      if (code == 'network_error' || code == 'client_error') {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.network,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage: 'No internet connection or server unreachable.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
      if (error.statusCode == 401) {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.unauthorized,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage: 'Authentication failed. Please sign in again.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
      if (error.statusCode == 403) {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.forbidden,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage: 'You are not authorized for this action.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
      if (error.statusCode >= 500 ||
          _isRetryableGatewayStatus(error.statusCode)) {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.server,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage: 'The server is unavailable. Please try again.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
      if (error.statusCode >= 400) {
        return ApiErrorEnvelope(
          kind: ApiErrorKind.client,
          statusCode: error.statusCode,
          code: error.code,
          requestId: requestId ?? error.traceId,
          friendlyMessage: 'Request could not be completed.',
          technicalMessage: error.toDisplayMessage(),
        );
      }
    }

    if (error is TimeoutException) {
      return ApiErrorEnvelope(
        kind: ApiErrorKind.timeout,
        requestId: requestId,
        friendlyMessage:
            'Server is taking too long to respond. Please try again.',
        technicalMessage: error.toString(),
      );
    }

    if (error is SocketException) {
      return ApiErrorEnvelope(
        kind: ApiErrorKind.network,
        requestId: requestId,
        friendlyMessage: 'No internet connection or server unreachable.',
        technicalMessage: error.toString(),
      );
    }

    return ApiErrorEnvelope(
      kind: ApiErrorKind.unknown,
      requestId: requestId,
      friendlyMessage: 'Something went wrong. Please try again.',
      technicalMessage: error.toString(),
    );
  }
}

bool _isRetryableGatewayStatus(int statusCode) {
  return statusCode == 502 || statusCode == 503 || statusCode == 504;
}
