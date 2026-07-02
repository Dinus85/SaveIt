import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// ID abbonamento App Store Connect / Play Console.
const kSaveInPremiumProductId = 'savein_premium_monthly';

enum BillingErrorCode {
  storeNotAvailable,
  productNotFound,
  purchaseCancelled,
  purchasePending,
  purchaseFailed,
  verificationFailed,
  platformNotSupported,
}

class BillingException implements Exception {
  final BillingErrorCode code;
  final String message;

  const BillingException(this.code, this.message);

  @override
  String toString() => 'BillingException(${code.name}): $message';
}

class BillingVerifyResult {
  final DateTime premiumUntil;
  final bool autoRenew;
  final String productId;
  final String? originalTransactionId;

  const BillingVerifyResult({
    required this.premiumUntil,
    required this.autoRenew,
    required this.productId,
    this.originalTransactionId,
  });
}

class BillingService {
  BillingService._();

  static final InAppPurchase _iap = InAppPurchase.instance;
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<bool> isAvailable() async {
    if (!isSupportedPlatform) return false;
    return _iap.isAvailable();
  }

  static Future<ProductDetails?> loadProduct() async {
    if (!await isAvailable()) return null;

    final response = await _iap.queryProductDetails({kSaveInPremiumProductId});
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        '[BillingService] Prodotto non trovato: ${response.notFoundIDs}',
      );
    }
    if (response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  static Future<BillingVerifyResult> purchaseAndVerify(
    ProductDetails product,
  ) async {
    if (!await isAvailable()) {
      throw const BillingException(
        BillingErrorCode.storeNotAvailable,
        'Gli acquisti in-app non sono disponibili su questo dispositivo.',
      );
    }

    final completer = Completer<BillingVerifyResult>();
    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID != kSaveInPremiumProductId) continue;
          if (completer.isCompleted) continue;

          if (purchase.status == PurchaseStatus.canceled) {
            await sub.cancel();
            completer.completeError(
              const BillingException(
                BillingErrorCode.purchaseCancelled,
                'Acquisto annullato.',
              ),
            );
            return;
          }

          if (purchase.status == PurchaseStatus.error) {
            await sub.cancel();
            completer.completeError(
              BillingException(
                BillingErrorCode.purchaseFailed,
                purchase.error?.message ?? 'Errore durante il pagamento.',
              ),
            );
            return;
          }

          if (purchase.status == PurchaseStatus.pending) {
            continue;
          }

          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            try {
              final result = await _verifyPurchase(purchase);
              if (purchase.pendingCompletePurchase) {
                await _iap.completePurchase(purchase);
              }
              await sub.cancel();
              completer.complete(result);
            } catch (e) {
              await sub.cancel();
              completer.completeError(e);
            }
            return;
          }
        }
      },
      onError: (dynamic err) {
        if (!completer.isCompleted) {
          sub.cancel();
          completer.completeError(
            BillingException(
              BillingErrorCode.purchaseFailed,
              err.toString(),
            ),
          );
        }
      },
    );

    final purchaseParam = PurchaseParam(productDetails: product);
    final initiated = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!initiated) {
      await sub.cancel();
      throw const BillingException(
        BillingErrorCode.purchaseFailed,
        'Impossibile avviare la schermata di acquisto.',
      );
    }

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        sub.cancel();
        throw const BillingException(
          BillingErrorCode.purchaseFailed,
          'Timeout durante l\'acquisto. Riprova.',
        );
      },
    );
  }

  static Future<BillingVerifyResult?> restorePurchases() async {
    if (!await isAvailable()) {
      throw const BillingException(
        BillingErrorCode.storeNotAvailable,
        'Ripristino acquisti non disponibile su questo dispositivo.',
      );
    }

    BillingVerifyResult? restored;
    late StreamSubscription<List<PurchaseDetails>> sub;
    final completer = Completer<void>();

    sub = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID != kSaveInPremiumProductId) continue;
          if (purchase.status != PurchaseStatus.purchased &&
              purchase.status != PurchaseStatus.restored) {
            continue;
          }
          try {
            restored = await _verifyPurchase(purchase);
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
          } catch (e) {
            debugPrint('[BillingService] restore verify failed: $e');
          }
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );

    await _iap.restorePurchases();
    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
    await sub.cancel();
    return restored;
  }

  static Future<BillingVerifyResult> _verifyPurchase(
    PurchaseDetails purchase,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _verifyWithAppStore(purchase);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _verifyWithGooglePlay(purchase);
    }
    throw const BillingException(
      BillingErrorCode.platformNotSupported,
      'Piattaforma non supportata per gli acquisti in-app.',
    );
  }

  static Future<BillingVerifyResult> _verifyWithAppStore(
    PurchaseDetails purchase,
  ) async {
    final transactionId = _extractTransactionId(purchase);
    if (transactionId == null || transactionId.isEmpty) {
      throw const BillingException(
        BillingErrorCode.verificationFailed,
        'Transazione App Store non valida.',
      );
    }

    try {
      final callable = _functions.httpsCallable('verifyAppStorePurchase');
      final response = await callable.call<Map<String, dynamic>>({
        'transactionId': transactionId,
      });
      final data = Map<String, dynamic>.from(response.data);
      final premiumUntilRaw = data['premiumUntil']?.toString();
      if (premiumUntilRaw == null || premiumUntilRaw.isEmpty) {
        throw const BillingException(
          BillingErrorCode.verificationFailed,
          'Risposta verifica Premium non valida.',
        );
      }
      return BillingVerifyResult(
        premiumUntil: DateTime.parse(premiumUntilRaw).toLocal(),
        autoRenew: (data['autoRenew'] as bool?) ?? true,
        productId: (data['productId'] as String?) ?? kSaveInPremiumProductId,
        originalTransactionId: data['originalTransactionId']?.toString(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw BillingException(
        BillingErrorCode.verificationFailed,
        e.message ?? 'Verifica acquisto App Store fallita.',
      );
    } catch (e) {
      if (e is BillingException) rethrow;
      throw BillingException(
        BillingErrorCode.verificationFailed,
        'Errore durante la verifica: $e',
      );
    }
  }

  static Future<BillingVerifyResult> _verifyWithGooglePlay(
    PurchaseDetails purchase,
  ) async {
    final purchaseToken = _extractGooglePurchaseToken(purchase);
    if (purchaseToken == null || purchaseToken.isEmpty) {
      throw const BillingException(
        BillingErrorCode.verificationFailed,
        'Token acquisto Google Play non valido.',
      );
    }

    try {
      final callable = _functions.httpsCallable('verifyGooglePlayPurchase');
      final response = await callable.call<Map<String, dynamic>>({
        'purchaseToken': purchaseToken,
        'productId': purchase.productID,
      });
      final data = Map<String, dynamic>.from(response.data);
      final premiumUntilRaw = data['premiumUntil']?.toString();
      if (premiumUntilRaw == null || premiumUntilRaw.isEmpty) {
        throw const BillingException(
          BillingErrorCode.verificationFailed,
          'Risposta verifica Premium Google Play non valida.',
        );
      }
      return BillingVerifyResult(
        premiumUntil: DateTime.parse(premiumUntilRaw).toLocal(),
        autoRenew: (data['autoRenew'] as bool?) ?? true,
        productId: (data['productId'] as String?) ?? kSaveInPremiumProductId,
        originalTransactionId: data['state']?.toString(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw BillingException(
        BillingErrorCode.verificationFailed,
        e.message ?? 'Verifica acquisto Google Play fallita.',
      );
    } catch (e) {
      if (e is BillingException) rethrow;
      throw BillingException(
        BillingErrorCode.verificationFailed,
        'Errore durante la verifica Google Play: $e',
      );
    }
  }

  static String? _extractTransactionId(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) {
      return purchaseId;
    }

    final localData = purchase.verificationData.localVerificationData.trim();
    if (localData.isEmpty) return null;

    try {
      final decoded = jsonDecode(localData);
      if (decoded is Map<String, dynamic>) {
        for (final key in ['transactionId', 'originalTransactionId', 'transaction_id']) {
          final value = decoded[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      return localData;
    }
    return null;
  }

  static String? _extractGooglePurchaseToken(PurchaseDetails purchase) {
    final serverData = purchase.verificationData.serverVerificationData.trim();
    if (serverData.isNotEmpty) return serverData;

    final localData = purchase.verificationData.localVerificationData.trim();
    if (localData.isEmpty) return null;

    try {
      final decoded = jsonDecode(localData);
      if (decoded is Map<String, dynamic>) {
        for (final key in ['purchaseToken', 'token']) {
          final value = decoded[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      return localData;
    }
    return null;
  }
}
