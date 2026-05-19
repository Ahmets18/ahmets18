const state = {
  database: null,
  filtered: [],
  currentPage: 1,
  pageSize: 10
};

const elements = {
  searchInput: document.getElementById("searchInput"),
  resultsBody: document.getElementById("resultsBody"),
  resultLabel: document.getElementById("resultLabel"),
  pager: document.getElementById("pager"),
  totalRecords: document.getElementById("totalRecords"),
  totalFiles: document.getElementById("totalFiles"),
  matchedRecords: document.getElementById("matchedRecords")
};

init().catch((error) => {
  console.error(error);
  elements.resultsBody.innerHTML = `<tr><td colspan="10" class="empty">Veri yüklenemedi. database.txt hazır değil.</td></tr>`;
  elements.resultLabel.textContent = "Veri kaynağı okunamadı.";
});

async function init() {
  state.database = await loadDatabase();
  state.filtered = sortRecords(state.database.records ?? []);

  renderSummary();
  renderResults();

  elements.searchInput.addEventListener("input", () => {
    filterAndRender(elements.searchInput.value);
  });
}

async function loadDatabase() {
  try {
    const response = await fetch("./data/database.txt", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Database not found: ${response.status}`);
    }
    return JSON.parse(await response.text());
  } catch {
    const seed = document.getElementById("databaseSeed")?.textContent?.trim();
    if (seed) {
      return JSON.parse(seed);
    }
    throw new Error("Database could not be loaded");
  }
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
    const message = query
      ? `“${query}” için sonuç bulunamadı.`
      : "Henüz içe aktarılmış kayıt yok.";
    elements.resultLabel.textContent = message;
    elements.resultsBody.innerHTML = `<tr><td colspan="10" class="empty">${escapeHtml(message)}</td></tr>`;
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
    ? `“${query}” için ${count} kayıt bulundu.`
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
      <td><strong>${escapeHtml(record.customerName)}</strong></td>
      <td>${escapeHtml(record.sourceFile)}</td>
      <td>${escapeHtml(record.material)}</td>
      <td>${escapeHtml(record.color)}</td>
      <td>${formatNumber(record.quantity)}</td>
      <td>${formatNumber(record.pvcMeters)}</td>
      <td><span class="badge ${cutClass}">${escapeHtml(record.cutStatus || "Bilinmiyor")}</span></td>
      <td>${formatCellHighlights(record.cellHighlights)}</td>
      <td>${formatRangeNotes(record.rangeNotes || record.notes)}</td>
    </tr>
  `;
}

function sortRecords(records) {
  return [...records].sort((left, right) => {
    const rightTime = new Date(right.orderDate ?? 0).getTime();
    const leftTime = new Date(left.orderDate ?? 0).getTime();
    if (rightTime !== leftTime) return rightTime - leftTime;
    return String(right.sourceFile ?? "").localeCompare(String(left.sourceFile ?? ""), "tr-TR");
  });
}

function formatCellHighlights(items) {
  const list = normalizeList(items);
  if (!list.length) return "<span class='muted'>-</span>";
  return `<div class="cell-list">${list
    .map((item) => {
      const cell = escapeHtml(item.cell || "");
      const label = escapeHtml(item.label || "");
      const value = escapeHtml(item.value ?? "");
      const header = label ? `${cell}: ${label}` : cell;
      return `<div><strong>${header}</strong> - ${value}</div>`;
    })
    .join("")}</div>`;
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
