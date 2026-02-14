// Pipeline — Content Script
// Extracts job posting data from the current page.
// Shared between Safari and Chrome extensions.

(() => {
  "use strict";

  // ---------------------------------------------------------------------------
  // Platform-specific selectors
  // ---------------------------------------------------------------------------

  const SELECTORS = {
    "linkedin.com": {
      container: ".jobs-description-content__text, .description__text, .show-more-less-html__markup",
      title: ".top-card-layout__title, .t-24.t-bold, .job-details-jobs-unified-top-card__job-title",
      company:
        ".topcard__org-name-link, .top-card-layout__second-subline a, .job-details-jobs-unified-top-card__company-name",
      location:
        ".topcard__flavor--bullet, .top-card-layout__bullet, .job-details-jobs-unified-top-card__bullet",
    },
    "indeed.com": {
      container: "#jobDescriptionText, .jobsearch-JobComponent-description",
      title: ".jobsearch-JobInfoHeader-title, h1[data-testid='jobsearch-JobInfoHeader-title']",
      company: "[data-company-name], .jobsearch-InlineCompanyRating-companyHeader a",
      location: "[data-testid='job-location'], .jobsearch-JobInfoHeader-subtitle > div:last-child",
    },
    "glassdoor.com": {
      container: ".JobDetails_jobDescription__uW_fK, .desc, .jobDescriptionContent",
      title: ".JobDetails_jobTitle__Rbnx1, [data-test='job-title']",
      company: ".EmployerProfile_employerName__K0giS, [data-test='employer-name']",
      location: ".JobDetails_location__mSg5h, [data-test='location']",
    },
    "naukri.com": {
      container: ".styles_JDC__dang-inner-html__h0K4t, .dang-inner-html, .job-desc",
      title: ".styles_jd-header-title__rZwM1, .jd-header-title",
      company: ".styles_jd-header-comp-name__MvqAI, .jd-header-comp-name a",
      location: ".styles_jhc__loc___Du2H, .loc .location",
    },
  };

  // ---------------------------------------------------------------------------
  // DOM extraction helpers
  // ---------------------------------------------------------------------------

  function getHostKey() {
    const host = location.hostname.replace(/^www\./, "");
    for (const key of Object.keys(SELECTORS)) {
      if (host.includes(key)) return key;
    }
    return null;
  }

  function textFromSelector(selector) {
    if (!selector) return "";
    const el = document.querySelector(selector);
    return el ? el.textContent.trim() : "";
  }

  function descriptionFromSelector(selector) {
    if (!selector) return "";
    const el = document.querySelector(selector);
    if (!el) return "";
    // Return inner text — preserves line breaks better than textContent
    return el.innerText.trim();
  }

  // Strip elements that add noise: nav, footer, ads, scripts, styles
  const STRIP_TAGS = [
    "nav",
    "footer",
    "header",
    "script",
    "style",
    "noscript",
    "iframe",
    "svg",
    "[role='banner']",
    "[role='navigation']",
    "[role='contentinfo']",
    ".ad",
    ".ads",
    ".advertisement",
    ".cookie-banner",
    ".cookie-notice",
  ];

  function genericExtract() {
    // Clone body, remove noisy elements, return text
    const clone = document.body.cloneNode(true);
    for (const sel of STRIP_TAGS) {
      clone.querySelectorAll(sel).forEach((el) => el.remove());
    }
    return {
      title: document.title,
      company: "",
      location: "",
      description: clone.innerText.trim().substring(0, 15000),
    };
  }

  // ---------------------------------------------------------------------------
  // Main extraction
  // ---------------------------------------------------------------------------

  function extractJobData() {
    const hostKey = getHostKey();

    if (!hostKey) {
      return { ...genericExtract(), url: location.href, platform: "other" };
    }

    const sel = SELECTORS[hostKey];

    return {
      title: textFromSelector(sel.title),
      company: textFromSelector(sel.company),
      location: textFromSelector(sel.location),
      description: descriptionFromSelector(sel.container) || genericExtract().description,
      url: location.href,
      platform: hostKey.replace(".com", ""),
    };
  }

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

  // Listen for messages from popup or background
  const messageHandler =
    typeof browser !== "undefined" ? browser.runtime.onMessage : chrome.runtime.onMessage;

  messageHandler.addListener((request, _sender, sendResponse) => {
    if (request.action === "extractJobData") {
      try {
        const data = extractJobData();
        sendResponse({ success: true, data });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
    }
    // Return true for async response support in Chrome
    return true;
  });
})();
