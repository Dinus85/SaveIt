const {google} = require("googleapis");

const DEFAULT_PACKAGE_NAME = "eu.savein.app";
const PREMIUM_PRODUCT_ID = "savein_premium_monthly";

let db;
let admin;
let onCall;
let HttpsError;
let writeAccountHistory;

const readConfig = () => ({
  packageName: (process.env.GOOGLE_PLAY_PACKAGE_NAME || DEFAULT_PACKAGE_NAME).trim(),
  productId: (process.env.GOOGLE_PLAY_PREMIUM_PRODUCT_ID || PREMIUM_PRODUCT_ID).trim(),
});

const getPublisherClient = async () => {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const authClient = await auth.getClient();
  return google.androidpublisher({
    version: "v3",
    auth: authClient,
  });
};

const timestampToDate = (value) => {
  if (!value) return null;
  if (value.toDate) return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const parseExpiryDate = (subscription) => {
  const lineItems = Array.isArray(subscription.lineItems) ?
    subscription.lineItems :
    [];
  let expiry = null;
  for (const item of lineItems) {
    const candidate = timestampToDate(item.expiryTime);
    if (candidate && (!expiry || candidate > expiry)) {
      expiry = candidate;
    }
  }
  return expiry;
};

const parseAutoRenew = (subscription) => {
  const lineItems = Array.isArray(subscription.lineItems) ?
    subscription.lineItems :
    [];
  return lineItems.some((item) => Boolean(item.autoRenewingPlan));
};

const isAdminUser = (userData) =>
  (userData?.role || "").toString().toLowerCase() === "admin";

const verifyPurchaseToken = async ({purchaseToken}) => {
  const config = readConfig();
  const publisher = await getPublisherClient();
  const response = await publisher.purchases.subscriptionsv2.get({
    packageName: config.packageName,
    token: purchaseToken,
  });
  const subscription = response.data || {};
  const expiryDate = parseExpiryDate(subscription);
  const autoRenew = parseAutoRenew(subscription);
  const state = (subscription.subscriptionState || "").toString();
  const lineItems = Array.isArray(subscription.lineItems) ?
    subscription.lineItems :
    [];
  const productIds = lineItems
      .map((item) => (item.productId || "").toString())
      .filter(Boolean);

  if (productIds.length > 0 && !productIds.includes(config.productId)) {
    throw new HttpsError(
        "failed-precondition",
        "Prodotto abbonamento Google Play non valido.",
    );
  }
  if (!expiryDate || expiryDate <= new Date()) {
    throw new HttpsError(
        "failed-precondition",
        "Abbonamento Google Play scaduto o non valido.",
    );
  }
  if (state === "SUBSCRIPTION_STATE_EXPIRED" ||
      state === "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED") {
    throw new HttpsError(
        "failed-precondition",
        "Abbonamento Google Play non attivo.",
    );
  }

  return {
    subscription,
    expiryDate,
    autoRenew,
    state,
    productId: productIds[0] || config.productId,
  };
};

const applyGooglePremiumActive = async ({
  uid,
  purchaseToken,
  productId,
  expiryDate,
  autoRenew,
  state,
  subscription,
}) => {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const beforeRole = userData.role || "free";
  const beforePremiumUntil = userData.premiumUntil || null;

  const patch = {
    googleSubscription: {
      productId,
      purchaseToken,
      autoRenew,
      state,
      latestOrderId: subscription.latestOrderId || null,
      regionCode: subscription.regionCode || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!isAdminUser(userData)) {
    patch.role = "premium";
    patch.premiumUntil = admin.firestore.Timestamp.fromDate(expiryDate);
    patch.premiumSource = "google_play";
  }

  await userRef.set(patch, {merge: true});
  await writeAccountHistory({
    userId: uid,
    type: "premium_google_play_active",
    title: "Premium attivato/rinnovato da Google Play",
    source: "google_play_verify",
    before: {
      role: beforeRole,
      premiumUntil: beforePremiumUntil,
    },
    after: {
      role: patch.role || beforeRole,
      premiumUntil: expiryDate.toISOString(),
      productId,
      autoRenew,
      state,
    },
  });
};

const register = ({
  db: firestoreDb,
  admin: firebaseAdmin,
  onCall: onCallFactory,
  HttpsError: httpsErrorClass,
  writeAccountHistory: writeHistory,
}) => {
  db = firestoreDb;
  admin = firebaseAdmin;
  onCall = onCallFactory;
  HttpsError = httpsErrorClass;
  writeAccountHistory = writeHistory;

  const verifyGooglePlayPurchase = onCall(async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login richiesto");
    }

    const purchaseToken = (request.data?.purchaseToken || "").toString().trim();
    const productId = (request.data?.productId || "").toString().trim();
    const config = readConfig();
    if (!purchaseToken) {
      throw new HttpsError("invalid-argument", "purchaseToken richiesto");
    }
    if (productId && productId !== config.productId) {
      throw new HttpsError(
          "failed-precondition",
          "Prodotto Google Play non valido.",
      );
    }

    try {
      const verified = await verifyPurchaseToken({purchaseToken});
      await applyGooglePremiumActive({
        uid: request.auth.uid,
        purchaseToken,
        ...verified,
      });

      return {
        ok: true,
        premiumUntil: verified.expiryDate.toISOString(),
        autoRenew: verified.autoRenew,
        productId: verified.productId,
        state: verified.state,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("verifyGooglePlayPurchase error:", error);
      throw new HttpsError(
          "failed-precondition",
          "Verifica acquisto Google Play non riuscita. Riprova.",
      );
    }
  });

  return {verifyGooglePlayPurchase};
};

module.exports = {register};
