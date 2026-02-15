// Pipeline — Chrome Background Script
// Routes messages between content script/popup and the native messaging host.

const NATIVE_HOST_NAME = "io.github.digitaltracer.pipeline";
const NATIVE_MESSAGE_TIMEOUT_MS = 60000;

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "saveJobToPipeline") {
    handleSave(request.data)
      .then((result) => sendResponse(result))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (request.action === "checkDuplicate") {
    handleDuplicateCheck(request.data)
      .then((result) => sendResponse(result))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true;
  }
});

function sendNativeMessage(message) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error("Native host timed out. Check Pipeline app permissions and host install."));
    }, NATIVE_MESSAGE_TIMEOUT_MS);

    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message, (response) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);

      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response);
      }
    });
  });
}

async function handleSave(jobData) {
  try {
    return await sendNativeMessage({
      command: "parse",
      url: jobData.url,
      title: jobData.title,
      company: jobData.company,
      location: jobData.location,
      description: jobData.description,
      platform: jobData.platform,
    });
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function handleDuplicateCheck(jobData) {
  try {
    return await sendNativeMessage({
      command: "check-duplicate",
      url: jobData.url,
      company: jobData.company,
      role: jobData.title,
    });
  } catch (err) {
    return { success: false, error: err.message };
  }
}
