// Pipeline — Content Script
// Extracts job posting data from the current page.
// Shared between Safari and Chrome extensions.
//
// Extraction priority:
//   1. Platform-specific extraction (LinkedIn, Indeed, Glassdoor, Greenhouse, Lever, Workday)
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
  const PARTIAL_CONFIDENCE_THRESHOLD = 0.42;
  const MAX_DESCRIPTION_LENGTH = 15000;
  const DEBUG_TEXT_LIMIT = 20000;
  const ADAPTER_VERSION = "adapter-v1";

  const RESULT_STATE = {
    SUCCESS: "success",
    PARTIAL: "partial",
    UNSUPPORTED: "unsupported",
    BROKEN_SITE_ADAPTER: "broken_site_adapter",
  };

  const SITE_KEYS = {
    LinkedIn: "linkedin",
    Indeed: "indeed",
    Glassdoor: "glassdoor",
    Greenhouse: "greenhouse",
    Lever: "lever",
    Workday: "workday",
    Naukri: "naukri",
    Instahyre: "instahyre",
    Other: "other",
  };

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

  function isDescriptionBulletLine(line) {
    return /^(?:[•●◦▪‣∙*-]|\d{1,3}[.)]|[A-Za-z][.)])\s+/.test(line);
  }

  function normalizeDescriptionLine(line) {
    const normalized = normalizeText(line || "");
    if (!normalized) return "";

    if (isDescriptionBulletLine(normalized)) {
      const body = normalizeText(
        normalized.replace(/^(?:[•●◦▪‣∙*-]|\d{1,3}[.)]|[A-Za-z][.)])\s+/, "")
      );
      return body ? `• ${body}` : "";
    }

    return normalized;
  }

  function isLikelyDescriptionHeading(line) {
    const normalized = normalizeText(line || "");
    if (!normalized || normalized.length > 80) return false;
    if (normalized.endsWith(":")) return true;
    if (/[.!?]/.test(normalized)) return false;

    const words = normalized.split(/\s+/).filter(Boolean);
    if (!words.length || words.length > 8) return false;
    if (!/^[A-Z0-9]/.test(normalized)) return false;

    const connectorWords = new Set(["a", "an", "and", "for", "in", "of", "on", "or", "the", "to", "with"]);
    const titleishWords = words.filter((word) => {
      const cleaned = word.replace(/^[^A-Za-z0-9]+|[^A-Za-z0-9:]+$/g, "");
      if (!cleaned) return false;
      if (connectorWords.has(cleaned.toLowerCase())) return true;
      return /^[A-Z0-9]/.test(cleaned) || /^[A-Z]{2,}$/.test(cleaned);
    }).length;

    return titleishWords >= Math.max(1, words.length - 1);
  }

  function classifyDescriptionLine(line) {
    if (!line) return "blank";
    if (line.startsWith("• ")) return "bullet";
    if (isLikelyDescriptionHeading(line)) return "heading";
    return "paragraph";
  }

  function formatDescriptionText(text) {
    const rawLines = String(text || "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .replace(/\u00a0/g, " ")
      .split("\n");

    const formatted = [];
    let previousKind = "blank";

    for (const rawLine of rawLines) {
      const line = normalizeDescriptionLine(rawLine);
      if (!line) {
        if (formatted.length && formatted[formatted.length - 1] !== "") {
          formatted.push("");
        }
        previousKind = "blank";
        continue;
      }

      const currentKind = classifyDescriptionLine(line);
      const lastIndex = formatted.length - 1;

      if (
        currentKind === "paragraph" &&
        previousKind === "paragraph" &&
        lastIndex >= 0 &&
        formatted[lastIndex] !== ""
      ) {
        formatted[lastIndex] = `${formatted[lastIndex]} ${line}`;
      } else {
        const needsBlankLine =
          formatted.length > 0 &&
          formatted[lastIndex] !== "" &&
          (currentKind === "heading" ||
            previousKind === "heading" ||
            (currentKind === "paragraph" && previousKind === "bullet") ||
            (currentKind === "bullet" && previousKind === "paragraph"));

        if (needsBlankLine) {
          formatted.push("");
        }

        formatted.push(line);
      }

      previousKind = currentKind;
    }

    return normalizeText(formatted.join("\n").replace(/\n{3,}/g, "\n\n"));
  }

  function stripHtml(html) {
    const div = document.createElement("div");
    div.innerHTML = html;
    return formatDescriptionText(div.innerText);
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

  function normalizeAbsoluteUrl(value) {
    const normalized = normalizeText(value);
    if (!normalized) return "";

    try {
      return new URL(normalized, window.location.origin).href;
    } catch {
      return normalized;
    }
  }

  function looksLikePersonName(text) {
    const value = normalizeText(text);
    if (!value || value.length < 5 || value.length > 80) return false;
    if (/\d/.test(value) || /[|@]/.test(value)) return false;
    if (/\b(meet the hiring team|people you can reach out to|school alumni|mutual connection|message|connect|follow|show all|about the job)\b/i.test(value)) {
      return false;
    }

    const words = value.split(/\s+/).filter(Boolean);
    if (words.length < 2 || words.length > 5) return false;

    return words.every((word) => /^[A-Z][A-Za-z'’.-]*$/.test(word));
  }

  function isLinkedInContactNoiseLine(line) {
    const value = normalizeText(line);
    if (!value) return true;
    const lower = value.toLowerCase();

    if (
      lower === "meet the hiring team" ||
      lower === "people you can reach out to" ||
      lower === "show all" ||
      lower === "message" ||
      lower === "connect" ||
      lower === "follow" ||
      lower === "about the job" ||
      lower === "apply" ||
      lower === "save" ||
      lower === "share" ||
      lower === "show more options"
    ) {
      return true;
    }

    if (/^\d+(?:st|nd|rd|th)$/.test(lower) || lower === "following") return true;
    if (/\bmutual connection\b/.test(lower)) return true;
    if (/\bschool alumni\b/.test(lower)) return true;
    if (/\blogo\b/.test(lower)) return true;

    return false;
  }

  function normalizeContactRole(role) {
    const normalized = normalizeText(role);
    if (!normalized) return "Other";

    switch (normalized.toLowerCase()) {
      case "recruiter":
        return "Recruiter";
      case "hiring manager":
      case "hiringmanager":
        return "Hiring Manager";
      case "interviewer":
        return "Interviewer";
      case "referrer":
        return "Referrer";
      default:
        return "Other";
    }
  }

  function inferLinkedInContactRole(title) {
    const lower = normalizeText(title).toLowerCase();
    if (!lower) return "Other";
    if (/\b(recruit|recruiting|talent|sourc|staffing|people partner|human resources|hr)\b/.test(lower)) {
      return "Recruiter";
    }
    if (/\b(hiring manager|manager|director|head|lead|vp|vice president)\b/.test(lower)) {
      return "Hiring Manager";
    }
    return "Other";
  }

  function normalizeContact(contact, fallbackCompanyName = "") {
    if (!contact) return null;

    const fullName = normalizeText(contact.fullName || contact.name || "");
    if (!looksLikePersonName(fullName)) return null;

    return {
      fullName,
      companyName: normalizeText(contact.companyName || fallbackCompanyName || ""),
      title: normalizeText(contact.title || ""),
      relationship: normalizeText(contact.relationship || ""),
      linkedInURL: normalizeAbsoluteUrl(contact.linkedInURL || contact.linkedinURL || contact.url || ""),
      role: normalizeContactRole(contact.role || inferLinkedInContactRole(contact.title || "")),
    };
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
    return formatDescriptionText(text).substring(0, MAX_DESCRIPTION_LENGTH);
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

  function isValidDescription(value, minLength = MIN_DESCRIPTION_LENGTH) {
    if (!value) return false;
    const text = normalizeText(value);
    if (text.length < minLength) return false;
    if (text.split(/\s+/).length < (minLength < 120 ? 15 : 35)) return false;
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

    // Primary regex: explicit currency symbols/codes
    const salaryRegex =
      /(?:[\$\u20B9]|USD|INR|EUR|GBP|Rs\.?)\s?(?:\d{2,3}(?:,\d{3})+|\d+(?:\.\d+)?\s?[kKmM])(?:\s*(?:-|to|–)\s*(?:[\$\u20B9]|USD|INR|EUR|GBP|Rs\.?)?\s?(?:\d{2,3}(?:,\d{3})+|\d+(?:\.\d+)?\s?[kKmM]))?(?:\s*(?:\/|per)\s*(?:year|yr|month|mo|hour|hr|annum))?/i;

    // Indian salary formats: ₹12 LPA, 8-12 LPA, 10 lakhs, 15 CTC
    const indianSalaryRegex =
      /(?:[\u20B9]|INR|Rs\.?)\s?\d+(?:\.\d+)?\s*(?:LPA|lakhs?|CTC|crore)?(?:\s*(?:-|to|–)\s*(?:[\u20B9]|INR|Rs\.?)?\s?\d+(?:\.\d+)?\s*(?:LPA|lakhs?|CTC|crore)?)?/i;

    // Bare range fallback: "80,000 - 120,000" (only with salary context)
    const bareRangeRegex =
      /\b(\d{2,3}(?:,\d{3})+)\s*(?:-|to|–)\s*(\d{2,3}(?:,\d{3})+)\b/;

    const lines = compactMultiline(text)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean);

    for (const line of lines.slice(0, 120)) {
      const hasSalaryContext = /\b(salary|compensation|pay|base|ctc|ote|package|lpa|lakhs?)\b/i.test(line);

      // Try primary currency regex
      const match = line.match(salaryRegex);
      if (match) {
        if (!hasSalaryContext && !/(?:per|\/)\s*(?:year|yr|month|mo|hour|hr|annum)|[-–]|\bto\b/i.test(match[0])) {
          continue;
        }
        if (isLikelySalaryValue(match[0], line)) return normalizeText(match[0]);
      }

      // Try Indian salary format
      const indianMatch = line.match(indianSalaryRegex);
      if (indianMatch && isLikelySalaryValue(indianMatch[0], line)) {
        return normalizeText(indianMatch[0]);
      }

      // Try bare range only with salary context
      if (hasSalaryContext) {
        const bareMatch = line.match(bareRangeRegex);
        if (bareMatch && isLikelySalaryValue(bareMatch[0], line)) {
          return normalizeText(bareMatch[0]);
        }
      }
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
    const lines = formatDescriptionText(text)
      .split("\n")
      .map((line) => normalizeText(line));

    const contentLines = lines.filter(Boolean);

    if (!contentLines.length) return "";

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

    const core = lines
      .slice(startIndex, endIndex)
      .filter((line, index, source) => {
        if (!line) {
          const previous = source[index - 1];
          const next = source[index + 1];
          return Boolean(previous && next);
        }
        return !isUiNoiseLine(line);
      });

    return clampDescription(core.join("\n"));
  }

  function truncateDebugText(text, limit = DEBUG_TEXT_LIMIT) {
    const value = normalizeText(text || "");
    if (!value) return "";
    if (value.length <= limit) return value;
    return `${value.substring(0, limit)}\n\n[truncated ${value.length - limit} chars]`;
  }

  function truncateRawDebugText(text, limit = DEBUG_TEXT_LIMIT) {
    const value = String(text || "").trim();
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

  function summarizeDebugElement(element, extras = {}) {
    if (!(element instanceof Element)) return null;
    return {
      tagName: element.tagName.toLowerCase(),
      domFingerprint: buildDomFingerprint(element),
      textPreview: truncateDebugText(element.innerText || "", 2500),
      htmlPreview: truncateRawDebugText(element.outerHTML || "", 5000),
      ...extras,
    };
  }

  function collectDebugPacket(outcome) {
    const { context, adapterRun, rawCandidates, payload, resultState } = outcome || {};
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
      extractorVersion: ADAPTER_VERSION,
      url: window.location.href,
      platform: detectPlatform(),
      siteKey: context?.siteKey || detectSiteKey(),
      variantKey: adapterRun?.variantKey || "",
      adapterVersion: ADAPTER_VERSION,
      resultState: resultState || RESULT_STATE.UNSUPPORTED,
      fallbackUsed: Boolean(payload?.extractionQuality?.fallbackUsed),
      validationErrors: adapterRun?.validation?.errors || [],
      matchedSelectors: adapterRun?.diagnostics?.matchedSelectors || {},
      missingRequiredSelectors: adapterRun?.diagnostics?.missingRequiredSelectors || [],
      domFingerprint: adapterRun?.diagnostics?.domFingerprint || buildDomFingerprint(),
      documentTitle: document.title || "",
      extraction: payload || null,
      candidates: {
        siteAdapter: toDebugRecord(rawCandidates?.siteAdapter),
        jsonLd: toDebugRecord(rawCandidates?.jsonLd),
        microdata: toDebugRecord(rawCandidates?.microdata),
        semanticDom: toDebugRecord(rawCandidates?.semanticDom),
        meta: toDebugRecord(rawCandidates?.meta),
      },
      meta,
      jsonLdCount: document.querySelectorAll('script[type="application/ld+json"]').length,
      jsonLdScripts,
      mainText,
      bodyTextHead,
    };
  }

  function collectDomDebugPacket(outcome) {
    const { context, adapterRun, payload, resultState } = outcome || {};
    const currentJobId = context?.siteKey === SITE_KEYS.LinkedIn ? getLinkedInCurrentJobId() : "";
    const linkedInCandidates =
      context?.siteKey === SITE_KEYS.LinkedIn
        ? getLinkedInDetailsRegionCandidates()
            .slice(0, 8)
            .map(({ element, score }) =>
              summarizeDebugElement(element, {
                score,
                currentJobMatch: hasLinkedInCurrentJobSignal(element, currentJobId),
                hasListSignals: hasLinkedInListPaneSignals(element),
                jobLinkCount: countLinkedInJobLinks(element),
              })
            )
            .filter(Boolean)
        : [];
    const semanticCandidates = getSemanticDomCandidates()
      .slice(0, 5)
      .map(({ element, score }) =>
        summarizeDebugElement(element, {
          score,
          jobLinkCount: countLinkedInJobLinks(element),
        })
      )
      .filter(Boolean);

    return {
      timestamp: new Date().toISOString(),
      extractorVersion: ADAPTER_VERSION,
      url: window.location.href,
      platform: detectPlatform(),
      siteKey: context?.siteKey || detectSiteKey(),
      variantKey: adapterRun?.variantKey || "",
      resultState: resultState || RESULT_STATE.UNSUPPORTED,
      documentTitle: document.title || "",
      currentJobId,
      extraction: payload || null,
      adapterDiagnostics: adapterRun
        ? {
            validationErrors: adapterRun.validation?.errors || [],
            matchedSelectors: adapterRun.diagnostics?.matchedSelectors || {},
            missingRequiredSelectors: adapterRun.diagnostics?.missingRequiredSelectors || [],
            domFingerprint: adapterRun.diagnostics?.domFingerprint || "",
          }
        : null,
      linkedInCandidates,
      semanticCandidates,
      bodyPreview: summarizeDebugElement(document.body, {
        childElementCount: document.body?.childElementCount || 0,
      }),
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

  function getLinkedInCurrentJobId() {
    try {
      return normalizeText(new URLSearchParams(location.search).get("currentJobId") || "");
    } catch {
      return "";
    }
  }

  function hasLinkedInListPaneSignals(element) {
    if (!(element instanceof Element)) return false;
    return Boolean(
      element.querySelector(
        ".jobs-search-results-list, .jobs-search-results__list-item, ul.scaffold-layout__list-container, .scaffold-layout__list"
      )
    );
  }

  function countLinkedInJobLinks(element) {
    if (!(element instanceof Element)) return 0;
    return element.querySelectorAll('a[href*="/jobs/view/"], a[href*="/jobs/collections/"]').length;
  }

  function hasLinkedInCurrentJobSignal(element, jobId = getLinkedInCurrentJobId()) {
    if (!(element instanceof Element) || !jobId) return false;
    const selectors = [
      `[data-job-id="${jobId}"]`,
      `[data-urn*="${jobId}"]`,
      `a[href*="/jobs/view/${jobId}"]`,
      `a[href*="currentJobId=${jobId}"]`,
    ];

    return selectors.some((selector) => {
      try {
        return Boolean(element.matches(selector) || element.querySelector(selector));
      } catch {
        return false;
      }
    });
  }

  function addLinkedInAncestorCandidates(element, candidates, maxDepth = 6) {
    let current = element instanceof Element ? element : null;
    let depth = 0;

    while (current && depth < maxDepth) {
      if (/^(SECTION|ARTICLE|MAIN|DIV|ASIDE)$/.test(current.tagName)) {
        candidates.add(current);
      }
      current = current.parentElement;
      depth += 1;
    }
  }

  function scoreLinkedInDetailsRegion(element) {
    if (!(element instanceof Element)) return -10;
    if (hasLinkedInListPaneSignals(element)) return -10;

    const text = normalizeText(element?.innerText || "");
    if (!text || text.length < MIN_DESCRIPTION_LENGTH) return -10;

    let score = 0;
    if (text.length >= 280 && text.length <= 16000) score += 2;
    if (hasLinkedInCurrentJobSignal(element)) score += 4;
    if (
      element.querySelector(
        ".job-details-jobs-unified-top-card, .jobs-unified-top-card, .jobs-unified-top-card__job-title, .job-details-jobs-unified-top-card__job-title"
      )
    ) {
      score += 3;
    }
    if (element.querySelector('button[aria-label*="apply" i], .jobs-apply-button, .jobs-apply-button--top-card, [data-live-test-job-apply-button]')) {
      score += 3;
    }
    if (element.querySelector(".jobs-apply-button, .jobs-apply-button--top-card, [data-live-test-job-apply-button]")) {
      score += 2;
    }
    if (element.querySelector('a[href*="/company/"]')) score += 2;
    if (element.querySelector("h1, h2, [role='heading']")) score += 1;
    if (
      element.querySelector(
        ".jobs-description-content__text, .jobs-description__content, .jobs-box__html-content, #job-details"
      )
    ) {
      score += 5;
    }
    if (/\b(about the job|responsibilities|qualifications|job description)\b/i.test(text)) score += 2;
    if (/\b(posted\s+\d+\s+(hour|day|week|month)s?\s+ago|easy apply|actively reviewing applicants)\b/i.test(text)) score += 1;
    if (/\b(top job picks for you|jobs for you|jobs where you’re more likely to hear back|jobs where you're more likely to hear back|explore companies that hire for your skills)\b/i.test(text)) score -= 5;
    if (/\b(people also viewed|more jobs|promoted|feed post|load more|show all)\b/i.test(text)) score -= 3;
    const jobLinkCount = countLinkedInJobLinks(element);
    if (jobLinkCount >= 6) score -= 6;
    else if (jobLinkCount >= 3) score -= 2;
    return score;
  }

  function getLinkedInDetailsRegionCandidates() {
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

    const genericSeedSelectors = [
      'button[aria-label*="apply" i]',
      ".jobs-apply-button",
      ".jobs-apply-button--top-card",
      "[data-live-test-job-apply-button]",
      'a[href*="/company/"]',
      'h1, h2, [role="heading"]',
      ".jobs-description-content__text",
      ".jobs-description__content",
      ".jobs-box__html-content",
      "#job-details",
      '[aria-label*="job details" i]',
      '[data-test-id*="job-title" i]',
      '[data-testid*="job-title" i]',
    ];

    for (const selector of genericSeedSelectors) {
      document.querySelectorAll(selector).forEach((element) => addLinkedInAncestorCandidates(element, candidates));
    }

    const currentJobId = getLinkedInCurrentJobId();
    if (currentJobId) {
      const currentJobSelectors = [
        `[data-job-id="${currentJobId}"]`,
        `[data-urn*="${currentJobId}"]`,
        `a[href*="/jobs/view/${currentJobId}"]`,
        `a[href*="currentJobId=${currentJobId}"]`,
      ];

      for (const selector of currentJobSelectors) {
        try {
          document.querySelectorAll(selector).forEach((element) => addLinkedInAncestorCandidates(element, candidates, 8));
        } catch {
          // Invalid selector or no matches; continue scanning the rest.
        }
      }
    }

    const scored = Array.from(candidates)
      .map((element) => ({ element, score: scoreLinkedInDetailsRegion(element) }))
      .filter((candidate) => candidate.score >= 4)
      .sort((a, b) => b.score - a.score);

    return scored;
  }

  function findLinkedInDetailsRegion() {
    return getLinkedInDetailsRegionCandidates()[0]?.element || null;
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

    const fallbackText = normalizeText(root.innerText || "");
    if (/\b(about the job|job description|responsibilities|qualifications|what you'll do)\b/i.test(fallbackText)) {
      const normalized = cleanDescriptionText(dedupeWords(clampDescription(fallbackText)) || fallbackText);
      if (isValidDescription(normalized)) return normalized;
    }

    return "";
  }

  function findLinkedInHiringTeamHeading(root) {
    return Array.from(root.querySelectorAll("h1, h2, h3, h4, strong, span, div, p")).find(
      (element) => normalizeText(element.textContent || "").toLowerCase() === "meet the hiring team"
    );
  }

  function selectLinkedInHiringTeamSection(heading, root) {
    let best = heading.parentElement || null;
    let bestScore = -1;

    for (let current = heading.parentElement; current && current !== root; current = current.parentElement) {
      const text = normalizeText(current.innerText || "");
      if (!text || text.length > 1600) continue;

      let score = 0;
      if (/meet the hiring team/i.test(text)) score += 2;
      if (/people you can reach out to/i.test(text)) score += 1;
      if (/mutual connection/i.test(text)) score += 1;
      if (/message/i.test(text)) score += 1;
      if (current.querySelector('a[href*="/in/"], a[href*="linkedin.com/in/"]')) score += 2;
      if (text.length >= 40 && text.length <= 500) score += 1;
      if (/about the job/i.test(text)) score -= 3;

      if (score > bestScore) {
        best = current;
        bestScore = score;
      }
    }

    return best;
  }

  function extractLinkedInHiringContact(root, companyName) {
    const heading = findLinkedInHiringTeamHeading(root);
    if (!heading) return null;

    const section = selectLinkedInHiringTeamSection(heading, root) || root;
    const candidateCards = new Set();

    section.querySelectorAll('a[href*="/in/"], a[href*="linkedin.com/in/"]').forEach((anchor) => {
      const card = anchor.closest("li, article, section, div") || anchor;
      if (card instanceof Element) candidateCards.add(card);
    });

    if (!candidateCards.size) {
      candidateCards.add(section);
    }

    let bestCard = null;
    let bestScore = -1;

    for (const card of candidateCards) {
      const text = normalizeText(card.innerText || "");
      if (!text) continue;

      let score = 0;
      if (card.querySelector('a[href*="/in/"], a[href*="linkedin.com/in/"]')) score += 2;
      if (/mutual connection/i.test(text)) score += 1;
      if (/message/i.test(text)) score += 1;
      if (text.length >= 20 && text.length <= 400) score += 1;
      if (/about the job/i.test(text)) score -= 3;

      if (score > bestScore) {
        bestCard = card;
        bestScore = score;
      }
    }

    const source = bestCard || section;
    const lines = compactMultiline(source.innerText || section.innerText || "")
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean)
      .filter((line) => !isLinkedInContactNoiseLine(line));

    let fullName = "";
    let title = "";

    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (!looksLikePersonName(line)) continue;
      fullName = line;
      title =
        lines
          .slice(index + 1)
          .find((candidate) => !isLinkedInContactNoiseLine(candidate) && !looksLikePersonName(candidate)) || "";
      break;
    }

    if (!fullName) return null;

    const profileLink = source.querySelector('a[href*="/in/"], a[href*="linkedin.com/in/"]');
    return normalizeContact(
      {
        fullName,
        companyName,
        title,
        relationship: "LinkedIn hiring team",
        linkedInURL: profileLink ? profileLink.getAttribute("href") || "" : "",
        role: inferLinkedInContactRole(title),
      },
      companyName
    );
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
    const rootText = normalizeText(root.innerText || "");
    const rootLines = compactMultiline(rootText)
      .split("\n")
      .map((line) => normalizeText(line))
      .filter(Boolean)
      .slice(0, 40);

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
    const fallbackTitle = extractBestTitle(root, rootLines, parsedTitleCompany.title);
    const title = looksLikeTitle(titleCandidate)
      ? titleCandidate
      : looksLikeTitle(fallbackTitle)
      ? fallbackTitle
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
      ) ||
      pickFirstText(
        [
          '[data-test-id*="company" i]',
          '[data-testid*="company" i]',
          'a[href*="/company/"]',
        ],
        root
      ) ||
      extractCompanyFromLines(rootLines, title) ||
      parsedTitleCompany.company;
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
      ) || extractLocationFromLines(topLines) || extractLocationFromLines(rootLines)
    );
    const location = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = extractLinkedInDescriptionText(root);
    const contact = extractLinkedInHiringContact(root, company);
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
      contact,
      salary,
      postedAt,
      applicationDeadline,
      source: "linkedin-panel",
    };
  }

  // ---------------------------------------------------------------------------
  // 4. Indeed extraction
  // ---------------------------------------------------------------------------

  function extractFromIndeed() {
    if (!location.hostname.includes("indeed.com")) return null;

    const title = cleanTitle(
      pickFirstText([
        'h1.jobsearch-JobInfoHeader-title',
        '[data-testid="jobsearch-JobInfoHeader-title"]',
        '.jobsearch-JobInfoHeader-title',
        'h1[class*="JobInfoHeader"]',
        'h1',
      ])
    );

    const company =
      pickFirstText([
        '[data-testid="inlineHeader-companyName"]',
        '[data-company-name="true"]',
        '.jobsearch-InlineCompanyRating-companyHeader a',
        '[data-testid="company-name"]',
        '.jobsearch-CompanyInfoContainer a',
      ]) || parseTitleCompanyFromDocumentTitle().company;

    const locationCandidate = cleanLocation(
      pickFirstText([
        '[data-testid="inlineHeader-companyLocation"]',
        '[data-testid="job-location"]',
        '.jobsearch-JobInfoHeader-subtitle .companyLocation',
        '.jobsearch-CompanyInfoContainer [data-testid="companyLocation"]',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '#jobDescriptionText',
        '.jobsearch-JobComponent-description',
        '[data-testid="jobDescriptionText"]',
        '#jobDescriptionText .jobsearch-JobComponent-description',
      ])
    );

    const salaryText = pickFirstText([
      '#salaryInfoAndJobType',
      '[data-testid="attribute_snippet_testid"]',
      '.jobsearch-JobMetadataHeader-item',
    ]);
    const salary = isLikelySalaryValue(salaryText, salaryText) ? normalizeText(salaryText) : extractSalaryFromText(description);

    const postedAt = extractPostedDateFromText(
      pickFirstText(['.jobsearch-HiringInsights-entry--bullet']) || description
    );
    const applicationDeadline = extractDeadlineDateFromText(description);

    if (!title && !description) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "indeed-panel" };
  }

  // ---------------------------------------------------------------------------
  // 5. Glassdoor extraction
  // ---------------------------------------------------------------------------

  function extractFromGlassdoor() {
    if (!location.hostname.includes("glassdoor.com")) return null;

    const title = cleanTitle(
      pickFirstText([
        '[data-test="jobTitle"]',
        '[data-testid="jobTitle"]',
        '.JobDetails_jobTitle__Rbbh0',
        'h1',
      ])
    );

    const company =
      pickFirstText([
        '[data-test="employer-name"]',
        '[data-testid="employer-name"]',
        '[data-test="employerName"]',
        '.EmployerProfile_employerName__2cxZV a',
        '.employer-name',
      ]) || parseTitleCompanyFromDocumentTitle().company;

    const locationCandidate = cleanLocation(
      pickFirstText([
        '[data-test="location"]',
        '[data-testid="location"]',
        '[data-test="emp-location"]',
        '.JobDetails_location__mSg5h',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '[data-test="jobDescription"]',
        '[data-testid="jobDescription"]',
        '.jobDescriptionContent',
        '#JobDescriptionContainer',
        '.JobDetails_jobDescription__uW_fK',
      ])
    );

    const salaryText = pickFirstText([
      '[data-test="detailSalary"]',
      '[data-testid="detailSalary"]',
      '.SalaryEstimate_salaryEstimate__QpbTY',
      '.RatingAndEarnings_salary__wRCPu',
    ]);
    const salary = isLikelySalaryValue(salaryText, salaryText) ? normalizeText(salaryText) : extractSalaryFromText(description);

    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    if (!title && !description) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "glassdoor-panel" };
  }

  // ---------------------------------------------------------------------------
  // 6. Greenhouse extraction
  // ---------------------------------------------------------------------------

  function extractFromGreenhouse() {
    if (!location.hostname.includes("greenhouse.io")) return null;

    const title = cleanTitle(
      pickFirstText([
        '.app-title',
        '.job-post-title',
        '#header .company-name + h1',
        'h1.heading',
        'h1',
      ])
    );

    const companyFromDom = pickFirstText([
      '.company-name',
      '#header .company-name',
      '.logo-container a[title]',
    ]);
    const parsed = parseTitleCompanyFromDocumentTitle();
    const company = isValidCompany(companyFromDom) ? companyFromDom : (parsed.company || "");

    const locationCandidate = cleanLocation(
      pickFirstText([
        '.location',
        '.body .location',
        '.job-post-location',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '#content .body',
        '#content',
        '.job-post-content',
        '.job_description',
      ])
    );

    const salary = extractSalaryFromText(description);
    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    // Greenhouse postings can be shorter
    if (!title && !isValidDescription(description, 60)) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "greenhouse-panel" };
  }

  // ---------------------------------------------------------------------------
  // 7. Lever extraction
  // ---------------------------------------------------------------------------

  function extractFromLever() {
    if (!location.hostname.includes("lever.co")) return null;

    const title = cleanTitle(
      pickFirstText([
        '.posting-headline h2',
        '.section-wrapper .posting-headline h2',
        'h2',
      ])
    );

    const companyFromTitle = (() => {
      const logoTitle = document.querySelector('.main-header-logo a[title]');
      if (logoTitle) return normalizeText(logoTitle.getAttribute("title") || "");
      return "";
    })();
    const companyFromDom = pickFirstText(['.company-name', '.main-header-content .company-name']);
    const parsed = parseTitleCompanyFromDocumentTitle();
    const company = isValidCompany(companyFromDom) ? companyFromDom : (isValidCompany(companyFromTitle) ? companyFromTitle : (parsed.company || ""));

    const locationCandidate = cleanLocation(
      pickFirstText([
        '.posting-categories .sort-by-time.posting-category .display',
        '.posting-categories .location',
        '.location',
        '.posting-categories .workplaceTypes',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '.section-wrapper .content',
        '.posting-page .content',
        '[data-qa="job-description"]',
        '.posting-page .section-wrapper',
      ])
    );

    const salary = extractSalaryFromText(description);
    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    // Lever postings can be shorter
    if (!title && !isValidDescription(description, 60)) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "lever-panel" };
  }

  // ---------------------------------------------------------------------------
  // 8. Workday extraction
  // ---------------------------------------------------------------------------

  function extractFromWorkday() {
    if (!location.hostname.includes("workday.com") && !location.hostname.includes("myworkdayjobs.com")) return null;

    const title = cleanTitle(
      pickFirstText([
        '[data-automation-id="jobPostingHeader"]',
        'h2[data-automation-id="jobPostingHeader"]',
        'h1[data-automation-id="jobPostingHeader"]',
        '[data-automation-id="job-title"]',
        'h1',
        'h2',
      ])
    );

    const companyFromDom = pickFirstText([
      '[data-automation-id="jobPostingCompanyName"]',
      '[data-automation-id="company"]',
    ]);
    const parsed = parseTitleCompanyFromDocumentTitle();
    const company = isValidCompany(companyFromDom) ? companyFromDom : (parsed.company || "");

    const locationCandidate = cleanLocation(
      pickFirstText([
        '[data-automation-id="locations"]',
        '[data-automation-id="jobPostingLocation"]',
        '[data-automation-id="location"]',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '[data-automation-id="jobPostingDescription"]',
        '[data-automation-id="job-posting-description"]',
        '.job-description',
      ])
    );

    const salary = extractSalaryFromText(description);
    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    if (!title && !description) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "workday-panel" };
  }

  // ---------------------------------------------------------------------------
  // 9. Naukri extraction
  // ---------------------------------------------------------------------------

  function extractFromNaukri() {
    if (!location.hostname.includes("naukri.com")) return null;

    const title = cleanTitle(
      pickFirstText([
        ".styles_jd-header-title__rZwM1",
        ".jd-header-title",
        '[class*="jd-header-title"]',
        'h1[class*="title"]',
        "h1",
      ])
    );

    const companyCandidate =
      pickFirstText([
        ".styles_jd-header-comp-name__MvqAI a",
        ".styles_jd-header-comp-name__MvqAI",
        ".jd-header-comp-name a",
        '[class*="comp-name"] a',
        '[class*="company"] a',
      ]) || parseTitleCompanyFromDocumentTitle().company;
    const company = isValidCompany(companyCandidate) ? companyCandidate : "";

    const locationCandidate = cleanLocation(
      pickFirstText([
        ".styles_jhc__location__W_pVs",
        ".jd-header-location",
        '[class*="location"]',
        '[title*="location" i]',
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        ".styles_job-desc-container__txpYf",
        ".styles_JDC__dang-inner-html__h0K4t",
        "#jobDescriptionContainer",
        '[class*="job-desc"]',
        '[class*="dang-inner-html"]',
      ])
    );

    const salary = extractSalaryFromText(
      pickFirstText([
        ".styles_jhc__salary__jdfEC",
        ".jd-header-salary",
        '[class*="salary"]',
      ]) || description
    );
    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    if (!title && !description) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "naukri-panel" };
  }

  // ---------------------------------------------------------------------------
  // 10. Instahyre extraction
  // ---------------------------------------------------------------------------

  function extractFromInstahyre() {
    if (!location.hostname.includes("instahyre.com")) return null;

    const title = cleanTitle(
      pickFirstText([
        '[class*="job-title"]',
        ".profile--heading",
        "h1",
      ])
    );

    const companyCandidate =
      pickFirstText([
        '[class*="company-name"]',
        '[class*="employer-name"]',
        'a[href*="/company/"]',
      ]) || parseTitleCompanyFromDocumentTitle().company;
    const company = isValidCompany(companyCandidate) ? companyCandidate : "";

    const locationCandidate = cleanLocation(
      pickFirstText([
        '[class*="location"]',
        ".job-location",
        ".location",
      ])
    );
    const loc = looksLikeLocation(locationCandidate) ? locationCandidate : "";

    const description = clampDescription(
      pickFirstInnerText([
        '[class*="job-description"]',
        ".job-description",
        ".description",
        "main",
      ])
    );

    const salary = extractSalaryFromText(description);
    const postedAt = extractPostedDateFromText(description);
    const applicationDeadline = extractDeadlineDateFromText(description);

    if (!title && !description) return null;

    return { title, company, location: loc, description, salary, postedAt, applicationDeadline, source: "instahyre-panel" };
  }

  // ---------------------------------------------------------------------------
  // Platform-specific extractor dispatcher
  // ---------------------------------------------------------------------------

  function extractFromPlatformSpecific() {
    switch (detectPlatform()) {
      case "LinkedIn":   return extractFromLinkedInPanel();
      case "Indeed":     return extractFromIndeed();
      case "Glassdoor":  return extractFromGlassdoor();
      case "Greenhouse": return extractFromGreenhouse();
      case "Lever":      return extractFromLever();
      case "Workday":    return extractFromWorkday();
      case "Naukri":     return extractFromNaukri();
      case "Instahyre":  return extractFromInstahyre();
      default:           return null;
    }
  }

  function createExtractionContext() {
    const platform = detectPlatform();
    return {
      url: window.location.href,
      platform,
      siteKey: getSiteKey(platform),
      adapterVersion: ADAPTER_VERSION,
      documentTitle: document.title || "",
    };
  }

  const ADAPTER_REGISTRY = {
    [SITE_KEYS.LinkedIn]: {
      matches: (context) => context.siteKey === SITE_KEYS.LinkedIn,
      selectVariant() {
        if (document.querySelector(".jobs-search__job-details--container, .jobs-search-two-pane__job-details, .jobs-search-two-pane__job-details-pane")) {
          return "two-pane-detail";
        }
        if (document.querySelector(".jobs-details, .scaffold-layout__detail")) {
          return "scaffold-detail";
        }
        if (document.querySelector(".jobs-unified-top-card, .job-details-jobs-unified-top-card")) return "unified-top-card";
        return "generic-linkedin";
      },
      prepare() {
        const root = findLinkedInDetailsRegion();
        if (root) tryExpandLinkedInDescription(root);
      },
      extract: () => extractFromLinkedInPanel(),
      validate: (record) => validateAdapterRecord(record),
      buildDiagnostics() {
        const root = findLinkedInDetailsRegion() || document;
        const audit = auditSelectorGroups({
          title: {
            required: true,
            selectors: [
              ".job-details-jobs-unified-top-card__job-title",
              ".jobs-unified-top-card__job-title",
              '[class*="jobs-unified-top-card__job-title"]',
            ],
          },
          company: {
            required: true,
            selectors: [
              ".job-details-jobs-unified-top-card__company-name a",
              ".jobs-unified-top-card__company-name a",
              '[class*="jobs-unified-top-card__company-name"] a',
            ],
          },
          location: {
            required: false,
            selectors: [
              ".jobs-unified-top-card__bullet",
              ".job-details-jobs-unified-top-card__tertiary-description-container",
            ],
          },
          description: {
            required: true,
            selectors: [
              ".jobs-description-content__text",
              ".jobs-description__content",
              ".jobs-box__html-content",
              "#job-details",
            ],
          },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Indeed]: {
      matches: (context) => context.siteKey === SITE_KEYS.Indeed,
      selectVariant() {
        return document.querySelector('[data-testid="jobsearch-JobInfoHeader-title"]') ? "testid" : "legacy";
      },
      prepare() {},
      extract: () => extractFromIndeed(),
      validate: (record) => validateAdapterRecord(record),
      buildDiagnostics() {
        const root = document.querySelector("#jobDescriptionText, .jobsearch-JobComponent-description")?.closest("main, article, section, div") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: ['h1.jobsearch-JobInfoHeader-title', '[data-testid="jobsearch-JobInfoHeader-title"]'] },
          company: { required: true, selectors: ['[data-testid="inlineHeader-companyName"]', '[data-company-name="true"]'] },
          location: { required: false, selectors: ['[data-testid="inlineHeader-companyLocation"]', '[data-testid="job-location"]'] },
          description: { required: true, selectors: ["#jobDescriptionText", '[data-testid="jobDescriptionText"]'] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Glassdoor]: {
      matches: (context) => context.siteKey === SITE_KEYS.Glassdoor,
      selectVariant() {
        return document.querySelector('[data-test="jobTitle"], [data-testid="jobTitle"]') ? "testid" : "generic";
      },
      prepare() {},
      extract: () => extractFromGlassdoor(),
      validate: (record) => validateAdapterRecord(record),
      buildDiagnostics() {
        const root = document.querySelector('[data-test="jobDescription"], #JobDescriptionContainer')?.closest("main, article, section, div") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: ['[data-test="jobTitle"]', '[data-testid="jobTitle"]'] },
          company: { required: true, selectors: ['[data-test="employer-name"]', '[data-testid="employer-name"]'] },
          location: { required: false, selectors: ['[data-test="location"]', '[data-testid="location"]'] },
          description: { required: true, selectors: ['[data-test="jobDescription"]', "#JobDescriptionContainer"] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Greenhouse]: {
      matches: (context) => context.siteKey === SITE_KEYS.Greenhouse,
      selectVariant() {
        return document.querySelector(".job-post-content, .job-post-title") ? "job-post" : "generic";
      },
      prepare() {},
      extract: () => extractFromGreenhouse(),
      validate: (record) => validateAdapterRecord(record, { minDescriptionLength: 60 }),
      buildDiagnostics() {
        const root = document.querySelector("#content, .job-post-content") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: [".app-title", ".job-post-title", "h1.heading"] },
          company: { required: true, selectors: [".company-name", "#header .company-name"] },
          location: { required: false, selectors: [".location", ".job-post-location"] },
          description: { required: true, selectors: ["#content .body", "#content", ".job-post-content"] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Lever]: {
      matches: (context) => context.siteKey === SITE_KEYS.Lever,
      selectVariant() {
        return document.querySelector(".posting-headline") ? "posting-page" : "generic";
      },
      prepare() {},
      extract: () => extractFromLever(),
      validate: (record) => validateAdapterRecord(record, { minDescriptionLength: 60 }),
      buildDiagnostics() {
        const root = document.querySelector(".posting-page, .section-wrapper") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: [".posting-headline h2", ".section-wrapper .posting-headline h2"] },
          company: { required: true, selectors: [".company-name", ".main-header-content .company-name"] },
          location: { required: false, selectors: [".posting-categories .location", ".location"] },
          description: { required: true, selectors: [".section-wrapper .content", ".posting-page .content"] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Workday]: {
      matches: (context) => context.siteKey === SITE_KEYS.Workday,
      selectVariant() {
        return document.querySelector('[data-automation-id="jobPostingHeader"]') ? "automation-id" : "generic";
      },
      prepare() {},
      extract: () => extractFromWorkday(),
      validate: (record) => validateAdapterRecord(record),
      buildDiagnostics() {
        const root = document.querySelector('[data-automation-id="jobPostingDescription"], .job-description')?.closest("main, article, section, div") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: ['[data-automation-id="jobPostingHeader"]', '[data-automation-id="job-title"]'] },
          company: { required: true, selectors: ['[data-automation-id="jobPostingCompanyName"]', '[data-automation-id="company"]'] },
          location: { required: false, selectors: ['[data-automation-id="locations"]', '[data-automation-id="jobPostingLocation"]'] },
          description: { required: true, selectors: ['[data-automation-id="jobPostingDescription"]', '[data-automation-id="job-posting-description"]'] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Naukri]: {
      matches: (context) => context.siteKey === SITE_KEYS.Naukri,
      selectVariant() {
        return document.querySelector(".styles_jd-header-title__rZwM1") ? "modern" : "legacy";
      },
      prepare() {},
      extract: () => extractFromNaukri(),
      validate: (record) => validateAdapterRecord(record, { minDescriptionLength: 80 }),
      buildDiagnostics() {
        const root = document.querySelector(".styles_job-desc-container__txpYf, #jobDescriptionContainer")?.closest("main, article, section, div") || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: [".styles_jd-header-title__rZwM1", ".jd-header-title", '[class*="jd-header-title"]'] },
          company: { required: true, selectors: [".styles_jd-header-comp-name__MvqAI a", ".jd-header-comp-name a"] },
          location: { required: false, selectors: [".styles_jhc__location__W_pVs", ".jd-header-location"] },
          description: { required: true, selectors: [".styles_job-desc-container__txpYf", ".styles_JDC__dang-inner-html__h0K4t", "#jobDescriptionContainer"] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
    [SITE_KEYS.Instahyre]: {
      matches: (context) => context.siteKey === SITE_KEYS.Instahyre,
      selectVariant() {
        return document.querySelector('[class*="job-description"]') ? "job-description" : "generic";
      },
      prepare() {},
      extract: () => extractFromInstahyre(),
      validate: (record) => validateAdapterRecord(record, { minDescriptionLength: 80 }),
      buildDiagnostics() {
        const root = document.querySelector('[class*="job-description"], .job-description, main') || document;
        const audit = auditSelectorGroups({
          title: { required: true, selectors: ['[class*="job-title"]', ".profile--heading", "h1"] },
          company: { required: true, selectors: ['[class*="company-name"]', '[class*="employer-name"]', 'a[href*="/company/"]'] },
          location: { required: false, selectors: ['[class*="location"]', ".job-location", ".location"] },
          description: { required: true, selectors: ['[class*="job-description"]', ".job-description", ".description"] },
        }, root);
        return { ...audit, domFingerprint: buildDomFingerprint(root) };
      },
    },
  };

  function runSiteAdapter(context) {
    const adapter = ADAPTER_REGISTRY[context.siteKey];
    if (!adapter || !adapter.matches(context)) return null;

    const variantKey = typeof adapter.selectVariant === "function" ? adapter.selectVariant(context) || "default" : "default";
    const adapterContext = { ...context, variantKey };

    if (typeof adapter.prepare === "function") {
      adapter.prepare(adapterContext);
    }

    const record = normalizeRecord(typeof adapter.extract === "function" ? adapter.extract(adapterContext) : null);
    const validation =
      typeof adapter.validate === "function"
        ? adapter.validate(record, adapterContext)
        : validateAdapterRecord(record);
    const diagnostics =
      typeof adapter.buildDiagnostics === "function"
        ? adapter.buildDiagnostics(adapterContext, record, validation)
        : { matchedSelectors: {}, missingRequiredSelectors: [], domFingerprint: buildDomFingerprint() };

    return {
      siteKey: context.siteKey,
      variantKey,
      adapterVersion: context.adapterVersion,
      record,
      validation,
      diagnostics,
    };
  }

  // ---------------------------------------------------------------------------
  // 11. Semantic DOM extraction (class-agnostic heuristics)
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

  function getSemanticDomCandidates() {
    return getCandidateRegions()
      .map((element) => ({ element, score: scoreRegion(element) }))
      .filter((candidate) => candidate.score >= 2)
      .sort((a, b) => b.score - a.score);
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
    if (host.includes("greenhouse.io")) return "Greenhouse";
    if (host.includes("lever.co")) return "Lever";
    if (host.includes("workday.com") || host.includes("myworkdayjobs.com")) return "Workday";
    return "Other";
  }

  function getSiteKey(platform = detectPlatform()) {
    return SITE_KEYS[platform] || SITE_KEYS.Other;
  }

  function detectSiteKey() {
    return getSiteKey(detectPlatform());
  }

  function isSupportedSiteKey(siteKey) {
    return Boolean(siteKey && siteKey !== SITE_KEYS.Other);
  }

  function firstMatchingSelector(selectors, root = document) {
    for (const selector of selectors || []) {
      try {
        if (root.querySelector(selector)) return selector;
      } catch {
        // Invalid selector for the current browser context — ignore it.
      }
    }
    return "";
  }

  function auditSelectorGroups(groups, root = document) {
    const matchedSelectors = {};
    const missingRequiredSelectors = [];

    for (const [field, config] of Object.entries(groups || {})) {
      const selectors = Array.isArray(config) ? config : config.selectors || [];
      const required = !Array.isArray(config) && Boolean(config.required);
      const matched = firstMatchingSelector(selectors, root);

      if (matched) {
        matchedSelectors[field] = matched;
      } else if (required) {
        missingRequiredSelectors.push(field);
      }
    }

    return { matchedSelectors, missingRequiredSelectors };
  }

  function buildDomFingerprint(root = document.body) {
    const element = root instanceof Element ? root : document.body;
    if (!element) return "";

    const tag = element.tagName ? element.tagName.toLowerCase() : "";
    const id = element.id ? `#${element.id}` : "";
    const classes = element.classList ? Array.from(element.classList).slice(0, 4).map((name) => `.${name}`).join("") : "";
    const heading = normalizeText(element.querySelector("h1, h2, h3")?.textContent || "");

    return normalizeText(`${tag}${id}${classes}${heading ? ` :: ${heading}` : ""}`).slice(0, 220);
  }

  function validateAdapterRecord(record, options = {}) {
    const {
      minDescriptionLength = MIN_DESCRIPTION_LENGTH,
      requireCompanyOrLocation = true,
    } = options;

    const errors = [];
    const normalized = normalizeRecord(record);

    if (!normalized) {
      return { ok: false, errors: ["missing_record"] };
    }
    if (!looksLikeTitle(normalized.title)) errors.push("missing_title");
    if (!isValidDescription(normalized.description, minDescriptionLength)) errors.push("missing_description");
    if (requireCompanyOrLocation && !normalized.company && !normalized.location) errors.push("missing_company_or_location");

    return { ok: errors.length === 0, errors };
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
      contact: normalizeContact(record.contact, record.company || ""),
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
      case "indeed-panel":
      case "glassdoor-panel":
      case "greenhouse-panel":
      case "lever-panel":
      case "workday-panel":
      case "naukri-panel":
      case "instahyre-panel":
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
        case "indeed-panel":
        case "glassdoor-panel":
        case "greenhouse-panel":
        case "lever-panel":
        case "workday-panel":
        case "naukri-panel":
        case "instahyre-panel":
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

  function contactScore(contact, source) {
    if (!contact?.fullName) return 0;

    let score = sourceBonus(source) + 0.12;
    if (contact.title) score += 0.05;
    if (contact.linkedInURL) score += 0.04;
    if (contact.role && contact.role !== "Other") score += 0.03;
    return score;
  }

  function bestContact(records) {
    let bestValue = null;
    let bestSource = "";
    let bestScore = -1;

    for (const record of records) {
      const value = normalizeContact(record.contact, record.company || "");
      if (!value) continue;
      const score = contactScore(value, record.source);
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

  function isPartialResult(data, confidence) {
    if (!data) return false;
    const hasTitle = looksLikeTitle(data.title);
    const hasDescription = isValidDescription(data.description, 60);
    const hasCompanyOrLocation = Boolean(data.company || data.location);
    const signalCount = [hasTitle, hasDescription, hasCompanyOrLocation, Boolean(data.salary)].filter(Boolean).length;
    return signalCount >= 2 && confidence >= PARTIAL_CONFIDENCE_THRESHOLD;
  }

  function buildMergedPayload(records, context) {
    const normalizedRecords = records.map(normalizeRecord).filter(Boolean);
    if (!normalizedRecords.length) return null;

    const fields = {
      title: bestField("title", normalizedRecords),
      company: bestField("company", normalizedRecords),
      location: bestField("location", normalizedRecords),
      description: bestField("description", normalizedRecords),
      salary: bestField("salary", normalizedRecords),
    };

    const title = fields.title.value;
    const company = fields.company.value;
    const jobLocation = fields.location.value;
    const description = fields.description.value;
    const contact = bestContact(normalizedRecords);
    const salary = fields.salary.value;
    const postedAt = bestDateField("postedAt", normalizedRecords);
    const applicationDeadline = bestDateField("applicationDeadline", normalizedRecords);
    const confidence = computeConfidence(fields);

    return {
      payload: {
      title,
      company,
      location: jobLocation,
      description,
      contact: contact.value,
      salary,
      postedAt: postedAt.value,
      applicationDeadline: applicationDeadline.value,
      url: window.location.href,
      platform: context.platform,
      extractionQuality: {
        confidence,
        sources: {
          title: fields.title.source || "",
          company: fields.company.source || "",
          location: fields.location.source || "",
          description: fields.description.source || "",
          contact: contact.source || "",
          salary: fields.salary.source || "",
          postedAt: postedAt.source || "",
          applicationDeadline: applicationDeadline.source || "",
        },
      },
      },
      fields,
      confidence,
      records: normalizedRecords,
    };
  }

  function primarySiteSource(siteKey) {
    switch (siteKey) {
      case SITE_KEYS.LinkedIn:
        return "linkedin-panel";
      case SITE_KEYS.Indeed:
        return "indeed-panel";
      case SITE_KEYS.Glassdoor:
        return "glassdoor-panel";
      case SITE_KEYS.Greenhouse:
        return "greenhouse-panel";
      case SITE_KEYS.Lever:
        return "lever-panel";
      case SITE_KEYS.Workday:
        return "workday-panel";
      case SITE_KEYS.Naukri:
        return "naukri-panel";
      case SITE_KEYS.Instahyre:
        return "instahyre-panel";
      default:
        return "";
    }
  }

  function usesFallbackSources(sources, siteKey) {
    const primarySource = primarySiteSource(siteKey);
    return Object.values(sources || {}).some((source) => source && source !== primarySource);
  }

  function decoratePayload(payload, merged, context, adapterRun, resultState) {
    if (!payload) return null;

    return {
      ...payload,
      extractionQuality: {
        ...payload.extractionQuality,
        confidence: merged?.confidence ?? payload.extractionQuality?.confidence ?? 0,
        resultState,
        siteKey: context.siteKey,
        variantKey: adapterRun?.variantKey || "",
        adapterVersion: ADAPTER_VERSION,
        fallbackUsed: usesFallbackSources(payload.extractionQuality?.sources, context.siteKey),
        validationErrors: adapterRun?.validation?.errors || [],
      },
    };
  }

  function gatherExtractionSnapshot() {
    const context = createExtractionContext();
    const adapterRun = isSupportedSiteKey(context.siteKey) ? runSiteAdapter(context) : null;

    return {
      context,
      adapterRun,
      rawCandidates: {
        siteAdapter: adapterRun?.record || null,
        jsonLd: extractFromJsonLd(),
        microdata: extractFromMicrodata(),
        semanticDom: extractFromSemanticDom(),
        meta: extractFromMeta(),
      },
    };
  }

  function selectExtractionOutcome(snapshot) {
    const { context, adapterRun, rawCandidates } = snapshot;
    const supportedSite = isSupportedSiteKey(context.siteKey);
    const successMerge = buildMergedPayload(
      [rawCandidates.siteAdapter, rawCandidates.jsonLd, rawCandidates.microdata],
      context
    );
    const partialMerge = buildMergedPayload(
      [rawCandidates.siteAdapter, rawCandidates.jsonLd, rawCandidates.microdata, rawCandidates.semanticDom, rawCandidates.meta],
      context
    );

    if (supportedSite && successMerge && isUsableResult(successMerge.payload, successMerge.confidence)) {
      return {
        ...snapshot,
        payload: decoratePayload(successMerge.payload, successMerge, context, adapterRun, RESULT_STATE.SUCCESS),
        resultState: RESULT_STATE.SUCCESS,
      };
    }

    if (supportedSite && partialMerge && isPartialResult(partialMerge.payload, partialMerge.confidence)) {
      return {
        ...snapshot,
        payload: decoratePayload(partialMerge.payload, partialMerge, context, adapterRun, RESULT_STATE.PARTIAL),
        resultState: RESULT_STATE.PARTIAL,
      };
    }

    if (!supportedSite && partialMerge && isUsableResult(partialMerge.payload, partialMerge.confidence)) {
      return {
        ...snapshot,
        payload: decoratePayload(partialMerge.payload, partialMerge, context, adapterRun, RESULT_STATE.SUCCESS),
        resultState: RESULT_STATE.SUCCESS,
      };
    }

    return {
      ...snapshot,
      payload:
        partialMerge && isPartialResult(partialMerge.payload, partialMerge.confidence)
          ? decoratePayload(partialMerge.payload, partialMerge, context, adapterRun, supportedSite ? RESULT_STATE.PARTIAL : RESULT_STATE.UNSUPPORTED)
          : null,
      resultState: supportedSite ? RESULT_STATE.BROKEN_SITE_ADAPTER : RESULT_STATE.UNSUPPORTED,
    };
  }

  function extractJobData() {
    return selectExtractionOutcome(gatherExtractionSnapshot());
  }

  function extractJobDataAndDebugPacket() {
    const outcome = extractJobData();
    const debugPacket = collectDebugPacket(outcome);
    return { outcome, debugPacket };
  }

  const PLATFORM_DELAYS = {
    LinkedIn:  [0, 180, 420, 780, 1250],
    Workday:   [0, 300, 700, 1200, 2000],
    Glassdoor: [0, 200, 500, 900, 1500],
  };
  const DEFAULT_DELAYS = [0, 120, 320];

  function getDelaysForPlatform() {
    return PLATFORM_DELAYS[detectPlatform()] || DEFAULT_DELAYS;
  }

  async function extractJobDataWithRetries() {
    const delays = getDelaysForPlatform();
    for (const delayMs of delays) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const outcome = extractJobData();
      if (outcome?.resultState === RESULT_STATE.SUCCESS) return outcome;
    }
    return extractJobData();
  }

  async function extractDebugPacketWithRetries() {
    const delays = getDelaysForPlatform();
    for (const delayMs of delays) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const { outcome, debugPacket } = extractJobDataAndDebugPacket();
      if (outcome?.resultState === RESULT_STATE.SUCCESS) return debugPacket;
    }

    // Return at least one packet even if extraction fails confidence gating.
    return extractJobDataAndDebugPacket().debugPacket;
  }

  async function extractDomDebugPacketWithRetries() {
    const delays = getDelaysForPlatform();
    for (const delayMs of delays) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const outcome = extractJobData();
      if (outcome?.payload || outcome?.resultState) {
        return collectDomDebugPacket(outcome);
      }
    }

    return collectDomDebugPacket(extractJobData());
  }

  function buildFailureDiagnostics(outcome) {
    const records = outcome?.rawCandidates
      ? Object.values(outcome.rawCandidates).map(normalizeRecord).filter(Boolean)
      : [];
    const fallbackMerge = outcome?.payload?.extractionQuality
      ? { confidence: outcome.payload.extractionQuality.confidence, payload: outcome.payload }
      : buildMergedPayload(records, outcome?.context || createExtractionContext());

    const fields = records.length
      ? {
          title: bestField("title", records),
          company: bestField("company", records),
          location: bestField("location", records),
          description: bestField("description", records),
          salary: bestField("salary", records),
        }
      : null;

    return {
      platform: outcome?.context?.platform || detectPlatform(),
      siteKey: outcome?.context?.siteKey || detectSiteKey(),
      variantKey: outcome?.adapterRun?.variantKey || "",
      resultState: outcome?.resultState || RESULT_STATE.UNSUPPORTED,
      staleAdapter: outcome?.resultState === RESULT_STATE.BROKEN_SITE_ADAPTER,
      fallbackUsed: Boolean(outcome?.payload?.extractionQuality?.fallbackUsed),
      confidence: fallbackMerge?.confidence || 0,
      fieldsFound: fields
        ? {
            title: !!fields.title.value,
            company: !!fields.company.value,
            location: !!fields.location.value,
            description: !!fields.description.value,
            salary: !!fields.salary.value,
          }
        : {},
      descriptionLength: normalizeText(fields?.description?.value || "").length,
      validationErrors: outcome?.adapterRun?.validation?.errors || [],
      matchedSelectors: outcome?.adapterRun?.diagnostics?.matchedSelectors || {},
      missingRequiredSelectors: outcome?.adapterRun?.diagnostics?.missingRequiredSelectors || [],
      domFingerprint: outcome?.adapterRun?.diagnostics?.domFingerprint || buildDomFingerprint(),
    };
  }

  function failureMessageForOutcome(outcome) {
    switch (outcome?.resultState) {
      case RESULT_STATE.BROKEN_SITE_ADAPTER:
        return "This supported site appears to have changed. Copy the debug packet so the adapter can be updated.";
      case RESULT_STATE.PARTIAL:
        return "Pipeline found part of the job posting, but not enough to save safely.";
      case RESULT_STATE.UNSUPPORTED:
      default:
        return "This page does not look like a complete supported job posting.";
    }
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
          const outcome = await extractJobDataWithRetries();
          if (!outcome?.payload || outcome.resultState !== RESULT_STATE.SUCCESS) {
            sendResponse({
              success: false,
              error: failureMessageForOutcome(outcome),
              diagnostics: buildFailureDiagnostics(outcome),
            });
            return;
          }
          sendResponse({ success: true, data: outcome.payload });
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
    if (request.action === "collectDomDebugPacket") {
      (async () => {
        try {
          const data = await extractDomDebugPacketWithRetries();
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
