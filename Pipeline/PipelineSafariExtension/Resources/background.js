// Pipeline — Background Script
// Routes messages between content script and native layer (Safari native handler
// or Chrome native messaging host).

const isSafari = typeof browser !== "undefined" && typeof browser.runtime.sendNativeMessage === "function";
const NATIVE_MESSAGE_TIMEOUT_MS = 60000;
const NATIVE_TIMEOUT_ERROR = "Native host timed out. Check Pipeline app permissions and host install.";

// ---------------------------------------------------------------------------
// Message handling
// ---------------------------------------------------------------------------

const runtime = typeof browser !== "undefined" ? browser : chrome;

function withTimeout(promise, timeoutMs, message) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error(message));
    }, timeoutMs);

    promise
      .then((value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(value);
      })
      .catch((err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        reject(err instanceof Error ? err : new Error(String(err)));
      });
  });
}

runtime.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "saveJobToPipeline") {
    handleSave(request.data)
      .then((result) => sendResponse(result))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true; // async
  }

  if (request.action === "checkDuplicate") {
    handleDuplicateCheck(request.data)
      .then((result) => sendResponse(result))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true;
  }
});

// ---------------------------------------------------------------------------
// Native communication
// ---------------------------------------------------------------------------

async function sendNativeMessage(command, payload) {
  const message = { command, ...payload };

  if (isSafari) {
    // Safari Web Extension — sends to SafariWebExtensionHandler
    return withTimeout(
      browser.runtime.sendNativeMessage("application.id", message),
      NATIVE_MESSAGE_TIMEOUT_MS,
      NATIVE_TIMEOUT_ERROR
    );
  } else {
    // Chrome — sends to native messaging host
    return withTimeout(
      new Promise((resolve, reject) => {
        chrome.runtime.sendNativeMessage(
          "io.github.digitaltracer.pipeline",
          message,
          (response) => {
            if (chrome.runtime.lastError) {
              reject(new Error(chrome.runtime.lastError.message));
            } else {
              resolve(response);
            }
          }
        );
      }),
      NATIVE_MESSAGE_TIMEOUT_MS,
      NATIVE_TIMEOUT_ERROR
    );
  }
}

// ---------------------------------------------------------------------------
// Command handlers
// ---------------------------------------------------------------------------

async function handleSave(jobData) {
  try {
    const response = await sendNativeMessage("parse", {
      url: jobData.url,
      title: jobData.title,
      company: jobData.company,
      location: jobData.location,
      description: jobData.description,
      platform: jobData.platform,
    });
    return response;
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function handleDuplicateCheck(jobData) {
  try {
    const response = await sendNativeMessage("check-duplicate", {
      url: jobData.url,
      company: jobData.company,
      role: jobData.title,
    });
    return response;
  } catch (err) {
    return { success: false, error: err.message };
  }
}
