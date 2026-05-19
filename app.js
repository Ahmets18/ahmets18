const AUTH_EMAIL = "artiebatlama18@local.invalid";
const AUTH_CONFIRM_MESSAGE = "Supabase Authentication ayarlarında e-posta onayı kapalı olmalı.";
const SESSION_STORAGE_KEY = "siparis_supabase_session";
const SUPABASE_CONFIG = {
  url: "https://svhmejuufiwqtwhlvxzc.supabase.co",
  anonKey: "sb_publishable_A7kHP4ezS8WZmabvGIKtDQ_6e0kt1WN",
  table: "orders"
};

const state = {
  database: null,
  filtered: [],
  currentPage: 1,
  pageSize: 10,
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
  matchedRecords: document.getElementById("matchedRecords")
};

bootstrap().catch((error) => {
  console.error(error);
  if (elements.resultsBody) {
    elements.resultsBody.innerHTML = `<tr><td colspan="8" class="empty">Canlı veri yüklenemedi. Supabase bağlantısını kontrol et.</td></tr>`;
  }
  if (elements.resultLabel) {
    elements.resultLabel.textContent = "Canlı veri kaynağı okunamadı.";
  }
});

async function bootstrap() {
  setupAuth();

  state.session = loadStoredSession();
  if (state.session?.access_token) {
    const valid = await verifySession(state.session.access_token);
    if (valid) {
      unlockApp();
      await startApp();
      return;
    }
    clearStoredSession();
    state.session = null;
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

  if (!SUPABASE_CONFIG.url || !SUPABASE_CONFIG.anonKey) {
    setAuthError("Supabase bağlantısı bulunamadı.");
    return;
  }

  setAuthError("");

  try {
    let session = await signInWithSupabase(password);
    if (!session) {
      session = await signUpWithSupabase(password);
    }
    if (!session) {
      setAuthError("Şifre yanlış.");
      elements.passwordInput?.focus();
      elements.passwordInput?.select?.();
      return;
    }

    state.session = session;
    saveStoredSession(session);
    unlockApp();
    await startApp();
  } catch (error) {
    console.error(error);
    setAuthError(AUTH_CONFIRM_MESSAGE);
  }
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

  const supabaseDatabase = await loadSupabaseDatabase();
  if (supabaseDatabase && Array.isArray(supabaseDatabase.records) && supabaseDatabase.records.length) {
    return supabaseDatabase;
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

function loadStoredSession() {
  try {
    const raw = sessionStorage.getItem(SESSION_STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (error) {
    console.warn("Stored session okunamadi.", error);
    return null;
  }
}

function saveStoredSession(session) {
  sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
}

function clearStoredSession() {
  sessionStorage.removeItem(SESSION_STORAGE_KEY);
}

async function signInWithSupabase(password) {
  const response = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_CONFIG.anonKey,
      Authorization: `Bearer ${SUPABASE_CONFIG.anonKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ email: AUTH_EMAIL, password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    return null;
  }

  return {
    access_token: payload.access_token,
    refresh_token: payload.refresh_token,
    expires_at: payload.expires_at,
    token_type: payload.token_type,
    user: payload.user ?? null
  };
}

async function signUpWithSupabase(password) {
  const response = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/signup`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_CONFIG.anonKey,
      Authorization: `Bearer ${SUPABASE_CONFIG.anonKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ email: AUTH_EMAIL, password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    return null;
  }

  const session = payload.session ?? payload.data?.session ?? null;
  if (!session?.access_token) {
    return null;
  }

  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    token_type: session.token_type,
    user: session.user ?? payload.user ?? null
  };
}

async function verifySession(accessToken) {
  try {
    const response = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/user`, {
      headers: {
        apikey: SUPABASE_CONFIG.anonKey,
        Authorization: `Bearer ${accessToken}`
      }
    });
    return response.ok;
  } catch (error) {
    console.warn("Session doğrulanamadı.", error);
    return false;
  }
}

function loadEmbeddedDatabase() {
  const text = window.LOCAL_DATABASE_TEXT;
  if (!text || typeof text !== "string" || !text.trim()) {
    return null;
  }

  try {
    const parsed = JSON.parse(text);
    const records = Array.isArray(parsed.records) ? parsed.records : [];
    return {
      generatedAt: parsed.generatedAt ?? new Date().toISOString(),
      cutoffDate: parsed.cutoffDate ?? "",
      totalRecords: Number(parsed.totalRecords ?? records.length),
      totalFiles: Number(parsed.totalFiles ?? 0),
      records
    };
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
    const parsed = JSON.parse(text);
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
  } catch (error) {
    console.warn("database.txt okunamadi.", error);
    return null;
  }
}

async function loadSupabaseDatabase() {
  if (!SUPABASE_CONFIG.url || !SUPABASE_CONFIG.anonKey || !state.session?.access_token || !SUPABASE_CONFIG.table) {
    return null;
  }

  try {
    const response = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/${SUPABASE_CONFIG.table}?select=*`, {
      headers: {
        apikey: SUPABASE_CONFIG.anonKey,
        Authorization: `Bearer ${state.session.access_token}`,
        Accept: "application/json"
      },
      cache: "no-store"
    });

    if (!response.ok) {
      return null;
    }

    const rows = await response.json().catch(() => []);
    if (!Array.isArray(rows) || !rows.length) {
      return emptyDatabase();
    }

    return buildDatabaseFromRows(rows);
  } catch (error) {
    console.warn("Supabase verisi okunamadi.", error);
    return null;
  }
}

function buildDatabaseFromRows(rows) {
  const records = rows.map(normalizeSupabaseRow).filter(Boolean);
  const totalFiles = new Set(records.map((record) => record.sourceFile).filter(Boolean)).size;
  const orderDates = records
    .map((record) => new Date(record.orderDate ?? 0).getTime())
    .filter((value) => Number.isFinite(value) && value > 0);
  const generatedAt = orderDates.length ? new Date(Math.max(...orderDates)).toISOString() : new Date().toISOString();
  const cutoffDate = orderDates.length ? new Date(Math.min(...orderDates)).toISOString() : "";

  return {
    generatedAt,
    cutoffDate,
    totalRecords: records.length,
    totalFiles,
    records
  };
}

function normalizeSupabaseRow(row) {
  if (!row || typeof row !== "object") return null;
  return {
    id: row.id ?? "",
    customerName: row.customer_name ?? "",
    material: row.material ?? "",
    color: row.color ?? "",
    pvcMeters: row.pvc_meters ?? null,
    quantity: row.quantity ?? null,
    cutStatus: row.cut_status ?? "Bilinmiyor",
    notes: row.notes ?? "",
    cellHighlights: row.cell_highlights ?? [],
    rangeNotes: row.range_notes ?? [],
    orderDate: row.order_date ?? "",
    sourceFile: row.source_file ?? "",
    sheetName: row.sheet_name ?? "",
    sourceRow: row.source_row ?? null
  };
}

function renderSummary() {
  const { totalRecords = 0, totalFiles = 0 } = state.database;
  elements.totalRecords.textContent = formatCount(totalRecords);
  elements.totalFiles.textContent = formatCount(totalFiles);
  elements.matchedRecords.textContent = formatCount(state.filtered.length);
}

function filterAndRender(query) {
  const normalizedQuery = normalize(query);
  const allRecords = sortRecords(state.database.records ?? []);

  state.filtered = normalizedQuery
    ? allRecords.filter((record) => {
        const haystack = normalize(
          [
            record.customerName,
            record.material,
            record.color,
            record.opt,
            record.plaka,
            record.cutStatus,
            record.notes,
            textifyItems(record.cellHighlights),
            textifyItems(record.rangeNotes),
            record.sourceFile,
            record.sheetName
          ].join(" ")
        );
        return haystack.includes(normalizedQuery);
      })
    : allRecords;

  state.currentPage = 1;
  renderResults(query);
  elements.matchedRecords.textContent = formatCount(state.filtered.length);
}

function renderResults(query = "") {
  const count = state.filtered.length;
  if (!count) {
    const message = query ? `"${query}" için sonuç bulunamadı.` : "Henüz içe aktarılmış kayıt yok.";
    elements.resultLabel.textContent = message;
    elements.resultsBody.innerHTML = `<tr><td colspan="8" class="empty">${escapeHtml(message)}</td></tr>`;
    renderPager(0, 0);
    return;
  }

  const totalPages = Math.max(1, Math.ceil(count / state.pageSize));
  if (state.currentPage > totalPages) {
    state.currentPage = totalPages;
  }

  const start = (state.currentPage - 1) * state.pageSize;
  const end = start + state.pageSize;
  const pageItems = state.filtered.slice(start, end);
  const shown = pageItems.length;

  const label = query
    ? `"${query}" için ${count} kayıt bulundu.`
    : `En yeni ${Math.min(count, state.pageSize)} kayıt gösteriliyor.`;
  elements.resultLabel.textContent = label;

  const rows = pageItems.map(renderRow).join("");
  elements.resultsBody.innerHTML = rows;
  renderPager(totalPages, shown);
}

function renderPager(totalPages, shownCount) {
  if (!totalPages) {
    elements.pager.innerHTML = "";
    return;
  }

  const prevDisabled = state.currentPage <= 1 ? "disabled" : "";
  const nextDisabled = state.currentPage >= totalPages ? "disabled" : "";
  const pageText = `Sayfa ${state.currentPage} / ${totalPages}`;
  const rowsText = `${formatCount(shownCount)} kayıt`;

  elements.pager.innerHTML = `
    <button class="pager-btn" type="button" data-page="prev" ${prevDisabled}>Önceki</button>
    <span class="pager-info">${escapeHtml(pageText)} · ${escapeHtml(rowsText)}</span>
    <button class="pager-btn" type="button" data-page="next" ${nextDisabled}>Sonraki</button>
  `;

  elements.pager.querySelectorAll("button[data-page]").forEach((button) => {
    button.addEventListener("click", () => {
      if (button.dataset.page === "prev" && state.currentPage > 1) {
        state.currentPage -= 1;
      }
      if (button.dataset.page === "next" && state.currentPage < totalPages) {
        state.currentPage += 1;
      }
      renderResults(elements.searchInput.value);
    });
  });
}

function renderRow(record) {
  const date = formatDate(record.orderDate);
  const cutClass =
    record.cutStatus === "Kesildi"
      ? "done"
      : record.cutStatus === "Kesilmedi"
      ? "waiting"
      : "unknown";

  return `
    <tr>
      <td>${escapeHtml(date)}</td>
      <td>${escapeHtml(displayFileName(record.sourceFile))}</td>
      <td>${escapeHtml(record.opt || getCellValue(record.cellHighlights, "D12") || "-")}</td>
      <td>${escapeHtml(record.material || getCellValue(record.cellHighlights, "A15") || "-")}</td>
      <td>${escapeHtml(record.plaka || buildPlakaValue(record.cellHighlights) || "-")}</td>
      <td>${formatNumber(record.pvcMeters)}</td>
      <td><span class="badge ${cutClass}">${escapeHtml(record.cutStatus || "Bilinmiyor")}</span></td>
      <td>${formatRangeNotes(record.rangeNotes || record.notes)}</td>
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

function sortRecords(records) {
  return [...records].sort((left, right) => {
    const rightTime = new Date(right.orderDate ?? 0).getTime();
    const leftTime = new Date(left.orderDate ?? 0).getTime();
    if (rightTime !== leftTime) return rightTime - leftTime;
    return String(right.sourceFile ?? "").localeCompare(String(left.sourceFile ?? ""), "tr-TR");
  });
}

function formatRangeNotes(items) {
  const list = normalizeList(items);
  if (!list.length) return "<span class='muted'>-</span>";
  return `<div class="cell-list">${list
    .map((item) => {
      if (typeof item === "string") {
        return `<div>${escapeHtml(item)}</div>`;
      }
      const cell = escapeHtml(item.cell || "");
      const label = escapeHtml(item.label || "");
      const value = escapeHtml(item.value ?? "");
      const prefix = label ? `${cell} / ${label}` : cell;
      return `<div>${prefix ? `<strong>${prefix}</strong> - ` : ""}${value}</div>`;
    })
    .join("")}</div>`;
}

function normalizeList(items) {
  if (!items) return [];
  return Array.isArray(items) ? items : [items];
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
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
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
