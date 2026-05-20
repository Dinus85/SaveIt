const functions = require("firebase-functions");
const functionsV1 = require("firebase-functions/v1");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Inizializza Firebase Admin
admin.initializeApp();

const db = admin.firestore();

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

const normalizeEmail = (email) => (email || "").toString().toLowerCase().trim();
const CROSS_PROMO_DURATION_DAYS = 30;
const CROSS_PROMO_CLAIM_WINDOW_DAYS = 14;
const PROMOTION_BANNERS_COLLECTION = "promotion_banners";
const PROMOTION_REDEMPTIONS_COLLECTION = "promotion_redemptions";
const PROMOTION_EVENTS_COLLECTION = "promotion_banner_events";
const SAVEIN_SMARTCHEF_PROMO_ID = "savein_smartchef_launch";

const addDays = (date, days) => {
  const copy = new Date(date.getTime());
  copy.setDate(copy.getDate() + days);
  return copy;
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

const promotionBannerResponse = (promo) => ({
  id: promo.id,
  type: (promo.type || "generic_promo").toString(),
  title: (promo.title || "").toString(),
  message: (promo.message || "").toString(),
  ctaLabel: (promo.ctaLabel || "Scopri").toString(),
  secondaryCtaLabel: (promo.secondaryCtaLabel || "").toString(),
  action: (promo.action || "open_url").toString(),
  actionUrl: (promo.actionUrl || "").toString(),
  targetApp: (promo.targetApp || "").toString(),
  priority: Number(promo.priority || 0),
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
  const candidates = [];
  for (const doc of snap.docs) {
    const promo = {id: doc.id, ...doc.data()};
    if (!promotionMatchesApp(promo, "savein")) continue;
    if (!isPromotionInWindow(promo)) continue;
    const oncePerUser = promo.oncePerUser !== false;
    const direction = promo.direction || (promo.id === SAVEIN_SMARTCHEF_PROMO_ID ? "savein_to_smartchef" : "");
    if (oncePerUser) {
      const usable = await isPromotionUsableForUser({email, promotionId: promo.id, direction});
      if (!usable) continue;
    }
    candidates.push(promo);
  }

  candidates.sort((a, b) => Number(b.priority || 0) - Number(a.priority || 0));
  return {banner: candidates.length ? promotionBannerResponse(candidates[0]) : null};
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
      const premiumUntil = addDays(now, CROSS_PROMO_DURATION_DAYS);
      const claimBy = addDays(now, CROSS_PROMO_CLAIM_WINDOW_DAYS);
      const promoId = `${email}|savein_to_smartchef`;
      const userRef = db.collection("users").doc(auth.uid);
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

        transaction.set(userRef, {
          role: "premium",
          premiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
          premiumSource: "cross_promo_savein_to_smartchef",
          roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          roleUpdatedBy: "cross_promo_savein_to_smartchef",
          email,
          normalizedEmail: email,
        }, {merge: true});

        transaction.set(promoRef, {
          email,
          normalizedEmail: email,
          sourceApp: "savein",
          targetApp: "smartchef",
          status: "pending",
          sourceUid: auth.uid,
          durationDays: CROSS_PROMO_DURATION_DAYS,
          claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
          saveinActivatedAt: admin.firestore.Timestamp.fromDate(now),
          saveinPremiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
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
          premiumUntil: admin.firestore.Timestamp.fromDate(premiumUntil),
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
          durationDays: CROSS_PROMO_DURATION_DAYS,
          claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
          saveinActivatedAt: now.toISOString(),
          saveinPremiumUntil: premiumUntil.toISOString(),
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
          premiumUntil: premiumUntil.toISOString(),
          claimBy: claimBy.toISOString(),
        },
      });

      return {
        success: true,
        status: "pending",
        targetApp: "smartchef",
        durationDays: CROSS_PROMO_DURATION_DAYS,
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

  await db.collection("cross_app_promos").doc(promoId).set({
    status: "claimed",
    smartchefUid: (body.smartchefUid || "").toString(),
    smartchefClaimedAt: body.smartchefClaimedAt ?
      admin.firestore.Timestamp.fromDate(new Date(body.smartchefClaimedAt)) :
      admin.firestore.FieldValue.serverTimestamp(),
    smartchefPremiumUntil: smartchefPremiumUntil && !Number.isNaN(smartchefPremiumUntil.getTime()) ?
      admin.firestore.Timestamp.fromDate(smartchefPremiumUntil) :
      null,
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
    durationDays: CROSS_PROMO_DURATION_DAYS,
    claimWindowDays: CROSS_PROMO_CLAIM_WINDOW_DAYS,
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
      const premiumUntil = addDays(now, CROSS_PROMO_DURATION_DAYS);
      const promoId = `${email}|smartchef_to_savein`;
      const promoRef = db.collection("cross_app_promos").doc(promoId);
      const userRef = db.collection("users").doc(auth.uid);
      let claimed = false;
      let reason = "not_found";
      let claimBy = null;

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
      });

      if (claimed) {
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
              saveinPremiumUntil: premiumUntil.toISOString(),
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
            premiumUntil: premiumUntil.toISOString(),
          },
        });
      }

      return {
        success: true,
        claimed,
        reason,
        sourceApp: "smartchef",
        targetApp: "savein",
        durationDays: CROSS_PROMO_DURATION_DAYS,
        premiumUntil: claimed ? premiumUntil.toISOString() : null,
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

      const now = admin.firestore.FieldValue.serverTimestamp();
      const senderEmail = auth.token.email || "";
      const campaignRef = db.collection("notification_campaigns").doc();
      const batch = db.batch();

      batch.set(campaignRef, {
        title,
        body,
        userIds,
        sendInApp,
        sendPush,
        senderId: auth.uid,
        senderEmail,
        createdAt: now,
        status: "sending",
      });

      if (sendInApp) {
        for (const userId of userIds) {
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
          });
        }
      }

      await batch.commit();

      let tokenCount = 0;
      let pushSuccessCount = 0;
      let pushFailureCount = 0;

      if (sendPush) {
        for (const userId of userIds) {
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
      }, {merge: true});

      await db.collection("admin_logs").add({
        action: "notification_sent",
        actorId: auth.uid,
        actorEmail: senderEmail,
        targetUserId: userIds.join(","),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: {
          campaignId: campaignRef.id,
          recipients: userIds.length,
          sendInApp,
          sendPush,
          tokenCount,
          pushSuccessCount,
          pushFailureCount,
        },
      });

      return {
        success: true,
        campaignId: campaignRef.id,
        recipients: userIds.length,
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
      const chunkSize = 10;
      for (let i = 0; i < userIds.length; i += chunkSize) {
        const chunk = userIds.slice(i, i + chunkSize);
        const snapshot = await db.collection("users")
            .where(admin.firestore.FieldPath.documentId(), "in", chunk)
            .get();
        snapshot.forEach((doc) => {
          const email = doc.data()?.email;
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
        failedEmails: failedEmails.slice(0, 10), // max 10 in risposta
      };
    }
);