import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/wallet_reversal_service.dart';
import '../../infra/api_contract.dart';
import '../../infra/analytics_event_store.dart';
import '../../infra/audit_log_store.dart';
import '../../infra/audit_logger.dart';
import '../../infra/postgres_provider.dart';
import '../../infra/request_context.dart';
import '../../infra/sentry_observability.dart';
import '../../infra/token_service.dart';
import '../../jobs/job.dart';
import '../../jobs/job_processor.dart';
import '../marketplace/billing_ledger_repository.dart';
import '../marketplace/marketplace_entitlement_service.dart';
import '../marketplace/marketplace_offer_repository.dart';
import '../marketplace/marketplace_reconciliation_service.dart';
import '../marketplace/marketplace_revenue_service.dart';
import '../payments/payment_service.dart' as payments;
import '../../server/http_utils.dart';
import '../../server/middleware/admin_emergency_access_middleware.dart';

class AdminController {
  AdminController({
    Database? db,
    WalletReversalService? walletReversalService,
    required Map<String, Object?> runtimeConfigSnapshot,
    required Map<String, Object?> buildInfo,
    bool enableSentrySmokeEndpoint = false,
    MarketplaceReconciliationService? reconciliationService,
    MarketplaceRevenueService? revenueService,
    AuditLogger? auditLogger,
    AuditLogStore? auditLogStore,
    PostgresProvider? postgresProvider,
    payments.PaymentService? paymentService,
    TokenService? tokenService,
    String paystackSecretKey = '',
    String paystackApiBaseUrl = 'https://api.paystack.co',
    http.Client? httpClient,
    Duration paystackVerifyTimeout = const Duration(seconds: 8),
    AnalyticsEventStore? analyticsEventStore,
    QueueJobProcessor? queueJobProcessor,
    Uuid? uuid,
  }) : _db = db,
       _walletReversalService = walletReversalService,
       _runtimeConfigSnapshot = Map<String, Object?>.unmodifiable(
         runtimeConfigSnapshot,
       ),
       _buildInfo = Map<String, Object?>.unmodifiable(buildInfo),
       _enableSentrySmokeEndpoint = enableSentrySmokeEndpoint,
       _reconciliationService = reconciliationService,
       _revenueService = revenueService ?? MarketplaceRevenueService(),
       _auditLogger = auditLogger ?? AuditLogger(),
       _auditLogStore = auditLogStore ?? AuditLogStore(sqliteDb: db),
       _postgresProvider = postgresProvider,
       _paymentService = paymentService,
       _tokenService = tokenService ?? TokenService.fromEnvironment(),
       _paystackSecretKey = paystackSecretKey.trim(),
       _paystackApiBaseUrl = _normalizeApiBaseUrl(paystackApiBaseUrl),
       _httpClient = httpClient ?? http.Client(),
       _paystackVerifyTimeout = paystackVerifyTimeout,
       _analyticsEventStore = analyticsEventStore,
       _queueJobProcessor = queueJobProcessor,
       _uuid = uuid ?? const Uuid();

  final Database? _db;
  final WalletReversalService? _walletReversalService;
  final Map<String, Object?> _runtimeConfigSnapshot;
  final Map<String, Object?> _buildInfo;
  final bool _enableSentrySmokeEndpoint;
  final MarketplaceReconciliationService? _reconciliationService;
  final MarketplaceRevenueService _revenueService;
  final AuditLogger _auditLogger;
  final AuditLogStore _auditLogStore;
  final PostgresProvider? _postgresProvider;
  final payments.PaymentService? _paymentService;
  final TokenService _tokenService;
  final String _paystackSecretKey;
  final String _paystackApiBaseUrl;
  final http.Client _httpClient;
  final Duration _paystackVerifyTimeout;
  final AnalyticsEventStore? _analyticsEventStore;
  final QueueJobProcessor? _queueJobProcessor;
  final Uuid _uuid;

  static const Set<String> _tripStatuses = <String>{
    'created',
    'searching',
    'assigned',
    'enroute_pickup',
    'picked_up',
    'enroute_dropoff',
    'delivered',
    'canceled',
  };

  Router get router {
    final router = Router();
    router.get('/health', _adminHealth);
    router.get('/metrics', _adminMetrics);
    router.get('/payments/reconcile', _reconcilePaymentIntents);
    router.post('/payments/webhooks/retry', _retryPaymentWebhookProcessing);
    router.post('/webhooks/retry_failed', _retryPaymentWebhookProcessing);
    router.get('/users', _listUsers);
    router.post('/users/<userId>/disable', _disableUser);
    router.post('/users/<userId>/enable', _enableUser);
    router.get('/trips', _listTrips);
    router.get('/config', _runtimeConfig);
    router.get('/contract', _contract);
    router.post('/reversal', _reverseTransaction);
    router.get(
      '/marketplace/purchases/<purchaseId>/debug',
      _marketplacePurchaseDebug,
    );
    router.post(
      '/marketplace/purchases/<purchaseId>/reconcile',
      _marketplacePurchaseReconcile,
    );
    router.get('/marketplace/offers/explain', _marketplaceOffersExplain);
    router.get('/billing/orgs/<orgId>/overview', _billingOverview);
    router.post('/credits/grant', _grantCredits);
    router.post('/risk/<subjectType>/<subjectId>/adjust', _adjustRisk);
    router.post('/dunning/<caseId>/pause', _pauseDunning);
    router.post('/dunning/<caseId>/resume', _resumeDunning);
    router.post('/dunning/<caseId>/writeoff', _writeoffDunning);
    router.get('/audit', _auditSummary);
    router.post('/smoke/mint_token', _mintSmokeToken);
    if (_enableSentrySmokeEndpoint) {
      router.post('/ops/sentry-smoke', _sentrySmoke);
    }
    return router;
  }

  Future<Response> _mintSmokeToken(Request request) async {
    _requireAdmin(request);
    if (_isProductionEnvironment()) {
      return jsonErrorResponse(
        request,
        403,
        code: 'forbidden',
        message: 'Smoke token mint endpoint is disabled in production',
      );
    }
    if (!requestUsedAdminToken(request)) {
      return jsonErrorResponse(
        request,
        403,
        code: 'forbidden',
        message:
            'Smoke token mint requires ADMIN_TOKEN emergency access authentication',
      );
    }

    try {
      final payload = await readJsonBody(request);
      final requestedRoleRaw = (payload['role'] as String?)
          ?.trim()
          .toLowerCase();
      final requestedRole = switch (requestedRoleRaw) {
        'admin' => 'admin',
        'driver' => 'driver',
        'fleet_owner' => 'fleet_owner',
        'system' => 'system',
        _ => 'rider',
      };
      final phoneE164 =
          (payload['phone_e164'] as String?)?.trim().isNotEmpty == true
          ? (payload['phone_e164'] as String).trim()
          : '+15550001111';

      String userId;
      final db = _db;
      if (db != null) {
        userId = await _ensureSmokeUserSqlite(
          db: db,
          phoneE164: phoneE164,
          role: requestedRole,
        );
      } else if (_postgresProvider != null) {
        userId = await _ensureSmokeUserPostgres(
          provider: _postgresProvider,
          phoneE164: phoneE164,
          role: requestedRole,
        );
      } else {
        return jsonErrorResponse(
          request,
          501,
          code: 'not_implemented',
          message: 'Smoke token mint endpoint is unavailable in this mode',
        );
      }

      final expiresIn = const Duration(minutes: 15);
      final accessToken = _tokenService.issueToken(
        userId: userId,
        role: requestedRole,
        tokenTtl: expiresIn,
      );
      await _auditLogStore.recordFromRequest(
        request,
        action: 'admin.smoke.mint_token',
        resourceType: 'user',
        resourceId: userId,
        metadata: <String, Object?>{
          'role': requestedRole,
          'phone_e164': phoneE164,
          'expires_in_seconds': expiresIn.inSeconds,
        },
      );
      return jsonResponse(200, <String, Object?>{
        'ok': true,
        'access_token': accessToken,
        'expires_in_seconds': expiresIn.inSeconds,
        'user': <String, Object?>{
          'id': userId,
          'phone_e164': phoneE164,
          'role': requestedRole,
        },
        'trace_id': request.requestContext.traceId,
      });
    } catch (error, stackTrace) {
      stderr.writeln('WARN: admin_smoke_mint_failed: $error');
      stderr.writeln(stackTrace);
      return jsonErrorResponse(
        request,
        500,
        code: 'internal_error',
        message: 'Unable to mint smoke token',
      );
    }
  }

  Future<Response> _runtimeConfig(Request request) async {
    _requireAdmin(request);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'config': _runtimeConfigSnapshot,
    });
  }

  Future<Response> _adminHealth(Request request) async {
    _requireAdmin(request);
    final db = _db;
    var dbOk = db != null;
    final counts = <String, Object?>{
      'users': 0,
      'trips': 0,
      'trip_assignments': 0,
      'trip_events': 0,
    };
    final queueDepth = <String, Object?>{
      'dispatch_searching': 0,
      'dispatch_assigned': 0,
      'webhook_events_pending': 0,
    };

    if (db != null) {
      try {
        counts['users'] = await _countRows(db, 'users');
        counts['trips'] = await _countRows(db, 'trips');
        counts['trip_assignments'] = await _countRows(db, 'trip_assignments');
        counts['trip_events'] = await _countRows(db, 'trip_events');
        queueDepth['dispatch_searching'] = await _countRowsWhere(
          db,
          'trips',
          where: 'status = ?',
          whereArgs: const <Object>['searching'],
        );
        queueDepth['dispatch_assigned'] = await _countRowsWhere(
          db,
          'trip_assignments',
          where: 'status = ?',
          whereArgs: const <Object>['assigned'],
        );
        queueDepth['webhook_events_pending'] = await _countRowsWhere(
          db,
          'webhook_events',
          where: 'processed = ?',
          whereArgs: const <Object>[0],
        );
      } catch (_) {
        dbOk = false;
      }
    }

    final environment = (_runtimeConfigSnapshot['environment'] ?? 'unknown')
        .toString()
        .trim();
    final dbMode = (_runtimeConfigSnapshot['db_mode'] ?? 'unknown')
        .toString()
        .trim();
    final commit = (_buildInfo['commit'] ?? 'unknown').toString().trim();
    final runtime = (_buildInfo['runtime'] ?? '').toString().trim();
    final payload = <String, Object?>{
      'ok': dbOk,
      'service': 'hail-o-backend',
      'env': environment.isEmpty ? 'unknown' : environment,
      'db_mode': dbMode.isEmpty ? 'unknown' : dbMode,
      'db_ok': dbOk,
      'build': <String, Object?>{
        'commit': commit.isEmpty ? 'unknown' : commit,
        if (runtime.isNotEmpty) 'runtime': runtime,
      },
      'diagnostics': <String, Object?>{
        'counts': counts,
        'queue_depth': queueDepth,
      },
      'trace_id': request.requestContext.traceId,
    };
    return jsonResponse(dbOk ? 200 : 503, payload);
  }

  Future<Response> _adminMetrics(Request request) async {
    _requireAdmin(request);
    await _auditLogStore.recordFromRequest(
      request,
      action: 'admin.metrics',
      resourceType: 'admin_endpoint',
      resourceId: _auditResourceId(request),
    );
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Admin metrics are unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }

    final usersTotal = await _countRows(db, 'users');
    final usersDisabled = await _columnExists(db, 'users', 'disabled_at')
        ? await _countRowsWhere(
            db,
            'users',
            where: 'disabled_at IS NOT NULL',
            whereArgs: const <Object>[],
          )
        : 0;

    final tripsByStatus = await _statusCounts(db, table: 'trips');
    for (final status in _tripStatuses) {
      tripsByStatus.putIfAbsent(status, () => 0);
    }

    final purchasesByStatus = await _statusCounts(
      db,
      table: 'marketplace_purchases',
    );
    final paymentIntentsByStatus = await _statusCounts(
      db,
      table: 'payment_intents',
    );
    final tripsTotal = tripsByStatus.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final purchasesTotal = purchasesByStatus.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final since24h = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final paymentsSucceeded24h = await _countStatusSince(
      db,
      table: 'payment_intents',
      statuses: const <String>{'succeeded', 'captured'},
      sinceUtc: since24h,
    );
    final paymentsFailed24h = await _countStatusSince(
      db,
      table: 'payment_intents',
      statuses: const <String>{'failed', 'canceled', 'cancelled', 'expired'},
      sinceUtc: since24h,
    );
    final webhookFailedCount = await _countFailedWebhookEvents(db);

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'users_total': usersTotal,
      'trips_total': tripsTotal,
      'trips_by_status': tripsByStatus,
      'purchases_total': purchasesTotal,
      'purchases_by_status': purchasesByStatus,
      'payments_succeeded_24h': paymentsSucceeded24h,
      'payments_failed_24h': paymentsFailed24h,
      'webhook_failed_count': webhookFailedCount,
      'counters': <String, Object?>{
        'users': <String, Object?>{
          'total': usersTotal,
          'disabled': usersDisabled,
          'active': usersTotal - usersDisabled,
        },
        'trips_by_status': tripsByStatus,
        'purchases_by_status': purchasesByStatus,
        'payment_intents_by_status': paymentIntentsByStatus,
      },
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _reconcilePaymentIntents(Request request) async {
    _requireAdmin(request);
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Payment reconciliation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }

    final sinceRaw = (request.url.queryParameters['since'] ?? '').trim();
    final since = _parseDateTimeOrNull(sinceRaw);
    if (sinceRaw.isNotEmpty && since == null) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'error_code': 'VALIDATION_ERROR',
        'message': 'since must be an ISO-8601 datetime',
        'trace_id': request.requestContext.traceId,
      });
    }

    final minAgeMinutesRaw =
        (request.url.queryParameters['min_age_minutes'] ?? '15').trim();
    final minAgeMinutes = int.tryParse(minAgeMinutesRaw);
    if (minAgeMinutes == null || minAgeMinutes < 0 || minAgeMinutes > 10080) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'error_code': 'VALIDATION_ERROR',
        'message': 'min_age_minutes must be between 0 and 10080',
        'trace_id': request.requestContext.traceId,
      });
    }
    final verifyRemote =
        (request.url.queryParameters['verify_remote'] ?? 'false')
            .trim()
            .toLowerCase() ==
        'true';
    final limit = _parseLimit(request.url.queryParameters['limit']);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final cutoffIso = DateTime.now()
        .toUtc()
        .subtract(Duration(minutes: minAgeMinutes))
        .toIso8601String();
    final hasUpdatedAtColumn = await _columnExists(
      db,
      'payment_intents',
      'updated_at',
    );

    await _auditLogStore.recordFromRequest(
      request,
      action: 'admin.payments.reconcile',
      resourceType: 'admin_endpoint',
      resourceId: _auditResourceId(request),
      metadata: <String, Object?>{
        if (since != null) 'since': since.toIso8601String(),
        'min_age_minutes': minAgeMinutes,
        'verify_remote': verifyRemote,
        'limit': limit,
      },
    );

    if (!await _tableExists(db, 'payment_intents')) {
      return jsonResponse(200, <String, Object?>{
        'ok': true,
        'trace_id': request.requestContext.traceId,
        'data': <String, Object?>{
          'scanned': 0,
          'updated': 0,
          'intents': const <Map<String, Object?>>[],
        },
      });
    }

    final whereParts = <String>[
      'LOWER(status) IN (?, ?, ?)',
      'created_at <= ?',
    ];
    final whereArgs = <Object>[
      'pending',
      'requires_action',
      'processing',
      cutoffIso,
    ];
    if (since != null) {
      whereParts.add('created_at >= ?');
      whereArgs.add(since.toIso8601String());
    }
    final hasProviderRefColumn = await _columnExists(
      db,
      'payment_intents',
      'provider_ref',
    );
    final rows = await db.query(
      'payment_intents',
      columns: <String>[
        'id',
        'purchase_id',
        'provider',
        'status',
        if (hasProviderRefColumn) 'provider_ref',
        'created_at',
      ],
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
      limit: limit,
    );

    final updates = <Map<String, Object?>>[];
    for (final row in rows) {
      final mapped = Map<String, Object?>.from(row);
      final intentId = (mapped['id'] as String?)?.trim() ?? '';
      final purchaseId = (mapped['purchase_id'] as String?)?.trim() ?? '';
      final provider =
          (mapped['provider'] as String?)?.trim().toLowerCase() ?? '';
      final currentStatus =
          (mapped['status'] as String?)?.trim().toLowerCase() ?? '';
      final providerRef = (mapped['provider_ref'] as String?)?.trim() ?? '';
      if (intentId.isEmpty || currentStatus.isEmpty) {
        continue;
      }

      final decision = await _resolvePaymentIntentDecision(
        db: db,
        purchaseId: purchaseId,
        provider: provider,
        providerRef: providerRef,
        verifyRemote: verifyRemote,
      );
      if (decision == null || decision.status == currentStatus) {
        continue;
      }

      final updatePayload = <String, Object?>{'status': decision.status};
      if (hasUpdatedAtColumn) {
        updatePayload['updated_at'] = nowIso;
      }
      final changed = await db.update(
        'payment_intents',
        updatePayload,
        where: 'id = ?',
        whereArgs: <Object>[intentId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (changed <= 0) {
        continue;
      }
      updates.add(<String, Object?>{
        'intent_id': intentId,
        'purchase_id': purchaseId,
        'provider': provider,
        'from_status': currentStatus,
        'to_status': decision.status,
        'reason': decision.reason,
      });
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        if (since != null) 'since': since.toIso8601String(),
        'min_age_minutes': minAgeMinutes,
        'verify_remote': verifyRemote,
        'scanned': rows.length,
        'updated': updates.length,
        'intents': updates,
      },
    });
  }

  Future<_PaymentIntentDecision?> _resolvePaymentIntentDecision({
    required Database db,
    required String purchaseId,
    required String provider,
    required String providerRef,
    required bool verifyRemote,
  }) async {
    final hasMarketplaceWebhookTable =
        purchaseId.isNotEmpty &&
        await _tableExists(db, 'marketplace_webhook_events') &&
        await _columnExists(db, 'marketplace_webhook_events', 'purchase_id') &&
        await _columnExists(db, 'marketplace_webhook_events', 'event_type') &&
        await _columnExists(
          db,
          'marketplace_webhook_events',
          'signature_valid',
        );
    if (hasMarketplaceWebhookTable) {
      final webhookRows = await db.query(
        'marketplace_webhook_events',
        columns: const <String>['event_type', 'signature_valid'],
        where: 'purchase_id = ?',
        whereArgs: <Object>[purchaseId],
        orderBy: 'created_at DESC',
        limit: 20,
      );
      for (final webhookRow in webhookRows) {
        final signatureValid = webhookRow['signature_valid'];
        final isValid = signatureValid == true || signatureValid == 1;
        if (!isValid) {
          continue;
        }
        final eventType =
            (webhookRow['event_type'] as String?)?.trim().toLowerCase() ?? '';
        final mapped = _statusFromWebhookEventType(eventType);
        if (mapped != null) {
          return _PaymentIntentDecision(
            status: mapped,
            reason: 'webhook_event',
          );
        }
      }
    }

    final hasPurchaseTable =
        purchaseId.isNotEmpty &&
        await _tableExists(db, 'marketplace_purchases') &&
        await _columnExists(db, 'marketplace_purchases', 'status');
    if (hasPurchaseTable) {
      final purchaseRows = await db.query(
        'marketplace_purchases',
        columns: const <String>['status'],
        where: 'id = ?',
        whereArgs: <Object>[purchaseId],
        limit: 1,
      );
      if (purchaseRows.isNotEmpty) {
        final purchaseStatus =
            (purchaseRows.first['status'] as String?)?.trim().toLowerCase() ??
            '';
        if (purchaseStatus == 'paid' || purchaseStatus == 'active') {
          return const _PaymentIntentDecision(
            status: 'succeeded',
            reason: 'purchase_status',
          );
        }
        if (purchaseStatus == 'failed' ||
            purchaseStatus == 'canceled' ||
            purchaseStatus == 'cancelled' ||
            purchaseStatus == 'refunded') {
          return const _PaymentIntentDecision(
            status: 'failed',
            reason: 'purchase_status',
          );
        }
      }
    }

    if (verifyRemote &&
        provider == 'paystack' &&
        providerRef.isNotEmpty &&
        _paystackSecretKey.startsWith('sk_')) {
      final remoteStatus = await _verifyPaystackReference(providerRef);
      if (remoteStatus != null) {
        return _PaymentIntentDecision(status: remoteStatus, reason: 'paystack');
      }
    }
    return null;
  }

  String? _statusFromWebhookEventType(String eventType) {
    switch (eventType) {
      case 'payment_succeeded':
      case 'invoice_paid':
      case 'charge.success':
        return 'succeeded';
      case 'payment_failed':
      case 'charge.failed':
      case 'refund':
      case 'refund_succeeded':
      case 'chargeback':
        return 'failed';
      default:
        return null;
    }
  }

  Future<String?> _verifyPaystackReference(String providerRef) async {
    if (_paystackSecretKey.trim().isEmpty || providerRef.trim().isEmpty) {
      return null;
    }
    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              '$_paystackApiBaseUrl/transaction/verify/'
              '${Uri.encodeComponent(providerRef.trim())}',
            ),
            headers: <String, String>{
              'authorization': 'Bearer $_paystackSecretKey',
              'accept': 'application/json',
            },
          )
          .timeout(_paystackVerifyTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
      final data = payload['data'];
      if (data is! Map) {
        return null;
      }
      final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
      if (status == 'success' || status == 'successful' || status == 'paid') {
        return 'succeeded';
      }
      if (status == 'failed' ||
          status == 'abandoned' ||
          status == 'reversed' ||
          status == 'cancelled' ||
          status == 'canceled') {
        return 'failed';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Response> _retryPaymentWebhookProcessing(Request request) async {
    _requireAdmin(request);
    final paymentService = _paymentService;
    if (paymentService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Webhook retry processing is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    Map<String, Object?>? payload;
    try {
      payload = await _readJsonBodyOrNull(request);
    } on FormatException catch (error) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'error_code': 'VALIDATION_ERROR',
        'message': error.message,
        'trace_id': request.requestContext.traceId,
      });
    }
    final queryLimit = request.url.queryParameters['limit'];
    final bodyLimit = payload == null ? null : payload['limit'];
    final resolvedLimitRaw = bodyLimit?.toString() ?? queryLimit;
    final limit = _parseLimit(resolvedLimitRaw);

    final queueProcessor = _queueJobProcessor;
    if (queueProcessor != null) {
      final events = await paymentService.listRetryableWebhookEvents(
        limit: limit,
      );
      var enqueued = 0;
      for (final event in events) {
        await queueProcessor.enqueueJob(
          QueueJobTypes.processWebhookEvent,
          payload: <String, Object?>{
            'provider': event.provider,
            'provider_event_id': event.eventId,
          },
          maxAttempts: 5,
        );
        enqueued += 1;
      }
      await _auditLogStore.recordFromRequest(
        request,
        action: 'admin.payments.webhooks.retry',
        resourceType: 'admin_endpoint',
        resourceId: _auditResourceId(request),
        metadata: <String, Object?>{
          'limit': limit,
          'scanned': events.length,
          'enqueued': enqueued,
          'mode': 'queue',
        },
      );
      return jsonResponse(200, <String, Object?>{
        'ok': true,
        'trace_id': request.requestContext.traceId,
        'data': <String, Object?>{
          'scanned': events.length,
          'enqueued': enqueued,
          'mode': 'queue',
        },
      });
    }

    final result = await paymentService.retryPendingWebhooks(limit: limit);
    await _auditLogStore.recordFromRequest(
      request,
      action: 'admin.payments.webhooks.retry',
      resourceType: 'admin_endpoint',
      resourceId: _auditResourceId(request),
      metadata: <String, Object?>{
        'limit': limit,
        'scanned': result.scanned,
        'retried': result.retried,
        'rescheduled': result.rescheduled,
        'failed': result.failed,
        'skipped': result.skipped,
      },
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        'scanned': result.scanned,
        'retried': result.retried,
        'rescheduled': result.rescheduled,
        'failed': result.failed,
        'skipped': result.skipped,
      },
    });
  }

  Future<Response> _disableUser(Request request, String userId) async {
    _requireAdmin(request);
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Admin moderation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'error_code': 'VALIDATION_ERROR',
        'message': 'user id is required',
        'trace_id': request.requestContext.traceId,
      });
    }
    final disabledAtIso = DateTime.now().toUtc().toIso8601String();
    final updated = await db.update(
      'users',
      <String, Object?>{
        'disabled_at': disabledAtIso,
        'updated_at': disabledAtIso,
      },
      where: 'id = ?',
      whereArgs: <Object>[normalizedUserId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated <= 0) {
      _logAdminAction(
        request: request,
        action: 'disable_user',
        success: false,
        targetId: normalizedUserId,
        reasonCode: 'not_found',
      );
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'User not found',
        'trace_id': request.requestContext.traceId,
      });
    }
    _logAdminAction(
      request: request,
      action: 'disable_user',
      success: true,
      targetId: normalizedUserId,
    );
    await _analyticsEventStore?.emitFromRequest(
      request,
      name: 'admin.user_disabled',
      properties: <String, Object?>{'user_id': normalizedUserId},
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'user_id': normalizedUserId,
      'disabled_at': disabledAtIso,
      'disabled': true,
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _enableUser(Request request, String userId) async {
    _requireAdmin(request);
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Admin moderation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'error_code': 'VALIDATION_ERROR',
        'message': 'user id is required',
        'trace_id': request.requestContext.traceId,
      });
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final updated = await db.update(
      'users',
      <String, Object?>{'disabled_at': null, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: <Object>[normalizedUserId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated <= 0) {
      _logAdminAction(
        request: request,
        action: 'enable_user',
        success: false,
        targetId: normalizedUserId,
        reasonCode: 'not_found',
      );
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'User not found',
        'trace_id': request.requestContext.traceId,
      });
    }
    _logAdminAction(
      request: request,
      action: 'enable_user',
      success: true,
      targetId: normalizedUserId,
    );
    await _analyticsEventStore?.emitFromRequest(
      request,
      name: 'admin.user_enabled',
      properties: <String, Object?>{'user_id': normalizedUserId},
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'user_id': normalizedUserId,
      'disabled': false,
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _listUsers(Request request) async {
    _requireAdmin(request);
    await _auditLogStore.recordFromRequest(
      request,
      action: 'admin.list_users',
      resourceType: 'admin_endpoint',
      resourceId: _auditResourceId(request),
    );
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Admin user listing is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }

    final limit = _parseLimit(request.url.queryParameters['limit']);
    final cursor = _decodeCursor(request.url.queryParameters['cursor']);
    final whereParts = <String>[];
    final whereArgs = <Object>[];
    if (cursor != null) {
      whereParts.add('(created_at < ? OR (created_at = ? AND id < ?))');
      whereArgs.add(cursor.createdAtIso);
      whereArgs.add(cursor.createdAtIso);
      whereArgs.add(cursor.entityId);
    }

    final rows = await db.query(
      'users',
      columns: const <String>[
        'id',
        'role',
        'email',
        'display_name',
        'phone_e164',
        'disabled_at',
        'created_at',
        'updated_at',
      ],
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: limit + 1,
    );
    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.take(limit).toList(growable: false) : rows;
    final roleByUserId = await _resolveRolesByUser(db, pageRows);

    final users = pageRows
        .map((row) {
          final mapped = Map<String, Object?>.from(row);
          final userId = (mapped['id'] as String?) ?? '';
          final roles = roleByUserId[userId] ?? _fallbackRoles(mapped['role']);
          return <String, Object?>{
            'id': userId,
            'email': (mapped['email'] as String?)?.trim(),
            'display_name': (mapped['display_name'] as String?)?.trim(),
            'phone_e164': (mapped['phone_e164'] as String?)?.trim(),
            'disabled_at': (mapped['disabled_at'] as String?)?.trim(),
            'roles': roles,
            'created_at': (mapped['created_at'] as String?)?.trim(),
            'updated_at': (mapped['updated_at'] as String?)?.trim(),
          };
        })
        .toList(growable: false);

    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      nextCursor = _encodeCursor(
        (last['created_at'] as String?) ?? '',
        (last['id'] as String?) ?? '',
      );
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'users': users,
      if (nextCursor != null) 'next_cursor': nextCursor,
    });
  }

  Future<Response> _listTrips(Request request) async {
    _requireAdmin(request);
    final db = _db;
    if (db == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Admin trip listing is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final limit = _parseLimit(request.url.queryParameters['limit']);
    final statusFilter = _normalizeTripStatus(
      request.url.queryParameters['status'],
    );
    final cursor = _decodeCursor(request.url.queryParameters['cursor']);
    final whereParts = <String>[];
    final whereArgs = <Object>[];
    if (statusFilter != null) {
      whereParts.add('status = ?');
      whereArgs.add(statusFilter);
    }
    if (cursor != null) {
      whereParts.add('(created_at < ? OR (created_at = ? AND id < ?))');
      whereArgs.add(cursor.createdAtIso);
      whereArgs.add(cursor.createdAtIso);
      whereArgs.add(cursor.entityId);
    }

    final rows = await db.query(
      'trips',
      columns: const <String>[
        'id',
        'user_id',
        'status',
        'pickup_lat',
        'pickup_lng',
        'pickup_address',
        'dropoff_lat',
        'dropoff_lng',
        'dropoff_address',
        'notes',
        'scheduled_at',
        'created_at',
        'updated_at',
      ],
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: limit + 1,
    );
    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.take(limit).toList(growable: false) : rows;
    final trips = pageRows
        .map((row) {
          final mapped = Map<String, Object?>.from(row);
          return <String, Object?>{
            'id': mapped['id'],
            'user_id': mapped['user_id'],
            'status': mapped['status'],
            'pickup': <String, Object?>{
              'lat': (mapped['pickup_lat'] as num?)?.toDouble() ?? 0,
              'lng': (mapped['pickup_lng'] as num?)?.toDouble() ?? 0,
              'address': (mapped['pickup_address'] as String?)?.trim(),
            },
            'dropoff': <String, Object?>{
              'lat': (mapped['dropoff_lat'] as num?)?.toDouble() ?? 0,
              'lng': (mapped['dropoff_lng'] as num?)?.toDouble() ?? 0,
              'address': (mapped['dropoff_address'] as String?)?.trim(),
            },
            'notes': (mapped['notes'] as String?)?.trim(),
            'scheduled_at': (mapped['scheduled_at'] as String?)?.trim(),
            'created_at': (mapped['created_at'] as String?)?.trim(),
            'updated_at': (mapped['updated_at'] as String?)?.trim(),
          };
        })
        .toList(growable: false);

    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      nextCursor = _encodeCursor(
        (last['created_at'] as String?) ?? '',
        (last['id'] as String?) ?? '',
      );
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trips': trips,
      if (nextCursor != null) 'next_cursor': nextCursor,
    });
  }

  Future<Response> _contract(Request request) async {
    _requireAdmin(request);
    return jsonResponse(200, buildAdminContractPayload(buildInfo: _buildInfo));
  }

  Future<Response> _reverseTransaction(Request request) async {
    _requireAdmin(request);
    final walletReversalService = _walletReversalService;
    if (walletReversalService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Wallet reversal is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final body = await readJsonBody(request);

    final originalLedgerId = (body['original_ledger_id'] as num?)?.toInt();
    if (originalLedgerId == null || originalLedgerId <= 0) {
      throw const DomainInvariantError(code: 'original_ledger_id_required');
    }

    try {
      final result = await walletReversalService.reverseWalletLedgerEntry(
        originalLedgerId: originalLedgerId,
        requestedByUserId: request.requestContext.userId ?? '',
        requesterIsAdmin: true,
        reason: (body['reason'] as String?)?.trim().isNotEmpty == true
            ? (body['reason'] as String).trim()
            : 'admin_reversal',
        idempotencyKey: request.requestContext.idempotencyKey ?? '',
        reversalAmountMinor: (body['reversal_amount_minor'] as num?)?.toInt(),
      );
      _logAdminAction(
        request: request,
        action: 'wallet_reversal',
        success: true,
        targetId: originalLedgerId.toString(),
      );
      return jsonResponse(200, result);
    } catch (error) {
      _logAdminAction(
        request: request,
        action: 'wallet_reversal',
        success: false,
        targetId: originalLedgerId.toString(),
        reasonCode: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  Future<Response> _marketplacePurchaseDebug(
    Request request,
    String purchaseId,
  ) async {
    _requireAdmin(request);
    final reconciliationService = _reconciliationService;
    if (reconciliationService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Marketplace reconciliation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final result = await reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      dryRun: true,
    );
    if (result == null) {
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'Marketplace purchase not found',
        'trace_id': request.requestContext.traceId,
      });
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'data': <String, Object?>{
        'purchase': _purchasePayload(result.purchase),
        'latest_entitlements': result.entitlementsBefore
            .map(_entitlementPayload)
            .toList(growable: false),
        'ledger_entries': result.ledgerEntries
            .map(_ledgerPayload)
            .toList(growable: false),
        'webhook_events_summary': result.webhookEvents
            .map(_webhookPayload)
            .toList(growable: false),
        'timeline': result.timelineEvents
            .map(_timelinePayload)
            .toList(growable: false),
        'reconciliation_dry_run': <String, Object?>{
          'drift_detected': result.driftDetected,
          'would_apply': result.driftDetected,
          'current_status': result.currentStatus,
          'expected_status': result.expectedStatus,
          'drift_reasons': result.driftReasons,
        },
      },
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _marketplacePurchaseReconcile(
    Request request,
    String purchaseId,
  ) async {
    _requireAdmin(request);
    final reconciliationService = _reconciliationService;
    if (reconciliationService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Marketplace reconciliation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final result = await reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      dryRun: false,
    );
    if (result == null) {
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'Marketplace purchase not found',
        'trace_id': request.requestContext.traceId,
      });
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'data': <String, Object?>{
        'purchase_id': result.purchaseId,
        'before': <String, Object?>{'status': result.currentStatus},
        'after': <String, Object?>{'status': result.finalStatus},
        'applied': result.applied,
        'drift_detected': result.driftDetected,
        'drift_reasons': result.driftReasons,
      },
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _marketplaceOffersExplain(Request request) async {
    _requireAdmin(request);
    final query = request.url.queryParameters;
    final subjectType = (query['subject_type'] ?? 'org').trim();
    final subjectId = (query['subject_id'] ?? '').trim();
    final orgId = subjectType == 'org' ? subjectId : '';
    final offerId = (query['offer_id'] ?? 'offer_sedan_01').trim();
    final seats = int.tryParse((query['seats'] ?? '1').trim()) ?? 1;

    final preview = await _revenueService.pricingPreview(
      orgId: orgId.isEmpty ? 'admin-preview' : orgId,
      userId: request.requestContext.userId ?? 'admin',
      offerId: offerId,
      seats: seats,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        'subject_type': subjectType,
        'subject_id': subjectId,
        'matched_rules': const <Map<String, Object?>>[],
        'experiment_assignment': const <String, Object?>{
          'experiment_id': 'none',
          'variant_key': 'A',
        },
        'final_prices': preview.toMap(),
      },
    });
  }

  Future<Response> _billingOverview(Request request, String orgId) async {
    _requireAdmin(request);
    final data = await _revenueService.billingOverview(orgId);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': data,
    });
  }

  Future<Response> _grantCredits(Request request) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);
    final orgId =
        (body['org_id'] as String?)?.trim() ??
        (body['orgId'] as String?)?.trim() ??
        '';
    final amountMinor =
        (body['amount_minor'] as num?)?.toInt() ??
        (body['amountMinor'] as num?)?.toInt() ??
        0;
    final reason = (body['reason'] as String?)?.trim() ?? 'admin_grant';
    if (orgId.isEmpty || amountMinor <= 0) {
      _logAdminAction(
        request: request,
        action: 'grant_credits',
        success: false,
        reasonCode: 'validation_error',
      );
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'VALIDATION_ERROR',
        'message': 'org_id and amount_minor (>0) are required',
      });
    }
    try {
      await _revenueService.grantCredits(
        orgId: orgId,
        amountMinor: amountMinor,
        reason: reason,
      );
    } on MarketplaceRevenueException catch (error) {
      _logAdminAction(
        request: request,
        action: 'grant_credits',
        success: false,
        targetId: orgId,
        reasonCode: error.code,
      );
      return jsonResponse(error.statusCode, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': error.code,
        'message': error.message,
      });
    }
    final balance = await _revenueService.creditsBalance(orgId);
    _logAdminAction(
      request: request,
      action: 'grant_credits',
      success: true,
      targetId: orgId,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        'granted': amountMinor,
        'org_id': orgId,
        'balance': balance,
      },
    });
  }

  Future<Response> _adjustRisk(
    Request request,
    String subjectType,
    String subjectId,
  ) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);
    final delta =
        (body['delta'] as num?)?.toInt() ??
        (body['score_delta'] as num?)?.toInt() ??
        0;
    final reason = (body['reason'] as String?)?.trim() ?? 'manual_adjust';
    if (delta == 0) {
      _logAdminAction(
        request: request,
        action: 'adjust_risk',
        success: false,
        targetId: '$subjectType:$subjectId',
        reasonCode: 'validation_error',
      );
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'VALIDATION_ERROR',
        'message': 'delta must be non-zero',
      });
    }
    await _revenueService.adjustRisk(
      subjectType: subjectType,
      subjectId: subjectId,
      delta: delta,
      reason: reason,
    );
    final state = await _revenueService.riskState(
      subjectType: subjectType,
      subjectId: subjectId,
    );
    _logAdminAction(
      request: request,
      action: 'adjust_risk',
      success: true,
      targetId: '$subjectType:$subjectId',
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': state,
    });
  }

  Future<Response> _pauseDunning(Request request, String caseId) async {
    _requireAdmin(request);
    final updated = await _revenueService.pauseDunningCase(caseId);
    if (!updated) {
      _logAdminAction(
        request: request,
        action: 'pause_dunning',
        success: false,
        targetId: caseId,
        reasonCode: 'not_found',
      );
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'NOT_FOUND',
        'message': 'Dunning case not found',
      });
    }
    _logAdminAction(
      request: request,
      action: 'pause_dunning',
      success: true,
      targetId: caseId,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{'case_id': caseId, 'state': 'paused'},
    });
  }

  Future<Response> _resumeDunning(Request request, String caseId) async {
    _requireAdmin(request);
    final updated = await _revenueService.resumeDunningCase(caseId);
    if (!updated) {
      _logAdminAction(
        request: request,
        action: 'resume_dunning',
        success: false,
        targetId: caseId,
        reasonCode: 'not_found',
      );
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'NOT_FOUND',
        'message': 'Dunning case not found',
      });
    }
    _logAdminAction(
      request: request,
      action: 'resume_dunning',
      success: true,
      targetId: caseId,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{'case_id': caseId, 'state': 'active'},
    });
  }

  Future<Response> _writeoffDunning(Request request, String caseId) async {
    _requireAdmin(request);
    final updated = await _revenueService.writeoffDunningCase(caseId);
    if (!updated) {
      _logAdminAction(
        request: request,
        action: 'writeoff_dunning',
        success: false,
        targetId: caseId,
        reasonCode: 'not_found',
      );
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'NOT_FOUND',
        'message': 'Dunning case not found',
      });
    }
    _logAdminAction(
      request: request,
      action: 'writeoff_dunning',
      success: true,
      targetId: caseId,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{'case_id': caseId, 'state': 'written_off'},
    });
  }

  Future<Response> _auditSummary(Request request) async {
    _requireAdmin(request);
    final orgId =
        (request.url.queryParameters['org_id'] ??
                request.url.queryParameters['orgId'] ??
                '')
            .trim();
    if (orgId.isEmpty) {
      return jsonResponse(400, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'VALIDATION_ERROR',
        'message': 'org_id query parameter is required',
      });
    }
    final data = await _revenueService.auditSummary(orgId);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': data,
    });
  }

  Future<Response> _sentrySmoke(Request request) async {
    _requireAdmin(request);
    if (!BackendSentryObservability.isEnabled) {
      return jsonResponse(409, <String, Object?>{
        'ok': false,
        'trace_id': request.requestContext.traceId,
        'error_code': 'SENTRY_NOT_ENABLED',
        'message':
            'Sentry is not enabled. Set SENTRY_DSN and restart the backend.',
      });
    }
    final eventId = await BackendSentryObservability.captureMessage(
      'hailo_backend_sentry_smoke',
      request: request,
      source: 'admin_sentry_smoke',
    );
    _logAdminAction(request: request, action: 'sentry_smoke', success: true);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'event_id': eventId?.toString() ?? '',
      'message': 'Sentry smoke event captured',
    });
  }

  Map<String, Object?> _purchasePayload(MarketplacePurchaseRecord purchase) {
    return <String, Object?>{
      'id': purchase.id,
      'user_id': purchase.userId,
      'offer_id': purchase.offerId,
      'offer_title': purchase.offerTitle,
      'status': purchase.status,
      'currency': purchase.currency,
      'price_minor': purchase.totalAmountMinor,
      'seats_total': purchase.seatCount,
      'idempotency_key': purchase.idempotencyKey,
      'created_at': purchase.createdAt.toIso8601String(),
      'updated_at': purchase.updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _entitlementPayload(MarketplaceEntitlementRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'user_id': row.userId,
      'entitlement_type': row.entitlementType,
      'value_json': row.value,
      'status': row.status,
      'effective_from': row.effectiveFrom.toIso8601String(),
      'effective_to': row.effectiveTo?.toIso8601String(),
    };
  }

  Map<String, Object?> _ledgerPayload(BillingLedgerEntryRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'user_id': row.userId,
      'entry_type': row.entryType,
      'provider': row.provider,
      'provider_ref': row.providerRef,
      'amount_minor': row.amountMinor,
      'currency': row.currency,
      'metadata': row.metadata,
      'occurred_at': row.occurredAt.toIso8601String(),
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _webhookPayload(MarketplaceWebhookEventSummary row) {
    return <String, Object?>{
      'provider': row.provider,
      'provider_event_id': row.providerEventId,
      'event_type': row.eventType,
      'signature_valid': row.signatureValid,
      'processed': row.processed,
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _timelinePayload(MarketplaceTimelineEventRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'event_type': row.eventType,
      'event_data': row.eventData,
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  Future<Map<String, List<String>>> _resolveRolesByUser(
    Database db,
    List<Map<String, Object?>> userRows,
  ) async {
    final userIds = userRows
        .map((row) => (row['id'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (userIds.isEmpty || !await _tableExists(db, 'user_roles')) {
      return <String, List<String>>{};
    }
    final placeholders = List<String>.filled(userIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT user_id, role
      FROM user_roles
      WHERE user_id IN ($placeholders)
      ORDER BY role ASC
      ''', userIds);
    final byUser = <String, Set<String>>{};
    for (final row in rows) {
      final userId = (row['user_id'] as String?)?.trim() ?? '';
      final role = _mapRole(
        (row['role'] as String?)?.trim().toLowerCase() ?? '',
      );
      if (userId.isEmpty || role.isEmpty) {
        continue;
      }
      byUser.putIfAbsent(userId, () => <String>{}).add(role);
    }
    return byUser.map(
      (userId, roles) =>
          MapEntry<String, List<String>>(userId, roles.toList(growable: false)),
    );
  }

  List<String> _fallbackRoles(Object? rawRole) {
    final mapped = _mapRole((rawRole as String?)?.trim().toLowerCase() ?? '');
    if (mapped.isEmpty) {
      return const <String>['user'];
    }
    if (mapped == 'user') {
      return const <String>['user'];
    }
    return <String>['user', mapped];
  }

  String _mapRole(String role) {
    switch (role) {
      case 'admin':
        return 'admin';
      case 'driver':
        return 'driver';
      case 'inspector':
        return 'inspector';
      case 'merchant':
      case 'fleet_owner':
        return 'merchant';
      case 'rider':
      case 'user':
      default:
        return 'user';
    }
  }

  DateTime? _parseDateTimeOrNull(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  Future<Map<String, Object?>?> _readJsonBodyOrNull(Request request) async {
    final rawBody = await request.readAsString();
    final normalized = rawBody.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(normalized);
    if (decoded is! Map) {
      throw const FormatException('request body must be a JSON object');
    }
    return decoded.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }

  int _parseLimit(String? rawLimit) {
    final normalized = rawLimit?.trim() ?? '';
    if (normalized.isEmpty) {
      return 20;
    }
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed <= 0) {
      throw const DomainInvariantError(code: 'invalid_limit');
    }
    return parsed > 100 ? 100 : parsed;
  }

  String? _normalizeTripStatus(String? rawStatus) {
    final normalized = rawStatus?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    if (!_tripStatuses.contains(normalized)) {
      throw const DomainInvariantError(code: 'invalid_trip_status');
    }
    return normalized;
  }

  _AdminCursor? _decodeCursor(String? rawCursor) {
    final cursor = rawCursor?.trim() ?? '';
    if (cursor.isEmpty) {
      return null;
    }
    try {
      final normalized = _normalizeCursorBase64(cursor);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final separator = decoded.indexOf('|');
      if (separator <= 0 || separator >= decoded.length - 1) {
        throw const FormatException('invalid_cursor');
      }
      final createdAtIso = decoded.substring(0, separator).trim();
      final entityId = decoded.substring(separator + 1).trim();
      final createdAt = DateTime.tryParse(createdAtIso)?.toUtc();
      if (createdAt == null || entityId.isEmpty) {
        throw const FormatException('invalid_cursor');
      }
      return _AdminCursor(
        createdAtIso: createdAt.toIso8601String(),
        entityId: entityId,
      );
    } catch (_) {
      throw const DomainInvariantError(code: 'invalid_pagination_cursor');
    }
  }

  String _encodeCursor(String createdAtIso, String entityId) {
    final payload = '$createdAtIso|$entityId';
    final encoded = base64UrlEncode(utf8.encode(payload));
    return encoded.replaceAll('=', '');
  }

  String _normalizeCursorBase64(String rawCursor) {
    final cursor = rawCursor.trim();
    final remainder = cursor.length % 4;
    if (remainder == 0) {
      return cursor;
    }
    final padding = List<String>.filled(4 - remainder, '=').join();
    return '$cursor$padding';
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

  Future<int> _countRows(Database db, String tableName) async {
    if (!await _tableExists(db, tableName)) {
      return 0;
    }
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $tableName');
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countRowsWhere(
    Database db,
    String tableName, {
    required String where,
    required List<Object> whereArgs,
  }) async {
    if (!await _tableExists(db, tableName)) {
      return 0;
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $tableName WHERE $where',
      whereArgs,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, int>> _statusCounts(
    Database db, {
    required String table,
    String statusColumn = 'status',
  }) async {
    if (!await _tableExists(db, table) ||
        !await _columnExists(db, table, statusColumn)) {
      return <String, int>{};
    }

    final rows = await db.rawQuery('''
      SELECT $statusColumn AS status_key, COUNT(*) AS count
      FROM $table
      WHERE $statusColumn IS NOT NULL
      GROUP BY $statusColumn
      ORDER BY $statusColumn ASC
      ''');
    final counts = <String, int>{};
    for (final row in rows) {
      final key = (row['status_key'] as String?)?.trim().toLowerCase() ?? '';
      if (key.isEmpty) {
        continue;
      }
      counts[key] = (row['count'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<int> _countStatusSince(
    Database db, {
    required String table,
    required Set<String> statuses,
    required DateTime sinceUtc,
  }) async {
    if (!await _tableExists(db, table) ||
        !await _columnExists(db, table, 'status')) {
      return 0;
    }
    final normalizedStatuses = statuses
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedStatuses.isEmpty) {
      return 0;
    }
    final placeholders = List<String>.filled(
      normalizedStatuses.length,
      '?',
    ).join(', ');
    final whereParts = <String>['LOWER(status) IN ($placeholders)'];
    final whereArgs = <Object>[...normalizedStatuses];
    String? timeColumn;
    if (await _columnExists(db, table, 'updated_at')) {
      timeColumn = 'updated_at';
    } else if (await _columnExists(db, table, 'created_at')) {
      timeColumn = 'created_at';
    }
    if (timeColumn != null) {
      whereParts.add('$timeColumn >= ?');
      whereArgs.add(sinceUtc.toUtc().toIso8601String());
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE ${whereParts.join(' AND ')}',
      whereArgs,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countFailedWebhookEvents(Database db) async {
    if (!await _tableExists(db, 'webhook_events')) {
      return 0;
    }
    if (await _columnExists(db, 'webhook_events', 'processing_state')) {
      return _countRowsWhere(
        db,
        'webhook_events',
        where: 'LOWER(processing_state) = ?',
        whereArgs: const <Object>['failed'],
      );
    }
    if (await _columnExists(db, 'webhook_events', 'status')) {
      return _countRowsWhere(
        db,
        'webhook_events',
        where: 'LOWER(status) = ?',
        whereArgs: const <Object>['failed'],
      );
    }
    return 0;
  }

  Future<bool> _columnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    if (!await _tableExists(db, tableName)) {
      return false;
    }
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    for (final row in rows) {
      final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
      if (name == columnName.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      <Object>['table', tableName],
    );
    return rows.isNotEmpty;
  }

  bool _isProductionEnvironment() {
    final environment = (_runtimeConfigSnapshot['environment'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return environment == 'prod' || environment == 'production';
  }

  Future<String> _ensureSmokeUserSqlite({
    required Database db,
    required String phoneE164,
    required String role,
  }) async {
    final userColumns = await _sqliteTableColumns(db, 'users');
    if (!userColumns.contains('id')) {
      throw StateError('users_table_missing_id_column');
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();

    var userId = '';
    if (userColumns.contains('phone_e164')) {
      final existing = await db.query(
        'users',
        columns: const <String>['id'],
        where: 'phone_e164 = ?',
        whereArgs: <Object>[phoneE164],
        limit: 1,
      );
      userId = existing.isEmpty
          ? ''
          : ((existing.first['id'] as String?)?.trim() ?? '');
    }
    if (userId.isEmpty) {
      for (var attempt = 0; attempt < 4; attempt++) {
        final candidateId = _uuid.v4();
        final email = 'smoke.$candidateId@hailo.local';
        final row = <String, Object?>{'id': candidateId};
        if (userColumns.contains('phone_e164')) {
          row['phone_e164'] = phoneE164;
        }
        if (userColumns.contains('role')) {
          row['role'] = role;
        }
        if (userColumns.contains('email')) {
          row['email'] = email;
        }
        if (userColumns.contains('display_name')) {
          row['display_name'] = 'Smoke User';
        }
        if (userColumns.contains('created_at')) {
          row['created_at'] = nowIso;
        }
        if (userColumns.contains('updated_at')) {
          row['updated_at'] = nowIso;
        }
        try {
          await db.insert('users', row);
          userId = candidateId;
          break;
        } catch (_) {
          if (userColumns.contains('phone_e164')) {
            final retry = await db.query(
              'users',
              columns: const <String>['id'],
              where: 'phone_e164 = ?',
              whereArgs: <Object>[phoneE164],
              limit: 1,
            );
            if (retry.isNotEmpty) {
              userId = (retry.first['id'] as String?)?.trim() ?? '';
              if (userId.isNotEmpty) {
                break;
              }
            }
          }
        }
      }
    }
    if (userId.isEmpty) {
      throw StateError('unable_to_create_smoke_user');
    }

    final hasUserRoles =
        await _tableExists(db, 'user_roles') &&
        await _columnExists(db, 'user_roles', 'user_id') &&
        await _columnExists(db, 'user_roles', 'role');
    if (hasUserRoles) {
      await db.insert('user_roles', <String, Object?>{
        'user_id': userId,
        'role': role,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return userId;
  }

  Future<Set<String>> _sqliteTableColumns(Database db, String tableName) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = <String>{};
    for (final row in rows) {
      final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
      if (name.isNotEmpty) {
        columns.add(name);
      }
    }
    return columns;
  }

  Future<String> _ensureSmokeUserPostgres({
    required PostgresProvider provider,
    required String phoneE164,
    required String role,
  }) async {
    final existing = await provider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id::text
        FROM users
        WHERE phone_e164 = @phone_e164
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'phone_e164': phoneE164},
      ),
    );
    var userId = existing.isEmpty
        ? ''
        : (existing.first[0] as String?)?.trim() ?? '';
    if (userId.isEmpty) {
      for (var attempt = 0; attempt < 4; attempt++) {
        final candidateId = _uuid.v4();
        try {
          await provider.withConnection(
            (connection) => connection.execute(
              '''
              INSERT INTO users(id, phone_e164, created_at)
              VALUES(CAST(@id AS UUID), @phone_e164, @created_at)
              ON CONFLICT (phone_e164) DO NOTHING
              ''',
              substitutionValues: <String, Object?>{
                'id': candidateId,
                'phone_e164': phoneE164,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              },
            ),
          );
          final retry = await provider.withConnection(
            (connection) => connection.query(
              '''
              SELECT id::text
              FROM users
              WHERE phone_e164 = @phone_e164
              LIMIT 1
              ''',
              substitutionValues: <String, Object?>{'phone_e164': phoneE164},
            ),
          );
          if (retry.isNotEmpty) {
            userId = (retry.first[0] as String?)?.trim() ?? '';
            if (userId.isNotEmpty) {
              break;
            }
          }
        } catch (_) {
          // Retry generation for rare UUID collision cases.
        }
      }
    }
    if (userId.isEmpty) {
      throw StateError('unable_to_create_smoke_user');
    }

    try {
      await provider.withConnection(
        (connection) => connection.execute(
          '''
          INSERT INTO user_roles(user_id, role)
          VALUES(CAST(@user_id AS UUID), @role)
          ON CONFLICT (user_id, role) DO NOTHING
          ''',
          substitutionValues: <String, Object?>{
            'user_id': userId,
            'role': role,
          },
        ),
      );
    } catch (_) {
      // user_roles may not exist in minimal deployments; keep endpoint resilient.
    }
    return userId;
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }

  void _logAdminAction({
    required Request request,
    required String action,
    required bool success,
    String? targetId,
    String? reasonCode,
  }) {
    _auditLogger.adminAction(
      traceId: request.requestContext.traceId,
      actorUserId: request.requestContext.userId ?? 'unknown',
      action: action,
      success: success,
      targetId: targetId,
      reasonCode: reasonCode,
    );
    unawaited(
      _auditLogStore.recordFromRequest(
        request,
        action: 'admin.$action',
        resourceType: 'admin_endpoint',
        resourceId: _auditResourceId(request),
        metadata: <String, Object?>{
          'success': success,
          if (targetId != null && targetId.trim().isNotEmpty)
            'target_id': targetId.trim(),
          if (reasonCode != null && reasonCode.trim().isNotEmpty)
            'reason_code': reasonCode.trim(),
        },
      ),
    );
  }

  String _auditResourceId(Request request) {
    final path = request.url.path.trim();
    if (path.isEmpty) {
      return 'admin';
    }
    return path;
  }
}

class _AdminCursor {
  const _AdminCursor({required this.createdAtIso, required this.entityId});

  final String createdAtIso;
  final String entityId;
}

class _PaymentIntentDecision {
  const _PaymentIntentDecision({required this.status, required this.reason});

  final String status;
  final String reason;
}
