abstract class OtpProvider {
  String get providerName;

  Future<void> sendOtp({
    required String phoneE164,
    required String code,
    required Duration ttl,
  });
}
