/**
 * Script one-time: aggiunge il primo admin del dashboard SaveIn.
 * Eseguire con: node seed_dashboard_admin.js
 * Richiede che GOOGLE_APPLICATION_CREDENTIALS sia configurato,
 * oppure eseguirlo dalla cartella functions dopo aver fatto `firebase login`.
 */

const admin = require("firebase-admin");

admin.initializeApp({
  projectId: "saveit-app-1784d",
});

const db = admin.firestore();

async function seed() {
  const email = "dinopasi@hotmail.it";

  await db.collection("dashboard_accesses").doc(email).set(
      {
        email,
        dashboardRole: "admin",
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: "bootstrap",
        note: "Primo admin dashboard — accesso solo al pannello web",
      },
      {merge: true},
  );

  console.log(`✅ Admin aggiunto: ${email}`);
  console.log("Puoi ora accedere a https://savein.eu/dashboard/login");
  process.exit(0);
}

seed().catch((err) => {
  console.error("❌ Errore:", err.message);
  process.exit(1);
});
