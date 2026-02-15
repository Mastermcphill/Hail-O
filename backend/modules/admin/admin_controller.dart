import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/wallet_reversal_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class AdminController {
  AdminController({required WalletReversalService walletReversalService})
    : _walletReversalService = walletReversalService;

  final WalletReversalService _walletReversalService;

  Router get router {
    final router = Router();
    router.post('/reversal', _reverseTransaction);
    return router;
  }

  Future<Response> _reverseTransaction(Request request) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);

    final originalLedgerId = (body['original_ledger_id'] as num?)?.toInt();
    if (originalLedgerId == null || originalLedgerId <= 0) {
      throw const DomainInvariantError(code: 'original_ledger_id_required');
    }

    final result = await _walletReversalService.reverseWalletLedgerEntry(
      originalLedgerId: originalLedgerId,
      requestedByUserId: request.requestContext.userId ?? '',
      requesterIsAdmin: true,
      reason: (body['reason'] as String?)?.trim().isNotEmpty == true
          ? (body['reason'] as String).trim()
          : 'admin_reversal',
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      reversalAmountMinor: (body['reversal_amount_minor'] as num?)?.toInt(),
    );
    return jsonResponse(200, result);
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }
}
