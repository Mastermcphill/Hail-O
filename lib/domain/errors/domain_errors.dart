class DomainError implements Exception {
  const DomainError(this.code, {this.message, this.metadata = const {}});

  final String code;
  final String? message;
  final Map<String, Object?> metadata;

  @override
  String toString() => 'DomainError($code)';
}

class LifecycleViolationError extends DomainError {
  const LifecycleViolationError({
    required String code,
    String? message,
    Map<String, Object?> metadata = const {},
  }) : super(code, message: message, metadata: metadata);
}

class DomainInvariantError extends DomainError {
  const DomainInvariantError({
    required String code,
    String? message,
    Map<String, Object?> metadata = const {},
  }) : super(code, message: message, metadata: metadata);
}

class InsufficientFundsError extends DomainError {
  const InsufficientFundsError({
    required String code,
    String? message,
    Map<String, Object?> metadata = const {},
  }) : super(code, message: message, metadata: metadata);
}

class UnauthorizedActionError extends DomainError {
  const UnauthorizedActionError({
    required String code,
    String? message,
    Map<String, Object?> metadata = const {},
  }) : super(code, message: message, metadata: metadata);
}
