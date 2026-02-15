import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';

Middleware traceMiddleware({Uuid? uuid}) {
  final generator = uuid ?? const Uuid();

  return (Handler innerHandler) {
    return (Request request) async {
      final traceId = generator.v4();
      final existing = RequestContext.fromRequest(request);
      final tracedRequest = RequestContext.withContext(
        request,
        existing.copyWith(traceId: traceId),
      );
      final response = await innerHandler(tracedRequest);
      return response.change(
        headers: <String, String>{...response.headers, 'x-trace-id': traceId},
      );
    };
  };
}
