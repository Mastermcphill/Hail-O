class RideLifecycleViolation implements Exception {
  const RideLifecycleViolation(this.code, this.status);

  final String code;
  final String status;

  @override
  String toString() => 'RideLifecycleViolation($code, status=$status)';
}

class RideLifecycleGuardService {
  const RideLifecycleGuardService();

  static const Set<String> _cancellableStatuses = <String>{
    'pending',
    'accepted',
    'awaiting_connection_fee',
    'connection_fee_paid',
    'in_progress',
  };

  static const Set<String> _settleFinanceStatuses = <String>{
    'connection_fee_paid',
    'in_progress',
    'arrived',
    'completed',
    'finance_settled',
  };

  bool isAlreadyCancelled(String statusRaw) {
    return _normalized(statusRaw) == 'cancelled';
  }

  bool isAlreadyFinanceSettled(String statusRaw) {
    return _normalized(statusRaw) == 'finance_settled';
  }

  void assertCanCancel(String statusRaw) {
    final status = _normalized(statusRaw);
    if (_cancellableStatuses.contains(status)) {
      return;
    }
    if (status == 'cancelled') {
      throw const RideLifecycleViolation('ride_already_cancelled', 'cancelled');
    }
    throw RideLifecycleViolation('cancel_not_allowed_from_status', status);
  }

  void assertCanMarkConnectionFeePaid(String statusRaw) {
    final status = _normalized(statusRaw);
    if (status == 'awaiting_connection_fee') {
      return;
    }
    if (status == 'connection_fee_paid') {
      throw const RideLifecycleViolation(
        'connection_fee_already_paid',
        'connection_fee_paid',
      );
    }
    if (status == 'cancelled') {
      throw const RideLifecycleViolation('ride_cancelled', 'cancelled');
    }
    throw RideLifecycleViolation(
      'connection_fee_payment_not_allowed_from_status',
      status,
    );
  }

  void assertCanSettleFinance(String statusRaw) {
    final status = _normalized(statusRaw);
    if (_settleFinanceStatuses.contains(status)) {
      return;
    }
    if (status == 'cancelled') {
      throw const RideLifecycleViolation('ride_cancelled', 'cancelled');
    }
    throw RideLifecycleViolation(
      'finance_settlement_not_allowed_from_status',
      status,
    );
  }

  String _normalized(String statusRaw) => statusRaw.trim().toLowerCase();
}
