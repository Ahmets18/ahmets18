const AUTH_EMAIL = "artiebatlama18@local.invalid";
const AUTH_CONFIRM_MESSAGE = "Supabase Authentication ayarlarında e-posta onayı kapalı olmalı.";

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

let supabaseClient = null;

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

  const client = getSupabaseClient();
  if (!client) {
    lockApp();
    setAuthError("Supabase bağlantısı bulunamadı.");
    return;
  }

  const { data } = await client.auth.getSession();
  state.session = data?.session ?? null;

  client.auth.onAuthStateChange(async (_event, session) => {
    state.session = session ?? null;
    if (state.session) {
      unlockApp();
      await startApp();
      return;
    }

    state.appReady = false;
    state.database = null;
    state.filtered = [];
    lockApp();
  });

  if (state.session) {
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

function getSupabaseClient() {
  if (supabaseClient) {
    return supabaseClient;
  }

  const config = window.SUPABASE_CONFIG;
  if (!window.supabase || !config?.url || !config?.anonKey) {
    return null;
  }

  supabaseClient = window.supabase.createClient(config.url, config.anonKey, {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false
    }
  });

  return supabaseClient;
}

async function handleLogin(event) {
  event.preventDefault();

  const password = String(elements.passwordInput?.value ?? "");
  if (!password) {
    setAuthError("Şifre gir.");
    return;
  }

  const client = getSupabaseClient();
  if (!client) {
    setAuthError("Supabase bağlantısı bulunamadı.");
    return;
  }

  setAuthError("");

  const signIn = await client.auth.signInWithPassword({
    email: AUTH_EMAIL,
    password
  });

  if (signIn.data?.session) {
    state.session = signIn.data.session;
    unlockApp();
    await startApp();
    return;
  }

  const signUp = await client.auth.signUp({
    email: AUTH_EMAIL,
    password
  });

  if (signUp.data?.session) {
    state.session = signUp.data.session;
    unlockApp();
    await startApp();
    return;
  }

  const message = signUp.error?.message || signIn.error?.message || AUTH_CONFIRM_MESSAGE;
  if (/email/i.test(message) || /confirm/i.test(message)) {
    setAuthError(AUTH_CONFIRM_MESSAGE);
  } else if (/already registered/i.test(message)) {
    setAuthError("Şifre yanlış.");
  } else {
    setAuthError(message);
  }

  elements.passwordInput?.focus();
  elements.passwordInput?.select?.();
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
  const client = getSupabaseClient();
  const config = window.SUPABASE_CONFIG;
  if (!client || !config?.table) {
    return null;
  }

  try {
    const { data: rows, error } = await client
      .from(config.table)
      .select("*")
      .order("order_date", { ascending: false });

    if (error) {
      throw error;
    }

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
