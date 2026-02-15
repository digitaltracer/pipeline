// Pipeline — Content Script
// Extracts job posting data from the current page.
// Shared between Safari and Chrome extensions.
//
// Extraction priority:
//   1. JSON-LD / microdata (schema.org JobPosting)
//   2. Semantic DOM extraction (standards-first, class-agnostic heuristics)
//   3. Open Graph / meta tags as weak fallback
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
    const value = text.toLowerCase();
    if (/\b(remote|hybrid|on-site|onsite)\b/.test(value)) return true;
    if (/\b[a-z .'-]+,\s*[a-z]{2}\b/i.test(text)) return true;
    if (/\b[a-z .'-]+,\s*[a-z .'-]{3,}\b/i.test(text)) return true;
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
        !/\b(applicant|applied|day|days|hour|hours|week|weeks|month|months|promoted|reviewing|viewed)\b/i.test(
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
    if (company.length < 2 || company.length > 120) return false;
    const lower = company.toLowerCase();
    if (lower.includes("sign in") || lower.includes("join now")) return false;
    if (lower.includes("easy apply") || lower.includes("quick apply")) return false;
    if (lower.includes("posted") || lower.includes("minutes ago")) return false;
    if (lower.includes("full-time") || lower.includes("part-time")) return false;
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
      extractorVersion: "heuristic-v3-debug",
      url: window.location.href,
      platform: detectPlatform(),
      documentTitle: document.title || "",
      extraction: extractedData || null,
      candidates: {
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
          return {
            title,
            company,
            location,
            description,
            salary,
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

    if (!title && !description) return null;

    return {
      title,
      company,
      location,
      description,
      salary: "",
      source: "microdata",
    };
  }

  // ---------------------------------------------------------------------------
  // 3. Semantic DOM extraction (class-agnostic heuristics)
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

    return {
      title,
      company,
      location,
      description: text,
      salary,
      source: "semantic-dom",
    };
  }

  // ---------------------------------------------------------------------------
  // 4. Meta tag extraction (Open Graph, standard meta)
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
    const confidence = computeConfidence(fields);

    const payload = {
      title,
      company,
      location: jobLocation,
      description,
      salary,
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
    const delays = [0, 120, 320];
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
    const delays = [0, 120, 320];
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
