const AUTH_PASSWORD = "artiebatlama18";
const AUTH_ERROR_MESSAGE = "Giriş sırasında bir hata oluştu. Şifreyi kontrol et ve tekrar dene.";
const SESSION_STORAGE_KEY = "siparis_session";

const state = {
  database: null,
  filtered: [],
  currentPage: 1,
  pageSize: 20,
  appReady: false,
  session: null
};

const elements = {
  authScreen: document.getElementById("authScreen"),
  loginForm: document.getElementById("loginForm"),
  passwordInput: document.getElementById("passwordInput"),
  authError: document.getElementById("authError"),
  appShell: document.getElementById("appShell"),
  searchInput: document.getElementById("searchInput"),
  resultsBody: document.getElementById("resultsBody"),
  resultLabel: document.getElementById("resultLabel"),
  pager: document.getElementById("pager"),
  totalRecords: document.getElementById("totalRecords"),
  totalFiles: document.getElementById("totalFiles"),
  matchedRecords: document.getElementById("matchedRecords"),
  lastUpdated: document.getElementById("lastUpdated")
};

bootstrap().catch((error) => {
  console.error(error);
  if (elements.resultsBody) {
    elements.resultsBody.innerHTML = `<tr><td colspan="6" class="empty">Canlı veri yüklenemedi. GitHub veri dosyasını kontrol et.</td></tr>`;
  }
  if (elements.resultLabel) {
    elements.resultLabel.textContent = "Canlı veri kaynağı okunamadı.";
  }
});

async function bootstrap() {
  setupAuth();

  state.session = loadStoredSession();
  if (state.session?.unlocked) {
    unlockApp();
    await startApp();
    return;
  }

  lockApp();
  setAuthError("");
  elements.passwordInput?.focus();
}

function setupAuth() {
  elements.loginForm?.addEventListener("submit", handleLogin);
}

async function handleLogin(event) {
  event.preventDefault();

  const password = String(elements.passwordInput?.value ?? "");
  if (!password) {
    setAuthError("Şifre gir.");
    return;
  }

  setAuthError("");

  if (password !== AUTH_PASSWORD) {
    setAuthError("Şifre yanlış.");
    elements.passwordInput?.focus();
    elements.passwordInput?.select?.();
    return;
  }

  state.session = { unlocked: true };
  saveStoredSession(state.session);
  unlockApp();
  await startApp();
}

function setAuthError(message) {
  if (elements.authError) {
    elements.authError.textContent = message;
  }
}

function lockApp() {
  document.body.classList.remove("authenticated");
  document.body.classList.add("auth-locked");
  if (elements.authScreen) {
    elements.authScreen.hidden = false;
  }
  if (elements.appShell) {
    elements.appShell.hidden = true;
  }
}

function unlockApp() {
  document.body.classList.add("authenticated");
  document.body.classList.remove("auth-locked");
  if (elements.authScreen) {
    elements.authScreen.hidden = true;
  }
  if (elements.appShell) {
    elements.appShell.hidden = false;
  }
}

function loadStoredSession() {
  try {
    const raw = sessionStorage.getItem(SESSION_STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (error) {
    return null;
  }
}

function saveStoredSession(session) {
  try {
    sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
  } catch (error) {
    console.warn("Session kaydedilemedi.", error);
  }
}

async function startApp() {
  if (state.appReady) {
    return;
  }

  state.appReady = true;
  state.database = await loadDatabase();
  state.filtered = sortRecords(state.database.records ?? []);

  renderSummary();
  renderResults();

  elements.searchInput?.addEventListener("input", () => {
    filterAndRender(elements.searchInput.value);
  });
}

async function loadDatabase() {
  const embeddedDatabase = loadEmbeddedDatabase();
  if (embeddedDatabase && Array.isArray(embeddedDatabase.records) && embeddedDatabase.records.length) {
    return embeddedDatabase;
  }

  const localDatabase = await loadDatabaseTxt();
  if (localDatabase && Array.isArray(localDatabase.records) && localDatabase.records.length) {
    return localDatabase;
  }

  return emptyDatabase();
}

function emptyDatabase() {
  return {
    generatedAt: new Date().toISOString(),
    cutoffDate: "",
    totalRecords: 0,
    totalFiles: 0,
    records: []
  };
}

function loadEmbeddedDatabase() {
  const text = window.LOCAL_DATABASE_TEXT;
  if (!text || typeof text !== "string" || !text.trim()) {
    return null;
  }

  try {
    return coerceDatabase(JSON.parse(text));
  } catch (error) {
    console.warn("Embedded database okunamadi.", error);
    return null;
  }
}

async function loadDatabaseTxt() {
  try {
    const response = await fetch("data/database.txt", { cache: "no-store" });
    if (!response.ok) {
      return null;
    }
    const text = await response.text();
    if (!text.trim()) {
      return null;
    }
    return coerceDatabase(JSON.parse(text));
  } catch (error) {
    console.warn("database.txt okunamadi.", error);
    return null;
  }
}

function coerceDatabase(parsed) {
  if (!parsed || typeof parsed !== "object") {
    return null;
  }

  const records = Array.isArray(parsed.records) ? parsed.records : [];
  return {
    generatedAt: parsed.generatedAt ?? new Date().toISOString(),
    cutoffDate: parsed.cutoffDate ?? "",
    totalRecords: Number(parsed.totalRecords ?? records.length),
    totalFiles: Number(parsed.totalFiles ?? 0),
    records
  };
}

function renderSummary() {
  const { totalRecords = 0, totalFiles = 0 } = state.database;
  elements.totalRecords.textContent = formatCount(totalRecords);
  elements.totalFiles.textContent = formatCount(totalFiles);
  elements.matchedRecords.textContent = formatCount(state.filtered.length);
  if (elements.lastUpdated) {
    elements.lastUpdated.textContent = formatDateTime(state.database.generatedAt);
  }
}

function filterAndRender(query) {
  const normalizedQuery = normalize(query);
  const allRecords = sortRecords(state.database.records ?? []);

  state.filtered = normalizedQuery
    ? allRecords.filter((record) => {
        const haystack = normalize(buildSearchText(record));
        return haystack.includes(normalizedQuery);
      })
    : allRecords;

  state.currentPage = 1;
  renderSummary();
  renderResults(query);
}

function renderResults(query = "") {
  if (!elements.resultsBody) {
    return;
  }

  const total = state.filtered.length;
  const pageSize = state.pageSize;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const currentPage = Math.min(Math.max(state.currentPage, 1), totalPages);
  state.currentPage = currentPage;

  const startIndex = (currentPage - 1) * pageSize;
  const pageRecords = state.filtered.slice(startIndex, startIndex + pageSize);

  if (!total) {
    const message = query ? `"${query}" için sonuç bulunamadı.` : "Henüz içe aktarılmış kayıt yok.";
    elements.resultLabel.textContent = message;
    elements.resultsBody.innerHTML = `<tr><td colspan="6" class="empty">${escapeHtml(message)}</td></tr>`;
    renderPager(0, 0);
    return;
  }

  const suffix = query ? ` "${query}" için ${total} sonuç bulundu.` : ` Toplam ${total} sonuç listeleniyor.`;
  elements.resultLabel.textContent = `En güncel kayıtlar gösteriliyor.${suffix}`;
  elements.resultsBody.innerHTML = pageRecords.map((record) => renderRow(record)).join("");
  renderPager(total, totalPages);
}

function renderPager(total, totalPages) {
  if (!elements.pager) {
    return;
  }

  if (!total) {
    elements.pager.innerHTML = "";
    return;
  }

  const currentPage = state.currentPage;
  const start = (currentPage - 1) * state.pageSize + 1;
  const end = Math.min(currentPage * state.pageSize, total);
  elements.pager.innerHTML = `
    <button class="pager-btn pager-btn-left" data-action="prev" ${currentPage <= 1 ? "disabled" : ""}>Önceki</button>
    <span class="pager-info">${formatCount(total)} kayıttan ${start}-${end} arası gösteriliyor</span>
    <button class="pager-btn pager-btn-right" data-action="next" ${currentPage >= totalPages ? "disabled" : ""}>Sonraki</button>
  `;

  elements.pager.querySelectorAll(".pager-btn").forEach((button) => {
    button.addEventListener("click", () => {
      const action = button.dataset.action;
      if (action === "prev" && state.currentPage > 1) {
        state.currentPage -= 1;
      } else if (action === "next" && state.currentPage < totalPages) {
        state.currentPage += 1;
      }
      renderResults(elements.searchInput?.value ?? "");
    });
  });
}

function renderRow(record) {
  const cutStatus = String(record.cutStatus || "Bilinmiyor").toLowerCase();
  const cutClass = cutStatus.includes("kesildi") ? "done" : cutStatus.includes("kesilmedi") ? "waiting" : "unknown";
  const date = formatDate(record.orderDate);
  return `
    <tr>
      <td>${escapeHtml(date)}</td>
      <td>${escapeHtml(displayFileName(record.sourceFile))}</td>
      <td>${escapeHtml(buildMaterialDisplay(record))}</td>
      <td><span class="badge ${cutClass}">${escapeHtml(record.cutStatus || "Bilinmiyor")}</span></td>
      <td>${escapeHtml(record.opt || getCellValue(record.cellHighlights, "D12") || record.color || "-")}</td>
      <td>${formatRangeNotes(record.rangeNotes)}</td>
    </tr>
  `;
}

function displayFileName(value) {
  return String(value ?? "").replace(/\.xlsm$/i, "");
}

function getCellValue(items, cellName) {
  const list = normalizeList(items);
  const found = list.find((item) => item && typeof item === "object" && String(item.cell ?? "") === cellName);
  return found?.value ?? "-";
}

function buildPlakaValue(items) {
  const c46 = getCellValue(items, "C46");
  const d15 = getCellValue(items, "D15");
  const parts = [];
  if (c46 && c46 !== "-") parts.push(c46);
  if (d15 && d15 !== "-") parts.push(d15);
  return parts.length ? parts.join(" ") : "-";
}

function buildMaterialDisplay(record) {
  const material = String(record.material || getCellValue(record.cellHighlights, "A15") || "-").trim();
  const quantity = record.quantity ?? getCellValue(record.cellHighlights, "C46");
  const quantityText = String(quantity ?? "").trim();
  if (quantityText && material && material !== "-") {
    return `${quantityText} PLK ${material}`;
  }
  return material || "-";
}

function buildSearchText(record) {
  return [
    record.customerName,
    record.material,
    record.color,
    record.pvcMeters,
    record.quantity,
    record.cutStatus,
    record.notes,
    record.opt,
    record.plaka,
    record.orderDate,
    record.sourceFile,
    record.sheetName,
    record.sourceRow,
    record.jobCode,
    record.d5,
    buildMaterialDisplay(record),
    textifyItems(record.cellHighlights),
    textifyItems(record.rangeNotes)
  ].join(" ");
}

function extractPvcMeters(primaryValue, items, plakaValue) {
  const directValue = parseNumericValue(primaryValue);
  if (Number.isFinite(directValue)) {
    return directValue;
  }

  const fromHighlights = parseNumericValue(getCellValue(items, "C53")) ?? parseMetersFromText(getCellValue(items, "C53"));
  if (Number.isFinite(fromHighlights) && fromHighlights > 0) {
    return fromHighlights;
  }

  return null;
}

function parseMetersFromText(value) {
  const text = String(value ?? "");
  const match = text.match(/(\d+(?:[.,]\d+)?)\s*M\b/i);
  if (!match) return null;
  return parseNumericValue(match[1]);
}

function parseNumericValue(value) {
  if (value == null || value === "") return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const text = String(value).replace(",", ".").trim();
  const num = Number(text);
  return Number.isFinite(num) ? num : null;
}

function sortRecords(records) {
  return [...records].sort((left, right) => {
    const rightTime = new Date(right.orderDate ?? 0).getTime();
    const leftTime = new Date(left.orderDate ?? 0).getTime();
    if (rightTime !== leftTime) return rightTime - leftTime;
    return String(right.sourceFile ?? "").localeCompare(String(left.sourceFile ?? ""), "tr-TR");
  });
}

function formatRangeNotes(items) {
  const list = normalizeList(items).filter((item) => {
    if (typeof item === "string") {
      return isMeaningfulNoteValue(item);
    }
    if (!item || typeof item !== "object") {
      return false;
    }
    return isMeaningfulNoteValue(item.value);
  });
  if (!list.length) return "<span class='muted'>-</span>";
  return `<div class="cell-list">${list
    .map((item) => {
      if (typeof item === "string") {
        return `<div>${escapeHtml(item)}</div>`;
      }
      const value = escapeHtml(item.value ?? "");
      return `<div>${value}</div>`;
    })
    .join("")}</div>`;
}

function normalizeList(items) {
  if (!items) return [];
  return Array.isArray(items) ? items : [items];
}

function isMeaningfulNoteValue(value) {
  const text = String(value ?? "").trim();
  if (!text || text === "-") return false;
  const letters = text.replace(/[^A-Za-zÇĞİÖŞÜçğıöşü]/g, "");
  return letters.length >= 2;
}

function textifyItems(items) {
  return normalizeList(items)
    .map((item) => {
      if (typeof item === "string") return item;
      if (!item || typeof item !== "object") return "";
      return [item.cell, item.label, item.value].filter(Boolean).join(" ");
    })
    .join(" ");
}

function normalize(value) {
  return String(value ?? "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function formatDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("tr-TR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).format(date);
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("tr-TR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatNumber(value) {
  if (value === null || value === undefined || value === "") return "-";
  return new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 2 }).format(value);
}

function formatCount(value) {
  return new Intl.NumberFormat("tr-TR").format(value ?? 0);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
