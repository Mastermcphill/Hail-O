import 'package:shelf/shelf.dart';

Middleware securityHeadersMiddleware({
  bool enableStrictTransportSecurity = false,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      final headers = <String, String>{
        ...response.headers,
        'x-content-type-options': 'nosniff',
        'x-frame-options': 'SAMEORIGIN',
        'x-xss-protection': '1; mode=block',
      };
      if (enableStrictTransportSecurity) {
        headers['strict-transport-security'] =
            'max-age=31536000; includeSubDomains';
      }
      return response.change(headers: headers);
    };
  };
}
