const resourceName = typeof GetParentResourceName === "function" ? GetParentResourceName() : "cbk-npc";

const root = document.getElementById("root");
const sectionNav = document.getElementById("sectionNav");
const searchInput = document.getElementById("searchInput");
const sectionsEl = document.getElementById("sections");
const revisionEl = document.getElementById("revision");
const closeBtn = document.getElementById("closeBtn");
const saveBtn = document.getElementById("saveBtn");
const loadBtn = document.getElementById("loadBtn");
const unlockBtn = document.getElementById("unlockBtn");
const lockOwnerEl = document.getElementById("lockOwner");
const profileNameInput = document.getElementById("profileNameInput");
const profileSelect = document.getElementById("profileSelect");
const saveNamedBtn = document.getElementById("saveNamedBtn");
const loadNamedBtn = document.getElementById("loadNamedBtn");
const deleteProfileBtn = document.getElementById("deleteProfileBtn");
const cloneProfileBtn  = document.getElementById("cloneProfileBtn");
const profileMetaEl    = document.getElementById("profileMeta");
const toastEl = document.getElementById("toast");

let toastTimer = null;
let profileMetaMap = {};
const uiState = {
  sections: [],
  selectedCategory: "All",
  searchTerm: "",
};

function formatEpoch(epoch) {
  if (!epoch) return "\u2014";
  const d = new Date(epoch * 1000);
  const pad = n => String(n).padStart(2, "0");
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())}-${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function postNui(eventName, payload = {}) {
  return fetch(`https://${resourceName}/${eventName}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(payload),
  }).then(async (response) => {
    let body = null;
    try {
      body = await response.json();
    } catch (_) {
      body = null;
    }

    if (!response.ok) {
      throw new Error((body && body.reason) || "request_failed");
    }

    if (body && body.ok === false) {
      throw new Error(body.reason || "request_failed");
    }

    return body;
  });
}

function friendlyReason(reason) {
  const labels = {
    invalid_payload: "Invalid panel payload",
    invalid_path: "That setting path was rejected",
    path_not_supported: "That setting is not supported by the panel",
    path_not_allowed: "That setting cannot be edited from the panel",
    invalid_type: "That value type is not allowed",
    invalid_value: "That value is not allowed",
    permission_denied: "You do not have permission to edit settings",
    panel_locked: "Another admin currently holds the panel lock",
    rate_limited: "Too many changes too quickly",
    throttled: "Please slow down for a moment",
    request_failed: "Request failed",
  };

  if (!reason) return "Request failed";
  return labels[reason] || String(reason).replaceAll("_", " ");
}

function showRequestError(prefix, error) {
  showToast(`${prefix}: ${friendlyReason(error && error.message)}`, "error");
}

function sendPanelRequest(eventName, payload, failurePrefix) {
  return postNui(eventName, payload).catch((error) => {
    showRequestError(failurePrefix, error);
    throw error;
  });
}

function commitControlValue(control, value) {
  return sendPanelRequest("cbk:setValue", { path: control.path, value }, "Apply failed");
}

function normalizeSearchText(value) {
  return String(value || "").trim().toLowerCase();
}

function showToast(message, tone) {
  toastEl.textContent = message;
  toastEl.classList.remove("hidden", "error");
  if (tone === "error") {
    toastEl.classList.add("error");
  }

  if (toastTimer) {
    clearTimeout(toastTimer);
  }

  toastTimer = setTimeout(() => {
    toastEl.classList.add("hidden");
  }, 1400);
}

function formatValue(value) {
  if (typeof value === "number") {
    if (Math.abs(value - Math.round(value)) < 0.0001) {
      return String(Math.round(value));
    }
    return value.toFixed(2);
  }
  if (typeof value === "boolean") {
    return value ? "ON" : "OFF";
  }
  return String(value ?? "-");
}

function clampNumber(value, min, max) {
  let out = value;
  if (Number.isFinite(min)) {
    out = Math.max(min, out);
  }
  if (Number.isFinite(max)) {
    out = Math.min(max, out);
  }
  return out;
}

function normalizeSliderValue(control, rawValue) {
  const min = Number(control.min);
  const max = Number(control.max);
  const step = Number(control.step);
  let value = Number(rawValue);

  if (!Number.isFinite(value)) {
    value = Number(control.value ?? control.min ?? 0);
  }
  if (!Number.isFinite(value)) {
    value = 0;
  }

  value = clampNumber(
    value,
    Number.isFinite(min) ? min : undefined,
    Number.isFinite(max) ? max : undefined
  );

  if (Number.isFinite(step) && step > 0) {
    const base = Number.isFinite(min) ? min : 0;
    value = base + (Math.round((value - base) / step) * step);
    value = clampNumber(
      value,
      Number.isFinite(min) ? min : undefined,
      Number.isFinite(max) ? max : undefined
    );

    if (step >= 1) {
      value = Math.round(value);
    } else {
      value = Number(value.toFixed(4));
    }
  }

  return value;
}

function collectCategoryStats(sections) {
  const stats = [];
  const seen = new Set();

  for (const section of sections || []) {
    const category = section.category || "Other";
    if (!seen.has(category)) {
      seen.add(category);
      stats.push({ category, count: 0 });
    }

    const stat = stats.find((entry) => entry.category === category);
    stat.count += 1;
  }

  return stats;
}

function getVisibleSections() {
  const selectedCategory = uiState.selectedCategory || "All";
  const searchTerm = normalizeSearchText(uiState.searchTerm);
  const visible = [];

  for (const section of uiState.sections || []) {
    const category = section.category || "Other";
    if (selectedCategory !== "All" && category !== selectedCategory) {
      continue;
    }

    const haystack = normalizeSearchText(
      `${category} ${section.section || ""} ${section.description || ""}`
    );

    if (!searchTerm) {
      visible.push(section);
      continue;
    }

    if (haystack.includes(searchTerm)) {
      visible.push(section);
      continue;
    }

    const matchingControls = (section.controls || []).filter((control) => {
      const controlText = normalizeSearchText(
        `${control.label || ""} ${control.path || ""} ${control.note || ""}`
      );
      return controlText.includes(searchTerm);
    });

    if (matchingControls.length > 0) {
      visible.push({
        ...section,
        controls: matchingControls,
      });
    }
  }

  return visible;
}

function renderSectionNav() {
  if (!sectionNav) {
    return;
  }

  const categoryStats = collectCategoryStats(uiState.sections);
  const categories = [{ category: "All", count: uiState.sections.length }, ...categoryStats];

  if (!categories.some((entry) => entry.category === uiState.selectedCategory)) {
    uiState.selectedCategory = "All";
  }

  sectionNav.innerHTML = "";
  for (const entry of categories) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "section-nav-btn";
    if (entry.category === uiState.selectedCategory) {
      button.classList.add("is-active");
    }

    const label = document.createElement("span");
    label.className = "section-nav-label";
    label.textContent = entry.category;

    const count = document.createElement("span");
    count.className = "section-nav-count";
    count.textContent = `${entry.count} section${entry.count === 1 ? "" : "s"}`;

    button.appendChild(label);
    button.appendChild(count);
    button.addEventListener("click", () => {
      uiState.selectedCategory = entry.category;
      renderSectionNav();
      renderSections();
    });

    sectionNav.appendChild(button);
  }
}

function createControl(control) {
  const row = document.createElement("div");
  row.className = "control-row";
  if (control.disabled) {
    row.classList.add("is-disabled");
  }

  const labelWrap = document.createElement("div");
  labelWrap.className = "control-label-wrap";

  const label = document.createElement("div");
  label.className = "control-label";
  label.textContent = control.label;
  labelWrap.appendChild(label);

  if (control.note) {
    const note = document.createElement("div");
    note.className = "control-note";
    note.textContent = control.note;
    labelWrap.appendChild(note);
    row.title = control.note;
  }

  const right = document.createElement("div");
  right.className = "control-right";

  const valueEl = document.createElement("div");
  valueEl.className = "control-value";
  valueEl.textContent = formatValue(control.value);

  if (control.kind === "toggle") {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = Boolean(control.value);
    input.disabled = control.disabled === true;
    input.addEventListener("change", () => {
      valueEl.textContent = formatValue(input.checked);
      commitControlValue(control, input.checked).catch(() => {});
    });

    right.appendChild(input);
  } else if (control.kind === "slider") {
    const sliderWrap = document.createElement("div");
    sliderWrap.className = "slider-inputs";

    const input = document.createElement("input");
    input.type = "range";
    input.min = control.min;
    input.max = control.max;
    input.step = control.step;
    input.value = normalizeSliderValue(control, control.value ?? control.min);
    input.disabled = control.disabled === true;

    const numberInput = document.createElement("input");
    numberInput.type = "number";
    numberInput.className = "slider-number";
    numberInput.min = control.min;
    numberInput.max = control.max;
    numberInput.step = control.step;
    numberInput.value = normalizeSliderValue(control, control.value ?? control.min);
    numberInput.disabled = control.disabled === true;

    const syncSliderInputs = (rawValue) => {
      const normalized = normalizeSliderValue(control, rawValue);
      input.value = String(normalized);
      numberInput.value = String(normalized);
      valueEl.textContent = formatValue(normalized);
      return normalized;
    };

    const commitSliderValue = (rawValue) => {
      const normalized = syncSliderInputs(rawValue);
      commitControlValue(control, normalized).catch(() => {});
    };

    input.addEventListener("input", () => {
      syncSliderInputs(input.value);
    });

    input.addEventListener("change", () => {
      commitSliderValue(input.value);
    });

    numberInput.addEventListener("input", () => {
      const current = Number(numberInput.value);
      if (!Number.isFinite(current)) {
        return;
      }
      valueEl.textContent = formatValue(current);
      input.value = String(clampNumber(
        current,
        Number.isFinite(Number(control.min)) ? Number(control.min) : undefined,
        Number.isFinite(Number(control.max)) ? Number(control.max) : undefined
      ));
    });

    numberInput.addEventListener("change", () => {
      commitSliderValue(numberInput.value);
    });

    numberInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        commitSliderValue(numberInput.value);
      }
    });

    sliderWrap.appendChild(input);
    sliderWrap.appendChild(numberInput);
    right.appendChild(sliderWrap);
  } else if (control.kind === "number") {
    const input = document.createElement("input");
    input.type = "number";
    input.className = "slider-number";
    input.min = control.min;
    input.max = control.max;
    input.step = control.step;
    input.value = normalizeSliderValue(control, control.value ?? control.min ?? 0);
    input.disabled = control.disabled === true;

    input.addEventListener("input", () => {
      const current = Number(input.value);
      if (!Number.isFinite(current)) {
        return;
      }
      valueEl.textContent = formatValue(current);
    });

    input.addEventListener("change", () => {
      const normalized = normalizeSliderValue(control, input.value);
      input.value = String(normalized);
      valueEl.textContent = formatValue(normalized);
      commitControlValue(control, normalized).catch(() => {});
    });

    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        input.dispatchEvent(new Event("change"));
      }
    });

    right.appendChild(input);
  } else if (control.kind === "select") {
    const select = document.createElement("select");
    select.disabled = control.disabled === true;
    const options = Array.isArray(control.options) ? control.options : [];
    for (const optionValue of options) {
      const option = document.createElement("option");
      option.value = optionValue;
      option.textContent = optionValue;
      if (control.value === optionValue) {
        option.selected = true;
      }
      select.appendChild(option);
    }

    select.addEventListener("change", () => {
      valueEl.textContent = formatValue(select.value);
      commitControlValue(control, select.value).catch(() => {});
    });

    right.appendChild(select);
  }

  right.appendChild(valueEl);

  row.appendChild(labelWrap);
  row.appendChild(right);
  return row;
}

function renderSections() {
  sectionsEl.innerHTML = "";
  const sections = getVisibleSections();
  const categoryStats = collectCategoryStats(sections);

  if (sections.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No settings match the current category or search.";
    sectionsEl.appendChild(empty);
    return;
  }

  let currentCategory = null;
  let currentGrid = null;

  for (const section of sections) {
    const category = section.category || "Other";
    if (category !== currentCategory) {
      currentCategory = category;

      const categoryGroup = document.createElement("section");
      categoryGroup.className = "category-group";

      const header = document.createElement("div");
      header.className = "category-header";

      const title = document.createElement("h2");
      title.className = "category-title";
      title.textContent = category;

      const count = document.createElement("div");
      count.className = "category-count";
      const categoryInfo = categoryStats.find((entry) => entry.category === category);
      const countValue = categoryInfo ? categoryInfo.count : 0;
      count.textContent = `${countValue} section${countValue === 1 ? "" : "s"}`;

      header.appendChild(title);
      header.appendChild(count);
      categoryGroup.appendChild(header);

      currentGrid = document.createElement("div");
      currentGrid.className = "category-grid";
      categoryGroup.appendChild(currentGrid);
      sectionsEl.appendChild(categoryGroup);
    }

    const card = document.createElement("section");
    card.className = "section-card";

    const title = document.createElement("h3");
    title.className = "section-title";
    title.textContent = section.section;

    card.appendChild(title);

    if (section.description) {
      const description = document.createElement("p");
      description.className = "section-description";
      description.textContent = section.description;
      card.appendChild(description);
    }

    for (const control of section.controls || []) {
      card.appendChild(createControl(control));
    }

    currentGrid.appendChild(card);
  }
}

function renderProfiles(profiles, selectedProfile) {
  profileMetaMap = {};
  profileSelect.innerHTML = "";
  const items = Array.isArray(profiles) ? profiles : [];

  for (const item of items) {
    const name = typeof item === "object" && item !== null ? item.name : String(item);
    if (typeof item === "object" && item !== null) {
      profileMetaMap[name] = item;
    }
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    if (selectedProfile && selectedProfile === name) {
      option.selected = true;
    }
    profileSelect.appendChild(option);
  }

  if (!profileSelect.value && items.length > 0) {
    const first = items[0];
    profileSelect.value = typeof first === "object" && first !== null ? first.name : String(first);
  }

  updateProfileMeta();
}

function updateProfileMeta() {
  const selected = profileSelect.value;
  const meta = profileMetaMap[selected];

  if (!meta || (!meta.savedAt && !meta.savedBy && !meta.lastUsedAt && !meta.lastUsedBy)) {
    profileMetaEl.classList.add("hidden");
    return;
  }

  const savedStr = meta.savedAt
    ? formatEpoch(meta.savedAt) + (meta.savedBy ? ` by ${meta.savedBy}` : "")
    : "\u2014";
  const usedStr = meta.lastUsedAt
    ? formatEpoch(meta.lastUsedAt) + (meta.lastUsedBy ? ` by ${meta.lastUsedBy}` : "")
    : "\u2014";

  const entries = [
    ["Saved", savedStr],
    ["Last Used", usedStr],
  ];

  profileMetaEl.innerHTML = "";
  for (const [label, value] of entries) {
    const span = document.createElement("span");
    span.className = "meta-field";
    span.innerHTML = `<span class="meta-label">${label}</span>${value}`;
    profileMetaEl.appendChild(span);
  }
  profileMetaEl.classList.remove("hidden");
}

function bindActionButton(button, eventName, payloadFactory, failurePrefix) {
  button.addEventListener("click", () => {
    const payload = typeof payloadFactory === "function" ? payloadFactory() : payloadFactory;
    if (payload === null) {
      return;
    }

    sendPanelRequest(eventName, payload, failurePrefix).catch(() => {});
  });
}

window.addEventListener("message", (event) => {
  const data = event.data || {};

  if (data.action === "cbk:open") {
    uiState.searchTerm = "";
    uiState.selectedCategory = "All";
    if (searchInput) {
      searchInput.value = "";
    }
    root.classList.remove("hidden");
    postNui("cbk:requestProfiles").catch(() => {
      showToast("Profile list refresh failed", "error");
    });
    return;
  }

  if (data.action === "cbk:close") {
    root.classList.add("hidden");
    return;
  }

  if (data.action === "cbk:panelState") {
    revisionEl.textContent = `rev ${data.revision ?? 0}`;
    lockOwnerEl.textContent = `lock: ${data.lockOwner ?? "none"}`;
    uiState.sections = Array.isArray(data.sections) ? data.sections : [];
    renderProfiles(data.profiles || [], data.selectedProfile || "runtime");
    renderSectionNav();
    renderSections();
    return;
  }

  if (data.action === "cbk:toast") {
    showToast(data.message || "Updated", data.tone || "ok");
  }
});

closeBtn.addEventListener("click", () => {
  postNui("cbk:close").catch(() => {
    root.classList.add("hidden");
  });
});

bindActionButton(saveBtn, "cbk:saveProfile", {}, "Save profile failed");
bindActionButton(loadBtn, "cbk:loadProfile", {}, "Load profile failed");
bindActionButton(unlockBtn, "cbk:releaseLock", {}, "Release lock failed");

bindActionButton(saveNamedBtn, "cbk:saveNamedProfile", () => {
  const typedName = (profileNameInput.value || "").trim();
  if (!typedName) {
    showToast("Enter profile name", "error");
    return null;
  }

  return { name: typedName };
}, "Save selected profile failed");

bindActionButton(loadNamedBtn, "cbk:loadNamedProfile", () => {
  const selected = profileSelect.value;
  if (!selected) {
    showToast("Select a profile", "error");
    return null;
  }

  return { name: selected };
}, "Load selected profile failed");

bindActionButton(deleteProfileBtn, "cbk:deleteProfile", () => {
  const selected = profileSelect.value;
  if (!selected) {
    showToast("Select a profile", "error");
    return null;
  }

  return { name: selected };
}, "Delete profile failed");

cloneProfileBtn.addEventListener("click", () => {
  const selected = profileSelect.value;
  if (!selected) {
    showToast("Select a profile to clone", "error");
    return;
  }
  profileNameInput.value = selected + "_copy";
  profileNameInput.focus();
});

profileSelect.addEventListener("change", updateProfileMeta);

if (searchInput) {
  searchInput.addEventListener("input", () => {
    uiState.searchTerm = searchInput.value || "";
    renderSections();
  });
}

document.addEventListener("keyup", (event) => {
  if (event.key === "Escape") {
    postNui("cbk:close").catch(() => {
      root.classList.add("hidden");
    });
  }
});
