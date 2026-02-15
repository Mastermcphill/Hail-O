import 'package:shelf/shelf.dart';
import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/services/ride_booking_guard_service.dart';

import '../../infra/request_context.dart';
import '../http_utils.dart';

Middleware errorMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on UnauthorizedActionError catch (error) {
        return _errorResponse(request, 403, error.code, error.message);
      } on LifecycleViolationError catch (error) {
        return _errorResponse(request, 409, error.code, error.message);
      } on DomainInvariantError catch (error) {
        return _errorResponse(request, 409, error.code, error.message);
      } on InsufficientFundsError catch (error) {
        return _errorResponse(request, 409, error.code, error.message);
      } on DomainError catch (error) {
        return _errorResponse(request, 400, error.code, error.message);
      } on BookingBlockedException catch (error) {
        return _errorResponse(
          request,
          409,
          error.reason.code,
          error.toString(),
        );
      } on ArgumentError catch (error) {
        return _errorResponse(
          request,
          400,
          'invalid_argument',
          error.message?.toString(),
        );
      } on FormatException catch (error) {
        return _errorResponse(request, 400, 'invalid_format', error.message);
      } catch (_) {
        return _errorResponse(request, 500, 'internal_error', null);
      }
    };
  };
}

Response _errorResponse(
  Request request,
  int statusCode,
  String code,
  String? message,
) {
  final traceId = request.requestContext.traceId;
  return jsonResponse(statusCode, <String, Object?>{
    'code': code,
    'message': message ?? code,
    'trace_id': traceId,
  });
}
