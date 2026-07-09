/**
 * Crea o resetta l'account demo per App Store Review.
 * Uso: node scripts/setup_app_review_demo_user.js
 */
const admin = require("firebase-admin");

const PROJECT_ID = "saveit-app-1784d";
const DEMO_EMAIL = "tester1@tester.com";
const DEMO_PASSWORD = "Tester1!";
const DEMO_NAME = "App Review Tester";

admin.initializeApp({projectId: PROJECT_ID});

const auth = admin.auth();
const db = admin.firestore();

async function main() {
  let user;
  try {
    user = await auth.getUserByEmail(DEMO_EMAIL);
    user = await auth.updateUser(user.uid, {
      password: DEMO_PASSWORD,
      emailVerified: true,
      disabled: false,
      displayName: DEMO_NAME,
    });
    console.log(`Aggiornato utente esistente: ${user.uid}`);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    user = await auth.createUser({
      email: DEMO_EMAIL,
      password: DEMO_PASSWORD,
      emailVerified: true,
      displayName: DEMO_NAME,
    });
    console.log(`Creato nuovo utente: ${user.uid}`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("users").doc(user.uid).set(
      {
        userId: user.uid,
        email: DEMO_EMAIL,
        normalizedEmail: DEMO_EMAIL.toLowerCase(),
        name: DEMO_NAME,
        username: "@app.review.tester",
        app_id: "savein",
        role: "premium",
        dashboardRole: "none",
        isBlocked: false,
        blockedReason: null,
        blockedAt: null,
        premiumUntil: null,
        premiumSource: "app_review_demo",
        roleUpdatedAt: now,
        roleUpdatedBy: "app_review_setup",
        createdAt: now,
        lastLogin: now,
        consents: {
          marketing: {
            accepted: true,
            consentDate: now,
            lastModified: now,
            modifiedBy: "system",
            version: "1.0",
          },
          privacy: {
            accepted: true,
            consentDate: now,
            version: "1.0",
          },
          terms: {
            accepted: true,
            consentDate: now,
            version: "1.0",
          },
        },
      },
      {merge: true},
  );

  console.log("Profilo Firestore demo pronto (Premium, non bloccato).");
  console.log(`Email: ${DEMO_EMAIL}`);
  console.log(`Password: ${DEMO_PASSWORD}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
