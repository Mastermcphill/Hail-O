import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/request_metrics.dart';
import '../../infra/postgres_provider.dart';

class MarketplaceRevenueException implements Exception {
  const MarketplaceRevenueException({
    required this.code,
    required this.message,
    this.statusCode = 400,
  });

  final String code;
  final String message;
  final int statusCode;
}

class PricingPreview {
  const PricingPreview({
    required this.orgId,
    required this.offerId,
    required this.seats,
    required this.currency,
    required this.baseMinor,
    required this.couponMinor,
    required this.referralMinor,
    required this.creditsMinor,
    required this.finalDueMinor,
    required this.appliedCoupon,
    required this.appliedReferral,
  });

  final String orgId;
  final String offerId;
  final int seats;
  final String currency;
  final int baseMinor;
  final int couponMinor;
  final int referralMinor;
  final int creditsMinor;
  final int finalDueMinor;
  final String? appliedCoupon;
  final String? appliedReferral;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'org_id': orgId,
      'offer_id': offerId,
      'seats': seats,
      'currency': currency,
      'base_minor': baseMinor,
      'coupon_discount_minor': couponMinor,
      'referral_discount_minor': referralMinor,
      'credits_applied_minor': creditsMinor,
      'final_due_minor': finalDueMinor,
      'applied_coupon': appliedCoupon,
      'applied_referral': appliedReferral,
      'order_of_operations': const <String>[
        'base_price',
        'coupon',
        'referral',
        'credits',
        'provider',
      ],
    };
  }
}

class MarketplaceRevenueService {
  MarketplaceRevenueService({
    PostgresProvider? postgresProvider,
    RequestMetrics? metrics,
    DateTime Function()? nowUtc,
    Uuid? uuid,
    void Function(String line)? logSink,
  }) : _postgresProvider = postgresProvider,
       _metrics = metrics,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid(),
       _logSink = logSink ?? print;

  final PostgresProvider? _postgresProvider;
  final RequestMetrics? _metrics;
  final DateTime Function() _nowUtc;
  final Uuid _uuid;
  final void Function(String line) _logSink;

  final Map<String, String> _couponByOrg = <String, String>{};
  final Map<String, String> _referralByOrg = <String, String>{};
  final Map<String, int> _creditsByOrg = <String, int>{};
  final Map<String, List<Map<String, Object?>>> _creditLedgerByOrg =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<Map<String, Object?>>> _invoiceByOrg =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> _riskBySubject =
      <String, Map<String, Object?>>{};
  final Map<String, int> _couponUseCount = <String, int>{};
  final Set<String> _commsDedupe = <String>{};
  final List<Map<String, Object?>> _commsOutbox = <Map<String, Object?>>[];
  final Map<String, Map<String, Object?>> _dunningCases =
      <String, Map<String, Object?>>{};

  Future<Map<String, Object?>> applyCoupon({
    required String orgId,
    required String userId,
    required String couponCode,
    required String offerId,
    required int seats,
  }) async {
    final code = couponCode.trim().toUpperCase();
    final coupon = _seedCoupons[code];
    if (coupon == null) {
      throw const MarketplaceRevenueException(
        code: 'NOT_FOUND',
        message: 'Coupon not found',
        statusCode: 404,
      );
    }
    final now = _nowUtc();
    if (now.isBefore(coupon.validFrom) || now.isAfter(coupon.validUntil)) {
      throw const MarketplaceRevenueException(
        code: 'COUPON_INVALID',
        message: 'Coupon is not active',
      );
    }
    final used = _couponUseCount[code] ?? 0;
    if (coupon.maxUses != null && used >= coupon.maxUses!) {
      throw const MarketplaceRevenueException(
        code: 'COUPON_LIMIT_REACHED',
        message: 'Coupon redemption limit reached',
      );
    }
    _couponByOrg[orgId] = code;
    _couponUseCount[code] = used + 1;
    final preview = await pricingPreview(
      orgId: orgId,
      userId: userId,
      offerId: offerId,
      seats: seats,
    );
    _metrics?.recordCouponApply(result: 'success');
    return <String, Object?>{
      'coupon_code': code,
      'pricing_preview': preview.toMap(),
    };
  }

  Future<Map<String, Object?>> removeCoupon({
    required String orgId,
    required String userId,
    required String offerId,
    required int seats,
  }) async {
    _couponByOrg.remove(orgId);
    final preview = await pricingPreview(
      orgId: orgId,
      userId: userId,
      offerId: offerId,
      seats: seats,
    );
    return <String, Object?>{'removed': true, 'pricing_preview': preview.toMap()};
  }

  Future<Map<String, Object?>> applyReferral({
    required String orgId,
    required String userId,
    required String referralCode,
    required String offerId,
    required int seats,
  }) async {
    final code = referralCode.trim().toUpperCase();
    final referral = _seedReferrals[code];
    if (referral == null) {
      throw const MarketplaceRevenueException(
        code: 'NOT_FOUND',
        message: 'Referral code not found',
        statusCode: 404,
      );
    }
    if (referral.ownerId == userId.trim()) {
      await recordRiskEvent(
        subjectType: 'user',
        subjectId: userId,
        eventType: 'referral_self_loop',
        scoreDelta: 35,
      );
      throw const MarketplaceRevenueException(
        code: 'REFERRAL_SELF_REFERRAL',
        message: 'Self-referral is not allowed',
      );
    }
    _referralByOrg[orgId] = code;
    final preview = await pricingPreview(
      orgId: orgId,
      userId: userId,
      offerId: offerId,
      seats: seats,
    );
    _metrics?.recordReferralApply(result: 'success');
    return <String, Object?>{
      'referral_code': code,
      'pricing_preview': preview.toMap(),
    };
  }

  Future<PricingPreview> pricingPreview({
    required String orgId,
    required String userId,
    required String offerId,
    required int seats,
  }) async {
    final normalizedSeats = seats < 1 ? 1 : seats;
    final offerPrice = await _offerBaseMinor(offerId);
    final currency = await _offerCurrency(offerId);
    final baseMinor = offerPrice * normalizedSeats;
    final coupon = _couponByOrg[orgId];
    final referral = _referralByOrg[orgId];
    final couponMinor = _discountFromCoupon(baseMinor: baseMinor, couponCode: coupon);
    final referralMinor = _discountFromReferral(
      baseMinor: baseMinor - couponMinor,
      referralCode: referral,
    );
    final runningDue = (baseMinor - couponMinor - referralMinor).clamp(0, 1 << 60);
    final creditsBalance = await _creditsBalance(orgId: orgId);
    final creditsMinor = creditsBalance < runningDue ? creditsBalance : runningDue;
    final finalDueMinor = runningDue - creditsMinor;
    return PricingPreview(
      orgId: orgId,
      offerId: offerId,
      seats: normalizedSeats,
      currency: currency,
      baseMinor: baseMinor,
      couponMinor: couponMinor,
      referralMinor: referralMinor,
      creditsMinor: creditsMinor,
      finalDueMinor: finalDueMinor,
      appliedCoupon: coupon,
      appliedReferral: referral,
    );
  }

  Future<Map<String, Object?>> createInvoice({
    required String orgId,
    required String userId,
    required String purchaseId,
    required String offerId,
    required int seats,
  }) async {
    final preview = await pricingPreview(
      orgId: orgId,
      userId: userId,
      offerId: offerId,
      seats: seats,
    );
    final invoiceId = _uuid.v4();
    final now = _nowUtc();
    final invoice = <String, Object?>{
      'invoice_id': invoiceId,
      'org_id': orgId,
      'purchase_id': purchaseId,
      'currency': preview.currency,
      'subtotal_minor': preview.baseMinor,
      'discount_minor': preview.couponMinor + preview.referralMinor,
      'credit_applied_minor': preview.creditsMinor,
      'total_due_minor': preview.finalDueMinor,
      'status': preview.finalDueMinor == 0 ? 'paid' : 'open',
      'period_start': now.toIso8601String(),
      'period_end': now.add(const Duration(days: 30)).toIso8601String(),
      'due_at': now.add(const Duration(days: 3)).toIso8601String(),
      'created_at': now.toIso8601String(),
      'pricing_breakdown': preview.toMap(),
    };
    _invoiceByOrg.putIfAbsent(orgId, () => <Map<String, Object?>>[]).insert(0, invoice);
    _metrics?.recordInvoiceCreated(status: (invoice['status'] ?? '').toString());
    if (preview.creditsMinor > 0) {
      await _debitCredits(
        orgId: orgId,
        amountMinor: preview.creditsMinor,
        relatedType: 'invoice',
        relatedId: invoiceId,
      );
    }
    if ((invoice['status'] ?? '') == 'open') {
      _dunningCases[invoiceId] = <String, Object?>{
        'id': _uuid.v4(),
        'org_id': orgId,
        'purchase_id': purchaseId,
        'invoice_id': invoiceId,
        'state': 'active',
        'attempt_count': 0,
        'next_attempt_at': now.toIso8601String(),
        'last_error': null,
      };
    }
    return invoice;
  }

  Future<List<Map<String, Object?>>> listInvoices(String orgId) async {
    if (_postgresProvider == null) {
      return List<Map<String, Object?>>.from(_invoiceByOrg[orgId] ?? const <Map<String, Object?>>[]);
    }
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          org_id,
          purchase_id::text,
          currency,
          subtotal_minor,
          discount_minor,
          credit_applied_minor,
          total_due_minor,
          status,
          period_start,
          period_end,
          due_at,
          created_at
        FROM billing_invoices
        WHERE org_id = @org_id
        ORDER BY created_at DESC
        LIMIT 200
        ''',
        substitutionValues: <String, Object?>{'org_id': orgId},
      ),
    );
    return rows.map((row) => <String, Object?>{
      'invoice_id': (row[0] as String?)?.trim() ?? '',
      'org_id': (row[1] as String?)?.trim() ?? '',
      'purchase_id': (row[2] as String?)?.trim(),
      'currency': (row[3] as String?)?.trim() ?? 'NGN',
      'subtotal_minor': (row[4] as num?)?.toInt() ?? 0,
      'discount_minor': (row[5] as num?)?.toInt() ?? 0,
      'credit_applied_minor': (row[6] as num?)?.toInt() ?? 0,
      'total_due_minor': (row[7] as num?)?.toInt() ?? 0,
      'status': (row[8] as String?)?.trim() ?? '',
      'period_start': (row[9] as DateTime?)?.toUtc().toIso8601String(),
      'period_end': (row[10] as DateTime?)?.toUtc().toIso8601String(),
      'due_at': (row[11] as DateTime?)?.toUtc().toIso8601String(),
      'created_at': (row[12] as DateTime?)?.toUtc().toIso8601String(),
    }).toList(growable: false);
  }

  Future<Map<String, Object?>> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    final invoices = await listInvoices(orgId);
    Map<String, Object?>? target;
    for (final invoice in invoices) {
      if ((invoice['invoice_id'] ?? '').toString() == invoiceId) {
        target = invoice;
        break;
      }
    }
    if (target == null) {
      throw const MarketplaceRevenueException(
        code: 'NOT_FOUND',
        message: 'Invoice not found',
        statusCode: 404,
      );
    }

    final caseRecord = _dunningCases[invoiceId];
    final attemptNo = ((caseRecord?['attempt_count'] as int?) ?? 0) + 1;
    final recovered = attemptNo >= 2;
    _dunningCases[invoiceId] = <String, Object?>{
      ...(caseRecord ?? <String, Object?>{
        'id': _uuid.v4(),
        'org_id': orgId,
        'purchase_id': target['purchase_id'],
        'invoice_id': invoiceId,
      }),
      'state': recovered ? 'recovered' : (attemptNo >= 4 ? 'written_off' : 'active'),
      'attempt_count': attemptNo,
      'next_attempt_at': recovered
          ? null
          : _nowUtc().add(_dunningDelayForAttempt(attemptNo)).toIso8601String(),
      'last_error': recovered ? null : 'payment_failed',
    };
    _metrics?.recordDunningAttempt(outcome: recovered ? 'success' : 'fail');

    final status = recovered ? 'paid' : 'failed';
    target['status'] = status;
    if (recovered) {
      await enqueueComms(
        channel: 'email',
        recipient: 'billing@$orgId.local',
        templateId: 'payment_recovered',
        payload: <String, Object?>{'org_id': orgId, 'invoice_id': invoiceId},
        dedupeKey: '$orgId:payment_recovered:$invoiceId',
      );
    } else {
      final template = attemptNo >= 3
          ? 'invoice_failed_final'
          : (attemptNo == 2 ? 'invoice_failed_2' : 'invoice_failed_1');
      await enqueueComms(
        channel: 'email',
        recipient: 'billing@$orgId.local',
        templateId: template,
        payload: <String, Object?>{'org_id': orgId, 'invoice_id': invoiceId},
        dedupeKey: '$orgId:$template:$invoiceId',
      );
      await recordRiskEvent(
        subjectType: 'org',
        subjectId: orgId,
        eventType: 'failed_payment',
        scoreDelta: 20,
      );
    }
    return <String, Object?>{...target, 'retried': true};
  }

  Future<Map<String, Object?>> creditsBalance(String orgId) async {
    return <String, Object?>{
      'org_id': orgId,
      'currency': 'NGN',
      'balance_minor': await _creditsBalance(orgId: orgId),
    };
  }

  Future<List<Map<String, Object?>>> creditsLedger(String orgId) async {
    return List<Map<String, Object?>>.from(
      _creditLedgerByOrg[orgId] ?? const <Map<String, Object?>>[],
    );
  }

  Future<void> grantCredits({
    required String orgId,
    required int amountMinor,
    required String reason,
  }) async {
    if (amountMinor <= 0) {
      throw const MarketplaceRevenueException(
        code: 'VALIDATION_ERROR',
        message: 'amount_minor must be greater than zero',
      );
    }
    final current = await _creditsBalance(orgId: orgId);
    _creditsByOrg[orgId] = current + amountMinor;
    _creditLedgerByOrg.putIfAbsent(orgId, () => <Map<String, Object?>>[]).add(
      <String, Object?>{
        'id': _uuid.v4(),
        'org_id': orgId,
        'entry_type': 'manual_grant',
        'amount_minor': amountMinor,
        'currency': 'NGN',
        'related_type': 'admin',
        'related_id': reason,
        'created_at': _nowUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, Object?>> riskState({
    required String subjectType,
    required String subjectId,
  }) async {
    final key = '$subjectType::$subjectId';
    final row =
        _riskBySubject[key] ??
        <String, Object?>{
          'subject_type': subjectType,
          'subject_id': subjectId,
          'score_total': 0,
          'state': 'ok',
          'updated_at': _nowUtc().toIso8601String(),
        };
    return row;
  }

  Future<void> recordRiskEvent({
    required String subjectType,
    required String subjectId,
    required String eventType,
    required int scoreDelta,
  }) async {
    final key = '$subjectType::$subjectId';
    final existing = await riskState(subjectType: subjectType, subjectId: subjectId);
    final score = (existing['score_total'] as int? ?? 0) + scoreDelta;
    final state = _riskStateForScore(score);
    _riskBySubject[key] = <String, Object?>{
      'subject_type': subjectType,
      'subject_id': subjectId,
      'score_total': score,
      'state': state,
      'updated_at': _nowUtc().toIso8601String(),
    };
    _metrics?.recordRiskState(state: state);
    _logSink(jsonEncode(<String, Object?>{
      'event': 'risk_scored',
      'subject_type': subjectType,
      'subject_id': subjectId,
      'event_type': eventType,
      'score_delta': scoreDelta,
      'score_total': score,
      'state': state,
    }));
  }

  Future<void> assertMutationAllowed({
    required String userId,
    required String orgId,
    required String action,
  }) async {
    if (action.trim().toLowerCase().startsWith('read_')) {
      return;
    }
    final userRisk = await riskState(subjectType: 'user', subjectId: userId);
    final orgRisk = await riskState(subjectType: 'org', subjectId: orgId);
    final state = _dominantState(
      (userRisk['state'] ?? '').toString(),
      (orgRisk['state'] ?? '').toString(),
    );
    if (state == 'suspended' || state == 'restricted') {
      throw const MarketplaceRevenueException(
        code: 'RISK_LOCKED',
        message: 'Blocked by risk policy',
        statusCode: 403,
      );
    }
    if (state == 'flagged' &&
        <String>{'change_plan', 'update_seats', 'add_addon'}.contains(action)) {
      throw const MarketplaceRevenueException(
        code: 'RISK_LOCKED',
        message: 'Action requires manual review',
        statusCode: 403,
      );
    }
  }

  Future<Map<String, Object?>> enqueueComms({
    required String channel,
    required String recipient,
    required String templateId,
    required Map<String, Object?> payload,
    required String dedupeKey,
  }) async {
    final normalized = dedupeKey.trim();
    if (_commsDedupe.contains(normalized)) {
      return <String, Object?>{'deduped': true, 'dedupe_key': normalized};
    }
    _commsDedupe.add(normalized);
    final row = <String, Object?>{
      'id': _uuid.v4(),
      'channel': channel,
      'recipient': recipient,
      'template_id': templateId,
      'payload_json': payload,
      'status': 'queued',
      'attempts': 0,
      'next_retry_at': _nowUtc().toIso8601String(),
      'dedupe_key': normalized,
      'created_at': _nowUtc().toIso8601String(),
      'updated_at': _nowUtc().toIso8601String(),
    };
    _commsOutbox.add(row);
    return row;
  }

  Future<List<Map<String, Object?>>> runCommsSender({int limit = 50}) async {
    final results = <Map<String, Object?>>[];
    for (final row in _commsOutbox) {
      if (results.length >= limit) {
        break;
      }
      if ((row['status'] ?? '') != 'queued' && (row['status'] ?? '') != 'failed') {
        continue;
      }
      row['status'] = 'sent';
      row['attempts'] = (row['attempts'] as int? ?? 0) + 1;
      row['updated_at'] = _nowUtc().toIso8601String();
      _metrics?.recordCommsSent(
        channel: (row['channel'] ?? '').toString(),
        template: (row['template_id'] ?? '').toString(),
      );
      results.add(row);
    }
    return results;
  }

  Future<List<Map<String, Object?>>> runDunningRunner({int limit = 50}) async {
    final now = _nowUtc();
    final due = _dunningCases.values
        .where(
          (row) =>
              (row['state'] ?? '') == 'active' &&
              (() {
                final next = (row['next_attempt_at'] ?? '').toString();
                if (next.isEmpty) {
                  return true;
                }
                final parsed = DateTime.tryParse(next)?.toUtc();
                if (parsed == null) {
                  return true;
                }
                return !parsed.isAfter(now);
              })(),
        )
        .take(limit)
        .toList(growable: false);
    final results = <Map<String, Object?>>[];
    for (final row in due) {
      final orgId = (row['org_id'] ?? '').toString();
      final invoiceId = (row['invoice_id'] ?? '').toString();
      if (orgId.isEmpty || invoiceId.isEmpty) {
        continue;
      }
      final retried = await retryInvoice(orgId: orgId, invoiceId: invoiceId);
      results.add(retried);
    }
    return results;
  }

  Future<Map<String, Object?>> billingOverview(String orgId) async {
    return <String, Object?>{
      'org_id': orgId,
      'invoices': await listInvoices(orgId),
      'dunning_cases': _dunningCases.values
          .where((row) => (row['org_id'] ?? '').toString() == orgId)
          .toList(growable: false),
      'risk_state': await riskState(subjectType: 'org', subjectId: orgId),
      'credits_balance': await creditsBalance(orgId),
      'credits_ledger': await creditsLedger(orgId),
    };
  }

  Future<Map<String, Object?>> auditSummary(String orgId) async {
    final overview = await billingOverview(orgId);
    final comms = _commsOutbox
        .where((row) => (row['dedupe_key'] ?? '').toString().startsWith('$orgId:'))
        .toList(growable: false);
    return <String, Object?>{...overview, 'comms_outbox': comms};
  }

  Future<void> adjustRisk({
    required String subjectType,
    required String subjectId,
    required int delta,
    required String reason,
  }) {
    return recordRiskEvent(
      subjectType: subjectType,
      subjectId: subjectId,
      eventType: reason,
      scoreDelta: delta,
    );
  }

  Future<void> pauseDunningCase(String caseId) async {
    final row = _dunningCases[caseId];
    if (row == null) {
      return;
    }
    row['state'] = 'paused';
    row['next_attempt_at'] = null;
  }

  Future<void> resumeDunningCase(String caseId) async {
    final row = _dunningCases[caseId];
    if (row == null) {
      return;
    }
    row['state'] = 'active';
    row['next_attempt_at'] = _nowUtc().toIso8601String();
  }

  Future<void> writeoffDunningCase(String caseId) async {
    final row = _dunningCases[caseId];
    if (row == null) {
      return;
    }
    row['state'] = 'written_off';
    row['next_attempt_at'] = null;
    row['last_error'] = 'written_off_by_admin';
  }

  Future<int> _offerBaseMinor(String offerId) async {
    if (_postgresProvider != null) {
      final rows = await _postgresProvider.withConnection(
        (connection) => connection.query(
          'SELECT price_minor FROM marketplace_offers WHERE id = @id LIMIT 1',
          substitutionValues: <String, Object?>{'id': offerId},
        ),
      );
      if (rows.isNotEmpty) {
        return (rows.first[0] as num?)?.toInt() ?? 0;
      }
    }
    return _seedOfferPrices[offerId] ?? 0;
  }

  Future<String> _offerCurrency(String offerId) async {
    if (_postgresProvider != null) {
      final rows = await _postgresProvider.withConnection(
        (connection) => connection.query(
          'SELECT currency FROM marketplace_offers WHERE id = @id LIMIT 1',
          substitutionValues: <String, Object?>{'id': offerId},
        ),
      );
      if (rows.isNotEmpty) {
        return (rows.first[0] as String?)?.trim().isNotEmpty == true
            ? (rows.first[0] as String).trim()
            : 'NGN';
      }
    }
    return 'NGN';
  }

  int _discountFromCoupon({required int baseMinor, required String? couponCode}) {
    if (couponCode == null || couponCode.isEmpty) {
      return 0;
    }
    final coupon = _seedCoupons[couponCode];
    if (coupon == null) {
      return 0;
    }
    if (coupon.type == 'fixed') {
      return coupon.valueMinor > baseMinor ? baseMinor : coupon.valueMinor;
    }
    if (coupon.type == 'percent') {
      return ((baseMinor * coupon.percentValue) / 100).round();
    }
    return 0;
  }

  int _discountFromReferral({
    required int baseMinor,
    required String? referralCode,
  }) {
    if (referralCode == null || referralCode.isEmpty) {
      return 0;
    }
    final referral = _seedReferrals[referralCode];
    if (referral == null) {
      return 0;
    }
    if (referral.rewardKind == 'discount_percent') {
      return ((baseMinor * referral.rewardPercent) / 100).round();
    }
    final fixed = referral.rewardValueMinor;
    return fixed > baseMinor ? baseMinor : fixed;
  }

  Future<int> _creditsBalance({required String orgId}) async {
    return _creditsByOrg[orgId] ?? 0;
  }

  Future<void> _debitCredits({
    required String orgId,
    required int amountMinor,
    required String relatedType,
    required String relatedId,
  }) async {
    if (amountMinor <= 0) {
      return;
    }
    final current = await _creditsBalance(orgId: orgId);
    final next = current - amountMinor;
    if (next < 0) {
      throw const MarketplaceRevenueException(
        code: 'INSUFFICIENT_CREDITS',
        message: 'Credits cannot go negative',
        statusCode: 409,
      );
    }
    _creditsByOrg[orgId] = next;
    _metrics?.recordCreditsApplied(amountMinor: amountMinor);
    _creditLedgerByOrg.putIfAbsent(orgId, () => <Map<String, Object?>>[]).add(
      <String, Object?>{
        'id': _uuid.v4(),
        'org_id': orgId,
        'entry_type': 'credits_applied',
        'amount_minor': -amountMinor,
        'currency': 'NGN',
        'related_type': relatedType,
        'related_id': relatedId,
        'created_at': _nowUtc().toIso8601String(),
      },
    );
  }

  Duration _dunningDelayForAttempt(int attemptNo) {
    if (attemptNo <= 1) {
      return const Duration(hours: 0);
    }
    if (attemptNo == 2) {
      return const Duration(hours: 6);
    }
    if (attemptNo == 3) {
      return const Duration(hours: 24);
    }
    return const Duration(hours: 72);
  }

  String _riskStateForScore(int score) {
    if (score >= 100) {
      return 'suspended';
    }
    if (score >= 70) {
      return 'restricted';
    }
    if (score >= 50) {
      return 'flagged';
    }
    return 'ok';
  }

  String _dominantState(String userState, String orgState) {
    const rank = <String, int>{
      'ok': 0,
      'flagged': 1,
      'restricted': 2,
      'suspended': 3,
    };
    final userRank = rank[userState] ?? 0;
    final orgRank = rank[orgState] ?? 0;
    return userRank >= orgRank ? userState : orgState;
  }
}

class _Coupon {
  const _Coupon({
    required this.id,
    required this.type,
    required this.percentValue,
    required this.valueMinor,
    required this.validFrom,
    required this.validUntil,
    this.maxUses,
  });

  final String id;
  final String type;
  final int percentValue;
  final int valueMinor;
  final DateTime validFrom;
  final DateTime validUntil;
  final int? maxUses;
}

class _Referral {
  const _Referral({
    required this.code,
    required this.ownerId,
    required this.rewardKind,
    required this.rewardValueMinor,
    required this.rewardPercent,
  });

  final String code;
  final String ownerId;
  final String rewardKind;
  final int rewardValueMinor;
  final int rewardPercent;
}

final Map<String, int> _seedOfferPrices = <String, int>{
  'offer_sedan_01': 4200,
  'offer_suv_02': 5900,
  'offer_van_03': 7100,
};

final Map<String, _Coupon> _seedCoupons = <String, _Coupon>{
  'LAUNCH50': _Coupon(
    id: 'LAUNCH50',
    type: 'percent',
    percentValue: 50,
    valueMinor: 0,
    validFrom: DateTime.utc(2025, 1, 1),
    validUntil: DateTime.utc(2030, 1, 1),
    maxUses: 1000,
  ),
  'WELCOME1000': _Coupon(
    id: 'WELCOME1000',
    type: 'fixed',
    percentValue: 0,
    valueMinor: 1000,
    validFrom: DateTime.utc(2025, 1, 1),
    validUntil: DateTime.utc(2030, 1, 1),
    maxUses: 1000,
  ),
  'EXPIRED1': _Coupon(
    id: 'EXPIRED1',
    type: 'fixed',
    percentValue: 0,
    valueMinor: 1,
    validFrom: DateTime.utc(2020, 1, 1),
    validUntil: DateTime.utc(2021, 1, 1),
    maxUses: 1000,
  ),
  'LIMIT1': _Coupon(
    id: 'LIMIT1',
    type: 'fixed',
    percentValue: 0,
    valueMinor: 100,
    validFrom: DateTime.utc(2025, 1, 1),
    validUntil: DateTime.utc(2030, 1, 1),
    maxUses: 1,
  ),
};

final Map<String, _Referral> _seedReferrals = <String, _Referral>{
  'FRIEND100': const _Referral(
    code: 'FRIEND100',
    ownerId: 'ref-owner-1',
    rewardKind: 'discount_fixed',
    rewardValueMinor: 100,
    rewardPercent: 0,
  ),
};
