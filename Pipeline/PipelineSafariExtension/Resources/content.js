// Pipeline — Content Script
// Extracts job posting data from the current page.
// Shared between Safari and Chrome extensions.
//
// Extraction priority:
//   1. Platform-specific extraction (currently LinkedIn two-pane details view)
//   2. JSON-LD / microdata (schema.org JobPosting)
//   3. Semantic DOM extraction (standards-first, class-agnostic heuristics)
//   4. Open Graph / meta tags as weak fallback
//
// Important: we gate the final payload by confidence to avoid saving junk data.

(() => {
  "use strict";

  // Guard against duplicate injection (e.g. programmatic + manifest)
  if (window.__pipelineContentScriptInjected) return;
  window.__pipelineContentScriptInjected = true;

  const MIN_TITLE_LENGTH = 5;
  const MIN_DESCRIPTION_LENGTH = 120;
  const CONFIDENCE_THRESHOLD = 0.58;
  const MAX_DESCRIPTION_LENGTH = 15000;
  const DEBUG_TEXT_LIMIT = 20000;

  const JOB_KEYWORDS = [
    "responsibilities",
    "requirements",
    "qualifications",
    "about the role",
    "about the job",
    "experience",
    "apply",
    "benefits",
    "skills",
    "preferred qualifications",
    "minimum qualifications",
  ];

  const NOISE_KEYWORDS = [
    "cookie",
    "privacy policy",
    "terms of service",
    "sign in",
    "join now",
    "people also viewed",
    "promoted",
    "advertisement",
  ];

  const BAD_TITLE_PHRASES = [
    "use ai to assess how you fit",
    "show match details",
    "tailor my resume",
    "create cover letter",
    "help me stand out",
    "easy apply",
    "save",
    "top job picks for you",
    "jobs for you",
    "people also viewed",
  ];

  const DESCRIPTION_START_PATTERNS = [
    /about the job/i,
    /about the role/i,
    /job description/i,
    /what you will do/i,
    /responsibilities/i,
    /qualifications/i,
  ];

  const DESCRIPTION_END_PATTERNS = [
    /this job alert is on/i,
    /see how you compare/i,
    /exclusive job seeker insights/i,
    /about the company/i,
    /more jobs/i,
    /looking for talent/i,
    /linkedin corporation/i,
    /select language/i,
  ];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function normalizeText(value) {
    return (value || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+/g, " ")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  function stripHtml(html) {
    const div = document.createElement("div");
    div.innerHTML = html;
    return normalizeText(div.innerText);
  }

  function compactMultiline(text) {
    return normalizeText(
      text
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean)
        .join("\n")
    );
  }

  function dedupeWords(text) {
    const words = normalizeText(text).split(/\s+/);
    if (words.length < 12) return normalizeText(text);

    const uniqueRatio = new Set(words.map((w) => w.toLowerCase())).size / words.length;
    return uniqueRatio < 0.35 ? "" : normalizeText(text);
  }

  function countKeywordHits(text, words) {
    const lower = (text || "").toLowerCase();
    return words.reduce((count, word) => count + (lower.includes(word) ? 1 : 0), 0);
  }

  function looksLikeLocation(text) {
    if (!text) return false;
    const normalized = normalizeText(text);
    if (!normalized || normalized.length > 80) return false;
    const value = normalized.toLowerCase();
    if (
      /\b(top job picks|show match details|tailor my resume|create cover letter|our culture|connections)\b/i.test(
        value
      )
    ) {
      return false;
    }
    if (/\b(remote|hybrid|on-site|onsite)\b/.test(value)) return true;
    if (/\b[a-z .'-]+,\s*[a-z]{2}\b/i.test(normalized)) return true;
    if (/\b[a-z .'-]+,\s*[a-z .'-]{3,}\b/i.test(normalized)) return true;
    return false;
  }

  function cleanLocation(text) {
    const value = normalizeText(text);
    if (!value) return "";

    const segments = value
      .split(/\s*[·•|]\s*/)
      .map((segment) => normalizeText(segment))
      .filter(Boolean);

    const filtered = segments.filter(
      (segment) =>
        !/\b(applicant|applied|day|days|hour|hours|week|weeks|month|months|promoted|reviewing|viewed|premium|connections|our culture|show match details|tailor my resume|create cover letter|click apply|easy apply)\b/i.test(
          segment
        )
    );

    const base = (filtered.length ? filtered : segments)[0] || "";
    return normalizeText(base);
  }

  function cleanTitle(text) {
    const title = normalizeText(text)
      .replace(/\s*\|\s*LinkedIn.*$/i, "")
      .replace(/\s*-\s*LinkedIn.*$/i, "")
      .replace(/\s*\|\s*Indeed.*$/i, "")
      .replace(/\s*-\s*Indeed.*$/i, "")
      .trim();
    return title;
  }

  function looksLikeTitle(text) {
    const title = cleanTitle(text);
    if (title.length < MIN_TITLE_LENGTH) return false;
    if (title.length > 180) return false;
    const lower = title.toLowerCase();
    if (lower === "jobs" || lower === "job search") return false;
    if (lower.includes("sign in")) return false;
    if (BAD_TITLE_PHRASES.some((phrase) => lower.includes(phrase))) return false;
    return true;
  }

  function clampDescription(text) {
    return compactMultiline(text).substring(0, MAX_DESCRIPTION_LENGTH);
  }

  function isValidCompany(value) {
    if (!value) return false;
    const company = normalizeText(value);
    if (company.length < 2 || company.length > 80) return false;
    const lower = company.toLowerCase();
    if (lower.includes("sign in") || lower.includes("join now")) return false;
    if (lower.includes("easy apply") || lower.includes("quick apply")) return false;
    if (lower.includes("posted") || lower.includes("minutes ago")) return false;
    if (lower.includes("full-time") || lower.includes("part-time")) return false;
    if (lower.includes("employees") || lower.includes("connections")) return false;
    if (lower.includes("our culture") || lower.includes("show match details")) return false;
    if (company.split(/\s+/).length > 8) return false;
    if (looksLikeLocation(company)) return false;
    return true;
  }

  function isValidDescription(value) {
    if (!value) return false;
    const text = normalizeText(value);
    if (text.length < MIN_DESCRIPTION_LENGTH) return false;
    if (text.split(/\s+/).length < 35) return false;
    const noiseHits = countKeywordHits(text, NOISE_KEYWORDS);
    const jobHits = countKeywordHits(text, JOB_KEYWORDS);
    if (noiseHits >= 3) return false;
    if (jobHits > 0) return true;
    return /\b(job|role|position|candidate|responsibilit|qualif|experience)\b/i.test(text);
  }

  function parseTitleCompanyFromDocumentTitle() {
    const title = normalizeText(document.title || "");
    if (!title) return { title: "", company: "" };

    const patterns = [
      /^(.+?)\s+at\s+(.+?)(?:\s+\||\s+-|$)/i,
      /^(.+?)\s*-\s*(.+?)\s*-\s*(?:Job|Careers|LinkedIn|Indeed)/i,
    ];

    for (const pattern of patterns) {
      const match = title.match(pattern);
      if (match) {
        return {
          title: cleanTitle(match[1] || ""),
          company: normalizeText(match[2] || ""),
        };
      }
    }

    return { title: cleanTitle(title), company: "" };
  }

  function titleQualityScore(title, fallbackTitle) {
    const normalized = cleanTitle(title);
    if (!looksLikeTitle(normalized)) return -10;

    let score = 0;
    const lower = normalized.toLowerCase();
    const fallbackLower = (fallbackTitle || "").toLowerCase();

    if (fallbackLower && lower === fallbackLower) score += 4;
    if (
      /\b(engineer|developer|manager|analyst|designer|architect|lead|intern|specialist|consultant)\b/i.test(
        normalized
      )
    ) {
      score += 2;
    }
    const words = normalized.split(/\s+/).length;
    if (words >= 2 && words <= 10) score += 1;
    if (words > 15) score -= 1;

    return score;
  }

  function extractBestTitle(root, lines, fallbackTitle) {
    const candidates = [];

    root.querySelectorAll("h1, h2, h3, [role='heading']").forEach((element) => {
      const value = cleanTitle(normalizeText(element.textContent || ""));
      if (value) candidates.push(value);
    });

    for (const line of lines.slice(0, 12)) {
      if (line && !looksLikeLocation(line)) candidates.push(cleanTitle(line));
    }

    if (fallbackTitle) candidates.push(cleanTitle(fallbackTitle));

    let best = "";
    let bestScore = -Infinity;
    for (const candidate of candidates) {
      const score = titleQualityScore(candidate, fallbackTitle);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    return best || cleanTitle(fallbackTitle || "");
  }

  function pickFirstText(selectors, root = document) {
    for (const selector of selectors) {
      const element = root.querySelector(selector);
      if (!element) continue;
      const value = normalizeText(element.textContent || "");
      if (value) return value;
    }
    return "";
  }

  function pickFirstInnerText(selectors, root = document) {
    for (const selector of selectors) {
      const element = root.querySelector(selector);
      if (!(element instanceof HTMLElement)) continue;
      const value = normalizeText(element.innerText || "");
      if (value) return value;
    }
    return "";
  }

  function isLikelySalaryValue(value, context) {
    const candidate = normalizeText(value);
    if (!candidate) return false;

    if (/\$\d+(?:\.\d+)?\s*[bB]\b/.test(candidate)) return false;
    if (/\b(funding|raised|valuation|followers|employees)\b/i.test(context || "")) return false;

    const digitCount = (candidate.match(/\d/g) || []).length;
    const strongStructure =
      /[kKmM]|,\d{3}|(?:per|\/)\s*(?:year|yr|month|mo|hour|hr)|\bto\b|[-–]/i.test(candidate);

    if (!strongStructure && digitCount < 4) return false;
    if (digitCount < 3 && !/[kKmM]/.test(candidate)) return false;

    return true;
  }

  function extractSalaryFromText(text) {
    if (!text) return "";
    const salaryRegex =
      /(?:\$|USD|INR|EUR|GBP)\s?(?:\d{2,3}(?:,\d{3})+|\d+(?:\.\d+)?\s?[kKmM])(?:\s*(?:-|to|–)\s*(?:\$|USD|INR|EUR|GBP)?\s?(?:\d{2,3}(?:,\d{3})+|\d+(?:\.\d+)?\s?[kKmM]))?(?:\s*(?:\/|per)\s*(?:year|yr|month|mo|hour|hr))?/i;

    const lines = compactMultiline(text)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean);

    for (const line of lines.slice(0, 120)) {
      const hasSalaryContext = /\b(salary|compensation|pay|base|ctc|ote)\b/i.test(line);
      const match = line.match(salaryRegex);
      if (!match) continue;
      if (!hasSalaryContext && !/(?:per|\/)\s*(?:year|yr|month|mo|hour|hr)|[-–]|\bto\b/i.test(match[0])) {
        continue;
      }
      if (isLikelySalaryValue(match[0], line)) return normalizeText(match[0]);
    }

    return "";
  }

  function toISODateString(date) {
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date.toISOString() : "";
  }

  function parseAbsoluteDateValue(rawValue) {
    const normalized = normalizeText(rawValue);
    if (!normalized) return "";

    const sanitized = normalized
      .replace(/\b(apply by|application deadline|deadline|closing date|posted|date posted|valid through)\b[:\s-]*/gi, "")
      .replace(/\bat\b.+$/i, "")
      .trim();

    if (!sanitized) return "";

    const parsed = new Date(sanitized);
    return toISODateString(parsed);
  }

  function shiftDate(amount, unit) {
    const date = new Date();
    switch (unit) {
      case "hour":
        date.setHours(date.getHours() - amount);
        break;
      case "day":
        date.setDate(date.getDate() - amount);
        break;
      case "week":
        date.setDate(date.getDate() - amount * 7);
        break;
      case "month":
        date.setMonth(date.getMonth() - amount);
        break;
      default:
        return "";
    }
    return toISODateString(date);
  }

  function extractPostedDateFromText(text) {
    const normalized = compactMultiline(text || "");
    if (!normalized) return "";

    if (/\bposted\s+today\b/i.test(normalized) || /\btoday\b[^.\n]*\bposted\b/i.test(normalized)) {
      return toISODateString(new Date());
    }
    if (/\bposted\s+yesterday\b/i.test(normalized) || /\byesterday\b[^.\n]*\bposted\b/i.test(normalized)) {
      return shiftDate(1, "day");
    }

    const relativeMatch =
      normalized.match(/\bposted\b[^.\n]{0,40}?(\d+)\s+(hour|day|week|month)s?\s+ago\b/i) ||
      normalized.match(/\b(\d+)\s+(hour|day|week|month)s?\s+ago\b[^.\n]{0,40}?\bposted\b/i);
    if (relativeMatch) {
      return shiftDate(Number(relativeMatch[1]), relativeMatch[2].toLowerCase());
    }

    const absoluteMatch =
      normalized.match(/\bposted\b[^.\n]{0,40}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i) ||
      normalized.match(/\bdate posted\b[^.\n]{0,20}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i);
    return parseAbsoluteDateValue(absoluteMatch ? absoluteMatch[1] : "");
  }

  function extractDeadlineDateFromText(text) {
    const normalized = compactMultiline(text || "");
    if (!normalized) return "";

    const patterns = [
      /\bapply by\b[^.\n]{0,30}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i,
      /\bapplication deadline\b[^.\n]{0,30}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i,
      /\bdeadline\b[^.\n]{0,20}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i,
      /\bvalid through\b[^.\n]{0,20}?([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2})\b/i,
    ];

    for (const pattern of patterns) {
      const match = normalized.match(pattern);
      if (!match) continue;
      const parsed = parseAbsoluteDateValue(match[1]);
      if (parsed) return parsed;
    }

    return "";
  }

  function pickDateValue(selectors, root = document) {
    for (const selector of selectors) {
      const elements = Array.from(root.querySelectorAll(selector));
      for (const element of elements) {
        const candidate =
          element.getAttribute?.("datetime") ||
          element.getAttribute?.("content") ||
          element.getAttribute?.("dateTime") ||
          element.textContent ||
          "";
        const parsed = parseAbsoluteDateValue(candidate);
        if (parsed) return parsed;
      }
    }
    return "";
  }

  function isUiNoiseLine(line) {
    if (!line) return true;
    const value = line.toLowerCase();
    const exactNoise = new Set([
      "save",
      "easy apply",
      "show match details",
      "tailor my resume",
      "create cover letter",
      "help me stand out",
      "show all",
      "message",
      "follow",
      "job poster",
      "home",
      "jobs",
      "learning",
    ]);

    if (exactNoise.has(value)) return true;
    if (/^\d+\s*(notification|notifications)$/.test(value)) return true;
    if (/^promoted by/i.test(line)) return true;
    if (/^actively reviewing/i.test(line)) return true;
    if (/^over \d+ applicants?/i.test(line)) return true;
    if (/^(my network|messaging|for business|notifications)$/.test(value)) return true;

    return false;
  }

  function cleanDescriptionText(text) {
    const lines = compactMultiline(text)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean);

    if (!lines.length) return "";

    let startIndex = lines.findIndex((line) =>
      DESCRIPTION_START_PATTERNS.some((pattern) => pattern.test(line))
    );
    if (startIndex < 0) startIndex = 0;

    let endIndex = lines.findIndex(
      (line, index) =>
        index > startIndex + 4 &&
        DESCRIPTION_END_PATTERNS.some((pattern) => pattern.test(line))
    );
    if (endIndex < 0) endIndex = Math.min(lines.length, startIndex + 220);

    const core = lines.slice(startIndex, endIndex).filter((line) => !isUiNoiseLine(line));
    return clampDescription(core.join("\n"));
  }

  function truncateDebugText(text, limit = DEBUG_TEXT_LIMIT) {
    const value = normalizeText(text || "");
    if (!value) return "";
    if (value.length <= limit) return value;
    return `${value.substring(0, limit)}\n\n[truncated ${value.length - limit} chars]`;
  }

  function toDebugRecord(record) {
    if (!record) return null;
    const normalized = normalizeRecord(record);
    if (!normalized) return null;
    return {
      ...normalized,
      description: truncateDebugText(normalized.description, 6000),
    };
  }

  function collectDebugPacket(extractedData, rawCandidates) {
    const metaKeys = ["og:title", "og:description", "description", "twitter:title", "twitter:description"];
    const meta = {};
    for (const key of metaKeys) meta[key] = metaContent(key);

    const mainText = pickFirstText(["main", "[role='main']", "article"])
      ? truncateDebugText(
          (document.querySelector("main, [role='main'], article")?.innerText || ""),
          DEBUG_TEXT_LIMIT
        )
      : "";

    const bodyTextHead = truncateDebugText(document.body?.innerText || "", DEBUG_TEXT_LIMIT);

    const jsonLdScripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
      .slice(0, 8)
      .map((script, index) => ({
        index,
        preview: truncateDebugText(script.textContent || "", 2500),
      }));

    return {
      timestamp: new Date().toISOString(),
      extractorVersion: "heuristic-v4-debug",
      url: window.location.href,
      platform: detectPlatform(),
      documentTitle: document.title || "",
      extraction: extractedData || null,
      candidates: {
        linkedinPanel: toDebugRecord(rawCandidates.linkedinPanel),
        jsonLd: toDebugRecord(rawCandidates.jsonLd),
        microdata: toDebugRecord(rawCandidates.microdata),
        semanticDom: toDebugRecord(rawCandidates.semanticDom),
        meta: toDebugRecord(rawCandidates.meta),
      },
      meta,
      jsonLdCount: document.querySelectorAll('script[type="application/ld+json"]').length,
      jsonLdScripts,
      mainText,
      bodyTextHead,
    };
  }

  // ---------------------------------------------------------------------------
  // 1. JSON-LD extraction (schema.org JobPosting)
  // ---------------------------------------------------------------------------

  function extractFromJsonLd() {
    const scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (const script of scripts) {
      try {
        const data = JSON.parse(script.textContent);
        const posting = findJobPosting(data);
        if (posting) {
          const title = cleanTitle(posting.title || "");
          const company = extractCompanyFromLd(posting);
          const location = extractLocationFromLd(posting);
          const description = clampDescription(stripHtml(posting.description || ""));
          const salary = extractSalaryFromLd(posting);
          const postedAt = parseAbsoluteDateValue(posting.datePosted || "");
          const applicationDeadline = parseAbsoluteDateValue(posting.validThrough || "");
          return {
            title,
            company,
            location,
            description,
            salary,
            postedAt,
            applicationDeadline,
            source: "jsonld",
          };
        }
      } catch {
        // Invalid JSON — skip
      }
    }
    return null;
  }

  function findJobPosting(data) {
    if (!data) return null;

    // Direct JobPosting
    if (data["@type"] === "JobPosting") return data;

    // Array of types (e.g. ["JobPosting"])
    if (Array.isArray(data["@type"]) && data["@type"].includes("JobPosting")) return data;

    // @graph array
    if (Array.isArray(data["@graph"])) {
      for (const item of data["@graph"]) {
        const found = findJobPosting(item);
        if (found) return found;
      }
    }

    // Top-level array of objects
    if (Array.isArray(data)) {
      for (const item of data) {
        const found = findJobPosting(item);
        if (found) return found;
      }
    }

    return null;
  }

  function extractCompanyFromLd(posting) {
    const org = posting.hiringOrganization;
    if (!org) return "";
    if (typeof org === "string") return org;
    return org.name || "";
  }

  function extractLocationFromLd(posting) {
    const loc = posting.jobLocation;
    if (!loc) return "";

    // Can be a single object or array
    const locations = Array.isArray(loc) ? loc : [loc];
    const parts = [];

    for (const l of locations) {
      if (typeof l === "string") {
        parts.push(l);
        continue;
      }
      const addr = l.address;
      if (!addr) continue;
      if (typeof addr === "string") {
        parts.push(addr);
        continue;
      }
      // PostalAddress
      const addrParts = [
        addr.addressLocality,
        addr.addressRegion,
        addr.addressCountry,
      ].filter(Boolean);
      if (addrParts.length) parts.push(addrParts.join(", "));
    }

    return parts.join(" | ");
  }

  function extractSalaryFromLd(posting) {
    const salary = posting.baseSalary || posting.estimatedSalary;
    if (!salary) return "";

    const s = Array.isArray(salary) ? salary[0] : salary;
    if (!s) return "";

    const value = s.value;
    if (!value) {
      // Simple string
      if (typeof s === "string") return s;
      return "";
    }

    const currency = s.currency || "";
    if (typeof value === "object") {
      const min = value.minValue;
      const max = value.maxValue;
      const unit = value.unitText || s.unitText || "";
      if (min && max) return `${currency} ${min}–${max} ${unit}`.trim();
      if (min) return `${currency} ${min}+ ${unit}`.trim();
      if (max) return `${currency} up to ${max} ${unit}`.trim();
      if (value.value) return `${currency} ${value.value} ${unit}`.trim();
    }

    return `${currency} ${value}`.trim();
  }

  // ---------------------------------------------------------------------------
  // 2. Microdata extraction (schema.org itemprop)
  // ---------------------------------------------------------------------------

  function extractFromMicrodata() {
    const title = cleanTitle(
      pickFirstText([
        '[itemprop="title"]',
        '[itemprop="jobTitle"]',
        '[itemprop="name"]',
      ])
    );

    const company = pickFirstText([
      '[itemprop="hiringOrganization"] [itemprop="name"]',
      '[itemprop="hiringOrganization"]',
      '[itemprop="name"][itemtype*="Organization"]',
    ]);

    const location = pickFirstText([
      '[itemprop="jobLocation"] [itemprop="addressLocality"]',
      '[itemprop="jobLocation"] [itemprop="addressRegion"]',
      '[itemprop="jobLocation"]',
      '[itemprop="jobLocationType"]',
    ]);

    const description = clampDescription(
      pickFirstText(['[itemprop="description"]', '[itemprop="responsibilities"]'])
    );
    const postedAt = pickDateValue([
      '[itemprop="datePosted"]',
      'meta[itemprop="datePosted"]',
      'time[itemprop="datePosted"]'
    ]);
    const applicationDeadline = pickDateValue([
      '[itemprop="validThrough"]',
      'meta[itemprop="validThrough"]',
      'time[itemprop="validThrough"]'
    ]);

    if (!title && !description) return null;

    return {
      title,
      company,
      location,
      description,
      salary: "",
      postedAt,
      applicationDeadline,
      source: "microdata",
    };
  }

  // ---------------------------------------------------------------------------
  // 3. LinkedIn panel extraction (selected job details in two-pane layout)
  // ---------------------------------------------------------------------------

  function isLinkedInJobsContext() {
    return /(^|\.)linkedin\.com$/i.test(location.hostname) && /\/jobs(\/|$)/i.test(location.pathname);
  }

  function hasLinkedInListPaneSignals(element) {
    if (!(element instanceof Element)) return false;
    return Boolean(
      element.querySelector(
        ".jobs-search-results-list, .jobs-search-results__list-item, ul.scaffold-layout__list-container, .scaffold-layout__list"
      )
    );
  }

  function scoreLinkedInDetailsRegion(element) {
    if (!(element instanceof Element)) return -10;
    if (hasLinkedInListPaneSignals(element)) return -10;

    const text = normalizeText(element?.innerText || "");
    if (!text || text.length < MIN_DESCRIPTION_LENGTH) return -10;

    let score = 0;
    if (text.length >= 280 && text.length <= 16000) score += 2;
    if (
      element.querySelector(
        ".job-details-jobs-unified-top-card, .jobs-unified-top-card, .jobs-unified-top-card__job-title, .job-details-jobs-unified-top-card__job-title"
      )
    ) {
      score += 3;
    }
    if (element.querySelector(".jobs-apply-button, .jobs-apply-button--top-card, [data-live-test-job-apply-button]")) {
      score += 2;
    }
    if (element.querySelector('a[href*="/company/"]')) score += 2;
    if (
      element.querySelector(
        ".jobs-description-content__text, .jobs-description__content, .jobs-box__html-content, #job-details"
      )
    ) {
      score += 5;
    }
    if (/\b(about the job|responsibilities|qualifications|job description)\b/i.test(text)) score += 2;
    if (/\b(top job picks for you|jobs for you)\b/i.test(text)) score -= 4;
    if (/\b(people also viewed|more jobs|promoted)\b/i.test(text)) score -= 2;
    return score;
  }

  function findLinkedInDetailsRegion() {
    const candidates = new Set();
    const selectors = [
      ".jobs-search__job-details--container",
      ".jobs-search-two-pane__job-details",
      ".jobs-search-two-pane__job-details-pane",
      ".jobs-details",
      ".jobs-details__main-content",
      ".scaffold-layout__detail",
      "section.jobs-search__right-rail",
      "[aria-label*='job details' i]",
      "[id*='job-details' i]",
      "[data-testid*='job-details' i]",
    ];

    for (const selector of selectors) {
      document.querySelectorAll(selector).forEach((element) => candidates.add(element));
    }

    document
      .querySelectorAll(".jobs-description-content__text, .jobs-box__html-content, #job-details")
      .forEach((element) => {
        const container = element.closest("section, article, main, div");
        if (container) candidates.add(container);
      });

    document
      .querySelectorAll(
        ".job-details-jobs-unified-top-card, .jobs-unified-top-card, .jobs-unified-top-card__job-title, .job-details-jobs-unified-top-card__job-title"
      )
      .forEach((element) => {
        const container = element.closest(
          ".jobs-search__job-details--container, .jobs-search-two-pane__job-details, .jobs-search-two-pane__job-details-pane, .jobs-details, .scaffold-layout__detail, section, main"
        );
        if (container) candidates.add(container);
      });

    const scored = Array.from(candidates)
      .map((element) => ({ element, score: scoreLinkedInDetailsRegion(element) }))
      .filter((candidate) => candidate.score >= 4)
      .sort((a, b) => b.score - a.score);

    return scored[0]?.element || null;
  }

  function tryExpandLinkedInDescription(root) {
    const selectors = [
      'button[aria-label*="click to see more description" i]',
      'button[aria-label*="show more" i]',
      'button[aria-label*="see more" i]',
      ".jobs-description__footer-button",
      ".jobs-box__footer-button",
    ];

    for (const selector of selectors) {
      const button = root.querySelector(selector);
      if (!(button instanceof HTMLElement)) continue;
      if (button.getAttribute("aria-expanded") === "true") continue;

      const signal = `${normalizeText(button.textContent || "")} ${normalizeText(
        button.getAttribute("aria-label") || ""
      )}`.toLowerCase();
      if (signal && !/\b(more|expand|full)\b/.test(signal)) continue;

      button.click();
      return true;
    }

    return false;
  }

  function extractLinkedInDescriptionText(root) {
    const directSelectors = [
      ".jobs-description-content__text",
      ".jobs-description__content",
      ".jobs-box__html-content",
      "#job-details",
      '[id*="job-details" i]',
      '[data-test-id*="job-details" i]',
      '[data-testid*="job-details" i]',
    ];

    for (const selector of directSelectors) {
      const text = pickFirstInnerText([selector], root);
      if (!text) continue;
      const normalized = cleanDescriptionText(dedupeWords(clampDescription(text)) || text);
      if (isValidDescription(normalized)) return normalized;
    }

    const headings = Array.from(root.querySelectorAll("h2, h3, strong, span"))
      .map((el) => ({ el, text: normalizeText(el.textContent || "") }))
      .filter((entry) => /\b(about the job|job description|responsibilities|qualifications|what you'll do)\b/i.test(entry.text));

    for (const heading of headings) {
      const container = heading.el.closest("section, article, div");
      if (!container || hasLinkedInListPaneSignals(container)) continue;
      const text = normalizeText(container.innerText || "");
      if (!text) continue;
      const normalized = cleanDescriptionText(dedupeWords(clampDescription(text)) || text);
      if (isValidDescription(normalized)) return normalized;
    }

    return "";
  }

  function extractFromLinkedInPanel() {
    if (!isLinkedInJobsContext()) return null;

    const root = findLinkedInDetailsRegion();
    if (!root) return null;
    if (hasLinkedInListPaneSignals(root)) return null;

    tryExpandLinkedInDescription(root);

    const parsedTitleCompany = parseTitleCompanyFromDocumentTitle();
    const topCard =
      root.querySelector(".job-details-jobs-unified-top-card, .jobs-unified-top-card") || root;

    const titleCandidate = cleanTitle(
      pickFirstText(
        [
          ".job-details-jobs-unified-top-card__job-title",
          ".jobs-unified-top-card__job-title",
          '[class*="jobs-unified-top-card__job-title"]',
          '[data-test-id*="job-title" i]',
          '[data-testid*="job-title" i]',
        ],
        topCard
      )
    );
    const title = looksLikeTitle(titleCandidate)
      ? titleCandidate
      : looksLikeTitle(parsedTitleCompany.title)
      ? parsedTitleCompany.title
      : "";

    const companyCandidate =
      pickFirstText(
        [
          ".job-details-jobs-unified-top-card__company-name a",
          ".jobs-unified-top-card__company-name a",
          ".job-details-jobs-unified-top-card__company-name",
          ".jobs-unified-top-card__company-name",
          '[class*="jobs-unified-top-card__company-name"] a',
          '[class*="jobs-unified-top-card__company-name"]',
          '[data-test-id*="company" i]',
          '[data-testid*="company" i]',
          'a[href*="/company/"]',
        ],
        topCard
      ) || parsedTitleCompany.company;
    const company = isValidCompany(companyCandidate) ? companyCandidate : "";

    const topCardText = normalizeText(
      topCard.innerText || ""
    );
    const topLines = compactMultiline(topCardText)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean)
      .slice(0, 28);

    const locationCandidate = cleanLocation(
      pickFirstText(
        [
          ".jobs-unified-top-card__bullet",
          ".job-details-jobs-unified-top-card__tertiary-description-container",
          '[class*="jobs-unified-top-card__bullet"]',
          '[aria-label*="location" i]',
          '[data-test-id*="location" i]',
          '[data-testid*="location" i]',
        ],
        topCard
      ) || extractLocationFromLines(topLines)
    );
    const location = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = extractLinkedInDescriptionText(root);
    const salary =
      pickFirstText(
        [
          '[aria-label*="salary" i]',
          '[data-test-id*="salary" i]',
          '[data-testid*="salary" i]',
        ],
        topCard
      ) || extractSalaryFromText(`${topCardText}\n${description}`);
    const postedAt =
      pickDateValue(
        [
          'time[datetime][aria-label*="posted" i]',
          '[datetime][data-test-id*="posted" i]',
          '[datetime][data-testid*="posted" i]'
        ],
        root
      ) || extractPostedDateFromText(`${topCardText}\n${description}`);
    const applicationDeadline =
      pickDateValue(
        [
          '[itemprop="validThrough"]',
          'time[datetime][aria-label*="deadline" i]',
          '[datetime][data-test-id*="deadline" i]',
          '[datetime][data-testid*="deadline" i]'
        ],
        root
      ) || extractDeadlineDateFromText(`${topCardText}\n${description}`);

    if (!title && !description) return null;

    return {
      title,
      company,
      location,
      description,
      salary,
      postedAt,
      applicationDeadline,
      source: "linkedin-panel",
    };
  }

  // ---------------------------------------------------------------------------
  // 4. Semantic DOM extraction (class-agnostic heuristics)
  // ---------------------------------------------------------------------------

  function scoreRegion(element) {
    const text = normalizeText(element.innerText || "");
    if (!text || text.length < 160) return -10;

    let score = 0;

    if (text.length >= 400 && text.length <= 15000) score += 2;
    if (element.matches("main, article, [role='main'], [itemtype*='JobPosting']")) score += 2;
    if (element.querySelector("h1, h2")) score += 1;

    score += Math.min(countKeywordHits(text, JOB_KEYWORDS), 5);
    score -= Math.min(countKeywordHits(text, NOISE_KEYWORDS), 4);

    return score;
  }

  function getCandidateRegions() {
    const candidates = new Set();
    const selectors = [
      "main",
      "[role='main']",
      "article",
      "section",
      "[itemtype*='JobPosting']",
      "[itemprop='description']",
      "[id*='job' i]",
      "[id*='description' i]",
      "[aria-label*='job' i]",
      "[data-job-id]",
      "[data-testid*='job' i]",
      "[data-test-id*='job' i]",
    ];

    for (const selector of selectors) {
      document.querySelectorAll(selector).forEach((element) => candidates.add(element));
    }

    return Array.from(candidates);
  }

  function extractCompanyFromLines(lines, title) {
    for (const line of lines) {
      if (!line || line === title) continue;
      if (looksLikeLocation(line)) continue;
      if (countKeywordHits(line, JOB_KEYWORDS) > 0) continue;
      if (isValidCompany(line)) return line;
    }
    return "";
  }

  function extractLocationFromLines(lines) {
    for (const line of lines) {
      if (looksLikeLocation(line)) return cleanLocation(line);
    }
    return "";
  }

  function extractFromSemanticDom() {
    const candidates = getCandidateRegions()
      .map((element) => ({ element, score: scoreRegion(element) }))
      .filter((candidate) => candidate.score >= 2)
      .sort((a, b) => b.score - a.score);

    if (!candidates.length) return null;

    const best = candidates[0].element;
    const rawText = dedupeWords(clampDescription(best.innerText || ""));
    if (!rawText) return null;

    const cleanedDescription = cleanDescriptionText(rawText);
    const text = cleanedDescription || rawText;

    const rawLines = compactMultiline(rawText)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean)
      .slice(0, 40);

    const lines = compactMultiline(text)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean)
      .slice(0, 40);

    const parsedTitleCompany = parseTitleCompanyFromDocumentTitle();
    const title = extractBestTitle(best, rawLines.length ? rawLines : lines, parsedTitleCompany.title);
    const company =
      pickFirstText([
        '[itemprop="hiringOrganization"] [itemprop="name"]',
        '[itemprop="hiringOrganization"]',
      ], best) ||
      pickFirstText([
        'a[href*="/company/"]',
        '[aria-label*="company" i]',
        '[data-test-id*="company" i]',
        '[data-testid*="company" i]',
      ]) ||
      extractCompanyFromLines(rawLines.length ? rawLines : lines, title) ||
      parsedTitleCompany.company ||
      "";

    const location = cleanLocation(
      pickFirstText([
        '[itemprop="jobLocationType"]',
        '[itemprop="jobLocation"] [itemprop="addressLocality"]',
        '[itemprop="jobLocation"] [itemprop="addressRegion"]',
      ], best) ||
      pickFirstText([
        '[aria-label*="location" i]',
        '[data-test-id*="location" i]',
        '[data-testid*="location" i]',
      ]) ||
      extractLocationFromLines(rawLines.length ? rawLines : lines) ||
      ""
    );

    const salary = extractSalaryFromText(text);
    const postedAt =
      pickDateValue(
        [
          '[itemprop="datePosted"]',
          'time[datetime][aria-label*="posted" i]',
          '[datetime][data-test-id*="posted" i]',
          '[datetime][data-testid*="posted" i]'
        ],
        best
      ) || extractPostedDateFromText(rawText);
    const applicationDeadline =
      pickDateValue(
        [
          '[itemprop="validThrough"]',
          'time[datetime][aria-label*="deadline" i]',
          '[datetime][data-test-id*="deadline" i]',
          '[datetime][data-testid*="deadline" i]'
        ],
        best
      ) || extractDeadlineDateFromText(rawText);

    return {
      title,
      company,
      location,
      description: text,
      salary,
      postedAt,
      applicationDeadline,
      source: "semantic-dom",
    };
  }

  // ---------------------------------------------------------------------------
  // 5. Meta tag extraction (Open Graph, standard meta)
  // ---------------------------------------------------------------------------

  function metaContent(nameOrProp) {
    const el =
      document.querySelector(`meta[property="${nameOrProp}"]`) ||
      document.querySelector(`meta[name="${nameOrProp}"]`);
    return el ? normalizeText(el.getAttribute("content") || "") : "";
  }

  function extractFromMeta() {
    const title = cleanTitle(metaContent("og:title") || metaContent("twitter:title"));
    const description = clampDescription(
      metaContent("og:description") ||
        metaContent("twitter:description") ||
        metaContent("description")
    );
    const siteName = metaContent("og:site_name");
    const parsed = parseTitleCompanyFromDocumentTitle();

    if (!title && !description) return null;

    const company =
      (siteName && !/linkedin|indeed|glassdoor|naukri/i.test(siteName) ? siteName : "") ||
      parsed.company ||
      "";

    return {
      title: title || parsed.title || "",
      company,
      location: "",
      description,
      salary: "",
      postedAt: "",
      applicationDeadline: "",
      source: "meta",
    };
  }

  // ---------------------------------------------------------------------------
  // Platform detection
  // ---------------------------------------------------------------------------

  function detectPlatform() {
    const host = location.hostname.replace(/^www\./, "");
    if (host.includes("linkedin.com")) return "LinkedIn";
    if (host.includes("indeed.com")) return "Indeed";
    if (host.includes("glassdoor.com")) return "Glassdoor";
    if (host.includes("naukri.com")) return "Naukri";
    if (host.includes("instahyre.com")) return "Instahyre";
    return "Other";
  }

  // ---------------------------------------------------------------------------
  // Confidence and merge
  // ---------------------------------------------------------------------------

  function normalizeRecord(record) {
    if (!record) return null;
    return {
      title: cleanTitle(record.title || ""),
      company: normalizeText(record.company || ""),
      location: cleanLocation(record.location || ""),
      description: cleanDescriptionText(record.description || ""),
      salary: normalizeText(record.salary || ""),
      postedAt: normalizeText(record.postedAt || ""),
      applicationDeadline: normalizeText(record.applicationDeadline || ""),
      source: record.source || "unknown",
    };
  }

  function fieldScore(field, value) {
    if (!value) return 0;

    if (field === "title") {
      return looksLikeTitle(value) ? 0.32 : 0.05;
    }

    if (field === "company") {
      return isValidCompany(value) ? 0.18 : 0.03;
    }

    if (field === "location") {
      return looksLikeLocation(value) ? 0.1 : 0.05;
    }

    if (field === "description") {
      if (!isValidDescription(value)) return 0.04;
      if (value.length >= 600) return 0.33;
      if (value.length >= 250) return 0.26;
      return 0.18;
    }

    if (field === "salary") {
      return value ? 0.05 : 0;
    }

    return 0;
  }

  function sourceBonus(source) {
    switch (source) {
      case "linkedin-panel":
        return 0.14;
      case "jsonld":
        return 0.12;
      case "microdata":
        return 0.1;
      case "semantic-dom":
        return 0.08;
      case "meta":
        return 0.02;
      default:
        return 0;
    }
  }

  function bestField(field, records) {
    let bestValue = "";
    let bestSource = "";
    let bestScore = -1;

    for (const record of records) {
      const value = record[field] || "";
      if (!value) continue;
      const score = fieldScore(field, value) + sourceBonus(record.source);
      if (score > bestScore) {
        bestScore = score;
        bestValue = value;
        bestSource = record.source;
      }
    }

    return { value: bestValue, source: bestSource, score: Math.max(bestScore, 0) };
  }

  function bestDateField(field, records) {
    let bestValue = "";
    let bestSource = "";
    let bestScore = -1;

    for (const record of records) {
      const value = record[field] || "";
      if (!value) continue;

      let score = 0;
      switch (record.source) {
        case "jsonld":
          score = 0.5;
          break;
        case "microdata":
          score = 0.42;
          break;
        case "linkedin-panel":
          score = 0.34;
          break;
        case "semantic-dom":
          score = 0.28;
          break;
        default:
          score = 0.12;
          break;
      }

      if (score > bestScore) {
        bestScore = score;
        bestValue = value;
        bestSource = record.source;
      }
    }

    return { value: bestValue, source: bestSource };
  }

  function computeConfidence(fields) {
    const base =
      fields.title.score +
      fields.company.score +
      fields.location.score +
      fields.description.score +
      fields.salary.score;
    return Math.min(1, Math.max(0, base));
  }

  function isUsableResult(data, confidence) {
    if (!looksLikeTitle(data.title)) return false;
    if (!isValidDescription(data.description)) return false;
    if (!data.company && !data.location) return false;
    if (confidence < CONFIDENCE_THRESHOLD) return false;
    return true;
  }

  function gatherRawCandidates() {
    return {
      linkedinPanel: extractFromLinkedInPanel(),
      jsonLd: extractFromJsonLd(),
      microdata: extractFromMicrodata(),
      semanticDom: extractFromSemanticDom(),
      meta: extractFromMeta(),
    };
  }

  function extractJobDataFromCandidates(rawCandidates) {
    const records = Object.values(rawCandidates).map(normalizeRecord).filter(Boolean);
    if (!records.length) return null;

    const fields = {
      title: bestField("title", records),
      company: bestField("company", records),
      location: bestField("location", records),
      description: bestField("description", records),
      salary: bestField("salary", records),
    };

    const title = fields.title.value;
    const company = fields.company.value;
    const jobLocation = fields.location.value;
    const description = fields.description.value;
    const salary = fields.salary.value;
    const postedAt = bestDateField("postedAt", records);
    const applicationDeadline = bestDateField("applicationDeadline", records);
    const confidence = computeConfidence(fields);

    const payload = {
      title,
      company,
      location: jobLocation,
      description,
      salary,
      postedAt: postedAt.value,
      applicationDeadline: applicationDeadline.value,
      url: window.location.href,
      platform: detectPlatform(),
      extractionQuality: {
        confidence,
        sources: {
          title: fields.title.source || "",
          company: fields.company.source || "",
          location: fields.location.source || "",
          description: fields.description.source || "",
          salary: fields.salary.source || "",
          postedAt: postedAt.source || "",
          applicationDeadline: applicationDeadline.source || "",
        },
      },
    };

    if (!isUsableResult(payload, confidence)) return null;

    return payload;
  }

  function extractJobData() {
    const rawCandidates = gatherRawCandidates();
    return extractJobDataFromCandidates(rawCandidates);
  }

  function extractJobDataAndDebugPacket() {
    const rawCandidates = gatherRawCandidates();
    const extractedData = extractJobDataFromCandidates(rawCandidates);
    const debugPacket = collectDebugPacket(extractedData, rawCandidates);
    return { extractedData, debugPacket };
  }

  async function extractJobDataWithRetries() {
    const delays = detectPlatform() === "LinkedIn" ? [0, 180, 420, 780, 1250] : [0, 120, 320];
    for (const delayMs of delays) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const result = extractJobData();
      if (result) return result;
    }
    return null;
  }

  async function extractDebugPacketWithRetries() {
    const delays = detectPlatform() === "LinkedIn" ? [0, 180, 420, 780, 1250] : [0, 120, 320];
    for (const delayMs of delays) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const { extractedData, debugPacket } = extractJobDataAndDebugPacket();
      if (extractedData) return debugPacket;
    }

    // Return at least one packet even if extraction fails confidence gating.
    return extractJobDataAndDebugPacket().debugPacket;
  }

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

  const messageHandler =
    typeof browser !== "undefined" ? browser.runtime.onMessage : chrome.runtime.onMessage;

  messageHandler.addListener((request, _sender, sendResponse) => {
    if (request.action === "ping") {
      sendResponse({ pong: true });
      return;
    }
    if (request.action === "extractJobData") {
      (async () => {
        try {
          const data = await extractJobDataWithRetries();
          if (!data) {
            sendResponse({ success: false, error: "Low-confidence or missing job data" });
            return;
          }
          sendResponse({ success: true, data });
        } catch (err) {
          sendResponse({ success: false, error: err.message });
        }
      })();
      return true;
    }
    if (request.action === "collectDebugPacket") {
      (async () => {
        try {
          const data = await extractDebugPacketWithRetries();
          sendResponse({ success: true, data });
        } catch (err) {
          sendResponse({ success: false, error: err.message });
        }
      })();
      return true;
    }
    return false;
  });
})();
