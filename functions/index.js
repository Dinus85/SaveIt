const functions = require("firebase-functions");
const functionsV1 = require("firebase-functions/v1");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

// Inizializza Firebase Admin
admin.initializeApp();

const db = admin.firestore();
const SHARED_LINKS_COLLECTION = "shared_links";
const PLAN_LIMITS_DOC = "config/plan_limits";
const DEFAULT_STORAGE_BUCKET = "saveit-app-1784d.firebasestorage.app";

  const _default_feature_rules = () => ({
  "root_folders": {
    "free": {enabled: true, limit: 10, period: "total", requiresAd: false},
    "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
  },
  "child_folders": {
    "free": {enabled: true, limit: 4, period: "total", requiresAd: false},
    "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
  },
  "folder_levels": {
    "free": {enabled: true, limit: 1, period: "total", requiresAd: false},
    "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
  },
  "manual_tags": {
    "free": {enabled: false, limit: 0, period: "total", requiresAd: false},
    "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
  },
  "share_folder": {
    "free": {enabled: true, limit: 1, period: "day", requiresAd: true},
    "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
  },
  "share_post": {
    "free": {enabled: true, limit: 3, period: "day", requiresAd: true},
    "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
  },
  "import_shared": {
    "free": {enabled: true, limit: 5, period: "day", requiresAd: true},
    "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
  },
  "reminders": {
    "free": {enabled: true, limit: 0, period: "total", requiresAd: true},
    "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
  },
});

const _get_plan_limits = async () => {
  const doc = await db.doc(PLAN_LIMITS_DOC).get();
  return doc.exists ? doc.data() : {};
};
const SHARE_LINK_BASE_URL = (process.env.SHARE_LINK_BASE_URL || "https://savein.eu").replace(/\/$/, "");
const PLAY_STORE_URL = process.env.PLAY_STORE_URL || "https://play.google.com/store/apps/details?id=eu.savein.app";
const APP_STORE_URL = process.env.APP_STORE_URL || "";
const ASSET_LINKS = [
  {
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: "eu.savein.app",
      sha256_cert_fingerprints: [
        "88:71:25:D3:62:D3:2D:B6:FE:69:67:68:F8:02:BB:04:53:90:30:90:58:0C:69:5E:C6:12:9F:55:FD:95:4C:BD",
        "89:09:D4:4A:58:D6:7C:FC:53:0B:1B:F7:7E:4D:85:36:14:BD:CA:4F:BB:0F:48:46:31:4A:3E:30:FC:A8:64:D2",
      ],
    },
  },
];

const requireDashboardAdmin = async (auth, actionLabel) => {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }
  const role = await getDashboardRoleForCaller(auth);
  if (role !== "admin") {
    throw new HttpsError(
        "permission-denied",
        `Solo gli admin possono ${actionLabel}`
    );
  }
};

const firebaseStorageDownloadUrl = (bucketName, filePath, token) => {
  const encodedPath = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${token}`;
};

// Configurazione Nodemailer - supporta sia Aruba SMTP che Gmail
// Per Aruba: impostare EMAIL_HOST, EMAIL_PORT, EMAIL_USER, EMAIL_PASSWORD
// Per Gmail: impostare EMAIL_SERVICE=gmail, EMAIL_USER, EMAIL_PASSWORD

let cachedTransporter = null;
let cachedSignature = null;
let warnedMissingPassword = false;

const getEmailConfig = () => {
  const host = process.env.EMAIL_HOST || null;
  const port = parseInt(process.env.EMAIL_PORT || "465", 10);
  const secure = process.env.EMAIL_SECURE !== "false";
  const service = host ? null : (process.env.EMAIL_SERVICE || "gmail");
  const user = process.env.EMAIL_USER || "";
  const password = process.env.EMAIL_PASSWORD;
  const from = process.env.EMAIL_FROM || `SaveIn! <${user}>`;
  const support = process.env.SUPPORT_EMAIL || user;

  return {host, port, secure, service, user, password, from, support};
};

const getEmailTransport = () => {
  const config = getEmailConfig();

  if (!config.password) {
    if (!warnedMissingPassword) {
      console.warn(
          "ATTENZIONE: variabile EMAIL_PASSWORD non impostata. L'invio email fallirà."
      );
      warnedMissingPassword = true;
    }
    return {config, transporter: null};
  }

  const signature = `${config.host || config.service}|${config.user}`;
  if (!cachedTransporter || cachedSignature !== signature) {
    const transportOptions = config.host ?
      {
        host: config.host,
        port: config.port,
        secure: config.secure,
        auth: {user: config.user, pass: config.password},
        tls: {rejectUnauthorized: true},
      } :
      {
        service: config.service,
        auth: {user: config.user, pass: config.password},
      };
    cachedTransporter = nodemailer.createTransport(transportOptions);
    cachedSignature = signature;
  }

  return {config, transporter: cachedTransporter};
};

// Template HTML email — struttura unificata con logo, header e footer branded
const buildEmailHtml = (title, bodyHtml, footerNote = null) => {
  const year = new Date().getFullYear();
  const baseUrl = (process.env.APP_BASE_URL || "https://savein.eu").replace(/\/$/, "");
  const iconUrl = `${baseUrl}/email-assets/icon.png`;
  const nameUrl = `${baseUrl}/email-assets/name.png`;
  const accountUrl = `${baseUrl}/account`;

  const extraNote = footerNote
    ? `<tr><td style="padding:0 32px 12px 32px;">
         <p style="margin:0;font-size:12px;color:#666666;line-height:1.5;text-align:center;">${footerNote}</p>
         <hr style="border:none;border-top:1px solid #e8e8e8;margin:12px 0 0 0;">
       </td></tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background-color:#eef0f5;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" border="0"
       style="background-color:#eef0f5;padding:32px 16px;">
  <tr>
    <td align="center">
      <table width="600" cellpadding="0" cellspacing="0" border="0"
             style="max-width:600px;width:100%;">

        <!-- ===== HEADER ===== -->
        <tr>
          <td style="background-color:#ffffff;border-radius:12px 12px 0 0;
                     padding:24px 32px 20px 32px;text-align:center;
                     border-left:1px solid #e0e0e0;border-right:1px solid #e0e0e0;
                     border-top:1px solid #e0e0e0;">
            <img src="${baseUrl}/email-assets/logo-full.png" alt="SaveIn!"
                 width="520" style="display:block;margin:0 auto;max-width:100%;height:auto;">
          </td>
        </tr>

        <!-- ===== SEPARATORE HEADER/BODY ===== -->
        <tr>
          <td style="background-color:#e8e8e8;height:2px;
                     border-left:1px solid #e0e0e0;border-right:1px solid #e0e0e0;">
          </td>
        </tr>

        <!-- ===== BODY ===== -->
        <tr>
          <td style="background-color:#ffffff;padding:36px 40px 28px 40px;
                     border-left:1px solid #e0e0e0;border-right:1px solid #e0e0e0;">
            <h2 style="color:#1a1a2e;margin:0 0 22px 0;font-size:21px;font-weight:700;
                        line-height:1.3;">${title}</h2>
            <div style="color:#333333;font-size:15px;line-height:1.75;">
              ${bodyHtml}
            </div>
          </td>
        </tr>

        <!-- ===== DIVIDER ===== -->
        <tr>
          <td style="background-color:#ffffff;padding:0 40px;
                     border-left:1px solid #e0e0e0;border-right:1px solid #e0e0e0;">
            <hr style="border:none;border-top:1px solid #eeeeee;margin:0;">
          </td>
        </tr>

        <!-- ===== FOOTER ===== -->
        <tr>
          <td style="background-color:#f7f8fa;border:1px solid #e0e0e0;border-top:none;
                     border-radius:0 0 12px 12px;padding:20px 0 0 0;
                     border-bottom:3px solid #e0e0e0;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0">

              ${extraNote}

              <!-- Testo principale footer -->
              <tr>
                <td style="padding:0 32px 10px 32px;text-align:center;">
                  <p style="margin:0 0 5px 0;font-size:12px;color:#888888;line-height:1.5;">
                    Hai ricevuto questa email perché sei registrato su <strong style="color:#555555;">SaveIn!</strong>.
                  </p>
                  <p style="margin:0 0 5px 0;font-size:12px;color:#888888;">
                    Per assistenza:
                    <a href="mailto:support@savein.eu"
                       style="color:#1a1a2e;text-decoration:none;font-weight:600;">support@savein.eu</a>
                  </p>
                  <p style="margin:0;font-size:12px;color:#888888;">
                    Non vuoi ricevere email promozionali?
                    <a href="${accountUrl}"
                       style="color:#1a1a2e;text-decoration:underline;">Gestisci le preferenze</a>
                    nell'app →&nbsp;<em>Account&nbsp;›&nbsp;Notifiche</em>
                  </p>
                </td>
              </tr>

              <!-- Link footer: sito · supporto · privacy -->
              <tr>
                <td style="padding:12px 32px;text-align:center;border-top:1px solid #e8e8e8;">
                  <table cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
                    <tr>
                      <td style="padding:0 8px;">
                        <a href="${baseUrl}" style="color:#555555;font-size:11px;text-decoration:none;">savein.eu</a>
                      </td>
                      <td style="padding:0;color:#cccccc;font-size:11px;">·</td>
                      <td style="padding:0 8px;">
                        <a href="mailto:support@savein.eu" style="color:#555555;font-size:11px;text-decoration:none;">Supporto</a>
                      </td>
                      <td style="padding:0;color:#cccccc;font-size:11px;">·</td>
                      <td style="padding:0 8px;">
                        <a href="${baseUrl}/privacy" style="color:#555555;font-size:11px;text-decoration:none;">Privacy</a>
                      </td>
                      <td style="padding:0;color:#cccccc;font-size:11px;">·</td>
                      <td style="padding:0 8px;">
                        <a href="${baseUrl}/termini" style="color:#555555;font-size:11px;text-decoration:none;">Termini</a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- Copyright -->
              <tr>
                <td style="padding:0 32px 16px 32px;text-align:center;">
                  <p style="margin:0;font-size:11px;color:#bbbbbb;">
                    © ${year} SaveIn! · Tutti i diritti riservati ·
                    <a href="mailto:noreply@savein.eu" style="color:#bbbbbb;text-decoration:none;">noreply@savein.eu</a>
                  </p>
                </td>
              </tr>

            </table>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
};

// ===============================================
// FUNZIONE 1: Query utenti con marketing consent
// ===============================================
exports.getMarketingUsers = functions.https.onCall(async (data, context) => {
  // Verifica autenticazione
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Devi essere autenticato per accedere a questa funzione"
    );
  }

  // Verifica claim admin (opzionale)
  if (!context.auth.token.admin) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Solo gli admin possono accedere a questa funzione"
    );
  }

  try {
    // Query Firestore per utenti con marketing attivo
    const snapshot = await db.collection("users")
        .where("consents.marketing.accepted", "==", true)
        .orderBy("consents.marketing.consentDate", "desc")
        .limit(data.limit || 100)
        .get();

    const users = [];
    snapshot.forEach((doc) => {
      const userData = doc.data();
      users.push({
        id: doc.id,
        email: userData.email,
        name: userData.name,
        consentDate: userData.consents.marketing.consentDate,
        lastModified: userData.consents.marketing.lastModified,
      });
    });

    return {
      success: true,
      count: users.length,
      users: users,
    };
  } catch (error) {
    console.error("Errore query marketing users:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Errore durante il recupero degli utenti"
    );
  }
});

// ===============================================
// FUNZIONE 2: Statistiche marketing consent
// ===============================================
exports.getMarketingStats = functions.https.onCall(async (data, context) => {
  // Verifica autenticazione
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Devi essere autenticato"
    );
  }

  // Verifica claim admin
  if (!context.auth.token.admin) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Solo gli admin possono accedere"
    );
  }

  try {
    // Query tutti gli utenti
    const allUsersSnapshot = await db.collection("users").get();
    const totalUsers = allUsersSnapshot.size;

    // Query utenti con marketing attivo
    const marketingSnapshot = await db.collection("users")
        .where("consents.marketing.accepted", "==", true)
        .get();
    const marketingActive = marketingSnapshot.size;

    // Query utenti che hanno rifiutato
    const refusedSnapshot = await db.collection("users")
        .where("consents.marketing.accepted", "==", false)
        .get();
    const marketingRefused = refusedSnapshot.size;

    // Calcola percentuali
    const activePercentage = totalUsers > 0 ?
      Math.round((marketingActive / totalUsers) * 100) : 0;

    return {
      success: true,
      stats: {
        totalUsers: totalUsers,
        marketingActive: marketingActive,
        marketingRefused: marketingRefused,
        noResponse: totalUsers - marketingActive - marketingRefused,
        percentage: activePercentage,
      },
    };
  } catch (error) {
    console.error("Errore statistiche:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Errore durante il calcolo delle statistiche"
    );
  }
});

// ===============================================
// FUNZIONE 3: Export email per campagne
// ===============================================
exports.exportMarketingEmails = functions.https.onCall(
    async (data, context) => {
      // Verifica autenticazione e admin
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Devi essere autenticato"
        );
      }

      if (!context.auth.token.admin) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Solo gli admin possono esportare email"
        );
      }

      try {
        // Query utenti con marketing attivo
        const snapshot = await db.collection("users")
            .where("consents.marketing.accepted", "==", true)
            .get();

        const emails = [];
        let csvContent = "Email,Nome,Data Consenso\n";

        snapshot.forEach((doc) => {
          const userData = doc.data();
          const email = userData.email || "";
          const name = userData.name || "";
          let consentDate = "";

          // Gestione sicura della data consenso
          if (userData.consents &&
              userData.consents.marketing &&
              userData.consents.marketing.consentDate) {
            consentDate = userData.consents.marketing.consentDate
                .toDate().toISOString();
          }

          emails.push({
            email: email,
            name: name,
            consentDate: consentDate,
          });

          // Aggiungi riga CSV (gestisci virgole nei nomi)
          const safeName = name.includes(",") ? `"${name}"` : name;
          csvContent += `${email},${safeName},${consentDate}\n`;
        });

        return {
          success: true,
          count: emails.length,
          emails: emails,
          csv: csvContent,
        };
      } catch (error) {
        console.error("Errore export email:", error);
        throw new functions.https.HttpsError(
            "internal",
            "Errore durante l'export delle email"
        );
      }
    }
);

// ===============================================
// FUNZIONE 4: Query per data consenso
// ===============================================
exports.getMarketingUsersByDate = functions.https.onCall(
    async (data, context) => {
      // Verifica autenticazione e admin
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Devi essere autenticato"
        );
      }

      if (!context.auth.token.admin) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Solo gli admin possono accedere"
        );
      }

      try {
        const {startDate, endDate} = data;

        // Converti date string in timestamp Firestore
        const start = startDate ?
          admin.firestore.Timestamp.fromDate(new Date(startDate)) :
          admin.firestore.Timestamp.fromDate(new Date("2020-01-01"));

        const end = endDate ?
          admin.firestore.Timestamp.fromDate(new Date(endDate)) :
          admin.firestore.Timestamp.now();

        // Query con range di date
        const snapshot = await db.collection("users")
            .where("consents.marketing.accepted", "==", true)
            .where("consents.marketing.consentDate", ">=", start)
            .where("consents.marketing.consentDate", "<=", end)
            .orderBy("consents.marketing.consentDate", "desc")
            .get();

        const users = [];
        snapshot.forEach((doc) => {
          const userData = doc.data();
          users.push({
            id: doc.id,
            email: userData.email,
            name: userData.name,
            consentDate: userData.consents.marketing.consentDate
                .toDate().toISOString(),
          });
        });

        return {
          success: true,
          count: users.length,
          users: users,
          dateRange: {
            start: start.toDate().toISOString(),
            end: end.toDate().toISOString(),
          },
        };
      } catch (error) {
        console.error("Errore query by date:", error);
        throw new functions.https.HttpsError(
            "internal",
            "Errore durante la query per data"
        );
      }
    }
);

// ===============================================
// FUNZIONE 5: Invia email di contatto
// ===============================================
exports.sendContactEmail = onCall(async (request) => {
  const context = request;
  // Verifica autenticazione
  if (!request.auth) {
    throw new HttpsError(
        "unauthenticated",
        "Devi essere autenticato per inviare messaggi"
    );
  }

  try {
    console.log("sendContactEmail - auth uid:", request.auth.uid,
        "email:", request.auth.token?.email,
        "claims:", JSON.stringify(request.auth.token || {}));
    if (!request.auth.token?.email) {
      console.warn("sendContactEmail - nessuna email nel token JWT");
    }

    const {subject, message} = request.data;
    const userEmail = request.auth.token.email || request.auth.token.firebase?.identities?.["google.com"]?.[0] || "Email non disponibile";

    // Validazione input
    if (!subject || !message) {
      throw new HttpsError(
          "invalid-argument",
          "Oggetto e messaggio sono obbligatori"
      );
    }

    if (subject.length > 200) {
      throw new HttpsError(
          "invalid-argument",
          "L'oggetto deve essere massimo 200 caratteri"
      );
    }

    if (message.length > 5000) {
      throw new HttpsError(
          "invalid-argument",
          "Il messaggio deve essere massimo 5000 caratteri"
      );
    }

    const {config, transporter} = getEmailTransport();

    if (!config.password || !transporter) {
      throw new HttpsError(
          "failed-precondition",
          "Configurazione email mancante: imposta EMAIL_PASSWORD"
      );
    }

    console.log(`Inviando email da ${userEmail} verso ${config.support}: ${subject}`);

    const dateStr = new Date().toLocaleString("it-IT");

    // Email interna al supporto
    const supportMailOptions = {
      from: config.from,
      to: config.support,
      replyTo: userEmail,
      subject: `[SaveIn! Support] ${subject}`,
      html: buildEmailHtml(
          "Nuovo messaggio di supporto",
          `<div style="background:#f5f5f5;padding:15px;border-radius:5px;margin-bottom:20px;">
            <p style="margin:5px 0;"><strong>Da:</strong> ${userEmail}</p>
            <p style="margin:5px 0;"><strong>Oggetto:</strong> ${subject}</p>
            <p style="margin:5px 0;"><strong>Data:</strong> ${dateStr}</p>
          </div>
          <div style="background:#fff;padding:20px;border:1px solid #ddd;border-radius:5px;">
            <p style="white-space:pre-wrap;color:#333;line-height:1.6;">${message.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>")}</p>
          </div>
          <p style="font-size:12px;color:#888;margin-top:16px;">Clicca Rispondi per rispondere direttamente a ${userEmail}</p>`,
          "Pannello admin SaveIn!"
      ),
      text: `Nuovo messaggio da ${userEmail}\nOggetto: ${subject}\nData: ${dateStr}\n\n${message}`,
    };

    // Auto-risposta all'utente
    const autoReplyOptions = {
      from: config.from,
      to: userEmail,
      subject: `Abbiamo ricevuto il tuo messaggio - SaveIn`,
      html: buildEmailHtml(
          "Messaggio ricevuto",
          `<p>Ciao,</p>
          <p>abbiamo ricevuto il tuo messaggio riguardo: <strong>${subject}</strong></p>
          <p>Ti risponderemo il prima possibile all'indirizzo <strong>${userEmail}</strong>.</p>
          <div style="background:#f9f9f9;border-left:4px solid #1a1a2e;padding:12px 16px;margin:20px 0;border-radius:0 4px 4px 0;">
            <p style="margin:0;font-size:13px;color:#555;font-style:italic;">"${message.substring(0, 200)}${message.length > 200 ? "..." : ""}"</p>
          </div>
          <p>Se hai domande urgenti puoi scriverci direttamente a <a href="mailto:support@savein.eu" style="color:#1a1a2e;">support@savein.eu</a></p>
          <p>A presto,<br><strong>Il team SaveIn!</strong></p>`
      ),
      text: `Ciao,\n\nabbiamo ricevuto il tuo messaggio riguardo: ${subject}\n\nTi risponderemo il prima possibile.\n\nIl team SaveIn!\nsupport@savein.eu`,
    };

    await transporter.sendMail(supportMailOptions);
    await transporter.sendMail(autoReplyOptions);

    console.log(`✅ Email supporto inviata. Auto-risposta inviata a ${userEmail}`);

    // Salva il messaggio anche su Firestore per storico
    await db.collection("support_messages").add({
      userId: request.auth.uid,
      userEmail: userEmail,
      subject: subject,
      message: message,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "sent",
    });

    return {
      success: true,
      message: "Email inviata con successo",
    };
  } catch (error) {
    console.error("Errore invio email:", error);

    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
        "internal",
        `Errore durante l'invio dell'email: ${error.message}`
    );
  }
});

// ===============================================
// FUNZIONE: Invia email reset password via Aruba
// Genera il link Firebase + invia email custom
// ===============================================
exports.sendPasswordResetEmail = onCall({ invoker: "public" }, async (request) => {
  const data = request.data || {};
  const email = (data.email || "").toString().trim().toLowerCase();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Email non valida");
  }

  // Verifica che l'utente esista su Firebase Auth
  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch {
    // Non rivelare se l'email esiste o meno (sicurezza)
    console.log(`sendPasswordResetEmail: email non trovata: ${email}`);
    return {success: true};
  }

  // Genera il link di reset tramite Firebase Admin
  let resetLink;
  try {
    resetLink = await admin.auth().generatePasswordResetLink(email, {
      url: "https://savein.eu",
    });
  } catch (error) {
    console.error("Errore generazione link reset:", error);
    throw new HttpsError("internal", "Errore durante la generazione del link");
  }

  const {config, transporter} = getEmailTransport();
  if (!transporter) {
    throw new HttpsError(
        "failed-precondition",
        "Configurazione email mancante"
    );
  }

  const displayName = userRecord.displayName || email.split("@")[0];

  const mailOptions = {
    from: config.from,
    to: email,
    subject: "Reimposta la tua password SaveIn!",
    html: buildEmailHtml(
        "Reimposta la tua password",
        `<p>Ciao ${displayName},</p>
        <p>hai richiesto di reimpostare la password del tuo account SaveIn! associato a <strong>${email}</strong>.</p>
        <div style="text-align:center;margin:32px 0;">
          <a href="${resetLink}"
             style="background:#1a1a2e;color:#fff;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:16px;display:inline-block;">
            Reimposta Password
          </a>
        </div>
        <p style="font-size:13px;color:#888;">Il link è valido per <strong>1 ora</strong>. Dopo la scadenza dovrai richiederne uno nuovo.</p>
        <p style="font-size:13px;color:#888;">Se non hai richiesto tu il reset, ignora questa email. Il tuo account è al sicuro.</p>
        <p style="margin-top:24px;">A presto,<br><strong>Il team SaveIn!</strong></p>`,
        "Hai ricevuto questa email perché hai richiesto il reset della password su SaveIn!. " +
        "Per assistenza: <a href='mailto:support@savein.eu' style='color:#888;'>support@savein.eu</a>"
    ),
    text: `Ciao ${displayName},\n\nhai richiesto di reimpostare la password di SaveIn!.\n\nClicca sul link qui sotto (valido 1 ora):\n${resetLink}\n\nSe non hai richiesto tu il reset, ignora questa email.\n\nIl team SaveIn!`,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log(`✅ Email reset password inviata a ${email}`);
    return {success: true};
  } catch (error) {
    console.error(`❌ Errore invio email reset a ${email}:`, error.message);
    throw new HttpsError("internal", "Errore durante l'invio dell'email");
  }
});

// ===============================================
// FUNZIONE: Email di benvenuto al nuovo utente
// Triggered automaticamente da Firebase Auth
// ===============================================
exports.sendWelcomeEmail = functionsV1.auth.user().onCreate(async (user) => {
  const userEmail = user.email;
  const userName = user.displayName || userEmail.split("@")[0];

  if (!userEmail) {
    console.log("sendWelcomeEmail: nessuna email per utente", user.uid);
    return null;
  }

  const {config, transporter} = getEmailTransport();
  if (!transporter) {
    console.warn("sendWelcomeEmail: transporter non configurato, skip.");
    return null;
  }

  const mailOptions = {
    from: config.from,
    to: userEmail,
    subject: "Benvenuto in SaveIn!",
    html: buildEmailHtml(
        `Benvenuto in SaveIn!, ${userName}`,
        `<p>Ciao ${userName},</p>
        <p>grazie per esserti registrato su <strong>SaveIn!</strong>. Siamo contenti di averti a bordo!</p>
        <p style="margin:24px 0 8px;">Con SaveIn! puoi:</p>
        <ul style="padding-left:20px;line-height:2;">
          <li>📌 Salvare qualsiasi link direttamente dai social e dal web</li>
          <li>📁 Organizzare i salvataggi in cartelle e sottocartelle</li>
          <li>🔍 Ritrovare tutto velocemente con la ricerca</li>
          <li>🏷️ Aggiungere tag per categorizzare i tuoi contenuti</li>
        </ul>
        <p style="margin-top:24px;">Per iniziare, apri l'app e condividi un link da qualsiasi applicazione.</p>
        <p style="margin-top:24px;">Hai domande? Scrivici a <a href="mailto:support@savein.eu" style="color:#1a1a2e;">support@savein.eu</a></p>
        <p>A presto,<br><strong>Il team SaveIn!</strong></p>`,
        "Hai ricevuto questa email perché ti sei registrato su SaveIn!. " +
        "Per cancellarti dalla lista o per assistenza: <a href='mailto:support@savein.eu' style='color:#888;'>support@savein.eu</a>"
    ),
    text: `Benvenuto in SaveIn!, ${userName}!\n\nGrazie per esserti registrato.\n\nCon SaveIn! puoi salvare, organizzare e ritrovare qualsiasi link da social e web.\n\nPer assistenza: support@savein.eu\n\nIl team SaveIn!`,
  };

  const adminNotifyOptions = {
    from: config.from,
    to: process.env.SUPPORT_EMAIL || "support@savein.eu",
    subject: `🆕 Nuovo utente registrato: ${userName}`,
    html: buildEmailHtml(
        "Nuovo utente registrato",
        `<p>Si è appena registrato un nuovo utente su SaveIn!:</p>
        <table style="border-collapse:collapse;margin:16px 0;">
          <tr><td style="padding:6px 16px 6px 0;color:#666;">Email:</td><td><strong>${userEmail}</strong></td></tr>
          <tr><td style="padding:6px 16px 6px 0;color:#666;">Nome:</td><td><strong>${userName}</strong></td></tr>
          <tr><td style="padding:6px 16px 6px 0;color:#666;">UID:</td><td style="font-family:monospace;font-size:12px;">${user.uid}</td></tr>
          <tr><td style="padding:6px 16px 6px 0;color:#666;">Data:</td><td>${new Date().toLocaleString("it-IT", {timeZone: "Europe/Rome"})}</td></tr>
        </table>`,
        "Notifica automatica admin - SaveIn!"
    ),
    text: `Nuovo utente registrato su SaveIn!:\nEmail: ${userEmail}\nNome: ${userName}\nUID: ${user.uid}`,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log(`✅ Email benvenuto inviata a ${userEmail}`);
    await transporter.sendMail(adminNotifyOptions);
    console.log(`✅ Notifica admin inviata a ${process.env.SUPPORT_EMAIL}`);
  } catch (error) {
    console.error(`❌ Errore invio email benvenuto a ${userEmail}:`, error.message);
  }

  return null;
});

exports.cleanupUserDataOnDelete = functionsV1.auth.user().onDelete(async (user) => {
  const uid = user.uid;
  const email = user.email || "";
  console.info("User cleanup started", {uid, email});
  const stats = await cleanupUserOwnedData({uid, email, dryRun: false});
  console.info("User cleanup completed", {uid, email, stats});
  return null;
});

const normalizeEmail = (email) => (email || "").toString().toLowerCase().trim();
const CROSS_PROMO_DURATION_DAYS = 30;
const CROSS_PROMO_CLAIM_WINDOW_DAYS = 14;
const PROMOTION_BANNERS_COLLECTION = "promotion_banners";
const PROMOTION_REDEMPTIONS_COLLECTION = "promotion_redemptions";
const PROMOTION_EVENTS_COLLECTION = "promotion_banner_events";
const NEW_SIGNUP_PROMO_CONFIG_DOC = "new_signup_premium_promo";
const NEW_SIGNUP_PROMO_CLAIMS_COLLECTION = "new_signup_premium_promo_claims";
const SAVEIN_SMARTCHEF_PROMO_ID = "smartchef_savein_launch";

const addDays = (date, days) => {
  const copy = new Date(date.getTime());
  copy.setDate(copy.getDate() + days);
  return copy;
};

const premiumUntilAfterGift = (userData, durationDays, now = new Date()) => {
  const role = (userData?.role || "").toString().toLowerCase().trim();
  const isCurrentlyPremium = role === "premium" || role === "admin";
  if (!isCurrentlyPremium) {
    return addDays(now, Number(durationDays || CROSS_PROMO_DURATION_DAYS));
  }

  const currentUntil = timestampToDate(userData?.premiumUntil);
  const base = currentUntil && currentUntil > now ? currentUntil : now;
  return addDays(base, Number(durationDays || CROSS_PROMO_DURATION_DAYS));
};

const writeAccountHistory = async ({userId, type, title, source, before = {}, after = {}}) => {
  if (!userId) return;
  try {
    await db.collection("users").doc(userId).collection("account_history").add({
      type,
      title,
      source: source || "",
      before,
      after,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.warn("writeAccountHistory skipped:", error.message);
  }
};

const requireCrossPromoConfig = () => {
  const smartChefBackendUrl = (process.env.SMARTCHEF_BACKEND_URL || "").replace(/\/$/, "");
  const secret = process.env.CROSS_PROMO_SECRET || "";
  if (!smartChefBackendUrl || !secret) {
    throw new HttpsError(
        "failed-precondition",
        "Configurazione promo mancante: imposta SMARTCHEF_BACKEND_URL e CROSS_PROMO_SECRET."
    );
  }
  return {smartChefBackendUrl, secret};
};

const promoRedemptionId = (email, promotionId) =>
  `${normalizeEmail(email)}|${(promotionId || "").toString().trim()}`;

const emailDocId = (email) => normalizeEmail(email).replace(/\//g, "_");

const deleteQuerySnapshotDocs = async (query, {label = "query", dryRun = false, batchSize = 450} = {}) => {
  if (dryRun) {
    const aggregate = await query.count().get();
    const count = aggregate.data().count || 0;
    if (count > 0) {
      console.info(`User cleanup would delete ${count} docs from ${label}`);
    }
    return count;
  }

  let deleted = 0;
  while (true) {
    const snapshot = await query.limit(batchSize).get();
    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < batchSize) break;
  }
  if (deleted > 0) {
    console.info(`User cleanup ${dryRun ? "would delete" : "deleted"} ${deleted} docs from ${label}`);
  }
  return deleted;
};

const deleteDocumentTree = async (docRef, {dryRun = false} = {}) => {
  let deleted = 0;
  const collections = await docRef.listCollections();
  for (const collection of collections) {
    const snapshot = await collection.get();
    for (const doc of snapshot.docs) {
      deleted += await deleteDocumentTree(doc.ref, {dryRun});
    }
  }
  const docSnap = await docRef.get();
  if (docSnap.exists && !dryRun) {
    await docRef.delete();
  }
  return deleted + (docSnap.exists ? 1 : 0);
};

const cleanupStoragePrefix = async (prefix, {dryRun = false} = {}) => {
  const normalizedPrefix = (prefix || "").toString().replace(/^\/+/, "");
  if (!normalizedPrefix) return 0;
  const bucket = admin.storage().bucket(DEFAULT_STORAGE_BUCKET);
  const [files] = await bucket.getFiles({prefix: normalizedPrefix});
  if (!dryRun && files.length > 0) {
    await Promise.all(files.map((file) => file.delete({ignoreNotFound: true})));
  }
  if (files.length > 0) {
    console.info(`User cleanup ${dryRun ? "would delete" : "deleted"} ${files.length} storage files from ${normalizedPrefix}`);
  }
  return files.length;
};

const cleanupUserOwnedData = async ({uid, email, dryRun = false}) => {
  const normalizedEmail = normalizeEmail(email);
  const stats = {
    userTreeDocs: 0,
    sharedLinks: 0,
    sharedItemsOwnedByUser: 0,
    featureUsage: 0,
    promotionRedemptions: 0,
    newSignupClaims: 0,
    crossAppPromos: 0,
    supportMessages: 0,
    dashboardAccesses: 0,
    promotionEvents: 0,
    adminLogs: 0,
    storageFiles: 0,
  };

  if (uid) {
    stats.userTreeDocs += await deleteDocumentTree(db.collection("users").doc(uid), {dryRun});
    stats.featureUsage += await deleteDocumentTree(db.collection("feature_usage").doc(uid), {dryRun});
    stats.sharedLinks += await deleteQuerySnapshotDocs(
        db.collection(SHARED_LINKS_COLLECTION).where("ownerId", "==", uid),
        {label: "shared_links.ownerId", dryRun}
    );
    stats.sharedItemsOwnedByUser += await deleteQuerySnapshotDocs(
        db.collectionGroup("shared_items").where("ownerId", "==", uid),
        {label: "users/*/shared_items.ownerId", dryRun}
    );
    stats.promotionRedemptions += await deleteQuerySnapshotDocs(
        db.collection(PROMOTION_REDEMPTIONS_COLLECTION).where("userId", "==", uid),
        {label: "promotion_redemptions.userId", dryRun}
    );
    // Non cancellare new_signup_premium_promo_claims: sono storico anti-abuso
    // per email e devono sopravvivere a cancellazione account/cleanup per
    // impedire ri-registrazioni ripetute con la stessa email.
    stats.crossAppPromos += await deleteQuerySnapshotDocs(
        db.collection("cross_app_promos").where("sourceUid", "==", uid),
        {label: "cross_app_promos.sourceUid", dryRun}
    );
    stats.crossAppPromos += await deleteQuerySnapshotDocs(
        db.collection("cross_app_promos").where("saveinUid", "==", uid),
        {label: "cross_app_promos.saveinUid", dryRun}
    );
    stats.supportMessages += await deleteQuerySnapshotDocs(
        db.collection("support_messages").where("userId", "==", uid),
        {label: "support_messages.userId", dryRun}
    );
    stats.promotionEvents += await deleteQuerySnapshotDocs(
        db.collection(PROMOTION_EVENTS_COLLECTION).where("userId", "==", uid),
        {label: "promotion_banner_events.userId", dryRun}
    );
    stats.adminLogs += await deleteQuerySnapshotDocs(
        db.collection("admin_logs").where("targetUserId", "==", uid),
        {label: "admin_logs.targetUserId", dryRun}
    );
    stats.adminLogs += await deleteQuerySnapshotDocs(
        db.collection("admin_logs").where("actorId", "==", uid),
        {label: "admin_logs.actorId", dryRun}
    );
    stats.storageFiles += await cleanupStoragePrefix(`users/${uid}/`, {dryRun});
  }

  if (normalizedEmail) {
    stats.dashboardAccesses += await deleteDocumentTree(
        db.collection("dashboard_accesses").doc(normalizedEmail),
        {dryRun}
    );
    stats.promotionRedemptions += await deleteDocumentTree(
        db.collection(PROMOTION_REDEMPTIONS_COLLECTION).doc(promoRedemptionId(normalizedEmail, SAVEIN_SMARTCHEF_PROMO_ID)),
        {dryRun}
    );
    stats.crossAppPromos += await deleteDocumentTree(
        db.collection("cross_app_promos").doc(`${normalizedEmail}|savein_to_smartchef`),
        {dryRun}
    );
    stats.crossAppPromos += await deleteDocumentTree(
        db.collection("cross_app_promos").doc(`${normalizedEmail}|smartchef_to_savein`),
        {dryRun}
    );
    stats.supportMessages += await deleteQuerySnapshotDocs(
        db.collection("support_messages").where("userEmail", "==", normalizedEmail),
        {label: "support_messages.userEmail", dryRun}
    );
    stats.promotionEvents += await deleteQuerySnapshotDocs(
        db.collection(PROMOTION_EVENTS_COLLECTION).where("email", "==", normalizedEmail),
        {label: "promotion_banner_events.email", dryRun}
    );
    stats.promotionEvents += await deleteQuerySnapshotDocs(
        db.collection(PROMOTION_EVENTS_COLLECTION).where("normalizedEmail", "==", normalizedEmail),
        {label: "promotion_banner_events.normalizedEmail", dryRun}
    );
    stats.adminLogs += await deleteQuerySnapshotDocs(
        db.collection("admin_logs").where("actorEmail", "==", normalizedEmail),
        {label: "admin_logs.actorEmail", dryRun}
    );
  }

  return stats;
};

const timestampToDate = (value) => {
  if (!value) return null;
  if (value.toDate) return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const promotionMatchesApp = (promo, appId) => {
  const apps = Array.isArray(promo.apps) ? promo.apps : [];
  const app = (promo.app || promo.targetApp || "").toString().toLowerCase();
  return app === "both" || app === appId || apps.includes(appId) || apps.includes("both");
};

const isPromotionInWindow = (promo, now = new Date()) => {
  const startsAt = timestampToDate(promo.startsAt);
  const endsAt = timestampToDate(promo.endsAt);
  if (startsAt && now < startsAt) return false;
  if (endsAt && now > endsAt) return false;
  return true;
};

const isPromotionUsableForUser = async ({email, promotionId, direction}) => {
  const redemption = await db
      .collection(PROMOTION_REDEMPTIONS_COLLECTION)
      .doc(promoRedemptionId(email, promotionId))
      .get();
  if (redemption.exists) return false;

  const directions = direction ?
    [direction, "savein_to_smartchef", "smartchef_to_savein"] :
    ["savein_to_smartchef", "smartchef_to_savein"];
  for (const promoDirection of [...new Set(directions)]) {
    const crossPromo = await db.collection("cross_app_promos")
        .doc(`${email}|${promoDirection}`)
        .get();
    if (crossPromo.exists) {
      const status = (crossPromo.data()?.status || "").toString();
      if (["pending", "claimed"].includes(status)) {
        return false;
      }
    }
  }
  return true;
};

const userAlreadyInBothApps = async (email) => {
  const directions = ["savein_to_smartchef", "smartchef_to_savein"];
  for (const promoDirection of directions) {
    const crossPromo = await db.collection("cross_app_promos")
        .doc(`${email}|${promoDirection}`)
        .get();
    if (crossPromo.exists) {
      const status = (crossPromo.data()?.status || "").toString();
      if (status === "claimed") return true;
    }
  }
  return false;
};

const getConfiguredPromotion = async ({promotionId, appId, email, direction}) => {
  const snap = await db.collection(PROMOTION_BANNERS_COLLECTION).doc(promotionId).get();
  if (!snap.exists) return null;
  const promo = {id: snap.id, ...snap.data()};
  if (promo.active !== true) return null;
  if (!promotionMatchesApp(promo, appId)) return null;
  if (!isPromotionInWindow(promo)) return null;
  const oncePerUser = promo.oncePerUser !== false;
  if (oncePerUser) {
    const usable = await isPromotionUsableForUser({email, promotionId, direction});
    if (!usable) return null;
  }
  return promo;
};

const promotionImageUrlForApp = (promo, appId) => {
  const appImageField = appId === "smartchef" ?
    "smartchefImageUrl" :
    "saveinImageUrl";
  return (promo[appImageField] || promo.imageUrl || "").toString();
};

const promotionBannerResponse = (promo, appId = "savein") => {
  let message = (promo.message || "").toString();
  if (appId === "smartchef") {
    message = (promo.smartchefMessage || message).toString();
  } else if (appId === "savein") {
    message = (promo.saveinMessage || message).toString();
  }
  let secondaryCtaLabel = (promo.secondaryCtaLabel || "").toString();
  if (appId === "smartchef") {
    secondaryCtaLabel = (promo.smartchefSecondaryCtaLabel || secondaryCtaLabel).toString();
  } else if (appId === "savein") {
    secondaryCtaLabel = (promo.saveinSecondaryCtaLabel || secondaryCtaLabel).toString();
  }

  return {
    id: promo.id,
    type: (promo.type || "generic_promo").toString(),
    title: (promo.title || "").toString(),
    message: message,
    ctaLabel: (promo.ctaLabel || "Scopri").toString(),
    secondaryCtaLabel: secondaryCtaLabel,
    action: (promo.action || "open_url").toString(),
    actionUrl: (promo.actionUrl || "").toString(),
    imageUrl: promotionImageUrlForApp(promo, appId),
    saveinImageUrl: (promo.saveinImageUrl || "").toString(),
    smartchefImageUrl: (promo.smartchefImageUrl || "").toString(),
    targetApp: (promo.targetApp || "").toString(),
    priority: Number(promo.priority || 0),
    giftDays: Number(promo.giftDays || CROSS_PROMO_DURATION_DAYS),
  };
};

const restoreNewSignupPremiumForUser = async ({uid, email, premiumUntil, source}) => {
  // Se l'utente ha già Premium senza scadenza (admin-assegnato), non sovrascrivere
  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.exists) {
    const userData = userSnap.data() || {};
    const currentRole = (userData.role || "").toString().toLowerCase().trim();
    const currentPremiumUntil = timestampToDate(userData.premiumUntil);
    const hasUnlimitedAdminPremium = currentRole === "premium" && !currentPremiumUntil;
    if (hasUnlimitedAdminPremium) {
      // Premium illimitato da admin: non sovrascrivere con la scadenza della promo
      return;
    }
  }
  await db.collection("users").doc(uid).set({
    role: "premium",
    premiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
    premiumSource: "new_signup_promo",
    newSignupPremiumPromoClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
    newSignupPremiumPromoRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
    roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    roleUpdatedBy: source || "new_signup_promo_restore",
    email,
    normalizedEmail: normalizeEmail(email),
  }, {merge: true});
};

const getNewSignupPromoConfig = async () => {
  const configSnap = await db.collection("app_config").doc(NEW_SIGNUP_PROMO_CONFIG_DOC).get();
  const config = configSnap.exists ? configSnap.data() || {} : {};
  return {
    active: config.active === true,
    durationDays: Number(config.durationDays || 30),
    priceAfterTrial: (config.priceAfterTrial || "2.99").toString(),
  };
};

exports.getNewSignupPremiumPromoEligibility = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Devi essere autenticato.");
  }

  const email = normalizeEmail(auth.token?.email);
  if (!email) {
    throw new HttpsError("failed-precondition", "Email account non disponibile.");
  }

  const now = new Date();
  const config = await getNewSignupPromoConfig();
  const claimSnap = await db
      .collection(NEW_SIGNUP_PROMO_CLAIMS_COLLECTION)
      .doc(emailDocId(email))
      .get();

  if (claimSnap.exists) {
    const claim = claimSnap.data() || {};
    const premiumUntil = timestampToDate(claim.premiumUntil);
    const stillActive = premiumUntil && premiumUntil > now;
    if (stillActive) {
      await restoreNewSignupPremiumForUser({
        uid: auth.uid,
        email,
        premiumUntil,
        source: "new_signup_promo_existing_claim",
      });
    }

    return {
      canClaim: false,
      alreadyClaimed: true,
      restored: stillActive === true,
      expired: stillActive !== true,
      active: config.active,
      durationDays: config.durationDays,
      priceAfterTrial: config.priceAfterTrial,
      premiumUntil: premiumUntil ? premiumUntil.toISOString() : null,
      startedAt: timestampToDate(claim.startedAt)?.toISOString() || null,
    };
  }

  if (!config.active) {
    return {
      canClaim: false,
      alreadyClaimed: false,
      restored: false,
      expired: false,
      active: false,
      durationDays: config.durationDays,
      priceAfterTrial: config.priceAfterTrial,
      premiumUntil: null,
      startedAt: null,
    };
  }

  const userSnap = await db.collection("users").doc(auth.uid).get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const role = (userData.role || "").toString().toLowerCase().trim();
  const currentPremiumUntil = timestampToDate(userData.premiumUntil);
  const hasActivePremium = role === "premium" &&
    (!currentPremiumUntil || currentPremiumUntil > now);

  return {
    canClaim: role !== "admin" && !hasActivePremium,
    alreadyClaimed: false,
    restored: false,
    expired: false,
    active: true,
    durationDays: config.durationDays,
    priceAfterTrial: config.priceAfterTrial,
    premiumUntil: null,
    startedAt: null,
  };
});

exports.activateNewSignupPremiumPromo = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Devi essere autenticato.");
  }

  const email = normalizeEmail(auth.token?.email);
  if (!email) {
    throw new HttpsError("failed-precondition", "Email account non disponibile.");
  }

  const config = await getNewSignupPromoConfig();
  if (!config.active) {
    throw new HttpsError("failed-precondition", "Questa promo non è più attiva.");
  }

  const now = new Date();
  const claimRef = db.collection(NEW_SIGNUP_PROMO_CLAIMS_COLLECTION).doc(emailDocId(email));
  const userRef = db.collection("users").doc(auth.uid);

  const result = await db.runTransaction(async (transaction) => {
    const [claimSnap, userSnap] = await Promise.all([
      transaction.get(claimRef),
      transaction.get(userRef),
    ]);

    if (claimSnap.exists) {
      const claim = claimSnap.data() || {};
      const existingPremiumUntil = timestampToDate(claim.premiumUntil);
      if (existingPremiumUntil && existingPremiumUntil > now) {
        transaction.set(userRef, {
          role: "premium",
          premiumUntil: admin.firestore.Timestamp.fromDate(existingPremiumUntil),
          premiumSource: "new_signup_promo",
          newSignupPremiumPromoClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
          newSignupPremiumPromoRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
          roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          roleUpdatedBy: "new_signup_promo_existing_claim",
          email,
          normalizedEmail: email,
        }, {merge: true});

        return {
          status: "restored",
          premiumUntil: existingPremiumUntil,
          startedAt: timestampToDate(claim.startedAt) || null,
        };
      }

      throw new HttpsError("already-exists", "Hai già utilizzato questa promo.");
    }

    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const role = (userData.role || "").toString().toLowerCase().trim();
    const currentPremiumUntil = timestampToDate(userData.premiumUntil);
    const hasActivePremium = role === "premium" &&
      (!currentPremiumUntil || currentPremiumUntil > now);
    if (role === "admin" || hasActivePremium) {
      throw new HttpsError("failed-precondition", "Questa promo è disponibile solo per utenti Free.");
    }

    const premiumUntil = addDays(now, config.durationDays);
    const startedAtTs = admin.firestore.Timestamp.fromDate(now);
    const premiumUntilTs = admin.firestore.Timestamp.fromDate(premiumUntil);

    transaction.set(claimRef, {
      email,
      normalizedEmail: email,
      firstUserId: auth.uid,
      lastUserId: auth.uid,
      startedAt: startedAtTs,
      premiumUntil: premiumUntilTs,
      durationDays: config.durationDays,
      priceAfterTrial: config.priceAfterTrial,
      status: "claimed",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: false});

    transaction.set(userRef, {
      role: "premium",
      premiumUntil: premiumUntilTs,
      premiumSource: "new_signup_promo",
      newSignupPremiumPromoClaimedAt: startedAtTs,
      roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      roleUpdatedBy: "new_signup_promo",
      email,
      normalizedEmail: email,
    }, {merge: true});

    return {
      status: "claimed",
      premiumUntil,
      startedAt: now,
    };
  });

  await writeAccountHistory({
    userId: auth.uid,
    type: "new_signup_promo_claimed",
    title: "Promo nuovi iscritti: Premium attivato",
    source: "new_signup_promo",
    after: {
      role: "premium",
      premiumUntil: admin.firestore.Timestamp.fromDate(result.premiumUntil),
      durationDays: config.durationDays,
    },
  });

  return {
    status: result.status,
    premiumUntil: result.premiumUntil.toISOString(),
    startedAt: result.startedAt ? result.startedAt.toISOString() : null,
    durationDays: config.durationDays,
    priceAfterTrial: config.priceAfterTrial,
  };
});

exports.getActivePromotionBanner = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Devi essere autenticato.");
  }
  const email = normalizeEmail(auth.token?.email);
  if (!email) return {banner: null};

  const snap = await db.collection(PROMOTION_BANNERS_COLLECTION)
      .where("active", "==", true)
      .limit(30)
      .get();
  const alreadyInBothApps = await userAlreadyInBothApps(email);
  const candidates = [];
  for (const doc of snap.docs) {
    const promo = {id: doc.id, ...doc.data()};
    if (!promotionMatchesApp(promo, "savein")) continue;
    if (!isPromotionInWindow(promo)) continue;
    const isCrossPromo = (promo.type || "").toString() === "cross_promo";
    if (isCrossPromo && alreadyInBothApps) continue;
    if (!isCrossPromo && promo.oncePerUser !== false) {
      const direction = promo.direction || "";
      const usable = await isPromotionUsableForUser({email, promotionId: promo.id, direction});
      if (!usable) continue;
    }
    candidates.push(promo);
  }

  candidates.sort((a, b) => Number(b.priority || 0) - Number(a.priority || 0));
  return {
    banner: candidates.length ?
      promotionBannerResponse(candidates[0], "savein") :
      null,
  };
});

exports.recordPromotionBannerEvent = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Devi essere autenticato.");
  }
  const email = normalizeEmail(auth.token?.email);
  const data = request.data || {};
  const promotionId = (data.promotionId || "").toString().trim();
  const eventType = (data.eventType || "").toString().trim();
  const placement = (data.placement || "").toString().trim();
  if (!promotionId || !["view", "click"].includes(eventType)) {
    throw new HttpsError("invalid-argument", "Evento banner non valido.");
  }

  const docId = `${email}|${promotionId}|${eventType}|${placement || "default"}`;
  await db.collection(PROMOTION_EVENTS_COLLECTION).doc(docId).set({
    email,
    normalizedEmail: email,
    userId: auth.uid,
    promotionId,
    eventType,
    placement,
    count: admin.firestore.FieldValue.increment(1),
    firstSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

exports.uploadPromotionBannerImage = onCall(
    {timeoutSeconds: 60, memory: "512MiB"},
    async (request) => {
      const auth = request.auth;
      await requireDashboardAdmin(auth, "caricare immagini banner");

      const data = request.data || {};
      const docId = (data.docId || "banner").toString().trim();
      const fileName = (data.fileName || "banner.png").toString().trim();
      const contentType = (data.contentType || "image/png").toString().trim();
      const base64 = (data.base64 || "").toString();
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType)) {
        throw new HttpsError(
            "invalid-argument",
            "Formato immagine non valido. Usa PNG, JPG o WEBP."
        );
      }
      const buffer = Buffer.from(base64, "base64");
      if (!buffer.length) {
        throw new HttpsError("invalid-argument", "File immagine vuoto");
      }
      if (buffer.length > 5 * 1024 * 1024) {
        throw new HttpsError(
            "invalid-argument",
            "Immagine troppo grande. Usa un file sotto 5 MB."
        );
      }

      const safeDocId = docId.replace(/[^a-zA-Z0-9_-]/g, "_");
      const safeFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
      const token = crypto.randomUUID();
      const filePath = `promotion_banners/${safeDocId}/${Date.now()}_${safeFileName}`;
      const bucket = admin.storage().bucket();
      const file = bucket.file(filePath);
      await file.save(buffer, {
        metadata: {
          contentType,
          metadata: {
            firebaseStorageDownloadTokens: token,
            recommendedSize: "1200x400",
            uploadedBy: auth.token.email || auth.uid,
          },
        },
      });

      const encodedPath = encodeURIComponent(filePath);
      return {
        filePath,
        imageUrl: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`,
      };
    }
);

exports.listPromotionBannerImages = onCall(
    {timeoutSeconds: 60, memory: "512MiB"},
    async (request) => {
      const auth = request.auth;
      await requireDashboardAdmin(auth, "vedere lo storico immagini banner");

      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({prefix: "promotion_banners/"});
      const images = files
          .filter((file) => !file.name.endsWith("/"))
          .map((file) => {
            const metadata = file.metadata || {};
            const customMetadata = metadata.metadata || {};
            const tokens = (customMetadata.firebaseStorageDownloadTokens || "")
                .toString()
                .split(",")
                .map((token) => token.trim())
                .filter(Boolean);
            const token = tokens[0] || crypto.randomUUID();
            return {
              filePath: file.name,
              imageUrl: firebaseStorageDownloadUrl(bucket.name, file.name, token),
              fileName: file.name.split("/").pop() || file.name,
              size: Number(metadata.size || 0),
              contentType: metadata.contentType || "",
              createdAt: metadata.timeCreated || "",
              updatedAt: metadata.updated || "",
            };
          })
          .sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || ""));

      return {images};
    }
);

exports.deletePromotionBannerImage = onCall(
    {timeoutSeconds: 60, memory: "256MiB"},
    async (request) => {
      const auth = request.auth;
      await requireDashboardAdmin(auth, "eliminare immagini banner");

      const filePath = (request.data?.filePath || "").toString().trim();
      if (!filePath || !filePath.startsWith("promotion_banners/")) {
        throw new HttpsError("invalid-argument", "Percorso immagine non valido");
      }
      await admin.storage().bucket().file(filePath).delete({ignoreNotFound: true});
      return {ok: true};
    }
);

exports.syncCentralPromotionBanner = functions.https.onRequest(async (req, res) => {
  if (!["POST", "DELETE"].includes(req.method)) {
    res.status(405).json({ok: false, error: "method_not_allowed"});
    return;
  }

  const expectedSecret = process.env.CROSS_PROMO_SECRET || "";
  const providedSecret = req.get("X-Cross-Promo-Secret") || "";
  if (!expectedSecret || providedSecret !== expectedSecret) {
    res.status(403).json({ok: false, error: "forbidden"});
    return;
  }

  const body = req.body || {};
  const docId = (body.docId || body.id || "").toString().trim();
  if (!docId) {
    res.status(400).json({ok: false, error: "missing_doc_id"});
    return;
  }

  const ref = db.collection(PROMOTION_BANNERS_COLLECTION).doc(docId);
  if (req.method === "DELETE" || body.delete === true) {
    await ref.delete();
    res.json({ok: true, deleted: true});
    return;
  }

  const banner = body.banner || {};
  await ref.set({
    active: banner.active === true,
    app: (banner.app || banner.targetApp || "savein").toString(),
    apps: Array.isArray(banner.apps) ? banner.apps : ["savein"],
    type: (banner.type || "generic_promo").toString(),
    title: (banner.title || "").toString(),
    message: (banner.message || "").toString(),
    smartchefMessage: (banner.smartchefMessage || "").toString(),
    saveinMessage: (banner.saveinMessage || "").toString(),
    ctaLabel: (banner.ctaLabel || "").toString(),
    secondaryCtaLabel: (banner.secondaryCtaLabel || "").toString(),
    smartchefSecondaryCtaLabel: (banner.smartchefSecondaryCtaLabel || "").toString(),
    saveinSecondaryCtaLabel: (banner.saveinSecondaryCtaLabel || "").toString(),
    action: (banner.action || "open_url").toString(),
    actionUrl: (banner.actionUrl || "").toString(),
    imageUrl: (banner.imageUrl || "").toString(),
    saveinImageUrl: (banner.saveinImageUrl || "").toString(),
    smartchefImageUrl: (banner.smartchefImageUrl || "").toString(),
    targetApp: (banner.targetApp || banner.app || "savein").toString(),
    direction: (banner.direction || "").toString(),
    giftDays: Number(banner.giftDays || CROSS_PROMO_DURATION_DAYS),
    priority: Number(banner.priority || 0),
    oncePerUser: banner.oncePerUser !== false,
    startsAt: banner.startsAt || null,
    endsAt: banner.endsAt || null,
    sourceAdmin: "smartchef_central_promo_admin",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: (banner.updatedBy || "smartchef-central-admin").toString(),
    createdAt: banner.createdAt || admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  res.json({ok: true, id: docId});
});

exports.syncCentralNewSignupPremiumPromo = functions.https.onRequest(async (req, res) => {
  if (!["GET", "POST"].includes(req.method)) {
    res.status(405).json({ok: false, error: "method_not_allowed"});
    return;
  }

  const expectedSecret = process.env.CROSS_PROMO_SECRET || "";
  const providedSecret = req.get("X-Cross-Promo-Secret") || "";
  if (!expectedSecret || providedSecret !== expectedSecret) {
    res.status(403).json({ok: false, error: "forbidden"});
    return;
  }

  if (req.method === "GET") {
    const doc = await db.collection("app_config").doc(NEW_SIGNUP_PROMO_CONFIG_DOC).get();
    if (!doc.exists) {
      res.json({ok: true, config: null});
      return;
    }
    const data = doc.data() || {};
    const serializeTs = (value) => {
      if (!value) return null;
      if (value.toDate) return value.toDate().toISOString();
      if (value instanceof Date) return value.toISOString();
      return value;
    };
    res.json({
      ok: true,
      config: {
        ...data,
        startsAt: serializeTs(data.startsAt),
        endsAt: serializeTs(data.endsAt),
        updatedAt: serializeTs(data.updatedAt),
      },
    });
    return;
  }

  const body = req.body || {};
  const durationDays = Math.max(1, Math.min(Number(body.durationDays || 30), 365));
  const startsAt = body.startsAt ? new Date(body.startsAt) : null;
  const endsAt = body.endsAt ? new Date(body.endsAt) : null;

  const payload = {
    active: body.active === true,
    app: "savein",
    durationDays,
    priceAfterTrial: (body.priceAfterTrial || "2.99").toString().trim() || "2.99",
    startsAt: startsAt && !Number.isNaN(startsAt.getTime()) ?
      admin.firestore.Timestamp.fromDate(startsAt) :
      null,
    endsAt: endsAt && !Number.isNaN(endsAt.getTime()) ?
      admin.firestore.Timestamp.fromDate(endsAt) :
      null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: (body.updatedBy || "smartchef-central-admin").toString(),
    sourceAdmin: "smartchef_central_promo_admin",
  };

  await db.collection("app_config").doc(NEW_SIGNUP_PROMO_CONFIG_DOC).set(
      payload,
      {merge: true}
  );

  res.json({ok: true, config: {...payload, updatedAt: null}});
});

exports.activateSmartChefLaunchPromo = onCall(
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError(
            "unauthenticated",
            "Devi essere autenticato per attivare la promo."
        );
      }

      const email = normalizeEmail(auth.token?.email);
      if (!email) {
        throw new HttpsError(
            "failed-precondition",
            "Il tuo account non ha un'email valida."
        );
      }

      const configuredPromo = await getConfiguredPromotion({
        promotionId: SAVEIN_SMARTCHEF_PROMO_ID,
        appId: "savein",
        email,
        direction: "savein_to_smartchef",
      });
      if (!configuredPromo) {
        throw new HttpsError(
            "failed-precondition",
            "Questa promo non è attiva oppure è già stata utilizzata."
        );
      }

      const {smartChefBackendUrl, secret} = requireCrossPromoConfig();
      const now = new Date();
      const durationDays = Number(configuredPromo.giftDays || configuredPromo.durationDays || CROSS_PROMO_DURATION_DAYS);
      const premiumUntil = addDays(now, durationDays);
      const claimBy = addDays(now, CROSS_PROMO_CLAIM_WINDOW_DAYS);
      const promoId = `${email}|savein_to_smartchef`;
      const promoRef = db.collection("cross_app_promos").doc(promoId);
      const redemptionRef = db.collection(PROMOTION_REDEMPTIONS_COLLECTION)
          .doc(promoRedemptionId(email, SAVEIN_SMARTCHEF_PROMO_ID));

      await db.runTransaction(async (transaction) => {
        const promoSnap = await transaction.get(promoRef);
        const redemptionSnap = await transaction.get(redemptionRef);
        if (redemptionSnap.exists) {
          throw new HttpsError(
              "already-exists",
              "Hai già utilizzato questa promo."
          );
        }
        const existing = promoSnap.exists ? promoSnap.data() : {};
        if (existing?.status === "claimed") {
          throw new HttpsError(
              "already-exists",
              "Hai già completato questa promo con SmartChef."
          );
        }

        transaction.set(promoRef, {
          email,
          normalizedEmail: email,
          sourceApp: "savein",
          targetApp: "smartchef",
          status: "pending",
          sourceUid: auth.uid,
          durationDays,
          claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
          saveinStartedAt: admin.firestore.Timestamp.fromDate(now),
          saveinActivatedAt: null,
          saveinPremiumUntil: null,
          targetClaimBy: admin.firestore.Timestamp.fromDate(claimBy),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: existing?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        transaction.set(redemptionRef, {
          email,
          normalizedEmail: email,
          promotionId: SAVEIN_SMARTCHEF_PROMO_ID,
          sourceApp: "savein",
          targetApp: "smartchef",
          direction: "savein_to_smartchef",
          status: "started",
          userId: auth.uid,
          redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
          premiumUntil: null,
        }, {merge: true});
      });

      const response = await fetch(`${smartChefBackendUrl}/cross-promos/savein-pending`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Cross-Promo-Secret": secret,
        },
        body: JSON.stringify({
          email,
          sourceUid: auth.uid,
          durationDays,
          claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
          saveinActivatedAt: now.toISOString(),
          saveinPremiumUntil: null,
          claimBy: claimBy.toISOString(),
        }),
      });

      if (!response.ok) {
        const text = await response.text().catch(() => "");
        throw new HttpsError(
            "internal",
            `SmartChef non ha accettato la promo (${response.status}). ${text}`
        );
      }

      await db.collection("admin_logs").add({
        action: "cross_promo_savein_to_smartchef_started",
        actorId: auth.uid,
        actorEmail: email,
        targetEmail: email,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: {
          promoId,
          premiumUntil: null,
          claimBy: claimBy.toISOString(),
        },
      });

      return {
        success: true,
        status: "pending",
        targetApp: "smartchef",
        durationDays,
        claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
        premiumUntil: premiumUntil.toISOString(),
        claimBy: claimBy.toISOString(),
      };
    }
);

exports.confirmSmartChefCrossPromo = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ok: false, error: "method_not_allowed"});
    return;
  }

  const expectedSecret = process.env.CROSS_PROMO_SECRET || "";
  const providedSecret = req.get("X-Cross-Promo-Secret") || "";
  if (!expectedSecret || providedSecret !== expectedSecret) {
    res.status(403).json({ok: false, error: "forbidden"});
    return;
  }

  const body = req.body || {};
  const email = normalizeEmail(body.email);
  if (!email) {
    res.status(400).json({ok: false, error: "missing_email"});
    return;
  }

  const promoId = `${email}|savein_to_smartchef`;
  const smartchefPremiumUntil = body.smartchefPremiumUntil ?
    new Date(body.smartchefPremiumUntil) :
    null;
  const promoRef = db.collection("cross_app_promos").doc(promoId);
  const promoSnap = await promoRef.get();
  const existing = promoSnap.exists ? promoSnap.data() || {} : {};
  const durationDays = Number(existing.durationDays || CROSS_PROMO_DURATION_DAYS);
  const sourceUid = (existing.sourceUid || "").toString();
  let saveinPremiumUntil = addDays(new Date(), durationDays);

  if (sourceUid) {
    const sourceUserSnap = await db.collection("users").doc(sourceUid).get();
    const sourceUserData = sourceUserSnap.exists ? sourceUserSnap.data() || {} : {};
    saveinPremiumUntil = premiumUntilAfterGift(sourceUserData, durationDays, new Date());
    await db.collection("users").doc(sourceUid).set({
      role: "premium",
      premiumUntil: admin.firestore.Timestamp.fromDate(saveinPremiumUntil),
      premiumSource: "cross_promo_savein_to_smartchef",
      roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      roleUpdatedBy: "cross_promo_savein_to_smartchef",
      email,
      normalizedEmail: email,
    }, {merge: true});
    await writeAccountHistory({
      userId: sourceUid,
      type: "cross_promo_claimed",
      title: "Cross-promo completata: Premium attivato",
      source: "cross_promo_savein_to_smartchef",
      before: {
        role: sourceUserData.role || "",
        premiumUntil: sourceUserData.premiumUntil || null,
      },
      after: {
        role: "premium",
        premiumUntil: admin.firestore.Timestamp.fromDate(saveinPremiumUntil),
        durationDays,
        email,
      },
    });
  }

  await promoRef.set({
    status: "claimed",
    smartchefUid: (body.smartchefUid || "").toString(),
    smartchefClaimedAt: body.smartchefClaimedAt ?
      admin.firestore.Timestamp.fromDate(new Date(body.smartchefClaimedAt)) :
      admin.firestore.FieldValue.serverTimestamp(),
    smartchefPremiumUntil: smartchefPremiumUntil && !Number.isNaN(smartchefPremiumUntil.getTime()) ?
      admin.firestore.Timestamp.fromDate(smartchefPremiumUntil) :
      null,
    saveinActivatedAt: sourceUid ? admin.firestore.FieldValue.serverTimestamp() : null,
    saveinPremiumUntil: sourceUid ? admin.firestore.Timestamp.fromDate(saveinPremiumUntil) : null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await db.collection("admin_logs").add({
    action: "cross_promo_smartchef_claimed",
    actorEmail: email,
    targetEmail: email,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    details: {
      promoId,
      smartchefUid: (body.smartchefUid || "").toString(),
      smartchefPremiumUntil: body.smartchefPremiumUntil || null,
      saveinUid: sourceUid || null,
      saveinPremiumUntil: sourceUid ? saveinPremiumUntil.toISOString() : null,
    },
  });

  res.json({ok: true});
});

exports.receiveSmartChefLaunchPromo = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ok: false, error: "method_not_allowed"});
    return;
  }

  const expectedSecret = process.env.CROSS_PROMO_SECRET || "";
  const providedSecret = req.get("X-Cross-Promo-Secret") || "";
  if (!expectedSecret || providedSecret !== expectedSecret) {
    res.status(403).json({ok: false, error: "forbidden"});
    return;
  }

  const body = req.body || {};
  const email = normalizeEmail(body.email);
  if (!email) {
    res.status(400).json({ok: false, error: "missing_email"});
    return;
  }

  const now = new Date();
  const claimBy = body.claimBy ? new Date(body.claimBy) : addDays(now, CROSS_PROMO_CLAIM_WINDOW_DAYS);
  const durationDays = Math.max(1, Number(body.durationDays || CROSS_PROMO_DURATION_DAYS));
  const claimWindowDays = Math.max(1, Number(body.claimWindowDays || CROSS_PROMO_CLAIM_WINDOW_DAYS));
  const smartchefPremiumUntil = body.smartchefPremiumUntil ?
    new Date(body.smartchefPremiumUntil) :
    null;
  const promoId = `${email}|smartchef_to_savein`;
  const promoRef = db.collection("cross_app_promos").doc(promoId);
  const promoSnap = await promoRef.get();
  const existing = promoSnap.exists ? promoSnap.data() : {};

  if (existing?.status === "claimed") {
    res.json({ok: true, status: "claimed", email});
    return;
  }

  await promoRef.set({
    email,
    normalizedEmail: email,
    sourceApp: "smartchef",
    targetApp: "savein",
    status: "pending",
    smartchefUid: (body.smartchefUid || "").toString(),
    durationDays,
    claimWindowDays,
    smartchefActivatedAt: body.smartchefActivatedAt ?
      admin.firestore.Timestamp.fromDate(new Date(body.smartchefActivatedAt)) :
      admin.firestore.Timestamp.fromDate(now),
    smartchefPremiumUntil: smartchefPremiumUntil && !Number.isNaN(smartchefPremiumUntil.getTime()) ?
      admin.firestore.Timestamp.fromDate(smartchefPremiumUntil) :
      null,
    targetClaimBy: admin.firestore.Timestamp.fromDate(claimBy),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: existing?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await db.collection("admin_logs").add({
    action: "cross_promo_smartchef_to_savein_pending",
    actorEmail: email,
    targetEmail: email,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    details: {
      promoId,
      smartchefUid: (body.smartchefUid || "").toString(),
      claimBy: claimBy.toISOString(),
    },
  });

  res.json({
    ok: true,
    status: "pending",
    email,
    durationDays,
    claimBy: claimBy.toISOString(),
  });
});

exports.claimPendingSmartChefLaunchPromo = onCall(
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError(
            "unauthenticated",
            "Devi essere autenticato per attivare la promo."
        );
      }

      const email = normalizeEmail(auth.token?.email);
      if (!email) {
        throw new HttpsError(
            "failed-precondition",
            "Il tuo account non ha un'email valida."
        );
      }

      const now = new Date();
      const promoId = `${email}|smartchef_to_savein`;
      const promoRef = db.collection("cross_app_promos").doc(promoId);
      const userRef = db.collection("users").doc(auth.uid);
      let claimed = false;
      let reason = "not_found";
      let claimBy = null;
      let claimedPremiumUntil = null;
      let claimedDurationDays = CROSS_PROMO_DURATION_DAYS;

      await db.runTransaction(async (transaction) => {
        const promoSnap = await transaction.get(promoRef);
        if (!promoSnap.exists) {
          return;
        }

        const promo = promoSnap.data() || {};
        if (promo.status === "claimed") {
          reason = "already_claimed";
          return;
        }

        const targetClaimBy = promo.targetClaimBy?.toDate ?
          promo.targetClaimBy.toDate() :
          null;
        claimBy = targetClaimBy;
        if (targetClaimBy && now > targetClaimBy) {
          reason = "expired";
          transaction.set(promoRef, {
            status: "expired",
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          return;
        }

        const durationDays = Number(promo.durationDays || CROSS_PROMO_DURATION_DAYS);
        claimedDurationDays = durationDays;
        const userSnap = await transaction.get(userRef);
        const userData = userSnap.exists ? userSnap.data() || {} : {};
        const premiumUntil = premiumUntilAfterGift(userData, durationDays, now);

        transaction.set(userRef, {
          role: "premium",
          premiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
          premiumSource: "cross_promo_smartchef_to_savein",
          roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          roleUpdatedBy: "cross_promo_smartchef_to_savein",
          email,
          normalizedEmail: email,
        }, {merge: true});

        transaction.set(promoRef, {
          status: "claimed",
          saveinUid: auth.uid,
          saveinClaimedAt: admin.firestore.Timestamp.fromDate(now),
          saveinPremiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        claimed = true;
        reason = "claimed";
        claimBy = targetClaimBy;
        claimedPremiumUntil = premiumUntil;
      });

      if (claimed) {
        await writeAccountHistory({
          userId: auth.uid,
          type: "cross_promo_claimed",
          title: "Cross-promo completata: Premium attivato",
          source: "cross_promo_smartchef_to_savein",
          after: {
            role: "premium",
            premiumUntil: admin.firestore.Timestamp.fromDate(claimedPremiumUntil),
            durationDays: claimedDurationDays,
            email,
          },
        });

        const smartChefConfirmUrl = (process.env.SMARTCHEF_CROSS_PROMO_CONFIRM_URL || "").trim();
        const secret = process.env.CROSS_PROMO_SECRET || "";
        if (smartChefConfirmUrl && secret) {
          await fetch(smartChefConfirmUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Cross-Promo-Secret": secret,
            },
            body: JSON.stringify({
              email,
              saveinUid: auth.uid,
              saveinClaimedAt: now.toISOString(),
              saveinPremiumUntil: claimedPremiumUntil.toISOString(),
            }),
          }).catch(() => null);
        }

        await db.collection("admin_logs").add({
          action: "cross_promo_smartchef_to_savein_claimed",
          actorId: auth.uid,
          actorEmail: email,
          targetEmail: email,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          details: {
            promoId,
            premiumUntil: claimedPremiumUntil.toISOString(),
          },
        });
      }

      return {
        success: true,
        claimed,
        reason,
        sourceApp: "smartchef",
        targetApp: "savein",
        durationDays: claimedDurationDays,
        premiumUntil: claimed ? claimedPremiumUntil.toISOString() : null,
        claimBy: claimBy ? claimBy.toISOString() : null,
      };
    }
);

const getDashboardRoleForCaller = async (auth) => {
  const uid = auth?.uid;
  const email = normalizeEmail(auth?.token?.email);
  if (!uid) return "none";

  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.exists ? userDoc.data() : {};
  if (userData?.isBlocked === true) return "none";
  if (userData?.role === "admin" || userData?.dashboardRole === "admin") {
    return "admin";
  }

  if (email) {
    const accessDoc = await db.collection("dashboard_accesses").doc(email).get();
    if (accessDoc.exists) {
      return accessDoc.data()?.dashboardRole || "none";
    }
  }

  return userData?.dashboardRole || "none";
};

const callerCanSendDashboardNotification = async (auth) => {
  const role = await getDashboardRoleForCaller(auth);
  return role === "admin" || role === "editor";
};

const DASHBOARD_ACCESS_ROLES = new Set(["none", "author", "editor", "admin"]);

const countDashboardAdminsAfterEmailChange = async (targetEmail, newRole) => {
  const snap = await db.collection("dashboard_accesses").get();
  let count = 0;
  let targetExists = false;
  snap.docs.forEach((doc) => {
    const data = doc.data() || {};
    const email = normalizeEmail(data.normalizedEmail || doc.id);
    if (email === targetEmail) targetExists = true;
    const role = email === targetEmail ?
      newRole :
      (data.dashboardRole || "none").toString().trim();
    if (role === "admin") count += 1;
  });
  if (!targetExists && newRole === "admin") count += 1;
  return count;
};

exports.upsertDashboardLoginAccess = onCall(
    {region: "us-central1", timeoutSeconds: 30, memory: "256MiB"},
    async (request) => {
      await requireDashboardAdmin(request.auth, "gestire accessi dashboard");

      const data = request.data || {};
      const email = normalizeEmail(data.email);
      const dashboardRole = (data.dashboardRole || "").toString().trim();
      const password = (data.password || "").toString();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Email accesso dashboard non valida.");
      }
      if (!DASHBOARD_ACCESS_ROLES.has(dashboardRole)) {
        throw new HttpsError("invalid-argument", "Ruolo dashboard non valido.");
      }
      if (password && password.length < 6) {
        throw new HttpsError(
            "invalid-argument",
            "La password deve avere almeno 6 caratteri."
        );
      }

      const adminCountAfterChange =
        await countDashboardAdminsAfterEmailChange(email, dashboardRole);
      if (adminCountAfterChange < 1) {
        throw new HttpsError(
            "failed-precondition",
            "Deve rimanere almeno un admin dashboard."
        );
      }

      let authUser = null;
      if (dashboardRole !== "none") {
        try {
          authUser = await admin.auth().getUserByEmail(email);
          if (password) {
            authUser = await admin.auth().updateUser(authUser.uid, {password});
          }
        } catch (error) {
          if (error.code !== "auth/user-not-found") throw error;
          if (!password) {
            throw new HttpsError(
                "failed-precondition",
                "Password obbligatoria per creare un nuovo utente."
            );
          }
          authUser = await admin.auth().createUser({
            email,
            password,
            emailVerified: true,
          });
        }
      }

      const ref = db.collection("dashboard_accesses").doc(email);
      if (dashboardRole === "none") {
        await ref.delete();
      } else {
        const existing = await ref.get();
        await ref.set({
          email,
          normalizedEmail: email,
          uid: authUser?.uid || null,
          dashboardRole,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.auth.uid,
          updatedByEmail: normalizeEmail(request.auth.token?.email),
          createdAt: existing.exists ?
            existing.data()?.createdAt || admin.firestore.FieldValue.serverTimestamp() :
            admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      await db.collection("admin_logs").add({
        action: "dashboard_access_upserted",
        actorId: request.auth.uid,
        actorEmail: normalizeEmail(request.auth.token?.email),
        targetEmail: email,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: {dashboardRole},
      });

      return {ok: true};
    }
);

exports.sendDashboardNotification = onCall(
    async (request) => {
      const data = request.data || {};
      const auth = request.auth;

      if (!auth) {
        throw new HttpsError(
            "unauthenticated",
            "Devi essere autenticato"
        );
      }

      const canSend = await callerCanSendDashboardNotification(auth);
      if (!canSend) {
        throw new HttpsError(
            "permission-denied",
            "Non hai i permessi per inviare notifiche"
        );
      }

      const title = (data.title || "").toString().trim();
      const body = (data.body || "").toString().trim();
      const userIds = Array.isArray(data.userIds) ?
        [...new Set(data.userIds.map((id) => (id || "").toString().trim())
            .filter(Boolean))] :
        [];
      const sendInApp = data.sendInApp !== false;
      const sendPush = data.sendPush === true;
      const systemCommunication = data.systemCommunication === true ||
        data.system === true ||
        data.forceSystem === true;

      if (!title || !body) {
        throw new HttpsError(
            "invalid-argument",
            "Titolo e messaggio sono obbligatori"
        );
      }
      if (title.length > 120) {
        throw new HttpsError(
            "invalid-argument",
            "Il titolo deve essere massimo 120 caratteri"
        );
      }
      if (body.length > 1000) {
        throw new HttpsError(
            "invalid-argument",
            "Il messaggio deve essere massimo 1000 caratteri"
        );
      }
      if (userIds.length === 0) {
        throw new HttpsError(
            "invalid-argument",
            "Seleziona almeno un utente"
        );
      }
      if (userIds.length > 500) {
        throw new HttpsError(
            "invalid-argument",
            "Puoi inviare al massimo a 500 utenti per volta"
        );
      }
      if (!sendInApp && !sendPush) {
        throw new HttpsError(
            "invalid-argument",
            "Scegli almeno un canale di invio"
        );
      }

      const deliveryUserIds = [];
      let skippedConsentCount = 0;
      const chunkSize = 10;
      for (let i = 0; i < userIds.length; i += chunkSize) {
        const chunk = userIds.slice(i, i + chunkSize);
        const snapshot = await db.collection("users")
            .where(admin.firestore.FieldPath.documentId(), "in", chunk)
            .get();
        snapshot.forEach((doc) => {
          const userData = doc.data() || {};
          const marketingAccepted =
            userData?.consents?.marketing?.accepted === true ||
            userData?.acceptedMarketing === true;
          if (!systemCommunication && !marketingAccepted) {
            skippedConsentCount++;
            return;
          }
          deliveryUserIds.push(doc.id);
        });
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      const senderEmail = auth.token.email || "";
      const campaignRef = db.collection("notification_campaigns").doc();
      const batch = db.batch();

      batch.set(campaignRef, {
        title,
        body,
        userIds: deliveryUserIds,
        requestedUserIds: userIds,
        sendInApp,
        sendPush,
        systemCommunication,
        skippedConsentCount,
        senderId: auth.uid,
        senderEmail,
        createdAt: now,
        status: "sending",
      });

      if (sendInApp) {
        for (const userId of deliveryUserIds) {
          const notificationRef = db.collection("users")
              .doc(userId)
              .collection("notifications")
              .doc();
          batch.set(notificationRef, {
            title,
            body,
            campaignId: campaignRef.id,
            createdAt: now,
            readAt: null,
            senderId: auth.uid,
            senderEmail,
            systemCommunication,
          });
        }
      }

      await batch.commit();

      let tokenCount = 0;
      let pushSuccessCount = 0;
      let pushFailureCount = 0;

      if (sendPush) {
        for (const userId of deliveryUserIds) {
          const tokensSnapshot = await db.collection("users")
              .doc(userId)
              .collection("fcmTokens")
              .get();
          const tokens = tokensSnapshot.docs
              .map((doc) => doc.data()?.token)
              .filter((token) => typeof token === "string" && token.length > 0);
          tokenCount += tokens.length;

          for (let i = 0; i < tokens.length; i += 500) {
            const chunk = tokens.slice(i, i + 500);
            if (chunk.length === 0) continue;
            let response;
            try {
              response = await admin.messaging().sendEachForMulticast({
                tokens: chunk,
                notification: {
                  title,
                  body,
                },
                android: {
                  priority: "high",
                  notification: {
                    clickAction: "FLUTTER_NOTIFICATION_CLICK",
                  },
                },
                webpush: {
                  fcmOptions: {
                    link: "https://saveit-app-1784d.web.app/",
                  },
                },
                data: {
                  campaignId: campaignRef.id,
                  type: "dashboard_notification",
                  route: "home",
                  title,
                  body,
                  notificationTitle: title,
                  notificationBody: body,
                  systemCommunication: systemCommunication ? "true" : "false",
                },
              });
            } catch (error) {
              console.error("Errore invio push FCM:", error);
              pushFailureCount += chunk.length;
              continue;
            }
            pushSuccessCount += response.successCount;
            pushFailureCount += response.failureCount;

            const invalidTokens = [];
            response.responses.forEach((result, index) => {
              const code = result.error?.code || "";
              if (code === "messaging/registration-token-not-registered" ||
                  code === "messaging/invalid-registration-token") {
                invalidTokens.push(chunk[index]);
              }
            });

            for (const invalidToken of invalidTokens) {
              const tokenId = invalidToken.replace(/[^A-Za-z0-9_-]/g, "_");
              await db.collection("users")
                  .doc(userId)
                  .collection("fcmTokens")
                  .doc(tokenId)
                  .delete()
                  .catch(() => null);
            }
          }
        }
      }

      await campaignRef.set({
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        tokenCount,
        pushSuccessCount,
        pushFailureCount,
        skippedConsentCount,
      }, {merge: true});

      await db.collection("admin_logs").add({
        action: "notification_sent",
        actorId: auth.uid,
        actorEmail: senderEmail,
        targetUserId: userIds.join(","),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: {
          campaignId: campaignRef.id,
          recipients: deliveryUserIds.length,
          requestedRecipients: userIds.length,
          sendInApp,
          sendPush,
          systemCommunication,
          skippedConsentCount,
          tokenCount,
          pushSuccessCount,
          pushFailureCount,
        },
      });

      return {
        success: true,
        campaignId: campaignRef.id,
        recipients: deliveryUserIds.length,
        requestedRecipients: userIds.length,
        skippedConsentCount,
        tokenCount,
        pushSuccessCount,
        pushFailureCount,
      };
    }
);

// ===============================================
// FUNZIONE: Invia email a utenti selezionati dalla dashboard
// Usata dalla pagina Notifiche del pannello admin
// ===============================================
exports.sendBulkEmail = onCall(
    {timeoutSeconds: 300},
    async (request) => {
      const data = request.data || {};
      const auth = request.auth;

      if (!auth) {
        throw new HttpsError("unauthenticated", "Devi essere autenticato");
      }

      const role = await getDashboardRoleForCaller(auth);
      if (role !== "admin" && role !== "editor") {
        throw new HttpsError(
            "permission-denied",
            "Non hai i permessi per inviare email"
        );
      }

      const userIds = Array.isArray(data.userIds) ?
        [...new Set(data.userIds.map((id) => (id || "").toString().trim())
            .filter(Boolean))] :
        [];
      const subject = (data.subject || "").toString().trim();
      const emailBody = (data.emailBody || "").toString().trim();
      const systemCommunication = data.systemCommunication === true ||
        data.system === true ||
        data.forceSystem === true;

      if (userIds.length === 0) {
        throw new HttpsError("invalid-argument", "Seleziona almeno un utente");
      }
      if (userIds.length > 300) {
        throw new HttpsError(
            "invalid-argument",
            "Puoi inviare al massimo a 300 utenti per volta"
        );
      }
      if (!subject) {
        throw new HttpsError("invalid-argument", "L'oggetto è obbligatorio");
      }
      if (!emailBody) {
        throw new HttpsError("invalid-argument", "Il corpo email è obbligatorio");
      }

      const {config, transporter} = getEmailTransport();
      if (!transporter) {
        throw new HttpsError(
            "failed-precondition",
            "Configurazione email mancante: imposta EMAIL_PASSWORD"
        );
      }

      // Recupera le email degli utenti da Firestore
      const emailAddresses = [];
      let skippedConsentCount = 0;
      const chunkSize = 10;
      for (let i = 0; i < userIds.length; i += chunkSize) {
        const chunk = userIds.slice(i, i + chunkSize);
        const snapshot = await db.collection("users")
            .where(admin.firestore.FieldPath.documentId(), "in", chunk)
            .get();
        snapshot.forEach((doc) => {
          const userData = doc.data() || {};
          const marketingAccepted =
            userData?.consents?.marketing?.accepted === true ||
            userData?.acceptedMarketing === true;
          if (!systemCommunication && !marketingAccepted) {
            skippedConsentCount++;
            return;
          }
          const email = userData?.email;
          if (email && typeof email === "string" && email.includes("@")) {
            emailAddresses.push({userId: doc.id, email});
          }
        });
      }

      if (emailAddresses.length === 0) {
        throw new HttpsError(
            "not-found",
            "Nessun utente con email valida trovato"
        );
      }

      // Invio email con delay per evitare rate limit SMTP
      let sentCount = 0;
      let failCount = 0;
      const failedEmails = [];

      for (const {email, userId} of emailAddresses) {
        try {
          const mailOptions = {
            from: config.from,
            to: email,
            subject: subject,
            html: buildEmailHtml(
                subject,
                emailBody
                    .replace(/\n/g, "<br>")
                    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>"),
                "Hai ricevuto questa email perché sei registrato su SaveIn!. " +
                (systemCommunication ? "Questa è una comunicazione di sistema. " : "") +
                "Per assistenza o per cancellarti: " +
                "<a href='mailto:support@savein.eu' style='color:#888;'>support@savein.eu</a>"
            ),
            text: emailBody,
          };
          await transporter.sendMail(mailOptions);
          sentCount++;

          // Log in Firestore per ogni utente
          await db.collection("admin_logs").add({
            action: "bulk_email_sent",
            actorId: auth.uid,
            actorEmail: auth.token?.email || "",
            targetUserId: userId,
            targetEmail: email,
            subject: subject,
            systemCommunication,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Delay 200ms tra email per rispettare i limiti SMTP
          if (emailAddresses.length > 1) {
            await new Promise((resolve) => setTimeout(resolve, 200));
          }
        } catch (error) {
          console.error(`Errore invio email a ${email}:`, error.message);
          failCount++;
          failedEmails.push(email);
        }
      }

      console.log(`Bulk email: ${sentCount} inviate, ${failCount} fallite`);

      return {
        success: true,
        sentCount,
        failCount,
        totalRequested: emailAddresses.length,
        requestedRecipients: userIds.length,
        skippedConsentCount,
        failedEmails: failedEmails.slice(0, 10), // max 10 in risposta
      };
    }
);

const createShareToken = () => crypto.randomBytes(18).toString("base64url");

const sanitizeSharePayload = (type, payload) => {
  const source = payload && typeof payload === "object" ? payload : {};
  const title = (source.title || source.name || "").toString().trim();
  if (!["post", "folder"].includes(type)) {
    throw new HttpsError("invalid-argument", "Tipo condivisione non valido");
  }
  if (!title) {
    throw new HttpsError("invalid-argument", "Titolo condivisione mancante");
  }
  return source;
};

const normalizeShareId = (value) => (value || "").toString().trim();

const resolveShareResourceId = (type, payload, fallback) => {
  const source = payload && typeof payload === "object" ? payload : {};
  const candidate = type === "folder" ?
    (source.rootId || source.id || fallback) :
    (source.id || source.postId || fallback);
  return normalizeShareId(candidate);
};

const userFoldersRef = (userId) =>
  db.collection("users").doc(userId).collection("folders");

const userPostsRef = (userId) =>
  db.collection("users").doc(userId).collection("posts");

const assertSharedResourceExists = async ({ownerId, resourceId, type}) => {
  const normalizedResourceId = normalizeShareId(resourceId);
  if (!ownerId || !normalizedResourceId || !["post", "folder"].includes(type)) {
    throw new HttpsError("invalid-argument", "Riferimento condivisione non valido");
  }

  const doc = type === "folder" ?
    await userFoldersRef(ownerId).doc(normalizedResourceId).get() :
    await userPostsRef(ownerId).doc(normalizedResourceId).get();
  if (!doc.exists) {
    throw new HttpsError(
        "not-found",
        type === "folder" ? "Cartella da condividere non trovata" : "Post da condividere non trovato"
    );
  }
  return doc;
};

const validateTargetFolder = async (targetUserId, folderId) => {
  const normalized = normalizeShareId(folderId);
  if (!normalized || normalized === "all_folder") return null;

  const doc = await userFoldersRef(targetUserId).doc(normalized).get();
  if (!doc.exists) {
    throw new HttpsError("not-found", "Cartella di destinazione non trovata");
  }
  return normalized;
};

const resolveDefaultTargetFolder = async (targetUserId) => {
  const snapshot = await userFoldersRef(targetUserId)
      .where("isDefault", "==", true)
      .limit(1)
      .get();
  if (!snapshot.empty) return snapshot.docs[0].id;

  const ref = userFoldersRef(targetUserId).doc();
  await ref.set({
    name: "Tutti",
    color: "#BB86FC",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isDefault: true,
    parentId: null,
    isShared: false,
  });
  return ref.id;
};

const appendSharedTag = (tags) => {
  const list = Array.isArray(tags) ?
    tags.map((tag) => tag.toString()).filter((tag) => tag.trim()) :
    [];
  return list.includes("condiviso") ? list : [...list, "condiviso"];
};

const sharedPreviewStorageUrl = (value) => {
  const url = (value || "").toString().trim();
  if (!url) return null;
  const normalized = url.toLowerCase();
  const isUserScoped = normalized.includes("/users/") ||
    normalized.includes("users%2f");
  return isUserScoped && normalized.includes("post_previews") ? null : url;
};

const normalizePostUrlForHash = (value) => {
  const raw = (value || "").toString().trim();
  if (!raw) return "";
  try {
    const parsed = new URL(raw);
    parsed.hash = "";
    parsed.hostname = parsed.hostname.toLowerCase();
    if ((parsed.protocol === "https:" && parsed.port === "443") ||
        (parsed.protocol === "http:" && parsed.port === "80")) {
      parsed.port = "";
    }
    const removableParams = [
      "fbclid",
      "gclid",
      "igsh",
      "igshid",
      "mc_cid",
      "mc_eid",
      "si",
      "utm_campaign",
      "utm_content",
      "utm_medium",
      "utm_source",
      "utm_term",
    ];
    removableParams.forEach((param) => parsed.searchParams.delete(param));
    parsed.searchParams.sort();
    return parsed.toString().replace(/\/$/, "").toLowerCase();
  } catch (_) {
    return raw.toLowerCase();
  }
};

const postUrlHash = (value) =>
  crypto.createHash("sha256").update(value).digest("hex");

const globalPostPayload = (source, ownerId, normalizedUrl, urlHash) => ({
  urlHash,
  normalizedUrl,
  url: (source.url || "").toString().trim(),
  title: (source.title || "Post salvato").toString(),
  description: (source.description || "").toString(),
  imageUrl: source.imageUrl || null,
  previewStorageUrl: sharedPreviewStorageUrl(source.previewStorageUrl),
  creatorName: source.creatorName || null,
  creatorUsername: source.creatorUsername || null,
  metadataProvider: (source.metadataProvider || "client_scrape").toString(),
  firstOwnerId: ownerId || null,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  saveCount: 1,
});

const ensureGlobalPost = async ({source, ownerId}) => {
  const safeSource = source || {};
  const normalizedUrl = normalizePostUrlForHash(safeSource.url);
  if (!normalizedUrl) {
    throw new HttpsError("invalid-argument", "URL post mancante");
  }
  const urlHash = postUrlHash(normalizedUrl);
  const ref = db.collection("global_posts").doc(urlHash);

  const result = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      const existing = snap.data() || {};
      const patch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        saveCount: admin.firestore.FieldValue.increment(1),
      };
      if (!existing.previewStorageUrl && safeSource.previewStorageUrl) {
        patch.previewStorageUrl = sharedPreviewStorageUrl(safeSource.previewStorageUrl);
      }
      if (!existing.imageUrl && safeSource.imageUrl) patch.imageUrl = safeSource.imageUrl;
      transaction.set(ref, patch, {merge: true});
      return {
        globalPostId: ref.id,
        urlHash,
        normalizedUrl,
        canonical: {
          url: existing.url || safeSource.url || "",
          title: existing.title || safeSource.title || "Post salvato",
          description: existing.description || safeSource.description || "",
          imageUrl: existing.imageUrl || safeSource.imageUrl || null,
          previewStorageUrl: existing.previewStorageUrl ||
            sharedPreviewStorageUrl(safeSource.previewStorageUrl) ||
            null,
          creatorName: existing.creatorName || safeSource.creatorName || null,
          creatorUsername: existing.creatorUsername || safeSource.creatorUsername || null,
        },
        reused: true,
      };
    }

    const payload = globalPostPayload(safeSource, ownerId, normalizedUrl, urlHash);
    transaction.set(ref, payload);
    return {
      globalPostId: ref.id,
      urlHash,
      normalizedUrl,
      canonical: {
        url: payload.url,
        title: payload.title,
        description: payload.description,
        imageUrl: payload.imageUrl,
        previewStorageUrl: payload.previewStorageUrl,
        creatorName: payload.creatorName,
        creatorUsername: payload.creatorUsername,
      },
      reused: false,
    };
  });

  return result;
};

const maybeEnsureGlobalPost = async ({source, ownerId}) => {
  const safeSource = source || {};
  if (!normalizePostUrlForHash(safeSource.url)) return null;
  return ensureGlobalPost({source, ownerId});
};

const canonicalFromGlobalDoc = (existing, fallbackUrl) => ({
  url: existing.url || fallbackUrl || "",
  title: existing.title || "Post salvato",
  description: existing.description || "",
  imageUrl: existing.imageUrl || null,
  previewStorageUrl: existing.previewStorageUrl || null,
  creatorName: existing.creatorName || null,
  creatorUsername: existing.creatorUsername || null,
});

const lookupGlobalPostByUrl = async (rawUrl) => {
  const normalizedUrl = normalizePostUrlForHash(rawUrl);
  if (!normalizedUrl) {
    return {found: false, reused: false};
  }
  const urlHash = postUrlHash(normalizedUrl);
  const ref = db.collection("global_posts").doc(urlHash);
  const snap = await ref.get();
  if (!snap.exists) {
    return {
      found: false,
      reused: false,
      urlHash,
      normalizedUrl,
    };
  }
  const existing = snap.data() || {};
  return {
    found: true,
    reused: true,
    globalPostId: ref.id,
    urlHash,
    normalizedUrl,
    saveCount: existing.saveCount || 1,
    canonical: canonicalFromGlobalDoc(existing, normalizedUrl),
  };
};

const createBatchWriter = () => {
  let batch = db.batch();
  let count = 0;

  return {
    set: async (ref, data) => {
      batch.set(ref, data);
      count++;
      if (count >= 450) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    },
    delete: async (ref) => {
      batch.delete(ref);
      count++;
      if (count >= 450) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    },
    commit: async () => {
      if (count > 0) {
        await batch.commit();
      }
    },
  };
};

const copiedFolderData = (source, parentId, ownerId) => ({
  name: source.name || "Cartella condivisa",
  color: source.color || "#BB86FC",
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  isDefault: false,
  parentId: parentId || null,
  isShared: true,
  importedFromOwnerId: ownerId,
});

const copiedPostData = (source, folderId, ownerId, globalPost = null) => {
  const canonical = globalPost && globalPost.canonical ? globalPost.canonical : {};
  return {
    url: canonical.url || source.url || "",
    title: canonical.title || source.title || "Post condiviso",
    description: canonical.description || source.description || "",
    imageUrl: canonical.imageUrl || source.imageUrl || null,
    previewStorageUrl: canonical.previewStorageUrl ||
    sharedPreviewStorageUrl(source.previewStorageUrl),
    creatorName: canonical.creatorName || source.creatorName || null,
    creatorUsername: canonical.creatorUsername ||
    source.creatorUsername ||
    null,
    tags: appendSharedTag(source.tags),
    folderId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isShared: true,
    importedFromOwnerId: ownerId,
    globalPostId: globalPost ? globalPost.globalPostId : null,
    urlHash: globalPost ? globalPost.urlHash : null,
    normalizedUrl: globalPost ? globalPost.normalizedUrl : null,
  };
};

const copySharedPostFromSource = async ({
  ownerId,
  resourceId,
  targetUserId,
  targetFolderId,
}) => {
  const finalFolderId = await validateTargetFolder(targetUserId, targetFolderId) ||
    await resolveDefaultTargetFolder(targetUserId);
  const sourceDoc = await userPostsRef(ownerId).doc(resourceId).get();
  if (!sourceDoc.exists) {
    throw new HttpsError("not-found", "Post condiviso non trovato");
  }

  const destRef = userPostsRef(targetUserId).doc();
  const source = sourceDoc.data() || {};
  const globalPost = await maybeEnsureGlobalPost({source, ownerId});
  await destRef.set(copiedPostData(source, finalFolderId, ownerId, globalPost));
  return {
    importedPostId: destRef.id,
    importedFolderId: finalFolderId,
    foldersCopied: 0,
    postsCopied: 1,
  };
};

const resolveSharedPostPreviewFields = async (source, ownerId) => {
  const safeSource = source || {};
  let previewStorageUrl = sharedPreviewStorageUrl(safeSource.previewStorageUrl);
  let imageUrl = safeSource.imageUrl || null;
  if (!previewStorageUrl || !imageUrl) {
    const globalPost = await maybeEnsureGlobalPost({source: safeSource, ownerId});
    if (globalPost?.canonical) {
      previewStorageUrl = previewStorageUrl ||
        globalPost.canonical.previewStorageUrl ||
        null;
      imageUrl = imageUrl || globalPost.canonical.imageUrl || null;
    }
  }
  return {
    title: (safeSource.title || "Post condiviso").toString(),
    description: (safeSource.description || "").toString(),
    imageUrl,
    previewStorageUrl,
  };
};

const collectSharedFolderBundle = async ({ownerId, resourceId}) => {
  const rootId = normalizeShareId(resourceId);
  const sourceRootDoc = await userFoldersRef(ownerId).doc(rootId).get();
  const foldersSnapshot = await userFoldersRef(ownerId).get();
  const sourceFolders = foldersSnapshot.docs.map((doc) => ({
    id: doc.id,
    data: doc.data() || {},
  }));
  const postsSnapshot = await userPostsRef(ownerId).get();
  const sourcePosts = postsSnapshot.docs.map((doc) => doc.data() || {});
  const folderById = new Map(sourceFolders.map((folder) => [folder.id, folder]));

  if (!sourceRootDoc.exists) {
    throw new HttpsError("not-found", "Cartella condivisa non trovata");
  }

  if (!folderById.has(rootId)) {
    folderById.set(rootId, {id: rootId, data: sourceRootDoc.data() || {}});
  }

  const includedIds = new Set([rootId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const folder of sourceFolders) {
      const parentId = normalizeShareId(folder.data.parentId);
      if (parentId && includedIds.has(parentId) && !includedIds.has(folder.id)) {
        includedIds.add(folder.id);
        changed = true;
      }
    }
  }

  const depthOf = (folder) => {
    let depth = 0;
    let parentId = normalizeShareId(folder.data.parentId);
    const seen = new Set();
    while (parentId && includedIds.has(parentId) && !seen.has(parentId)) {
      seen.add(parentId);
      depth++;
      parentId = normalizeShareId(folderById.get(parentId)?.data?.parentId);
    }
    return depth;
  };

  const foldersToCopy = sourceFolders
      .filter((folder) => includedIds.has(folder.id))
      .sort((a, b) => {
        if (a.id === rootId) return -1;
        if (b.id === rootId) return 1;
        return depthOf(a) - depthOf(b);
      });

  const includedPosts = sourcePosts.filter((post) => {
    const sourceFolderId = normalizeShareId(post.folderId);
    return includedIds.has(sourceFolderId);
  });

  return {
    rootId,
    rootData: sourceRootDoc.data() || {},
    foldersToCopy,
    includedPosts,
  };
};

const loadSharedResourcePreview = async ({ownerId, resourceId, type}) => {
  if (type === "post") {
    const sourceDoc = await userPostsRef(ownerId).doc(resourceId).get();
    if (!sourceDoc.exists) {
      throw new HttpsError("not-found", "Post condiviso non trovato");
    }
    const previewPost = await resolveSharedPostPreviewFields(
        sourceDoc.data() || {},
        ownerId,
    );
    return {
      type: "post",
      ...previewPost,
      folderCount: 0,
      postCount: 1,
      folders: [],
      posts: [previewPost],
    };
  }

  const bundle = await collectSharedFolderBundle({ownerId, resourceId});
  const posts = [];
  for (const post of bundle.includedPosts) {
    posts.push(await resolveSharedPostPreviewFields(post, ownerId));
  }

  const subfolderCount = bundle.foldersToCopy
      .filter((folder) => folder.id !== bundle.rootId)
      .length;

  return {
    type: "folder",
    name: bundle.rootData.name || "Cartella condivisa",
    color: bundle.rootData.color || "#BB86FC",
    folderCount: subfolderCount,
    postCount: posts.length,
    folders: bundle.foldersToCopy
        .filter((folder) => folder.id !== bundle.rootId)
        .map((folder) => ({
          id: folder.id,
          name: folder.data.name || "Cartella",
          color: folder.data.color || "#BB86FC",
          parentId: normalizeShareId(folder.data.parentId) || null,
        })),
    posts,
  };
};

const copySharedFolderFromSource = async ({
  ownerId,
  resourceId,
  targetUserId,
  targetParentFolderId,
}) => {
  const rootId = normalizeShareId(resourceId);
  const sourceRootDoc = await userFoldersRef(ownerId).doc(rootId).get();
  const foldersSnapshot = await userFoldersRef(ownerId).get();
  const sourceFolders = foldersSnapshot.docs.map((doc) => ({
    id: doc.id,
    data: doc.data() || {},
  }));
  const postsSnapshot = await userPostsRef(ownerId).get();
  const sourcePosts = postsSnapshot.docs.map((doc) => doc.data() || {});
  const folderById = new Map(sourceFolders.map((folder) => [folder.id, folder]));

  if (!sourceRootDoc.exists) {
    throw new HttpsError("not-found", "Cartella condivisa non trovata");
  }

  const finalParentId = await validateTargetFolder(targetUserId, targetParentFolderId);
  if (!folderById.has(rootId)) {
    folderById.set(rootId, {id: rootId, data: sourceRootDoc.data() || {}});
  }

  const includedIds = new Set([rootId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const folder of sourceFolders) {
      const parentId = normalizeShareId(folder.data.parentId);
      if (parentId && includedIds.has(parentId) && !includedIds.has(folder.id)) {
        includedIds.add(folder.id);
        changed = true;
      }
    }
  }

  const depthOf = (folder) => {
    let depth = 0;
    let parentId = normalizeShareId(folder.data.parentId);
    const seen = new Set();
    while (parentId && includedIds.has(parentId) && !seen.has(parentId)) {
      seen.add(parentId);
      depth++;
      parentId = normalizeShareId(folderById.get(parentId)?.data?.parentId);
    }
    return depth;
  };

  const foldersToCopy = sourceFolders
      .filter((folder) => includedIds.has(folder.id))
      .sort((a, b) => {
        if (a.id === rootId) return -1;
        if (b.id === rootId) return 1;
        return depthOf(a) - depthOf(b);
      });

  const idMap = new Map();
  const writer = createBatchWriter();
  for (const folder of foldersToCopy) {
    const sourceParentId = normalizeShareId(folder.data.parentId);
    const parentId = folder.id === rootId ?
      finalParentId :
      (idMap.get(sourceParentId) || idMap.get(rootId) || finalParentId);
    const destRef = userFoldersRef(targetUserId).doc();
    idMap.set(folder.id, destRef.id);
    await writer.set(destRef, copiedFolderData(folder.data, parentId, ownerId));
  }

  let postsCopied = 0;
  for (const post of sourcePosts) {
    const sourceFolderId = normalizeShareId(post.folderId);
    if (!includedIds.has(sourceFolderId)) continue;

    const mappedFolderId = idMap.get(sourceFolderId) || idMap.get(rootId);
    if (!mappedFolderId) continue;

    const destRef = userPostsRef(targetUserId).doc();
    const globalPost = await maybeEnsureGlobalPost({source: post, ownerId});
    await writer.set(destRef, copiedPostData(post, mappedFolderId, ownerId, globalPost));
    postsCopied++;
  }

  await writer.commit();
  console.info("Import folder source copy completato", {
    ownerId,
    targetUserId,
    rootId,
    importedRootId: idMap.get(rootId) || null,
    foldersCopied: foldersToCopy.length,
    postsCopied,
  });
  return {
    importedRootId: idMap.get(rootId) || null,
    importedFolderId: idMap.get(rootId) || null,
    foldersCopied: foldersToCopy.length,
    postsCopied,
  };
};

const copySharedResourceFromSource = async ({
  ownerId,
  resourceId,
  type,
  targetUserId,
  targetFolderId,
  targetParentFolderId,
}) => {
  if (!ownerId || !resourceId || !["post", "folder"].includes(type)) {
    throw new HttpsError("invalid-argument", "Riferimento condivisione non valido");
  }
  if (ownerId === targetUserId) {
    throw new HttpsError("failed-precondition", "Non puoi importare un contenuto tuo");
  }

  if (type === "post") {
    return await copySharedPostFromSource({
      ownerId,
      resourceId,
      targetUserId,
      targetFolderId,
    });
  }

  return await copySharedFolderFromSource({
    ownerId,
    resourceId,
    targetUserId,
    targetParentFolderId,
  });
};

const findUserDocByEmail = async (email) => {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return null;

  const users = db.collection("users");
  const queries = [
    users.where("normalizedEmail", "==", normalizedEmail).limit(1),
    users.where("emailLower", "==", normalizedEmail).limit(1),
    users.where("email_lower", "==", normalizedEmail).limit(1),
    users.where("email", "==", email.toString().trim()).limit(1),
    users.where("email", "==", normalizedEmail).limit(1),
  ];

  for (const query of queries) {
    const snapshot = await query.get();
    if (!snapshot.empty) return snapshot.docs[0];
  }

  try {
    const authUser = await admin.auth().getUserByEmail(normalizedEmail);
    const userDoc = await users.doc(authUser.uid).get();
    if (userDoc.exists) return userDoc;
  } catch (error) {
    if (error.code !== "auth/user-not-found") {
      console.warn("Errore lookup Auth utente condivisione:", error);
    }
  }

  return null;
};

exports.findShareRecipientByEmail = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const email = (request.data?.email || "").toString().trim();
      if (!email) {
        throw new HttpsError("invalid-argument", "Email destinatario mancante");
      }

      const doc = await findUserDocByEmail(email);
      if (!doc) {
        throw new HttpsError("not-found", "Utente non trovato");
      }

      const data = doc.data() || {};
      return {
        id: doc.id,
        name: data.name || data.username || "Utente",
        email: data.email || email,
      };
    }
);

exports.ensureGlobalPost = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const data = request.data || {};
      const source = data.post && typeof data.post === "object" ? data.post : data;
      const result = await ensureGlobalPost({
        source,
        ownerId: request.auth.uid,
      });

      return {
        ok: true,
        ...result,
      };
    }
);

exports.getGlobalPostByUrl = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 15,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const data = request.data || {};
      const url = (data.url || "").toString().trim();
      if (!url) {
        throw new HttpsError("invalid-argument", "URL mancante");
      }

      const result = await lookupGlobalPostByUrl(url);
      return {
        ok: true,
        ...result,
      };
    }
);

exports.shareItemWithUser = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const data = request.data || {};
      const recipientId = (data.recipientId || "").toString().trim();
      const resourceId = (data.resourceId || "").toString().trim();
      const type = (data.type || "").toString().trim();
      const originalData = data.originalData && typeof data.originalData === "object" ?
        data.originalData :
        {};

      if (!recipientId || !resourceId || !["post", "folder"].includes(type)) {
        throw new HttpsError("invalid-argument", "Dati condivisione non validi");
      }
      if (recipientId === request.auth.uid) {
        throw new HttpsError("failed-precondition", "Non puoi condividere con te stesso");
      }
      await assertSharedResourceExists({
        ownerId: request.auth.uid,
        resourceId,
        type,
      });

      const recipientDoc = await db.collection("users").doc(recipientId).get();
      if (!recipientDoc.exists) {
        throw new HttpsError("not-found", "Destinatario non trovato");
      }

      await recipientDoc.ref.collection("shared_items").add({
        resourceId,
        type,
        ownerId: request.auth.uid,
        ownerName: request.auth.token.name || request.auth.token.email || "Un utente",
        ownerEmail: request.auth.token.email || "",
        importMode: "source_copy",
        sharedAt: admin.firestore.FieldValue.serverTimestamp(),
        originalData,
      });

      return {ok: true};
    }
);

exports.createShareLink = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }
      const type = (request.data?.type || "").toString().trim();
      const payload = sanitizeSharePayload(type, request.data?.payload);
      const resourceId = resolveShareResourceId(type, payload);
      if (!resourceId) {
        throw new HttpsError("invalid-argument", "Risorsa condivisione mancante");
      }
      await assertSharedResourceExists({
        ownerId: request.auth.uid,
        resourceId,
        type,
      });
      const title = (payload.title || payload.name || "contenuto SaveIn").toString();
      const token = createShareToken();
      const now = admin.firestore.FieldValue.serverTimestamp();
      const expiresAt = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
      );

      await db.collection(SHARED_LINKS_COLLECTION).doc(token).set({
        token,
        type,
        title,
        resourceId,
        payload,
        ownerId: request.auth.uid,
        ownerEmail: request.auth.token.email || "",
        ownerName: request.auth.token.name || request.auth.token.email || "Utente SaveIn",
        importMode: "source_copy",
        createdAt: now,
        updatedAt: now,
        expiresAt,
        status: "active",
        viewCount: 0,
        openCount: 0,
        importCount: 0,
      });

      return {
        token,
        url: `${SHARE_LINK_BASE_URL}/s/${token}`,
        type,
        title,
      };
    }
);

exports.getShareLink = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      const token = (request.data?.token || "").toString().trim();
      if (!token) {
        throw new HttpsError("invalid-argument", "Token mancante");
      }
      const doc = await db.collection(SHARED_LINKS_COLLECTION).doc(token).get();
      if (!doc.exists) {
        throw new HttpsError("not-found", "Condivisione non trovata");
      }
      const data = doc.data() || {};
      const expiresAt = data.expiresAt?.toDate?.();
      if (data.status !== "active" || (expiresAt && expiresAt < new Date())) {
        throw new HttpsError("failed-precondition", "Condivisione non disponibile");
      }
      await doc.ref.set({
        openCount: admin.firestore.FieldValue.increment(1),
        lastOpenedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return {
        token: doc.id,
        type: data.type,
        title: data.title,
        ownerName: data.ownerName || "Utente SaveIn",
        payload: data.payload || {},
      };
    }
);

exports.trackShareLinkImport = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      const token = (request.data?.token || "").toString().trim();
      if (!token) {
        throw new HttpsError("invalid-argument", "Token mancante");
      }
      await db.collection(SHARED_LINKS_COLLECTION).doc(token).set({
        importCount: admin.firestore.FieldValue.increment(1),
        lastImportedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return {ok: true};
    }
);

exports.previewSharedResource = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const shareId = normalizeShareId(request.data?.shareId);
      if (!shareId) {
        throw new HttpsError("invalid-argument", "Condivisione mancante");
      }

      const sharedItemRef = db.collection("users")
          .doc(request.auth.uid)
          .collection("shared_items")
          .doc(shareId);
      const sharedItemDoc = await sharedItemRef.get();
      if (!sharedItemDoc.exists) {
        throw new HttpsError("not-found", "Condivisione non trovata");
      }

      const sharedItem = sharedItemDoc.data() || {};
      const ownerId = normalizeShareId(sharedItem.ownerId);
      const type = normalizeShareId(sharedItem.type);
      const resourceId = normalizeShareId(
          sharedItem.resourceId ||
          resolveShareResourceId(type, sharedItem.originalData),
      );

      if (!ownerId || !resourceId || !["post", "folder"].includes(type)) {
        throw new HttpsError("invalid-argument", "Condivisione non valida");
      }

      const preview = await loadSharedResourcePreview({
        ownerId,
        resourceId,
        type,
      });

      return {ok: true, preview};
    }
);

exports.importSharedResource = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 120,
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login richiesto");
      }

      const data = request.data || {};
      const targetUserId = request.auth.uid;
      const shareId = normalizeShareId(data.shareId);
      const token = normalizeShareId(data.token);
      const targetFolderId = normalizeShareId(data.targetFolderId);
      const targetParentFolderId = normalizeShareId(data.targetParentFolderId);

      let source;
      let sharedItemRef = null;
      let shareLinkRef = null;

      if (shareId) {
        sharedItemRef = db.collection("users")
            .doc(targetUserId)
            .collection("shared_items")
            .doc(shareId);
        const sharedItemDoc = await sharedItemRef.get();
        if (!sharedItemDoc.exists) {
          throw new HttpsError("not-found", "Condivisione non trovata");
        }

        const sharedItem = sharedItemDoc.data() || {};
        source = {
          ownerId: normalizeShareId(sharedItem.ownerId),
          resourceId: normalizeShareId(
              sharedItem.resourceId ||
              resolveShareResourceId(normalizeShareId(sharedItem.type), sharedItem.originalData)
          ),
          type: normalizeShareId(sharedItem.type),
        };
      } else if (token) {
        shareLinkRef = db.collection(SHARED_LINKS_COLLECTION).doc(token);
        const shareLinkDoc = await shareLinkRef.get();
        if (!shareLinkDoc.exists) {
          throw new HttpsError("not-found", "Condivisione non trovata");
        }

        const shareLink = shareLinkDoc.data() || {};
        const expiresAt = shareLink.expiresAt?.toDate?.();
        if (shareLink.status !== "active" || (expiresAt && expiresAt < new Date())) {
          throw new HttpsError("failed-precondition", "Condivisione non disponibile");
        }

        const type = normalizeShareId(shareLink.type);
        source = {
          ownerId: normalizeShareId(shareLink.ownerId),
          resourceId: normalizeShareId(
              shareLink.resourceId ||
              resolveShareResourceId(type, shareLink.payload)
          ),
          type,
        };
      } else {
        throw new HttpsError("invalid-argument", "Condivisione mancante");
      }

      const result = await copySharedResourceFromSource({
        ...source,
        targetUserId,
        targetFolderId,
        targetParentFolderId,
      });

      if (sharedItemRef) {
        await sharedItemRef.delete();
      }
      if (shareLinkRef) {
        await shareLinkRef.set({
          importCount: admin.firestore.FieldValue.increment(1),
          lastImportedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      return {
        ok: true,
        type: source.type,
        ...result,
      };
    }
);

const shareFallbackMessage = (type) => type === "folder" ?
  "Hai ricevuto una cartella SaveIn! Scarica l'app gratis per importarla all'istante e avere tutte le nuove idee organizzate in un clic." :
  "C'è un contenuto SaveIn che ti aspetta! Scarica l'app gratis per aprirlo e salvarlo. Organizza le tue idee in un clic.";

const escapeHtml = (value) => value.toString().replace(/[<>&"]/g, (c) => ({
  "<": "&lt;",
  ">": "&gt;",
  "&": "&amp;",
  "\"": "&quot;",
}[c]));

exports.openShareLink = onRequest(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (req, res) => {
      const token = (req.path || "").split("/").filter(Boolean).pop() ||
        (req.query.token || "").toString();
      let type = "post";
      let title = "SaveIn";
      if (token) {
        try {
          const doc = await db.collection(SHARED_LINKS_COLLECTION).doc(token).get();
          if (doc.exists) {
            const data = doc.data() || {};
            type = data.type === "folder" ? "folder" : "post";
            title = data.title || title;
            await doc.ref.set({
              viewCount: admin.firestore.FieldValue.increment(1),
              lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        } catch (error) {
          console.error("Errore fallback share link", error);
        }
      }

      const message = shareFallbackMessage(type);
      res.set("Cache-Control", "no-cache,no-store,must-revalidate");
      res.status(200).send(`<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Apri con SaveIn</title>
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(message)}">
  <script>
    setTimeout(function(){ window.location.href = ${JSON.stringify(PLAY_STORE_URL)}; }, 1200);
  </script>
  <style>
    body{margin:0;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#D4FFEC;color:#10231a;display:grid;place-items:center;min-height:100vh;padding:24px}
    .card{max-width:520px;background:rgba(255,255,255,.92);border-radius:24px;padding:28px;box-shadow:0 18px 60px rgba(0,0,0,.14);text-align:center}
    h1{margin:0 0 12px;font-size:28px}
    p{font-size:17px;line-height:1.45;margin:0 0 22px}
    a{display:inline-block;background:#22c55e;color:#fff;text-decoration:none;font-weight:800;border-radius:14px;padding:14px 20px;margin:6px}
    small{display:block;margin-top:16px;color:#4b5563}
  </style>
</head>
<body>
  <main class="card">
    <h1>Apri con SaveIn!</h1>
    <p>${escapeHtml(message)}</p>
    <a href="${PLAY_STORE_URL}">Installa SaveIn gratis</a>
    ${APP_STORE_URL ? `<a href="${APP_STORE_URL}">Scarica su App Store</a>` : ""}
    <small>Dopo l'installazione, riapri lo stesso link dalla chat per importare il contenuto.</small>
  </main>
</body>
</html>`);
    }
);

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DASHBOARD
// ─────────────────────────────────────────────────────────────────────────────

const DASH_COOKIE = "__savein_dash";
const DASH_SESSION_MS = 14 * 24 * 60 * 60 * 1000; // 14 giorni
const FIREBASE_WEB_API_KEY = "AIzaSyDgHK8zKBpFy1dQZQ0_z0iNZ6Nr3j7ksPU";
const FIREBASE_AUTH_DOMAIN = "saveit-app-1784d.firebaseapp.com";
const FIREBASE_PROJECT_ID = "saveit-app-1784d";

const parseCookies = (header) => {
  if (!header) return {};
  return Object.fromEntries(
      (header.split(";") || []).map((c) => {
        const idx = c.indexOf("=");
        return [c.slice(0, idx).trim(), decodeURIComponent(c.slice(idx + 1).trim())];
      }),
  );
};

const dashVerifySession = async (sessionCookie) => {
  if (!sessionCookie) return null;
  try {
    const decoded = await admin.auth().verifySessionCookie(sessionCookie, true);
    const email = normalizeEmail(decoded.email || "");
    if (!email) return null;
    const doc = await db.collection("dashboard_accesses").doc(email).get();
    if (!doc.exists) return null;
    const data = doc.data();
    if (data.active === false) return null;
    if (!data.dashboardRole || data.dashboardRole === "none") return null;
    return {uid: decoded.uid, email, role: data.dashboardRole};
  } catch (_) {
    return null;
  }
};

const dashHtmlHead = (title) => `<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>${title}</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📌</text></svg>">
  <style>
    *{box-sizing:border-box}
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#f0f4f8;color:#1a202c}
    a{color:#2C7A7B;text-decoration:none}
    .btn{display:inline-flex;align-items:center;gap:6px;padding:10px 20px;border-radius:8px;font-size:14px;font-weight:700;border:none;cursor:pointer;transition:opacity .15s}
    .btn:hover{opacity:.88}
    .btn-primary{background:#2C7A7B;color:#fff}
    .card{background:#fff;border-radius:14px;padding:24px;box-shadow:0 2px 12px rgba(0,0,0,.07)}
    input{width:100%;padding:10px 12px;border:1.5px solid #E2E8F0;border-radius:8px;font-size:14px;outline:none;transition:border-color .2s}
    input:focus{border-color:#2C7A7B}
    label{display:block;font-size:13px;font-weight:600;color:#4A5568;margin-bottom:5px}
  </style>
</head>`;

const dashLoginPage = (err = "") => `${dashHtmlHead("SaveIn! Admin · Login")}
<body style="display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div class="card" style="width:100%;max-width:380px;">
    <div style="text-align:center;margin-bottom:28px;">
      <div style="font-size:44px;margin-bottom:8px;">📌</div>
      <h1 style="margin:0;font-size:22px;font-weight:800;">SaveIn! Admin</h1>
      <p style="margin:6px 0 0;color:#718096;font-size:14px;">Accesso riservato agli amministratori</p>
    </div>
    ${err ? `<div style="background:#FFF5F5;border:1px solid #FC8181;border-radius:8px;padding:10px 14px;color:#C53030;font-size:13px;margin-bottom:16px;">${err}</div>` : ""}
    <form id="frm">
      <div style="margin-bottom:14px;">
        <label>Email</label>
        <input id="em" type="email" required placeholder="admin@savein.eu"/>
      </div>
      <div style="margin-bottom:20px;">
        <label>Password</label>
        <input id="pw" type="password" required placeholder="••••••••"/>
      </div>
      <button type="submit" id="btn" class="btn btn-primary" style="width:100%;justify-content:center;">Accedi</button>
    </form>
    <p id="err" style="color:#C53030;font-size:13px;margin-top:12px;display:none;text-align:center;"></p>
  </div>
  <script type="module">
    import{initializeApp}from"https://www.gstatic.com/firebasejs/11.0.0/firebase-app.js";
    import{getAuth,signInWithEmailAndPassword}from"https://www.gstatic.com/firebasejs/11.0.0/firebase-auth.js";
    const app=initializeApp({apiKey:"${FIREBASE_WEB_API_KEY}",authDomain:"${FIREBASE_AUTH_DOMAIN}",projectId:"${FIREBASE_PROJECT_ID}"});
    const auth=getAuth(app);
    document.getElementById("frm").addEventListener("submit",async(e)=>{
      e.preventDefault();
      const btn=document.getElementById("btn");
      const errEl=document.getElementById("err");
      btn.disabled=true;btn.textContent="Accesso in corso…";errEl.style.display="none";
      try{
        const cred=await signInWithEmailAndPassword(auth,document.getElementById("em").value.trim(),document.getElementById("pw").value);
        const idToken=await cred.user.getIdToken();
        const r=await fetch("/dashboard/session",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({idToken})});
        if(r.ok){window.location.href="/dashboard";}
        else{const b=await r.json().catch(()=>({}));throw new Error(b.error||"Accesso negato");}
      }catch(ex){
        errEl.textContent=ex.code==="auth/invalid-credential"||ex.message?.includes("invalid-credential")?"Email o password non corretti.":(ex.message||"Errore durante il login.");
        errEl.style.display="block";btn.disabled=false;btn.textContent="Accedi";
      }
    });
  </script>
</body></html>`;

const dashPage = (user, stats, admins) => `${dashHtmlHead("SaveIn! Admin · Dashboard")}
<body>
  <nav style="background:#2C7A7B;color:#fff;padding:0 24px;display:flex;align-items:center;justify-content:space-between;height:56px;position:sticky;top:0;z-index:100;box-shadow:0 2px 8px rgba(0,0,0,.15);">
    <div style="font-weight:800;font-size:17px;display:flex;align-items:center;gap:10px;"><span>📌</span> SaveIn! Admin</div>
    <div style="display:flex;align-items:center;gap:16px;font-size:13px;">
      <span style="opacity:.85;">${escapeHtml(user.email)}</span>
      <a href="/dashboard/logout" style="background:rgba(255,255,255,.2);color:#fff;padding:5px 14px;border-radius:6px;font-weight:600;">Esci</a>
    </div>
  </nav>
  <div style="max-width:1100px;margin:32px auto;padding:0 20px;">
    <h2 style="margin:0 0 24px;font-size:24px;font-weight:800;">Panoramica</h2>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:32px;">
      ${[["👤","Utenti totali",stats.users],["⭐","Premium",stats.premium],["🆓","Free",stats.free],["📁","Cartelle",stats.folders]].map(([ic,lb,v])=>`
        <div class="card" style="display:flex;flex-direction:column;gap:4px;">
          <span style="font-size:26px;">${ic}</span>
          <span style="font-size:30px;font-weight:800;color:#2C7A7B;">${v!=null?v:"…"}</span>
          <span style="font-size:13px;color:#718096;font-weight:600;">${lb}</span>
        </div>`).join("")}
    </div>
    <div class="card" style="margin-bottom:24px;">
      <h3 style="margin:0 0 16px;font-size:16px;font-weight:800;">Amministratori Dashboard</h3>
      <table style="width:100%;border-collapse:collapse;font-size:14px;">
        <thead><tr style="border-bottom:2px solid #E2E8F0;">
          <th style="text-align:left;padding:8px 12px;color:#4A5568;">Email</th>
          <th style="text-align:left;padding:8px 12px;color:#4A5568;">Ruolo</th>
          <th style="text-align:left;padding:8px 12px;color:#4A5568;">Stato</th>
        </tr></thead>
        <tbody>
          ${admins.map((a)=>`<tr style="border-bottom:1px solid #EDF2F7;">
            <td style="padding:10px 12px;">${escapeHtml(a.email||a.id)}</td>
            <td style="padding:10px 12px;"><span style="background:#E6FFFA;color:#2C7A7B;padding:2px 8px;border-radius:20px;font-size:12px;font-weight:700;">${escapeHtml(a.role)}</span></td>
            <td style="padding:10px 12px;"><span style="color:${a.active===false?"#E53E3E":"#38A169"};font-size:13px;font-weight:600;">${a.active===false?"Disabilitato":"Attivo"}</span></td>
          </tr>`).join("")}
        </tbody>
      </table>
      <p style="margin-top:14px;font-size:13px;color:#718096;">Per aggiungere nuovi admin: crea un documento in Firestore nella collezione <code>dashboard_accesses</code> con ID = email, campo <code>dashboardRole: "admin"</code>.</p>
    </div>
  </div>
</body></html>`;

const dashLimitsPage = (user, featureRules) => {
  const features = [
    {id: "root_folders", name: "Cartelle nella Home"},
    {id: "child_folders", name: "Sottocartelle per cartella"},
    {id: "folder_levels", name: "Livelli di profondità"},
    {id: "share_folder", name: "Condivisione Cartella"},
    {id: "share_post", name: "Condivisione Post"},
    {id: "import_shared", name: "Importazione Contenuti"},
    {id: "reminders", name: "Reminder"},
  ];

  const periods = [
    {id: "total", name: "Totale"},
    {id: "day", name: "Giorno"},
    {id: "week", name: "Settimana"},
    {id: "month", name: "Mese"},
  ];

  return `${dashHtmlHead("SaveIn! Admin · Limiti Piani")}
<body>
  <nav style="background:#2C7A7B;color:#fff;padding:0 24px;display:flex;align-items:center;justify-content:space-between;height:56px;position:sticky;top:0;z-index:100;box-shadow:0 2px 8px rgba(0,0,0,.15);">
    <div style="display:flex;align-items:center;gap:24px;">
      <div style="font-weight:800;font-size:17px;display:flex;align-items:center;gap:10px;"><span>📌</span> SaveIn! Admin</div>
      <div style="display:flex;align-items:center;gap:16px;font-size:14px;font-weight:600;">
        <a href="/dashboard" style="color:#fff;opacity:.9;">Home</a>
        <a href="/dashboard/limits" style="color:#fff;opacity:.9;border-bottom:2px solid #fff;">Limiti Piani</a>
      </div>
    </div>
    <div style="display:flex;align-items:center;gap:16px;font-size:13px;">
      <span style="opacity:.85;">${escapeHtml(user.email)}</span>
      <a href="/dashboard/logout" style="background:rgba(255,255,255,.2);color:#fff;padding:5px 14px;border-radius:6px;font-weight:600;">Esci</a>
    </div>
  </nav>

  <div style="max-width:1100px;margin:32px auto;padding:0 20px;">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px;">
      <h2 style="margin:0;font-size:24px;font-weight:800;">Configurazione Limiti Piani</h2>
      <button type="button" onclick="saveLimits()" class="btn btn-primary">Salva Modifiche</button>
    </div>

    <div class="card" style="padding:0;overflow:hidden;">
      <table style="width:100%;border-collapse:collapse;font-size:14px;">
        <thead>
          <tr style="background:#F7FAFC;border-bottom:2px solid #E2E8F0;">
            <th style="text-align:left;padding:16px 20px;color:#4A5568;width:250px;">Funzionalità</th>
            <th style="text-align:center;padding:16px 20px;color:#4A5568;background:rgba(44,122,123,0.05);">Piano FREE</th>
            <th style="text-align:center;padding:16px 20px;color:#4A5568;background:rgba(44,122,123,0.1);">Piano PREMIUM</th>
          </tr>
        </thead>
        <tbody>
          ${features.map((f) => {
    const free = featureRules[f.id]?.free || {enabled: true, limit: 0, period: "total", requiresAd: false};
    const premium = featureRules[f.id]?.premium || {enabled: true, limit: 0, period: "total", requiresAd: false};
    return `
            <tr style="border-bottom:1px solid #EDF2F7;">
              <td style="padding:20px;font-weight:700;color:#2D3748;">
                ${f.name}
                <div style="font-size:11px;font-weight:400;color:#718096;margin-top:4px;">ID: ${f.id}</div>
              </td>
              <!-- FREE -->
              <td style="padding:20px;background:rgba(44,122,123,0.02);">
                <div style="display:flex;flex-direction:column;gap:12px;">
                  <label style="display:flex;align-items:center;gap:8px;margin:0;cursor:pointer;">
                    <input type="checkbox" data-feature="${f.id}" data-tier="free" data-field="enabled" ${free.enabled ? "checked" : ""} style="width:auto;">
                    Abilitato
                  </label>
                  <div>
                    <label>Limite (0 = illimitato)</label>
                    <input type="number" data-feature="${f.id}" data-tier="free" data-field="limit" value="${free.limit}" style="padding:6px 10px;">
                  </div>
                  <div>
                    <label>Periodo</label>
                    <select data-feature="${f.id}" data-tier="free" data-field="period" style="width:100%;padding:6px 10px;border-radius:8px;border:1.5px solid #E2E8F0;">
                      ${periods.map((p) => `<option value="${p.id}" ${free.period === p.id ? "selected" : ""}>${p.name}</option>`).join("")}
                    </select>
                  </div>
                  <label style="display:flex;align-items:center;gap:8px;margin:0;cursor:pointer;">
                    <input type="checkbox" data-feature="${f.id}" data-tier="free" data-field="requiresAd" ${free.requiresAd ? "checked" : ""} style="width:auto;">
                    Richiede Pubblicità
                  </label>
                </div>
              </td>
              <!-- PREMIUM -->
              <td style="padding:20px;background:rgba(44,122,123,0.05);">
                <div style="display:flex;flex-direction:column;gap:12px;">
                  <label style="display:flex;align-items:center;gap:8px;margin:0;cursor:pointer;">
                    <input type="checkbox" data-feature="${f.id}" data-tier="premium" data-field="enabled" ${premium.enabled ? "checked" : ""} style="width:auto;">
                    Abilitato
                  </label>
                  <div>
                    <label>Limite (0 = illimitato)</label>
                    <input type="number" data-feature="${f.id}" data-tier="premium" data-field="limit" value="${premium.limit}" style="padding:6px 10px;">
                  </div>
                  <div>
                    <label>Periodo</label>
                    <select data-feature="${f.id}" data-tier="premium" data-field="period" style="width:100%;padding:6px 10px;border-radius:8px;border:1.5px solid #E2E8F0;">
                      ${periods.map((p) => `<option value="${p.id}" ${premium.period === p.id ? "selected" : ""}>${p.name}</option>`).join("")}
                    </select>
                  </div>
                  <label style="display:flex;align-items:center;gap:8px;margin:0;cursor:pointer;">
                    <input type="checkbox" data-feature="${f.id}" data-tier="premium" data-field="requiresAd" ${premium.requiresAd ? "checked" : ""} style="width:auto;">
                    Richiede Pubblicità
                  </label>
                </div>
              </td>
            </tr>`;
  }).join("")}
        </tbody>
      </table>
    </div>
  </div>

  <script>
    async function saveLimits() {
      const rules = {};
      document.querySelectorAll("[data-feature]").forEach(el => {
        const feat = el.dataset.feature;
        const tier = el.dataset.tier;
        const field = el.dataset.field;
        
        if (!rules[feat]) rules[feat] = { free: {}, premium: {} };
        
        let val;
        if (el.type === "checkbox") val = el.checked;
        else if (el.type === "number") val = parseInt(el.value) || 0;
        else val = el.value;
        
        rules[feat][tier][field] = val;
      });

      try {
        const r = await fetch("/dashboard/limits", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ rules })
        });
        if (r.ok) alert("Limiti salvati con successo!");
        else alert("Errore durante il salvataggio.");
      } catch (e) {
        alert("Errore: " + e.message);
      }
    }
  </script>
</body></html>`;
};

exports.adminDashboard = onRequest(
    {
      region: "us-central1",
      timeoutSeconds: 30,
      memory: "256MiB",
    },
    async (req, res) => {
      const rawPath = (req.path || "/").replace(/\/+$/, "") || "/";
      const seg = rawPath.startsWith("/dashboard") ?
        rawPath.slice("/dashboard".length) || "/" :
        rawPath;
      const method = req.method.toUpperCase();
      const cookies = parseCookies(req.headers.cookie);

      // POST /session → verifica idToken, crea session cookie
      if (seg === "/session" && method === "POST") {
        try {
          const body = req.body || {};
          const idToken = body.idToken;
          if (!idToken) {
            res.status(400).json({error: "idToken mancante"});
            return;
          }
          const decoded = await admin.auth().verifyIdToken(idToken);
          const email = normalizeEmail(decoded.email || "");
          const doc = await db.collection("dashboard_accesses").doc(email).get();
          if (!doc.exists || doc.data().active === false || !doc.data().dashboardRole || doc.data().dashboardRole === "none") {
            res.status(403).json({error: "Accesso non autorizzato per questo account"});
            return;
          }
          const sessionCookie = await admin.auth().createSessionCookie(idToken, {expiresIn: DASH_SESSION_MS});
          res.setHeader("Set-Cookie", `${DASH_COOKIE}=${sessionCookie}; HttpOnly; Secure; SameSite=Strict; Max-Age=${DASH_SESSION_MS / 1000}; Path=/dashboard`);
          res.json({ok: true});
        } catch (e) {
          res.status(401).json({error: "Token non valido"});
        }
        return;
      }

      // GET /logout
      if (seg === "/logout" && method === "GET") {
        res.setHeader("Set-Cookie", `${DASH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Max-Age=0; Path=/dashboard`);
        res.redirect(302, "/dashboard/login");
        return;
      }

      // GET /login
      if (seg === "/login" && method === "GET") {
        res.setHeader("Content-Type", "text/html; charset=utf-8");
        res.send(dashLoginPage());
        return;
      }

      // Tutte le altre route: verifica sessione
      const user = await dashVerifySession(cookies[DASH_COOKIE]);
      if (!user) {
        res.redirect(302, "/dashboard/login");
        return;
      }

      // GET / → dashboard home
      if ((seg === "/" || seg === "") && method === "GET") {
        try {
          const [usersSnap, premiumSnap, foldersSnap, adminsSnap] = await Promise.all([
            db.collection("users").count().get(),
            db.collection("users").where("role", "==", "premium").count().get(),
            db.collection("folders").count().get(),
            db.collection("dashboard_accesses").get(),
          ]);
          const total = usersSnap.data().count;
          const prem = premiumSnap.data().count;
          const stats = {
            users: total,
            premium: prem,
            free: total - prem,
            folders: foldersSnap.data().count,
          };
          const admins = adminsSnap.docs.map((d) => ({
            id: d.id,
            email: d.data().email || d.id,
            role: d.data().dashboardRole || "admin",
            active: d.data().active,
          }));
          res.setHeader("Content-Type", "text/html; charset=utf-8");
          res.send(dashPage(user, stats, admins));
        } catch (e) {
          res.status(500).send("Errore interno: " + e.message);
        }
        return;
      }

      // GET /limits → configurazione limiti
      if (seg === "/limits" && method === "GET") {
        try {
          const limits = await _get_plan_limits();
          const featureRules = limits.featureRules || _default_feature_rules();
          res.setHeader("Content-Type", "text/html; charset=utf-8");
          res.send(dashLimitsPage(user, featureRules));
        } catch (e) {
          res.status(500).send("Errore interno: " + e.message);
        }
        return;
      }

      // POST /limits → salva configurazione limiti
      if (seg === "/limits" && method === "POST") {
        try {
          const body = req.body || {};
          const rules = body.rules;
          if (!rules) {
            res.status(400).json({error: "Dati mancanti"});
            return;
          }
          await db.doc(PLAN_LIMITS_DOC).set({
            featureRules: rules,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: user.email,
          }, {merge: true});
          res.json({ok: true});
        } catch (e) {
          res.status(500).json({error: e.message});
        }
        return;
      }

      res.status(404).send("Pagina non trovata");
    }
);

exports.assetLinks = onRequest(
    {
      region: "us-central1",
      timeoutSeconds: 10,
      memory: "256MiB",
      invoker: "public",
    },
    (req, res) => {
      res.set("Content-Type", "application/json");
      res.set("Cache-Control", "public,max-age=3600");
      res.status(200).send(JSON.stringify(ASSET_LINKS));
    }
);

const appStoreBilling = require("./app_store_billing");
Object.assign(
    exports,
    appStoreBilling.register({
      db,
      admin,
      onCall,
      onRequest,
      HttpsError,
      writeAccountHistory,
    }),
);

const legalContentPage = require("./legal_content_page");
Object.assign(exports, legalContentPage.register({onRequest}));

const googlePlayBilling = require("./google_play_billing");
Object.assign(
    exports,
    googlePlayBilling.register({
      db,
      admin,
      onCall,
      HttpsError,
      writeAccountHistory,
    }),
);