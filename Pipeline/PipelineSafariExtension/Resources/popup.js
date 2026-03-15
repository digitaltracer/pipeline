// Pipeline — Popup Script
// Orchestrates data extraction and saving to the native app.

(() => {
  "use strict";

  const runtime = typeof browser !== "undefined" ? browser : chrome;

  // DOM references
  const statusEl = document.getElementById("status");
  const statusIcon = document.getElementById("status-icon");
  const statusText = document.getElementById("status-text");
  const loadingEl = document.getElementById("loading");
  const previewEl = document.getElementById("preview");
  const emptyEl = document.getElementById("empty");
  const saveBtn = document.getElementById("save-btn");
  const saveForLaterBtn = document.getElementById("save-for-later-btn");
  const copyJsonBtn = document.getElementById("copy-json-btn");
  const debugBtn = document.getElementById("debug-btn");
  const reExtractBtn = document.getElementById("re-extract-btn");

  const previewTitle = document.getElementById("preview-title");
  const previewCompany = document.getElementById("preview-company");
  const previewLocation = document.getElementById("preview-location");
  const salaryField = document.getElementById("salary-field");
  const previewSalary = document.getElementById("preview-salary");
  const previewDescription = document.getElementById("preview-description");
  const emptyReason = document.getElementById("empty-reason");
  const diagnosticsEl = document.getElementById("diagnostics");
  const diagnosticsContent = document.getElementById("diagnostics-content");

  let extractedData = null;
  let descriptionPreviewText = ""; // track the formatted preview for edit detection

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  function showOnly(el) {
    [loadingEl, previewEl, emptyEl].forEach((e) => e.classList.add("hidden"));
    el.classList.remove("hidden");
  }

  function showStatus(type, message) {
    statusEl.className = `status ${type}`;
    statusIcon.textContent = type === "success" ? "\u2713" : type === "warning" ? "\u26A0" : "\u2717";
    statusText.textContent = message;
    statusEl.classList.remove("hidden");
  }

  function hideStatus() {
    statusEl.classList.add("hidden");
  }

  function setEmptyReason(message) {
    if (!message) {
      emptyReason.classList.add("hidden");
      emptyReason.textContent = "";
      return;
    }
    emptyReason.textContent = message;
    emptyReason.classList.remove("hidden");
  }

  function resetSaveButtons() {
    saveBtn.disabled = false;
    saveBtn.innerHTML = '<span class="btn-icon">+</span> Save to Pipeline';
    saveForLaterBtn.disabled = false;
    saveForLaterBtn.textContent = "Save for Later";
  }

  function resetCopyJsonButton() {
    copyJsonBtn.disabled = false;
    copyJsonBtn.textContent = "Copy Parsed JSON";
  }

  function formatDescriptionPreview(text, maxLength = 2000) {
    const normalized = String(text || "").replace(/\r\n?/g, "\n").trim();
    if (!normalized) return "";
    if (normalized.length <= maxLength) return normalized;
    return `${normalized.substring(0, maxLength).trimEnd()}...`;
  }

  function setSavingState(mode) {
    saveBtn.disabled = true;
    saveForLaterBtn.disabled = true;
    saveBtn.textContent = mode === "save" ? "Saving..." : "Save to Pipeline";
    saveForLaterBtn.textContent = mode === "queue" ? "Queuing..." : "Save for Later";
  }

  function populatePreview(fromCache) {
    if (!extractedData) return;

    resetSaveButtons();
    resetCopyJsonButton();

    previewTitle.value = extractedData.title || "";
    previewCompany.value = extractedData.company || "";
    previewLocation.value = extractedData.location || "";
    if (extractedData.salary) {
      previewSalary.value = extractedData.salary;
      salaryField.classList.remove("hidden");
    } else {
      salaryField.classList.add("hidden");
    }
    descriptionPreviewText = formatDescriptionPreview(extractedData.description);
    previewDescription.value = descriptionPreviewText;

    if (fromCache) {
      reExtractBtn.classList.remove("hidden");
    } else {
      reExtractBtn.classList.add("hidden");
    }

    showOnly(previewEl);
  }

  function renderDiagnostics(diag) {
    if (!diag || !diagnosticsEl || !diagnosticsContent) return;

    let html = `<div class="field-status"><span>Platform</span><span>${diag.platform || "Unknown"}</span></div>`;
    html += `<div class="field-status"><span>Confidence</span><span>${(diag.confidence * 100).toFixed(0)}%</span></div>`;

    if (diag.fieldsFound) {
      for (const [field, found] of Object.entries(diag.fieldsFound)) {
        const cls = found ? "found" : "missing";
        const icon = found ? "\u2713" : "\u2717";
        html += `<div class="field-status"><span>${field}</span><span class="${cls}">${icon}</span></div>`;
      }
    }

    if (typeof diag.descriptionLength === "number") {
      html += `<div class="field-status"><span>Desc. length</span><span>${diag.descriptionLength} chars</span></div>`;
    }

    diagnosticsContent.innerHTML = html;
    diagnosticsEl.classList.remove("hidden");
  }

  function hideDiagnostics() {
    if (diagnosticsEl) diagnosticsEl.classList.add("hidden");
  }

  function getEditedData() {
    if (!extractedData) return extractedData;

    const edited = { ...extractedData };
    const titleVal = previewTitle.value.trim();
    const companyVal = previewCompany.value.trim();
    const locationVal = previewLocation.value.trim();
    const salaryVal = previewSalary.value.trim();
    const descVal = previewDescription.value.trim();

    if (titleVal) edited.title = titleVal;
    if (companyVal) edited.company = companyVal;
    edited.location = locationVal;
    edited.salary = salaryVal;

    // Only override description if user actually edited it
    if (descVal && descVal !== descriptionPreviewText) {
      edited.description = descVal;
    }

    return edited;
  }

  async function ensureContentScript(tabId) {
    try {
      await runtime.tabs.sendMessage(tabId, { action: "ping" });
      return;
    } catch {
      // Content script is likely not injected for this tab yet.
    }

    if (!runtime.scripting || typeof runtime.scripting.executeScript !== "function") return;

    try {
      await runtime.scripting.executeScript({
        target: { tabId },
        files: ["content.js"],
      });
      await new Promise((resolve) => setTimeout(resolve, 120));
    } catch (err) {
      console.warn("Pipeline: could not inject content script:", err);
    }
  }

  async function getActiveTabId() {
    const [tab] = await runtime.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) throw new Error("Could not determine active tab.");
    return tab.id;
  }

  async function copyText(value) {
    const text = String(value || "");
    if (!text) throw new Error("Nothing to copy.");

    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    document.body.removeChild(textarea);
  }

  async function copyDebugPacket() {
    debugBtn.disabled = true;
    const prevLabel = debugBtn.textContent;
    debugBtn.textContent = "Collecting...";

    try {
      const tabId = await getActiveTabId();
      await ensureContentScript(tabId);
      const response = await runtime.tabs.sendMessage(tabId, { action: "collectDebugPacket" });

      if (!response?.success || !response.data) {
        throw new Error(response?.error || "Could not collect debug packet.");
      }

      await copyText(JSON.stringify(response.data, null, 2));
      showStatus("success", "Debug packet copied. Paste it in chat.");
    } catch (err) {
      showStatus("error", `Debug copy failed: ${err.message}`);
    } finally {
      debugBtn.disabled = false;
      debugBtn.textContent = prevLabel;
    }
  }

  async function copyParsedJson() {
    const data = getEditedData();
    if (!data) {
      showStatus("error", "No parsed data available to copy.");
      return;
    }

    copyJsonBtn.disabled = true;
    copyJsonBtn.textContent = "Copying...";

    try {
      await copyText(JSON.stringify(data, null, 2));
      showStatus("success", "Parsed JSON copied.");
      copyJsonBtn.textContent = "Copied";
      setTimeout(() => {
        if (!copyJsonBtn.disabled) {
          copyJsonBtn.textContent = "Copy Parsed JSON";
        }
      }, 1200);
    } catch (err) {
      showStatus("error", `Copy failed: ${err.message}`);
      copyJsonBtn.textContent = "Copy Parsed JSON";
    } finally {
      copyJsonBtn.disabled = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Extraction
  // ---------------------------------------------------------------------------

  async function extractFromPage(skipCache) {
    showOnly(loadingEl);
    hideStatus();
    setEmptyReason("");
    hideDiagnostics();
    salaryField.classList.add("hidden");

    try {
      const tabId = await getActiveTabId();

      // Check cache first (unless re-extracting)
      if (!skipCache) {
        try {
          const cached = await runtime.runtime.sendMessage({
            action: "getCachedExtraction",
            tabId,
          });
          if (cached?.success && cached.data) {
            extractedData = cached.data;
            populatePreview(true);
            return;
          }
        } catch {
          // Cache miss or unsupported — proceed with fresh extraction
        }
      }

      await ensureContentScript(tabId);

      const response = await runtime.tabs.sendMessage(tabId, { action: "extractJobData" });

      if (!response?.success || !response.data) {
        setEmptyReason(response?.error || "This page does not look like a complete job posting.");
        if (response?.diagnostics) {
          renderDiagnostics(response.diagnostics);
        }
        showOnly(emptyEl);
        return;
      }

      extractedData = response.data;

      // Cache the result
      try {
        await runtime.runtime.sendMessage({
          action: "cacheExtraction",
          tabId,
          data: response.data,
        });
      } catch {
        // Cache storage failed — not critical
      }

      populatePreview(false);
    } catch (err) {
      console.error("Pipeline extraction error:", err);
      setEmptyReason(err.message || "Could not extract job details from this page.");
      showOnly(emptyEl);
    }
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  async function saveJob(saveForLater = false) {
    if (!extractedData) return;

    setSavingState(saveForLater ? "queue" : "save");
    hideStatus();

    try {
      await doSave(saveForLater);
    } catch (err) {
      showStatus("error", `Error: ${err.message}`);
      resetSaveButtons();
    }
  }

  async function doSave(saveForLater) {
    try {
      const dataToSave = getEditedData();

      const result = await runtime.runtime.sendMessage({
        action: "saveJobToPipeline",
        data: dataToSave,
        saveForLater,
      });

      if (result?.success) {
        showStatus("success", saveForLater ? "Saved for later in Pipeline!" : "Saved to Pipeline!");
        saveBtn.textContent = "Saved";
        saveForLaterBtn.textContent = saveForLater ? "Queued" : "Save for Later";
        saveBtn.disabled = true;
        saveForLaterBtn.disabled = true;
      } else if (result?.isDuplicate) {
        showStatus("warning", result?.error || "This job is already saved in Pipeline.");
        saveBtn.textContent = "Already Saved";
        saveForLaterBtn.textContent = "Already Saved";
        saveBtn.disabled = true;
        saveForLaterBtn.disabled = true;
      } else {
        showStatus("error", result?.error || "Failed to save. Please try again.");
        resetSaveButtons();
      }
    } catch (err) {
      showStatus("error", `Error: ${err.message}`);
      resetSaveButtons();
    }
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  saveBtn.addEventListener("click", () => saveJob(false));
  saveForLaterBtn.addEventListener("click", () => saveJob(true));
  copyJsonBtn.addEventListener("click", copyParsedJson);
  debugBtn.addEventListener("click", copyDebugPacket);
  reExtractBtn.addEventListener("click", () => {
    reExtractBtn.classList.add("hidden");
    extractFromPage(true);
  });
  extractFromPage(false);
})();
