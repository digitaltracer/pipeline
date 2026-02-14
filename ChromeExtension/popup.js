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

  const previewTitle = document.getElementById("preview-title");
  const previewCompany = document.getElementById("preview-company");
  const previewLocation = document.getElementById("preview-location");
  const previewDescription = document.getElementById("preview-description");

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

  // ---------------------------------------------------------------------------
  // Extraction
  // ---------------------------------------------------------------------------

  async function extractFromPage() {
    showOnly(loadingEl);
    hideStatus();

    try {
      const [tab] = await runtime.tabs.query({ active: true, currentWindow: true });
      if (!tab?.id) {
        showOnly(emptyEl);
        return;
      }

      const response = await runtime.tabs.sendMessage(tab.id, { action: "extractJobData" });

      if (!response?.success || !response.data) {
        showOnly(emptyEl);
        return;
      }

      extractedData = response.data;

      // Populate preview
      previewTitle.textContent = extractedData.title || "\u2014";
      previewCompany.textContent = extractedData.company || "\u2014";
      previewLocation.textContent = extractedData.location || "\u2014";
      previewDescription.textContent = extractedData.description
        ? extractedData.description.substring(0, 300) + (extractedData.description.length > 300 ? "..." : "")
        : "\u2014";

      showOnly(previewEl);

      // Check for duplicates
      const dupResult = await runtime.runtime.sendMessage({
        action: "checkDuplicate",
        data: extractedData,
      });

      if (dupResult?.isDuplicate) {
        showStatus("warning", "This job may already be saved in Pipeline.");
      }
    } catch (err) {
      console.error("Pipeline extraction error:", err);
      showOnly(emptyEl);
    }
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  async function saveJob() {
    if (!extractedData) return;

    saveBtn.disabled = true;
    saveBtn.textContent = "Saving...";
    hideStatus();

    try {
      const result = await runtime.runtime.sendMessage({
        action: "saveJobToPipeline",
        data: extractedData,
      });

      if (result?.success) {
        showStatus("success", "Saved to Pipeline!");
        saveBtn.textContent = "Saved";
      } else {
        showStatus("error", result?.error || "Failed to save. Please try again.");
        saveBtn.disabled = false;
        saveBtn.innerHTML = '<span class="btn-icon">+</span> Save to Pipeline';
      }
    } catch (err) {
      showStatus("error", `Error: ${err.message}`);
      saveBtn.disabled = false;
      saveBtn.innerHTML = '<span class="btn-icon">+</span> Save to Pipeline';
    }
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  saveBtn.addEventListener("click", saveJob);
  extractFromPage();
})();
