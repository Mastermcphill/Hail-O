import 'dart:io';

import 'package:shelf/shelf.dart';

String resolveClientIp(Request request, {required bool trustProxyHeaders}) {
  if (trustProxyHeaders) {
    final forwarded = request.headers['x-forwarded-for']?.trim() ?? '';
    if (forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final realIp = request.headers['x-real-ip']?.trim() ?? '';
    if (realIp.isNotEmpty) {
      return realIp;
    }
  }

  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo is HttpConnectionInfo) {
    final address = connectionInfo.remoteAddress.address.trim();
    if (address.isNotEmpty) {
      return address;
    }
  }

  return 'unknown';
}
