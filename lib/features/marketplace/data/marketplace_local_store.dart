import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MarketplaceLocalStore {
  const MarketplaceLocalStore();

  Future<String?> readCheckoutIdempotencyKey(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_signatureToIdempotencyKey(signature));
  }

  Future<void> writeCheckoutIdempotencyKey({
    required String signature,
    required String idempotencyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _signatureToIdempotencyKey(signature),
      idempotencyKey,
    );
  }

  Future<String?> readPendingCheckoutKeyForOffer(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingCheckoutKeyForOffer(offerId));
  }

  Future<void> writePendingCheckoutKeyForOffer({
    required String offerId,
    required String idempotencyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingCheckoutKeyForOffer(offerId), idempotencyKey);
  }

  Future<void> clearPendingCheckoutKeyForOffer(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingCheckoutKeyForOffer(offerId));
  }

  Future<String?> readPurchaseIdByIdempotencyKey(String idempotencyKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_idempotencyKeyToPurchase(idempotencyKey));
  }

  Future<void> writePurchaseIdByIdempotencyKey({
    required String idempotencyKey,
    required String purchaseId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _idempotencyKeyToPurchase(idempotencyKey),
      purchaseId,
    );
  }

  String _signatureToIdempotencyKey(String signature) {
    return 'marketplace.checkout.signature.${_digest(signature)}';
  }

  String _pendingCheckoutKeyForOffer(String offerId) {
    return 'marketplace.checkout.pending.${_digest(offerId)}';
  }

  String _idempotencyKeyToPurchase(String idempotencyKey) {
    return 'marketplace.checkout.purchase.${_digest(idempotencyKey)}';
  }

  String _digest(String value) {
    return sha1.convert(utf8.encode(value)).toString();
  }
}
