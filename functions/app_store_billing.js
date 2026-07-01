const fs = require("fs");
const path = require("path");
const {
  AppStoreServerAPIClient,
  AutoRenewStatus,
  Environment,
  NotificationTypeV2,
  SignedDataVerifier,
} = require("@apple/app-store-server-library");

const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

const APPLE_SUBSCRIPTION_EVENTS = "apple_subscription_events";

const ACTIVE_NOTIFICATION_TYPES = new Set([
  NotificationTypeV2.SUBSCRIBED,
  NotificationTypeV2.DID_RENEW,
  NotificationTypeV2.OFFER_REDEEMED,
  NotificationTypeV2.RENEWAL_EXTENDED,
  NotificationTypeV2.REFUND_REVERSED,
]);

const INACTIVE_NOTIFICATION_TYPES = new Set([
  NotificationTypeV2.EXPIRED,
  NotificationTypeV2.GRACE_PERIOD_EXPIRED,
  NotificationTypeV2.REFUND,
  NotificationTypeV2.REVOKE,
]);

let db;
let admin;
let onCall;
let onRequest;
let HttpsError;
let writeAccountHistory;

const readConfig = () => {
  const bundleId = (process.env.APP_STORE_BUNDLE_ID || "eu.savein.app").trim();
  const appAppleIdRaw = (process.env.APP_STORE_APP_APPLE_ID || "6785451010").trim();
  const appAppleId = Number.parseInt(appAppleIdRaw, 10);
  const environmentName = (process.env.APP_STORE_ENVIRONMENT || "Production").trim();
  const environment = environmentName.toLowerCase() === "sandbox" ?
    Environment.SANDBOX :
    Environment.PRODUCTION;
  const productIds = (process.env.APP_STORE_SUBSCRIPTION_PRODUCT_IDS ||
    process.env.APP_STORE_SUBSCRIPTION_PRODUCT_ID ||
    "savein_premium_monthly")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
  const issuerId = (process.env.APPLE_ISSUER_ID || "").trim();
  const keyId = (process.env.APPLE_KEY_ID || "").trim();
  const privateKey = normalizePrivateKey(process.env.APPLE_PRIVATE_KEY || "");
  const webhookSecret = (process.env.APP_STORE_WEBHOOK_SECRET || "").trim();

  return {
    bundleId,
    appAppleId: Number.isFinite(appAppleId) ? appAppleId : undefined,
    environment,
    environmentName,
    productIds: new Set(productIds),
    issuerId,
    keyId,
    privateKey,
    webhookSecret,
  };
};

const normalizePrivateKey = (value) => {
  const trimmed = (value || "").toString().trim();
  if (!trimmed) return "";
  if (trimmed.includes("BEGIN PRIVATE KEY")) {
    return trimmed.replace(/\\n/g, "\n");
  }
  try {
    return Buffer.from(trimmed, "base64").toString("utf8").replace(/\\n/g, "\n");
  } catch (_) {
    return trimmed.replace(/\\n/g, "\n");
  }
};

const loadAppleRootCertificates = () => {
  const candidates = [
    path.join(__dirname, "certs", "AppleRootCA-G3.cer"),
    path.join(__dirname, "certs", "AppleIncRootCertificate.cer"),
  ];
  const buffers = candidates
      .filter((filePath) => fs.existsSync(filePath))
      .map((filePath) => fs.readFileSync(filePath));
  if (buffers.length === 0) {
    buffers.push(Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64"));
  }
  return buffers;
};

let cachedProductionVerifier;
let cachedSandboxVerifier;

const getVerifier = (environment) => {
  const config = readConfig();
  const cacheKey = environment === Environment.SANDBOX ? "sandbox" : "production";
  if (cacheKey === "sandbox") {
    if (!cachedSandboxVerifier) {
      cachedSandboxVerifier = new SignedDataVerifier(
          loadAppleRootCertificates(),
          true,
          Environment.SANDBOX,
          config.bundleId,
      );
    }
    return cachedSandboxVerifier;
  }

  if (!cachedProductionVerifier) {
    cachedProductionVerifier = new SignedDataVerifier(
        loadAppleRootCertificates(),
        true,
        Environment.PRODUCTION,
        config.bundleId,
        config.appAppleId,
    );
  }
  return cachedProductionVerifier;
};

const getApiClient = (environment) => {
  const config = readConfig();
  if (!config.privateKey || !config.keyId || !config.issuerId) {
    throw new Error(
        "Configurazione App Store API mancante: APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY.",
    );
  }
  return new AppStoreServerAPIClient(
      config.privateKey,
      config.keyId,
      config.issuerId,
      config.bundleId,
      environment,
  );
};

const msToDate = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return null;
  return new Date(numeric);
};

const findUidByOriginalTransactionId = async (originalTransactionId) => {
  if (!originalTransactionId) return null;
  const snapshot = await db.collection("users")
      .where("appleSubscription.originalTransactionId", "==", originalTransactionId)
      .limit(1)
      .get();
  if (snapshot.empty) return null;
  return snapshot.docs[0].id;
};

const findUidByAppAccountToken = async (appAccountToken) => {
  if (!appAccountToken) return null;
  const snapshot = await db.collection("users")
      .where("appleSubscription.appAccountToken", "==", appAccountToken)
      .limit(1)
      .get();
  if (snapshot.empty) return null;
  return snapshot.docs[0].id;
};

const getUserData = async (uid) => {
  const snap = await db.collection("users").doc(uid).get();
  return snap.exists ? snap.data() : null;
};

const isAdminUser = (userData) =>
  (userData?.role || "").toString().toLowerCase() === "admin";

const shouldManagePremiumFromApple = (userData) => {
  if (isAdminUser(userData)) return false;
  const source = (userData?.premiumSource || "").toString().toLowerCase();
  if (source === "app_store") return true;
  if (userData?.appleSubscription?.originalTransactionId) return true;
  return false;
};

const buildAppleSubscriptionPatch = ({
  originalTransactionId,
  productId,
  transactionId,
  autoRenew,
  environment,
  appAccountToken,
  status,
}) => ({
  originalTransactionId: originalTransactionId || null,
  productId: productId || null,
  transactionId: transactionId || null,
  autoRenew: autoRenew !== false,
  environment: environment || null,
  appAccountToken: appAccountToken || null,
  status: status || null,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
});

const applyPremiumActive = async ({
  uid,
  expiresDate,
  originalTransactionId,
  productId,
  transactionId,
  autoRenew,
  environment,
  appAccountToken,
  notificationType,
  source = "app_store_webhook",
}) => {
  if (!uid) return {applied: false, reason: "missing_uid"};
  const userData = await getUserData(uid);
  if (!userData) return {applied: false, reason: "user_not_found"};

  const beforeRole = userData.role || "free";
  const beforePremiumUntil = userData.premiumUntil || null;
  const patch = {
    appleSubscription: buildAppleSubscriptionPatch({
      originalTransactionId,
      productId,
      transactionId,
      autoRenew,
      environment,
      appAccountToken,
      status: notificationType || "active",
    }),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!isAdminUser(userData)) {
    patch.role = "premium";
    patch.premiumSource = "app_store";
    if (expiresDate) {
      patch.premiumUntil = admin.firestore.Timestamp.fromDate(expiresDate);
    }
  }

  await db.collection("users").doc(uid).set(patch, {merge: true});
  await writeAccountHistory({
    userId: uid,
    type: "premium_app_store_active",
    title: "Premium attivato/rinnovato da App Store",
    source,
    before: {
      role: beforeRole,
      premiumUntil: beforePremiumUntil,
    },
    after: {
      role: patch.role || beforeRole,
      premiumUntil: expiresDate ? expiresDate.toISOString() : null,
      originalTransactionId,
      autoRenew,
    },
  });

  return {applied: true, uid};
};

const applyPremiumInactive = async ({
  uid,
  originalTransactionId,
  productId,
  transactionId,
  autoRenew = false,
  environment,
  notificationType,
  source = "app_store_webhook",
}) => {
  if (!uid) return {applied: false, reason: "missing_uid"};
  const userData = await getUserData(uid);
  if (!userData) return {applied: false, reason: "user_not_found"};
  if (!shouldManagePremiumFromApple(userData)) {
    return {applied: false, reason: "not_app_store_premium"};
  }

  const beforeRole = userData.role || "free";
  const beforePremiumUntil = userData.premiumUntil || null;
  const now = new Date();
  const patch = {
    appleSubscription: buildAppleSubscriptionPatch({
      originalTransactionId,
      productId,
      transactionId,
      autoRenew,
      environment,
      status: notificationType || "inactive",
    }),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!isAdminUser(userData)) {
    patch.role = "free";
    patch.premiumUntil = admin.firestore.Timestamp.fromDate(now);
    patch.premiumSource = "app_store";
  }

  await db.collection("users").doc(uid).set(patch, {merge: true});
  await writeAccountHistory({
    userId: uid,
    type: "premium_app_store_inactive",
    title: "Premium disattivato da App Store",
    source,
    before: {
      role: beforeRole,
      premiumUntil: beforePremiumUntil,
    },
    after: {
      role: patch.role || beforeRole,
      premiumUntil: now.toISOString(),
      originalTransactionId,
      autoRenew,
      notificationType,
    },
  });

  return {applied: true, uid};
};

const applyAutoRenewStatusOnly = async ({
  uid,
  autoRenew,
  originalTransactionId,
  productId,
  environment,
  notificationType,
}) => {
  if (!uid) return {applied: false, reason: "missing_uid"};
  const userData = await getUserData(uid);
  if (!userData) return {applied: false, reason: "user_not_found"};

  await db.collection("users").doc(uid).set({
    appleSubscription: buildAppleSubscriptionPatch({
      originalTransactionId,
      productId,
      autoRenew,
      environment,
      status: notificationType || "renewal_status_changed",
    }),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {applied: true, uid};
};

const validateProductId = (productId) => {
  const config = readConfig();
  if (!productId) return false;
  if (config.productIds.size === 0) return true;
  return config.productIds.has(productId);
};

const decodeSignedTransaction = async (signedTransactionInfo, environment) => {
  if (!signedTransactionInfo) return null;
  const verifier = getVerifier(environment);
  return verifier.verifyAndDecodeTransaction(signedTransactionInfo);
};

const decodeSignedRenewalInfo = async (signedRenewalInfo, environment) => {
  if (!signedRenewalInfo) return null;
  const verifier = getVerifier(environment);
  return verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo);
};

const resolveUidForTransaction = async (transaction, renewalInfo) => {
  const originalTransactionId = transaction?.originalTransactionId || null;
  const appAccountToken = transaction?.appAccountToken || renewalInfo?.appAccountToken || null;

  let uid = await findUidByOriginalTransactionId(originalTransactionId);
  if (!uid && appAccountToken) {
    uid = await findUidByAppAccountToken(appAccountToken);
  }
  return uid;
};

const resolveEnvironmentFromPayload = (notification) => {
  const value = (notification?.data?.environment || readConfig().environmentName || "Production")
      .toString()
      .toLowerCase();
  return value === "sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
};

const markNotificationProcessed = async (notificationUUID, payload) => {
  if (!notificationUUID) return false;
  const ref = db.collection(APPLE_SUBSCRIPTION_EVENTS).doc(notificationUUID);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return false;
    tx.set(ref, {
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      notificationType: payload.notificationType || null,
      subtype: payload.subtype || null,
      originalTransactionId: payload.originalTransactionId || null,
      uid: payload.uid || null,
      result: payload.result || null,
    });
    return true;
  });
};

const handleDecodedNotification = async (notification) => {
  const notificationType = notification.notificationType;
  const environment = resolveEnvironmentFromPayload(notification);
  const transaction = await decodeSignedTransaction(
      notification.data?.signedTransactionInfo,
      environment,
  );
  const renewalInfo = await decodeSignedRenewalInfo(
      notification.data?.signedRenewalInfo,
      environment,
  );

  if (notificationType === NotificationTypeV2.TEST) {
    return {ok: true, handled: "test"};
  }

  const productId = transaction?.productId || renewalInfo?.productId || null;
  if (productId && !validateProductId(productId)) {
    console.warn("App Store webhook: productId ignorato", productId);
    return {ok: true, handled: "ignored_product"};
  }

  const originalTransactionId = transaction?.originalTransactionId ||
    renewalInfo?.originalTransactionId ||
    null;
  const transactionId = transaction?.transactionId || null;
  const expiresDate = msToDate(transaction?.expiresDate) ||
    msToDate(renewalInfo?.renewalDate);
  const autoRenew = renewalInfo?.autoRenewStatus === undefined ?
    true :
    renewalInfo.autoRenewStatus === AutoRenewStatus.ON;
  const appAccountToken = transaction?.appAccountToken ||
    renewalInfo?.appAccountToken ||
    null;

  let uid = await resolveUidForTransaction(transaction, renewalInfo);

  if (ACTIVE_NOTIFICATION_TYPES.has(notificationType)) {
    if (!uid) {
      console.warn("App Store webhook attivo senza uid", {
        notificationType,
        originalTransactionId,
      });
      return {ok: true, handled: "missing_uid"};
    }
    await applyPremiumActive({
      uid,
      expiresDate,
      originalTransactionId,
      productId,
      transactionId,
      autoRenew,
      environment: notification.data?.environment || readConfig().environmentName,
      appAccountToken,
      notificationType,
    });
    return {ok: true, handled: "active", uid};
  }

  if (notificationType === NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS) {
    if (!uid) {
      uid = await findUidByOriginalTransactionId(originalTransactionId);
    }
    if (!uid) {
      return {ok: true, handled: "missing_uid"};
    }
    await applyAutoRenewStatusOnly({
      uid,
      autoRenew,
      originalTransactionId,
      productId,
      environment: notification.data?.environment || readConfig().environmentName,
      notificationType,
    });
    return {ok: true, handled: "auto_renew_status", uid};
  }

  if (INACTIVE_NOTIFICATION_TYPES.has(notificationType)) {
    if (!uid) {
      uid = await findUidByOriginalTransactionId(originalTransactionId);
    }
    if (!uid) {
      return {ok: true, handled: "missing_uid"};
    }
    await applyPremiumInactive({
      uid,
      originalTransactionId,
      productId,
      transactionId,
      autoRenew: false,
      environment: notification.data?.environment || readConfig().environmentName,
      notificationType,
    });
    return {ok: true, handled: "inactive", uid};
  }

  console.info("App Store webhook non gestito", {notificationType, subtype: notification.subtype});
  return {ok: true, handled: "ignored_type"};
};

const decodeNotificationPayload = async (signedPayload) => {
  const config = readConfig();
  const attempts = config.environment === Environment.SANDBOX ?
    [Environment.SANDBOX] :
    [Environment.PRODUCTION, Environment.SANDBOX];
  let lastError;
  for (const environment of attempts) {
    try {
      const verifier = getVerifier(environment);
      return await verifier.verifyAndDecodeNotification(signedPayload);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("Notifica App Store non valida.");
};

const verifyTransactionById = async (transactionId) => {
  const config = readConfig();
  const environments = config.environment === Environment.SANDBOX ?
    [Environment.SANDBOX] :
    [Environment.PRODUCTION, Environment.SANDBOX];

  let lastError;
  for (const environment of environments) {
    try {
      const client = getApiClient(environment);
      const response = await client.getTransactionInfo(transactionId);
      const verifier = getVerifier(environment);
      const transaction = await verifier.verifyAndDecodeTransaction(
          response.signedTransactionInfo,
      );
      return {transaction, environment};
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("Transazione App Store non trovata.");
};

const register = ({
  db: firestoreDb,
  admin: firebaseAdmin,
  onCall: onCallFactory,
  onRequest: onRequestFactory,
  HttpsError: httpsErrorClass,
  writeAccountHistory: writeHistory,
}) => {
  db = firestoreDb;
  admin = firebaseAdmin;
  onCall = onCallFactory;
  onRequest = onRequestFactory;
  HttpsError = httpsErrorClass;
  writeAccountHistory = writeHistory;

  const appStoreWebhook = onRequestFactory(
      {
        region: "us-central1",
        timeoutSeconds: 60,
        memory: "256MiB",
        invoker: "public",
      },
      async (req, res) => {
        if (req.method !== "POST") {
          res.status(405).json({ok: false, error: "method_not_allowed"});
          return;
        }

        const config = readConfig();
        const providedSecret = (req.query.secret || req.get("X-App-Store-Webhook-Secret") || "")
            .toString();
        if (config.webhookSecret && providedSecret !== config.webhookSecret) {
          res.status(403).json({ok: false, error: "forbidden"});
          return;
        }

        const signedPayload = (req.body?.signedPayload || "").toString().trim();
        if (!signedPayload) {
          res.status(400).json({ok: false, error: "missing_signed_payload"});
          return;
        }

        try {
          const notification = await decodeNotificationPayload(signedPayload);
          const notificationUUID = notification.notificationUUID;

          const shouldProcess = await markNotificationProcessed(notificationUUID, {
            notificationType: notification.notificationType,
            subtype: notification.subtype,
          });
          if (!shouldProcess) {
            res.status(200).json({ok: true, duplicate: true});
            return;
          }

          const result = await handleDecodedNotification(notification);
          if (notificationUUID) {
            await db.collection(APPLE_SUBSCRIPTION_EVENTS).doc(notificationUUID).set({
              result,
            }, {merge: true});
          }
          res.status(200).json({ok: true, ...result});
        } catch (error) {
          console.error("appStoreWebhook error:", error);
          res.status(400).json({ok: false, error: error.message || "invalid_notification"});
        }
      },
  );

  const verifyAppStorePurchase = onCallFactory(async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login richiesto");
    }

    const transactionId = (request.data?.transactionId || "").toString().trim();
    if (!transactionId) {
      throw new HttpsError("invalid-argument", "transactionId richiesto");
    }

    try {
      const {transaction, environment} = await verifyTransactionById(transactionId);
      const productId = transaction.productId || "";
      if (!validateProductId(productId)) {
        throw new HttpsError("failed-precondition", "Prodotto abbonamento non valido.");
      }

      const expiresDate = msToDate(transaction.expiresDate);
      if (!expiresDate || expiresDate <= new Date()) {
        throw new HttpsError("failed-precondition", "Abbonamento scaduto o non valido.");
      }

      const uid = request.auth.uid;
      const appAccountToken = (request.data?.appAccountToken || "").toString().trim() || null;
      await applyPremiumActive({
        uid,
        expiresDate,
        originalTransactionId: transaction.originalTransactionId,
        productId,
        transactionId: transaction.transactionId,
        autoRenew: true,
        environment: environment === Environment.SANDBOX ? "Sandbox" : "Production",
        appAccountToken,
        notificationType: "client_verify",
        source: "app_store_verify",
      });

      return {
        ok: true,
        premiumUntil: expiresDate.toISOString(),
        autoRenew: true,
        productId,
        originalTransactionId: transaction.originalTransactionId,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("verifyAppStorePurchase error:", error);
      throw new HttpsError(
          "failed-precondition",
          "Verifica acquisto App Store non riuscita. Riprova.",
      );
    }
  });

  return {appStoreWebhook, verifyAppStorePurchase};
};

module.exports = {register};
