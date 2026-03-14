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

  const previewTitle = document.getElementById("preview-title");
  const previewCompany = document.getElementById("preview-company");
  const previewLocation = document.getElementById("preview-location");
  const salaryField = document.getElementById("salary-field");
  const previewSalary = document.getElementById("preview-salary");
  const previewDescription = document.getElementById("preview-description");
  const emptyReason = document.getElementById("empty-reason");

  let extractedData = null;

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

  function formatDescriptionPreview(text, maxLength = 380) {
    const normalized = String(text || "").replace(/\r\n?/g, "\n").trim();
    if (!normalized) return "\u2014";
    if (normalized.length <= maxLength) return normalized;
    return `${normalized.substring(0, maxLength).trimEnd()}...`;
  }

  function setSavingState(mode) {
    saveBtn.disabled = true;
    saveForLaterBtn.disabled = true;
    saveBtn.textContent = mode === "save" ? "Saving..." : "Save to Pipeline";
    saveForLaterBtn.textContent = mode === "queue" ? "Queuing..." : "Save for Later";
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
    if (!extractedData) {
      showStatus("error", "No parsed data available to copy.");
      return;
    }

    copyJsonBtn.disabled = true;
    copyJsonBtn.textContent = "Copying...";

    try {
      await copyText(JSON.stringify(extractedData, null, 2));
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

  async function extractFromPage() {
    showOnly(loadingEl);
    hideStatus();
    setEmptyReason("");
    salaryField.classList.add("hidden");

    try {
      const tabId = await getActiveTabId();
      await ensureContentScript(tabId);

      const response = await runtime.tabs.sendMessage(tabId, { action: "extractJobData" });

      if (!response?.success || !response.data) {
        setEmptyReason(response?.error || "This page does not look like a complete job posting.");
        showOnly(emptyEl);
        return;
      }

      extractedData = response.data;
      resetSaveButtons();
      resetCopyJsonButton();

      // Populate preview
      previewTitle.textContent = extractedData.title || "\u2014";
      previewCompany.textContent = extractedData.company || "\u2014";
      previewLocation.textContent = extractedData.location || "\u2014";
      if (extractedData.salary) {
        previewSalary.textContent = extractedData.salary;
        salaryField.classList.remove("hidden");
      }
      previewDescription.textContent = formatDescriptionPreview(extractedData.description);

      showOnly(previewEl);
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
      const result = await runtime.runtime.sendMessage({
        action: "saveJobToPipeline",
        data: extractedData,
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
  extractFromPage();
})();
