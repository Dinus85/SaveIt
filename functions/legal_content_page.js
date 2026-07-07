// Pagine pubbliche /privacy e /terms: stesse sorgenti GitHub usate dall'app.
const LEGAL_CONTENT_BASE_URL =
  "https://raw.githubusercontent.com/Dinus85/saveit-legal-content/main";

const PRIVACY_POLICY_URL = `${LEGAL_CONTENT_BASE_URL}/privacy_policy.json`;
const TERMS_CONDITIONS_URL = `${LEGAL_CONTENT_BASE_URL}/terms_conditions.json`;

const CACHE_TTL_MS = 5 * 60 * 1000;
let cachedPrivacy = null;
let cachedPrivacyAt = 0;
let cachedTerms = null;
let cachedTermsAt = 0;

const escapeHtml = (value) =>
  String(value ?? "").replace(/[<>&"]/g, (c) => ({
    "<": "&lt;",
    ">": "&gt;",
    "&": "&amp;",
    '"': "&quot;",
  }[c]));

const formatInlineMarkdown = (text) => {
  let html = escapeHtml(text);
  html = html.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  html = html.replace(
      /\[([^\]]+)\]\(([^)]+)\)/g,
      (_match, label, url) =>
        `<a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`,
  );
  return html;
};

const markdownToHtml = (markdown) => {
  const lines = String(markdown || "").replace(/\r\n/g, "\n").split("\n");
  const parts = [];
  let inList = false;

  const closeList = () => {
    if (inList) {
      parts.push("</ul>");
      inList = false;
    }
  };

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    const trimmed = line.trim();

    if (!trimmed) {
      closeList();
      continue;
    }

    if (trimmed === "---") {
      closeList();
      parts.push("<hr>");
      continue;
    }

    if (trimmed.startsWith("### ")) {
      closeList();
      parts.push(`<h3>${formatInlineMarkdown(trimmed.slice(4))}</h3>`);
      continue;
    }

    if (trimmed.startsWith("## ")) {
      closeList();
      parts.push(`<h2>${formatInlineMarkdown(trimmed.slice(3))}</h2>`);
      continue;
    }

    if (trimmed.startsWith("# ")) {
      closeList();
      parts.push(`<h1>${formatInlineMarkdown(trimmed.slice(2))}</h1>`);
      continue;
    }

    if (trimmed.startsWith("- ")) {
      if (!inList) {
        parts.push("<ul>");
        inList = true;
      }
      parts.push(`<li>${formatInlineMarkdown(trimmed.slice(2))}</li>`);
      continue;
    }

    closeList();
    parts.push(`<p>${formatInlineMarkdown(trimmed)}</p>`);
  }

  closeList();
  return parts.join("\n");
};

const formatDisplayDate = (isoDate) => {
  if (!isoDate) return "N/A";
  const parsed = new Date(isoDate);
  if (Number.isNaN(parsed.getTime())) return isoDate;
  return parsed.toLocaleDateString("it-IT", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
};

const fetchPrivacyPolicy = async () => {
  const now = Date.now();
  if (cachedPrivacy && now - cachedPrivacyAt < CACHE_TTL_MS) {
    return cachedPrivacy;
  }

  const response = await fetch(PRIVACY_POLICY_URL, {
    headers: {"Accept": "application/json"},
  });
  if (!response.ok) {
    throw new Error(`GitHub privacy_policy.json HTTP ${response.status}`);
  }

  const data = await response.json();
  if (!data || typeof data.content !== "string") {
    throw new Error("privacy_policy.json non valido");
  }

  cachedPrivacy = data;
  cachedPrivacyAt = now;
  return data;
};

const fetchTermsConditions = async () => {
  const now = Date.now();
  if (cachedTerms && now - cachedTermsAt < CACHE_TTL_MS) {
    return cachedTerms;
  }

  const response = await fetch(TERMS_CONDITIONS_URL, {
    headers: {"Accept": "application/json"},
  });
  if (!response.ok) {
    throw new Error(`GitHub terms_conditions.json HTTP ${response.status}`);
  }

  const data = await response.json();
  if (!data || typeof data.content !== "string") {
    throw new Error("terms_conditions.json non valido");
  }

  cachedTerms = data;
  cachedTermsAt = now;
  return data;
};

const renderPrivacyHtml = (data) => {
  const title = data.title || "Privacy Policy";
  const version = data.version || "N/A";
  const updated = formatDisplayDate(data.lastUpdated);
  const bodyHtml = markdownToHtml(data.content);

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)} – SaveIn!</title>
  <meta name="description" content="Informativa sulla privacy di SaveIn!">
  <style>
    body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 24px 16px; color: #333; line-height: 1.7; }
    h1 { color: #1a1a2e; font-size: 28px; margin-bottom: 4px; }
    h2 { color: #1a1a2e; font-size: 18px; margin-top: 32px; }
    h3 { color: #333; font-size: 15px; margin-top: 20px; }
    .meta { color: #888; font-size: 13px; margin-bottom: 32px; }
    a { color: #1a1a2e; }
    hr { border: none; border-top: 1px solid #e0e0e0; margin: 40px 0; }
    ul { padding-left: 20px; }
    li { margin-bottom: 6px; }
    .footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid #e0e0e0; color: #888; font-size: 12px; }
  </style>
</head>
<body>
  <p class="meta">Ultimo aggiornamento: ${escapeHtml(updated)} &nbsp;·&nbsp; Versione ${escapeHtml(version)}</p>
  ${bodyHtml}
  <p class="footer">© SaveIn! · Contenuto sincronizzato da GitHub · <a href="https://savein.eu">savein.eu</a></p>
</body>
</html>`;
};

const renderErrorHtml = (message, sourceUrl = PRIVACY_POLICY_URL) => `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Privacy Policy – SaveIn!</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 720px; margin: 40px auto; padding: 0 16px; color: #333; line-height: 1.6; }
    a { color: #1a1a2e; }
  </style>
</head>
<body>
  <h1>Privacy Policy – SaveIn!</h1>
  <p>Impossibile caricare l'informativa in questo momento.</p>
  <p>${escapeHtml(message)}</p>
  <p><a href="${sourceUrl}">Apri sorgente GitHub</a></p>
</body>
</html>`;

const register = ({onRequest}) => {
  const renderPrivacyPage = onRequest(
      {
        region: "us-central1",
        timeoutSeconds: 15,
        memory: "256MiB",
        invoker: "public",
      },
      async (_req, res) => {
        try {
          const data = await fetchPrivacyPolicy();
          res.set("Content-Type", "text/html; charset=utf-8");
          res.set("Cache-Control", "public, max-age=300, s-maxage=300");
          res.status(200).send(renderPrivacyHtml(data));
        } catch (error) {
          console.error("renderPrivacyPage", error);
          res.set("Content-Type", "text/html; charset=utf-8");
          res.set("Cache-Control", "no-cache,no-store,must-revalidate");
          res.status(503).send(renderErrorHtml(error.message || "Errore sconosciuto"));
        }
      },
  );

  const renderTermsPage = onRequest(
      {
        region: "us-central1",
        timeoutSeconds: 15,
        memory: "256MiB",
        invoker: "public",
      },
      async (_req, res) => {
        try {
          const data = await fetchTermsConditions();
          res.set("Content-Type", "text/html; charset=utf-8");
          res.set("Cache-Control", "public, max-age=300, s-maxage=300");
          res.status(200).send(renderPrivacyHtml(data));
        } catch (error) {
          console.error("renderTermsPage", error);
          res.set("Content-Type", "text/html; charset=utf-8");
          res.set("Cache-Control", "no-cache,no-store,must-revalidate");
          res.status(503).send(renderErrorHtml(
              error.message || "Errore sconosciuto",
              TERMS_CONDITIONS_URL,
          ));
        }
      },
  );

  return {renderPrivacyPage, renderTermsPage};
};

module.exports = {
  register,
  LEGAL_CONTENT_BASE_URL,
  PRIVACY_POLICY_URL,
  TERMS_CONDITIONS_URL,
};
