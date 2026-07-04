const admin = require("firebase-admin");

const PROJECT_ID = "saveit-app-1784d";
const STORAGE_BUCKET = "saveit-app-1784d.firebasestorage.app";

admin.initializeApp({projectId: PROJECT_ID, storageBucket: STORAGE_BUCKET});

const db = admin.firestore();
const bucket = admin.storage().bucket(STORAGE_BUCKET);

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    return [key, rest.join("=") || "true"];
  })
);

const dryRun = args.delete !== "true";
const onlyUid = (args.uid || "").toString().trim();
const limit = Number(args.limit || 0);

const normalizeEmail = (email) => (email || "").toString().toLowerCase().trim();
const emailDocId = (email) => normalizeEmail(email).replace(/\//g, "_");
const promoRedemptionId = (email, promotionId) =>
  `${normalizeEmail(email)}|${(promotionId || "").toString().trim()}`;

const SHARED_LINKS_COLLECTION = "shared_links";
const PROMOTION_REDEMPTIONS_COLLECTION = "promotion_redemptions";
const NEW_SIGNUP_PROMO_CLAIMS_COLLECTION = "new_signup_premium_promo_claims";
const SAVEIN_SMARTCHEF_PROMO_ID = "smartchef_savein_launch";

const deleteQueryDocs = async (query, label) => {
  let total = 0;
  while (true) {
    const snapshot = await query.limit(450).get();
    if (snapshot.empty) break;
    total += snapshot.size;

    if (!dryRun) {
      const batch = db.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    } else {
      break;
    }

    if (snapshot.size < 450) break;
  }
  if (total > 0) {
    console.log(`${dryRun ? "Would delete" : "Deleted"} ${total} docs from ${label}`);
  }
  return total;
};

const deleteDocumentTree = async (docRef) => {
  let total = 0;
  const collections = await docRef.listCollections();
  for (const collection of collections) {
    const snapshot = await collection.get();
    for (const doc of snapshot.docs) {
      total += await deleteDocumentTree(doc.ref);
    }
  }

  const doc = await docRef.get();
  if (doc.exists) {
    total += 1;
    if (!dryRun) {
      await docRef.delete();
    }
  }
  return total;
};

const cleanupStoragePrefix = async (prefix) => {
  const [files] = await bucket.getFiles({prefix});
  if (!dryRun && files.length > 0) {
    await Promise.all(files.map((file) => file.delete({ignoreNotFound: true})));
  }
  if (files.length > 0) {
    console.log(`${dryRun ? "Would delete" : "Deleted"} ${files.length} storage files from ${prefix}`);
  }
  return files.length;
};

const userExistsInAuth = async (uid) => {
  try {
    await admin.auth().getUser(uid);
    return true;
  } catch (error) {
    if (error.code === "auth/user-not-found") return false;
    throw error;
  }
};

const cleanupUser = async (uid, userData) => {
  const email = normalizeEmail(userData.email || userData.normalizedEmail || userData.emailLower);
  const stats = {
    uid,
    email,
    userTreeDocs: await deleteDocumentTree(db.collection("users").doc(uid)),
    featureUsageDocs: await deleteDocumentTree(db.collection("feature_usage").doc(uid)),
    sharedLinks: await deleteQueryDocs(
      db.collection(SHARED_LINKS_COLLECTION).where("ownerId", "==", uid),
      "shared_links.ownerId"
    ),
    sharedItemsOwnedByUser: await deleteQueryDocs(
      db.collectionGroup("shared_items").where("ownerId", "==", uid),
      "users/*/shared_items.ownerId"
    ),
    promotionRedemptions: await deleteQueryDocs(
      db.collection(PROMOTION_REDEMPTIONS_COLLECTION).where("userId", "==", uid),
      "promotion_redemptions.userId"
    ),
    // Non cancellare new_signup_premium_promo_claims: e' uno storico
    // anti-abuso per email. Deve sopravvivere alla cancellazione account per
    // impedire ri-registrazioni ripetute con la stessa email per riottenere
    // la promo benvenuto.
    crossAppPromosSource: await deleteQueryDocs(
      db.collection("cross_app_promos").where("sourceUid", "==", uid),
      "cross_app_promos.sourceUid"
    ),
    crossAppPromosSaveIn: await deleteQueryDocs(
      db.collection("cross_app_promos").where("saveinUid", "==", uid),
      "cross_app_promos.saveinUid"
    ),
    supportMessagesByUid: await deleteQueryDocs(
      db.collection("support_messages").where("userId", "==", uid),
      "support_messages.userId"
    ),
    storageFiles: await cleanupStoragePrefix(`users/${uid}/`),
  };

  if (email) {
    stats.dashboardAccessDocs = await deleteDocumentTree(
      db.collection("dashboard_accesses").doc(email)
    );
    stats.promotionRedemptionEmailDoc = await deleteDocumentTree(
      db.collection(PROMOTION_REDEMPTIONS_COLLECTION).doc(
        promoRedemptionId(email, SAVEIN_SMARTCHEF_PROMO_ID)
      )
    );
    stats.crossAppPromoSaveInDoc = await deleteDocumentTree(
      db.collection("cross_app_promos").doc(`${email}|savein_to_smartchef`)
    );
    stats.crossAppPromoSmartChefDoc = await deleteDocumentTree(
      db.collection("cross_app_promos").doc(`${email}|smartchef_to_savein`)
    );
    stats.supportMessagesByEmail = await deleteQueryDocs(
      db.collection("support_messages").where("userEmail", "==", email),
      "support_messages.userEmail"
    );
  }

  return stats;
};

const main = async () => {
  console.log(`Running orphan user cleanup in ${dryRun ? "DRY-RUN" : "DELETE"} mode`);

  const snapshot = onlyUid
    ? await db.collection("users").where(admin.firestore.FieldPath.documentId(), "==", onlyUid).get()
    : await db.collection("users").get();

  const orphanStats = [];
  for (const doc of snapshot.docs) {
    if (limit > 0 && orphanStats.length >= limit) break;

    const uid = doc.id;
    const exists = await userExistsInAuth(uid);
    if (exists) continue;

    console.log(`\nOrphan Firestore user found: ${uid}`);
    orphanStats.push(await cleanupUser(uid, doc.data() || {}));
  }

  console.log("\nSummary:");
  console.log(JSON.stringify({
    mode: dryRun ? "dry-run" : "delete",
    scannedUsers: snapshot.size,
    orphanUsers: orphanStats.length,
    orphanStats,
  }, null, 2));
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Cleanup failed:", error);
    process.exit(1);
  });
