import 'dart:convert';

import 'package:crypto/crypto.dart';

enum SimStepType {
  bookRide,
  acceptRide,
  acceptRideAltDriver,
  startRide,
  completeRide,
  cancelRide,
  settleRide,
  openDispute,
  resolveDispute,
  reverseLatestCredit,
}

extension SimStepTypeCode on SimStepType {
  String get code {
    switch (this) {
      case SimStepType.bookRide:
        return 'book';
      case SimStepType.acceptRide:
        return 'accept';
      case SimStepType.acceptRideAltDriver:
        return 'accept_alt_driver';
      case SimStepType.startRide:
        return 'start';
      case SimStepType.completeRide:
        return 'complete';
      case SimStepType.cancelRide:
        return 'cancel';
      case SimStepType.settleRide:
        return 'settle';
      case SimStepType.openDispute:
        return 'dispute_open';
      case SimStepType.resolveDispute:
        return 'dispute_resolve';
      case SimStepType.reverseLatestCredit:
        return 'reverse_credit';
    }
  }
}

class SeededRng {
  SeededRng(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int maxExclusive) {
    if (maxExclusive <= 0) {
      throw ArgumentError('maxExclusive must be > 0');
    }
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state % maxExclusive;
  }

  bool chancePercent(int percent) {
    if (percent <= 0) {
      return false;
    }
    if (percent >= 100) {
      return true;
    }
    return nextInt(100) < percent;
  }
}

class SimEntityIds {
  const SimEntityIds({
    required this.rideId,
    required this.riderId,
    required this.driverId,
    required this.altDriverId,
    required this.adminId,
    required this.escrowId,
    required this.disputeId,
  });

  final String rideId;
  final String riderId;
  final String driverId;
  final String altDriverId;
  final String adminId;
  final String escrowId;
  final String disputeId;
}

class SimScenarioConfig {
  const SimScenarioConfig({
    required this.seed,
    required this.scenarioId,
    required this.stepCount,
    required this.entityIds,
  });

  final int seed;
  final String scenarioId;
  final int stepCount;
  final SimEntityIds entityIds;
}

class SimMutableState {
  bool booked = false;
  bool accepted = false;
  bool started = false;
  bool completed = false;
  bool cancelled = false;
  bool settled = false;
  bool disputeOpened = false;
  bool disputeResolved = false;
  bool reversalApplied = false;
}

class SimStepResult {
  const SimStepResult({
    required this.stepIndex,
    required this.stepType,
    required this.ok,
    required this.response,
    this.errorType,
    this.errorCode,
  });

  final int stepIndex;
  final SimStepType stepType;
  final bool ok;
  final Map<String, Object?> response;
  final String? errorType;
  final String? errorCode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'step_index': stepIndex,
      'step_type': stepType.code,
      'ok': ok,
      'response': response,
      'error_type': errorType,
      'error_code': errorCode,
    };
  }
}

class SimScenarioResult {
  const SimScenarioResult({
    required this.ok,
    required this.seed,
    required this.scenarioId,
    required this.stepResults,
    this.errorType,
    this.errorCode,
    this.reportJson,
  });

  final bool ok;
  final int seed;
  final String scenarioId;
  final List<SimStepResult> stepResults;
  final String? errorType;
  final String? errorCode;
  final String? reportJson;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ok': ok,
      'seed': seed,
      'scenario_id': scenarioId,
      'error_type': errorType,
      'error_code': errorCode,
      'step_results': stepResults.map((result) => result.toMap()).toList(),
      'report_json': reportJson,
    };
  }

  String deterministicDigest() {
    return sha256.convert(utf8.encode(jsonEncode(toMap()))).toString();
  }
}

class SimClock {
  SimClock(DateTime initialUtc) : _now = initialUtc.toUtc();

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration by) {
    _now = _now.add(by);
  }
}

String buildSimIdempotencyKey({
  required int seed,
  required String scenarioId,
  required int stepIndex,
  required SimStepType stepType,
  required SimEntityIds entityIds,
}) {
  return 'sim:$seed:$scenarioId:$stepIndex:${stepType.code}:${entityIds.rideId}:${entityIds.escrowId}';
}
