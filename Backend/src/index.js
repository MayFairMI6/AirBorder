import { handleAIExplain } from "./ai-explainer.js";
import countries from "i18n-iso-countries";

const PROVIDERS = Object.freeze({
  flightAwareBaseURL: "https://aeroapi.flightaware.com/aeroapi",
  amadeusTestBaseURL: "https://test.api.amadeus.com",
  amadeusProductionBaseURL: "https://api.amadeus.com",
  sherpaRequirementsURL: "https://requirements-api.joinsherpa.com/v3/trips?include=restriction%2Cprocedure",
  geminiInteractionsURL: "https://generativelanguage.googleapis.com/v1beta/interactions",
  googleVisionURL: "https://vision.googleapis.com/v1/images:annotate",
  googleTasksBaseURL: "https://tasks.googleapis.com/tasks/v1"
});

const LIMITS = Object.freeze({
  providerResponseBytes: 1_000_000,
  tokenResponseBytes: 256_000,
  sceneImageBytes: 512_000,
  recognizedTextCharacters: 2_000,
  providerTimeoutMilliseconds: 8_000,
  hotelCandidates: 20,
  normalizedRecords: 50,
  accessAssertionCharacters: 16_384,
  accessJWKSBytes: 256_000,
  reminderRequestBytes: 64_000,
  reminderSyncItems: 20,
  reminderTextCharacters: 2_000,
  googleOAuthTokenCharacters: 8_192,
  googleTaskScanPages: 20,
  googleTaskPageSize: 100,
  entryRequestBytes: 32_768,
  declaredAuthorizations: 20,
  officialVerificationLinks: 12
});

const SECURITY_POLICY = Object.freeze({
  accessClockSkewSeconds: 60,
  accessKeyCacheSeconds: 300,
  rateLimitRetryAfterSeconds: 60
});

const CACHE_TTLS = Object.freeze({
  flightSeconds: 60,
  hotelOffersSeconds: 120,
  activitiesSeconds: 900,
  facilitiesSeconds: 86_400,
  entryRequirementsSeconds: 3_600
});

const PROVIDER_POLICY_VERSION = "provider-policy-2026-07-14-v3";
const GOOGLE_TASKS_CONSENT_REVISION = "google-tasks-consent-2026-07-14-v1";
const GOOGLE_TASKS_MARKER_VERSION = "v1";

const PROVIDER_POLICIES = Object.freeze({
  flightaware: {
    capability: "flight-status",
    persistence: "license-dependent",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "provider contract and received timestamp"
  },
  amadeusFlights: {
    capability: "flight-status-fallback",
    persistence: "license-dependent",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "provider contract and received timestamp"
  },
  amadeusHotels: {
    capability: "hotel-availability",
    persistence: "short-cache-only",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "response receipt plus short revalidation interval"
  },
  amadeusActivities: {
    capability: "activities",
    persistence: "short-cache-only",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "response receipt plus revalidation interval"
  },
  hndOfficialRegistry: {
    capability: "airport-facilities",
    persistence: "versioned-registry",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "registry version; opening details require source verification"
  },
  sherpa: {
    capability: "entry-requirements",
    persistence: "protected-until-expiry",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "provider response or conservative proxy interval",
    canAuthorizeEntry: false
  },
  timatic: {
    capability: "entry-requirements-backup",
    persistence: "protected-until-expiry",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "contract adapter response or conservative proxy interval",
    canAuthorizeEntry: false
  },
  geminiEntryDiscovery: {
    capability: "official-entry-source-discovery",
    persistence: "protected-until-expiry",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "response receipt plus discovery revalidation interval",
    canAuthorizeEntry: false
  },
  workersAIExplanation: {
    capability: "grounded-explanation-ordering",
    persistence: "no-store",
    trainingAllowed: false,
    trainingPurposes: [],
    expirySource: "not cached; every operational fact remains client-supplied and sourced",
    canAffectSafetyDecision: false,
    canAuthorizeEntry: false
  }
});

const OFFICIAL_ENTRY_LINKS = Object.freeze({
  JP: [{ label: "Ministry of Foreign Affairs of Japan - Visa Exemption", url: "https://www.mofa.go.jp/j_info/visit/visa/short/novisa.html" }],
  US: [{ label: "U.S. Department of State - Visa Wizard", url: "https://travel.state.gov/content/travel/en/us-visas/visa-information-resources/wizard.html" }]
});

const OFFICIAL_ENTRY_DOMAINS = Object.freeze({
  JP: ["mofa.go.jp", "moj.go.jp", "isa.go.jp", "evisa.mofa.go.jp"],
  US: ["travel.state.gov", "cbp.gov", "uscis.gov", "esta.cbp.dhs.gov"]
});

const HND_REGISTRY_VERSION = "2026-07-14.1";
const HND_FACILITIES = Object.freeze([
  {
    id: "hnd-work-boxes",
    airportCode: "HND",
    terminal: null,
    name: "Work booths / work boxes",
    category: "workPod",
    accessZone: "airportLandside",
    openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], start: "07:00", end: "21:30", timeZone: "Asia/Tokyo" }],
    hoursStatus: "officialRecordVerifyFreshness",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/work_box.html"
  },
  {
    id: "hnd-terminal-hotels",
    airportCode: "HND",
    terminal: null,
    name: "The Royal Park Hotel Tokyo Haneda (Transit)",
    category: "transitHotel",
    accessZone: "airside",
    openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], allDay: true, timeZone: "Asia/Tokyo" }],
    hoursStatus: "officialRecordVerifyAvailability",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/hotel.html"
  },
  {
    id: "hnd-shower-rooms",
    airportCode: "HND",
    terminal: null,
    name: "Haneda Airport shower rooms",
    category: "shower",
    accessZone: "airportLandside",
    openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], allDay: true, timeZone: "Asia/Tokyo" }],
    hoursStatus: "officialRecordNoReservations",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/shower_room.html"
  },
  {
    id: "hnd-lounges",
    airportCode: "HND",
    terminal: null,
    name: "Haneda Airport lounges",
    category: "lounge",
    accessZone: "mixed",
    openingWindows: [],
    hoursStatus: "verifyOfficialSource",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/lounge.html"
  },
  {
    id: "hnd-observation-decks",
    airportCode: "HND",
    terminal: null,
    name: "Haneda observation decks",
    category: "attraction",
    accessZone: "airportLandside",
    openingWindows: [],
    hoursStatus: "verifyOfficialSource",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/observation_deck.html"
  },
  {
    id: "hnd-edo-koji",
    airportCode: "HND",
    terminal: "3",
    name: "Edo Koji",
    category: "foodAndAttraction",
    accessZone: "airportLandside",
    openingWindows: [],
    hoursStatus: "verifyOfficialSource",
    dayRoomVerified: false,
    officialRecordURL: "https://tokyo-haneda.com/en/shop_and_dine/search_r.html"
  },
  {
    id: "hnd-airport-garden",
    airportCode: "HND",
    terminal: "3",
    name: "Haneda Airport Garden",
    category: "foodHotelAndAttraction",
    accessZone: "nearbyLandside",
    openingWindows: [],
    hoursStatus: "verifyOperatorSource",
    dayRoomVerified: false,
    officialRecordURL: "https://www.shopping-sumitomo-rd.com/haneda/english/"
  }
]);

let amadeusTokenCache = null;
const accessKeyCache = new Map();

export default {
  async fetch(request, env = {}) {
    try {
      const url = new URL(request.url);

      if (url.pathname === "/health") {
        if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, { allow: "GET" });
        return health(env);
      }

      const authentication = await authenticateRequest(request, env);
      if (authentication.response) return authentication.response;
      const quotaResponse = await enforceRequestQuota(url, env, authentication.principal);
      if (quotaResponse) return quotaResponse;

      if (request.method === "POST" && url.pathname === "/v1/scene-ocr") {
        return await sceneOCR(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/ai/explain") {
        return await handleAIExplain(request, env, { providerPolicyVersion: PROVIDER_POLICY_VERSION });
      }
      if (request.method === "POST" && url.pathname === "/v1/reminders/google-tasks/sync") {
        return await syncGoogleTasks(request);
      }
      if (request.method === "POST" && url.pathname === "/v1/entry-requirements") {
        return await entryRequirements(request, env);
      }
      if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, { allow: "GET" });

      if (url.pathname === "/v1/provider-policies") return json({ policies: PROVIDER_POLICIES, version: PROVIDER_POLICY_VERSION });
      if (url.pathname === "/v1/flights/search") return await searchFlights(url, env);
      if (url.pathname === "/v1/hotels/search") return await searchHotels(url, env);
      if (url.pathname === "/v1/activities") return await searchActivities(url, env);
      if (url.pathname === "/v1/entry-requirements") return await legacyEntryRequirements(url, env);

      const facilityMatch = url.pathname.match(/^\/v1\/facilities\/airports\/([A-Z0-9]{3,4})$/i);
      if (facilityMatch) return airportFacilities(facilityMatch[1]);

      const boardMatch = url.pathname.match(/^\/v1\/airports\/([A-Z0-9]{3,4})\/(departures|arrivals)$/i);
      if (boardMatch) return await airportBoard(url, env, boardMatch[1], boardMatch[2]);

      const flightMatch = url.pathname.match(/^\/v1\/flights\/([A-Za-z0-9_-]{3,80})$/);
      if (flightMatch) return await flightByID(env, flightMatch[1]);

      return json({ error: "not_found" }, 404);
    } catch (error) {
      // Provider bodies, request details, credentials, and user profile data never reach logs or clients.
      console.error("proxy_request_failed", error instanceof Error ? error.name : "unknown");
      if (error instanceof ReminderRequestError) {
        return json({ error: error.code }, error.status);
      }
      if (error instanceof ProviderError) {
        const headers = error.retryAfter ? { "retry-after": error.retryAfter } : {};
        const code = error.status === 429 ? "rate_limited" : error.status === 504 ? "upstream_timeout" : "upstream_unavailable";
        return json({ error: code }, error.status, headers);
      }
      if (error instanceof GoogleAuthorizationError) {
        return json({ error: "google_oauth_required" }, 401, { "www-authenticate": "Bearer" });
      }
      if (error instanceof GoogleTaskListScanError) {
        return json({ error: "google_task_list_too_large_for_safe_sync" }, 409);
      }
      return json({ error: "upstream_unavailable" }, 502);
    }
  }
};

async function authenticateRequest(request, env) {
  const mode = String(env.REQUEST_AUTH_MODE || "cloudflare-access").trim().toLowerCase();
  if (mode === "none") {
    if (String(env.DEPLOYMENT_ENVIRONMENT || "development").toLowerCase() === "production") {
      return { principal: null, response: json({ error: "authentication_not_configured" }, 503) };
    }
    return { principal: "explicitly-unauthenticated-development", response: null };
  }
  if (mode !== "cloudflare-access") {
    return { principal: null, response: json({ error: "authentication_not_configured" }, 503) };
  }

  const issuer = accessIssuer(env.CF_ACCESS_TEAM_DOMAIN);
  const audiences = String(env.CF_ACCESS_AUD || "").split(",").map(value => value.trim()).filter(Boolean);
  if (!issuer || !audiences.length) {
    return { principal: null, response: json({ error: "authentication_not_configured" }, 503) };
  }

  const assertion = boundedText(
    request.headers.get("cf-access-jwt-assertion"),
    LIMITS.accessAssertionCharacters + 1
  );
  if (!assertion || assertion.length > LIMITS.accessAssertionCharacters) {
    return { principal: null, response: authenticationRequired() };
  }

  try {
    const claims = await verifyCloudflareAccessAssertion(assertion, issuer, audiences);
    const principal = boundedText(claims?.sub, 200);
    if (!principal) return { principal: null, response: authenticationRequired() };
    return { principal, response: null };
  } catch (error) {
    if (error instanceof ProviderError) {
      return { principal: null, response: json({ error: "authentication_unavailable" }, 503) };
    }
    return { principal: null, response: authenticationRequired() };
  }
}

function authenticationRequired() {
  return json(
    { error: "authentication_required" },
    401,
    { "www-authenticate": "Cloudflare-Access" }
  );
}

function accessIssuer(value) {
  const raw = String(value || "").trim().toLowerCase();
  if (!raw) return null;
  try {
    const parsed = new URL(raw.includes("://") ? raw : `https://${raw}`);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.port || parsed.pathname !== "/" || parsed.search || parsed.hash) return null;
    if (!parsed.hostname.endsWith(".cloudflareaccess.com")) return null;
    return parsed.origin;
  } catch {
    return null;
  }
}

async function verifyCloudflareAccessAssertion(assertion, issuer, allowedAudiences) {
  const parts = assertion.split(".");
  if (parts.length !== 3 || parts.some(part => !part)) throw new AuthenticationError();
  const header = parseBase64URLJSON(parts[0]);
  const claims = parseBase64URLJSON(parts[1]);
  if (header.alg !== "RS256" || !boundedText(header.kid, 200)) throw new AuthenticationError();

  const nowSeconds = Math.floor(Date.now() / 1_000);
  const expiresAt = Number(claims.exp);
  const notBefore = claims.nbf === undefined ? null : Number(claims.nbf);
  const issuedAt = claims.iat === undefined ? null : Number(claims.iat);
  const tokenAudiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (claims.iss !== issuer ||
      !Number.isFinite(expiresAt) || expiresAt <= nowSeconds - SECURITY_POLICY.accessClockSkewSeconds ||
      (notBefore !== null && (!Number.isFinite(notBefore) || notBefore > nowSeconds + SECURITY_POLICY.accessClockSkewSeconds)) ||
      (issuedAt !== null && (!Number.isFinite(issuedAt) || issuedAt > nowSeconds + SECURITY_POLICY.accessClockSkewSeconds)) ||
      !tokenAudiences.some(audience => allowedAudiences.includes(String(audience)))) {
    throw new AuthenticationError();
  }

  const keys = await accessVerificationKeys(issuer);
  const jwk = keys.find(candidate => candidate?.kid === header.kid && candidate?.kty === "RSA");
  if (!jwk) throw new AuthenticationError();
  let key;
  try {
    key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );
  } catch {
    throw new AuthenticationError();
  }
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decodeBase64URL(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!verified) throw new AuthenticationError();
  return claims;
}

async function accessVerificationKeys(issuer) {
  const cached = accessKeyCache.get(issuer);
  if (cached && cached.expiresAtMilliseconds > Date.now()) return cached.keys;
  const response = await providerFetch(`${issuer}/cdn-cgi/access/certs`, {
    headers: { Accept: "application/json" },
    cf: { cacheTtl: SECURITY_POLICY.accessKeyCacheSeconds }
  });
  const payload = await readBoundedJSON(response, LIMITS.accessJWKSBytes);
  if (!Array.isArray(payload.keys) || !payload.keys.length) throw new ProviderError(502);
  const keys = payload.keys.slice(0, 20);
  accessKeyCache.set(issuer, {
    keys,
    expiresAtMilliseconds: Date.now() + SECURITY_POLICY.accessKeyCacheSeconds * 1_000
  });
  return keys;
}

function parseBase64URLJSON(value) {
  try {
    const object = JSON.parse(new TextDecoder().decode(decodeBase64URL(value)));
    if (!object || typeof object !== "object" || Array.isArray(object)) throw new Error("invalid_object");
    return object;
  } catch {
    throw new AuthenticationError();
  }
}

function decodeBase64URL(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new AuthenticationError();
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = "=".repeat((4 - normalized.length % 4) % 4);
  try {
    return Uint8Array.from(atob(normalized + padding), character => character.charCodeAt(0));
  } catch {
    throw new AuthenticationError();
  }
}

async function enforceRequestQuota(url, env, principal) {
  if (!env.API_RATE_LIMITER) {
    return parseBoolean(env.REQUIRE_RATE_LIMITER, false) === true
      ? json({ error: "rate_limiter_not_configured" }, 503)
      : null;
  }
  const routeBucket = quotaBucket(url.pathname);
  const principalDigest = await sha256Hex(principal);
  try {
    const result = await env.API_RATE_LIMITER.limit({ key: `${principalDigest}:${routeBucket}` });
    if (result?.success === true) return null;
    return json(
      { error: "rate_limited" },
      429,
      { "retry-after": String(SECURITY_POLICY.rateLimitRetryAfterSeconds) }
    );
  } catch {
    return json({ error: "rate_limiter_unavailable" }, 503);
  }
}

function quotaBucket(pathname) {
  if (pathname.startsWith("/v1/flights/") || pathname.startsWith("/v1/airports/")) return "aviation";
  if (pathname.startsWith("/v1/hotels/") || pathname === "/v1/activities") return "discovery";
  if (pathname === "/v1/entry-requirements") return "entry";
  if (pathname === "/v1/scene-ocr") return "vision";
  if (pathname === "/v1/ai/explain") return "ai-explanation";
  if (pathname.startsWith("/v1/reminders/")) return "reminders";
  return "metadata";
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(value)));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

function health(env) {
  return json({
    status: "ok",
    configured: {
      flightStatus: Boolean(flightAwareKey(env)),
      hotelsAndActivities: Boolean(env.AMADEUS_CLIENT_ID && env.AMADEUS_CLIENT_SECRET),
      entryRequirements: Boolean(env.SHERPA_API_KEY || (env.TIMATIC_API_URL && env.TIMATIC_API_KEY)),
      entryRequirementBackup: Boolean(env.TIMATIC_API_URL && env.TIMATIC_API_KEY),
      entryOfficialSourceDiscovery: Boolean(env.GEMINI_API_KEY),
      cloudVision: Boolean(env.GOOGLE_VISION_API_KEY),
      groundedExplanation: Boolean(env.AI && typeof env.AI.run === "function")
    },
    facilityRegistryVersion: HND_REGISTRY_VERSION
  });
}

async function sceneOCR(request, env) {
  if (request.headers.get("x-cloud-vision-consent") !== "true") return json({ error: "consent_required" }, 403);
  if (!env.GOOGLE_VISION_API_KEY) return notConfigured("sceneOCR", "Google Cloud Vision");
  if ((request.headers.get("content-type") || "").split(";", 1)[0].trim().toLowerCase() !== "image/jpeg") {
    return json({ error: "unsupported_media_type" }, 415);
  }
  const declaredLength = Number(request.headers.get("content-length") || "0");
  if (declaredLength > LIMITS.sceneImageBytes) return json({ error: "image_too_large" }, 413);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length || bytes.length > LIMITS.sceneImageBytes) return json({ error: "image_too_large" }, 413);

  const providerResponse = await providerFetch(`${PROVIDERS.googleVisionURL}?key=${encodeURIComponent(env.GOOGLE_VISION_API_KEY)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      requests: [{
        image: { content: bytesToBase64(bytes) },
        features: [{ type: "TEXT_DETECTION", maxResults: 20 }],
        imageContext: { languageHints: ["en"] }
      }]
    })
  });
  const payload = await readBoundedJSON(providerResponse, LIMITS.providerResponseBytes);
  const annotation = payload.responses?.[0]?.fullTextAnnotation;
  const recognizedText = boundedText(annotation?.text, LIMITS.recognizedTextCharacters);
  const gateMatch = recognizedText.toUpperCase().match(/(?:GATE\s*)?([A-Z]\d{1,3})\b/);
  const results = recognizedText ? [{
    label: recognizedText,
    nodeID: gateMatch ? `gate-${gateMatch[1].toLowerCase()}` : null,
    confidence: averageBlockConfidence(annotation)
  }] : [];
  return json({
    results,
    advisory: true,
    captureId: boundedText(request.headers.get("x-capture-id"), 100) || null,
    source: sourceMetadata({ provider: "Google Cloud Vision", dataMode: "cloudProcessing", ttlSeconds: 0 })
  });
}

async function syncGoogleTasks(request) {
  if (request.headers.get("x-airportxr-google-tasks-consent") !== "true" ||
      request.headers.get("x-airportxr-google-tasks-consent-revision") !== GOOGLE_TASKS_CONSENT_REVISION) {
    return json({ error: "consent_required" }, 403);
  }
  const accessToken = googleOAuthBearerToken(request.headers.get("authorization"));
  if (!accessToken) throw new GoogleAuthorizationError();

  const rawPayload = await readBoundedRequestJSON(request, LIMITS.reminderRequestBytes);
  const payload = normalizeGoogleTasksSyncPayload(rawPayload);
  if (!payload || payload.consentRevision !== GOOGLE_TASKS_CONSENT_REVISION) {
    return json({ error: "invalid_reminder_sync" }, 400);
  }

  // A complete pre-mutation scan is the idempotency boundary. If a task list is
  // too large to scan within the named guardrail, fail before inserting rather
  // than risk creating a duplicate after a lost response.
  const existingTasks = await listGoogleTasks(payload.taskListID, accessToken);
  const managed = new Map();
  for (const task of existingTasks) {
    const marker = parseGoogleTasksMarker(task.notes);
    if (!marker || marker.scopeID !== payload.scopeID) continue;
    const records = managed.get(marker.reminderID) || [];
    records.push(task);
    managed.set(marker.reminderID, records);
  }
  for (const records of managed.values()) records.sort((left, right) => String(left.id).localeCompare(String(right.id)));

  const synchronized = [];
  const desiredIDs = new Set(payload.reminders.map(reminder => reminder.id));
  for (const reminder of payload.reminders) {
    const records = managed.get(reminder.id) || [];
    const resource = googleTaskResource(payload.scopeID, reminder);
    let task;
    if (records.length) {
      task = await updateGoogleTask(payload.taskListID, records[0].id, resource, accessToken);
      for (const duplicate of records.slice(1)) {
        await deleteGoogleTask(payload.taskListID, duplicate.id, accessToken);
      }
    } else {
      task = await insertGoogleTask(payload.taskListID, resource, accessToken);
    }
    const taskID = boundedText(task?.id, 300);
    if (!taskID) throw new ProviderError(502);
    synchronized.push({
      reminderID: reminder.id,
      taskID,
      webViewLink: safeExternalURL(task.webViewLink)
    });
  }

  const removedReminderIDs = [];
  for (const [reminderID, records] of [...managed.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    if (desiredIDs.has(reminderID)) continue;
    for (const record of records) await deleteGoogleTask(payload.taskListID, record.id, accessToken);
    removedReminderIDs.push(reminderID);
  }

  return json({
    tasks: synchronized.sort((left, right) => left.reminderID.localeCompare(right.reminderID)),
    removedReminderIDs,
    limitations: [
      "The Google Tasks API stores only the due date; it ignores the time portion. The exact Airport XR action time is retained in task notes, but Google controls notification timing and device delivery."
    ]
  });
}

async function readBoundedRequestJSON(request, maximumBytes) {
  const contentType = String(request.headers.get("content-type") || "").toLowerCase();
  if (!contentType.includes("application/json")) throw new ReminderRequestError(415, "unsupported_media_type");
  const declaredLengthHeader = request.headers.get("content-length");
  const declaredLength = declaredLengthHeader === null ? null : Number(declaredLengthHeader);
  if (declaredLength !== null && (!Number.isFinite(declaredLength) || declaredLength < 0 || declaredLength > maximumBytes)) {
    throw new ReminderRequestError(413, "request_too_large");
  }
  const reader = request.body?.getReader?.();
  if (!reader) throw new ReminderRequestError(400, "invalid_json");
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maximumBytes) {
      await reader.cancel();
      throw new ReminderRequestError(413, "request_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_object");
    return value;
  } catch {
    throw new ReminderRequestError(400, "invalid_json");
  }
}

function normalizeGoogleTasksSyncPayload(value) {
  const consentRevision = boundedText(value?.consentRevision, 100);
  const taskListID = boundedText(value?.taskListID, 200);
  const scopeID = boundedText(value?.scopeID, 128);
  if (consentRevision !== GOOGLE_TASKS_CONSENT_REVISION ||
      !/^[A-Za-z0-9@._~+-]{1,200}$/.test(taskListID) ||
      !/^[A-Za-z0-9._:-]{1,128}$/.test(scopeID) ||
      !Array.isArray(value?.reminders) || value.reminders.length > LIMITS.reminderSyncItems) return null;

  const reminders = [];
  const identifiers = new Set();
  for (const raw of value.reminders) {
    const id = boundedText(raw?.id, 128);
    const title = boundedText(raw?.title, 1_024);
    const notes = boundedText(raw?.notes, LIMITS.reminderTextCharacters);
    const intendedActionAt = safeTimestamp(raw?.intendedActionAt);
    const dueDate = boundedText(raw?.dueDate, 10);
    const timeZoneIdentifier = boundedText(raw?.timeZoneIdentifier, 100);
    const deepLink = safeAirportXRURL(raw?.deepLink);
    const sourceRevision = Number(raw?.sourceRevision);
    if (!/^[A-Za-z0-9._:-]{1,128}$/.test(id) || identifiers.has(id) || !title || !intendedActionAt ||
        !isISODate(dueDate) || !validTimeZone(timeZoneIdentifier) ||
        localISODate(intendedActionAt, timeZoneIdentifier) !== dueDate || !deepLink ||
        !Number.isSafeInteger(sourceRevision) || sourceRevision < 0) return null;
    identifiers.add(id);
    reminders.push({ id, title, notes, intendedActionAt, dueDate, timeZoneIdentifier, deepLink, sourceRevision });
  }
  reminders.sort((left, right) => left.id.localeCompare(right.id));
  return { consentRevision, taskListID, scopeID, reminders };
}

function googleOAuthBearerToken(value) {
  const match = String(value || "").match(/^Bearer (.+)$/);
  if (!match) return null;
  const token = match[1];
  if (token.length < 1 || token.length > LIMITS.googleOAuthTokenCharacters ||
      [...token].some(character => character.charCodeAt(0) <= 0x20 || character.charCodeAt(0) === 0x7f)) return null;
  return token;
}

function safeAirportXRURL(value) {
  try {
    const parsed = new URL(String(value || ""));
    return parsed.protocol === "airportxr:" && !parsed.username && !parsed.password ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function validTimeZone(value) {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format(new Date(0));
    return true;
  } catch {
    return false;
  }
}

function localISODate(timestamp, timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(new Date(timestamp));
  const part = type => parts.find(candidate => candidate.type === type)?.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function googleTasksMarker(scopeID, reminderID) {
  return `[AirportXR:${GOOGLE_TASKS_MARKER_VERSION} scope=${scopeID} reminder=${reminderID}]`;
}

function parseGoogleTasksMarker(notes) {
  const match = String(notes || "").match(/\[AirportXR:v1 scope=([A-Za-z0-9._:-]{1,128}) reminder=([A-Za-z0-9._:-]{1,128})\]/);
  return match ? { scopeID: match[1], reminderID: match[2] } : null;
}

function googleTaskResource(scopeID, reminder) {
  return {
    title: reminder.title,
    notes: [
      reminder.notes,
      `Exact Airport XR action time: ${reminder.intendedActionAt}`,
      `Airport time zone: ${reminder.timeZoneIdentifier}`,
      `Open: ${reminder.deepLink}`,
      googleTasksMarker(scopeID, reminder.id)
    ].filter(Boolean).join("\n"),
    // Google Tasks documents that only the date is retained; using midnight Z
    // preserves the already-derived local date without inventing an alert time.
    due: `${reminder.dueDate}T00:00:00.000Z`,
    status: "needsAction"
  };
}

async function listGoogleTasks(taskListID, accessToken) {
  const records = [];
  let pageToken = null;
  for (let page = 0; page < LIMITS.googleTaskScanPages; page += 1) {
    const url = new URL(`${PROVIDERS.googleTasksBaseURL}/lists/${encodeURIComponent(taskListID)}/tasks`);
    url.searchParams.set("maxResults", String(LIMITS.googleTaskPageSize));
    url.searchParams.set("showCompleted", "true");
    url.searchParams.set("showHidden", "true");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await googleTasksFetch(url, { headers: googleTasksHeaders(accessToken) });
    const payload = await readBoundedJSON(response, LIMITS.providerResponseBytes);
    if (payload.items !== undefined && !Array.isArray(payload.items)) throw new ProviderError(502);
    records.push(...(payload.items || []).map(task => ({
      id: boundedText(task?.id, 300),
      notes: boundedText(task?.notes, 8_192)
    })).filter(task => task.id));
    pageToken = boundedText(payload.nextPageToken, 1_024) || null;
    if (!pageToken) return records;
  }
  throw new GoogleTaskListScanError();
}

async function insertGoogleTask(taskListID, resource, accessToken) {
  const url = `${PROVIDERS.googleTasksBaseURL}/lists/${encodeURIComponent(taskListID)}/tasks`;
  const response = await googleTasksFetch(url, {
    method: "POST",
    headers: googleTasksHeaders(accessToken, true),
    body: JSON.stringify(resource)
  });
  return readBoundedJSON(response, LIMITS.providerResponseBytes);
}

async function updateGoogleTask(taskListID, taskID, resource, accessToken) {
  const url = `${PROVIDERS.googleTasksBaseURL}/lists/${encodeURIComponent(taskListID)}/tasks/${encodeURIComponent(taskID)}`;
  const response = await googleTasksFetch(url, {
    method: "PATCH",
    headers: googleTasksHeaders(accessToken, true),
    body: JSON.stringify(resource)
  });
  return readBoundedJSON(response, LIMITS.providerResponseBytes);
}

async function deleteGoogleTask(taskListID, taskID, accessToken) {
  const url = `${PROVIDERS.googleTasksBaseURL}/lists/${encodeURIComponent(taskListID)}/tasks/${encodeURIComponent(taskID)}`;
  await googleTasksFetch(url, {
    method: "DELETE",
    headers: googleTasksHeaders(accessToken)
  }, true);
}

function googleTasksHeaders(accessToken, includesBody = false) {
  return {
    Accept: "application/json",
    Authorization: `Bearer ${accessToken}`,
    ...(includesBody ? { "content-type": "application/json" } : {})
  };
}

async function googleTasksFetch(url, init, allowNotFound = false) {
  let response;
  try {
    response = await fetch(String(url), {
      ...init,
      signal: AbortSignal.timeout(LIMITS.providerTimeoutMilliseconds),
      cf: { cacheTtl: 0 }
    });
  } catch (error) {
    if (error?.name === "TimeoutError" || error?.name === "AbortError") throw new ProviderError(504);
    throw new ProviderError(502);
  }
  if (response.status === 401 || response.status === 403) throw new GoogleAuthorizationError();
  if (allowNotFound && response.status === 404) return response;
  if (!response.ok) {
    const retryAfter = boundedText(response.headers.get("retry-after"), 120) || null;
    if (response.status === 429) throw new ProviderError(429, retryAfter);
    if (response.status === 408 || response.status === 504) throw new ProviderError(504);
    throw new ProviderError(502);
  }
  return response;
}

async function searchFlights(url, env) {
  const rawIdent = (url.searchParams.get("flightNumber") || "").toUpperCase().replace(/\s+/g, "");
  const date = url.searchParams.get("date") || "";
  const designator = parseFlightDesignator(rawIdent);
  if (!designator || !isISODate(date)) {
    return json({ error: "invalid_query" }, 400);
  }

  const providerOrder = flightSearchProviderOrder(env);
  if (!providerOrder.length) return notConfigured("flightStatus", "FlightAware AeroAPI or Amadeus On-Demand Flight Status");
  const result = await executeProviderFallback(providerOrder.map(providerID => async () => {
    if (providerID === "amadeus") return searchAmadeusFlights(designator, date, env);
    return searchFlightAwareFlights(rawIdent, date, env);
  }));
  return capabilityJSON({ flights: result.flights }, result.source);
}

async function searchFlightAwareFlights(rawIdent, date, env) {
  const start = `${date}T00:00:00Z`;
  const endDate = new Date(start);
  endDate.setUTCDate(endDate.getUTCDate() + 2);
  const path = `/flights/${encodeURIComponent(rawIdent)}?start=${encodeURIComponent(start)}&end=${encodeURIComponent(endDate.toISOString())}&max_pages=1`;
  const payload = await flightAwareFetch(path, env);
  if (!Array.isArray(payload.flights)) throw new ProviderError(502);
  const flights = payload.flights.slice(0, LIMITS.normalizedRecords).map(normalizeFlight).filter(Boolean);
  return {
    flights,
    source: {
      provider: "FlightAware AeroAPI",
      dataMode: "live",
      ttlSeconds: CACHE_TTLS.flightSeconds,
      policy: "flightaware"
    }
  };
}

async function searchAmadeusFlights(designator, date, env) {
  const payload = await amadeusFetch("/v2/schedule/flights", {
    carrierCode: designator.carrierCode,
    flightNumber: designator.flightNumber,
    scheduledDepartureDate: date,
    ...(designator.operationalSuffix ? { operationalSuffix: designator.operationalSuffix } : {})
  }, env);
  if (!Array.isArray(payload.data)) throw new ProviderError(502);
  const flights = payload.data.slice(0, LIMITS.normalizedRecords).map(normalizeAmadeusFlight).filter(Boolean);
  return {
    flights,
    source: amadeusSource(env, "amadeusFlights", CACHE_TTLS.flightSeconds)
  };
}

async function executeProviderFallback(operations) {
  let lastError = new ProviderError(502);
  for (const operation of operations) {
    try {
      return await operation();
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error;
      lastError = error;
      if (error.status === 429) throw error;
    }
  }
  throw lastError;
}

function flightSearchProviderOrder(env) {
  const available = [];
  if (flightAwareKey(env)) available.push("flightaware");
  if (env.AMADEUS_CLIENT_ID && env.AMADEUS_CLIENT_SECRET) available.push("amadeus");
  const preferred = String(env.FLIGHT_PROVIDER || "flightaware").toLowerCase();
  return available.sort((left, right) => Number(right === preferred) - Number(left === preferred));
}

function parseFlightDesignator(value) {
  const match = String(value || "").match(/^([A-Z0-9]{2,3})(\d{1,5})([A-Z]?)$/);
  if (!match) return null;
  return { carrierCode: match[1], flightNumber: match[2], operationalSuffix: match[3] || null };
}

async function airportBoard(url, env, code, board) {
  const missing = requireFlightAware(env);
  if (missing) return missing;
  const date = url.searchParams.get("date") || new Date().toISOString().slice(0, 10);
  if (!isISODate(date)) return json({ error: "invalid_date" }, 400);
  const start = `${date}T00:00:00Z`;
  const end = `${date}T23:59:59Z`;
  const path = `/airports/${encodeURIComponent(code.toUpperCase())}/flights/${board}?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}&max_pages=1`;
  const payload = await flightAwareFetch(path, env);
  if (!Array.isArray(payload[board])) throw new ProviderError(502);
  return capabilityJSON({ flights: payload[board].slice(0, LIMITS.normalizedRecords).map(normalizeFlight).filter(Boolean) }, {
    provider: "FlightAware AeroAPI",
    dataMode: "live",
    ttlSeconds: CACHE_TTLS.flightSeconds,
    policy: "flightaware"
  });
}

async function flightByID(env, id) {
  const missing = requireFlightAware(env);
  if (missing) return missing;
  const payload = await flightAwareFetch(`/flights/${encodeURIComponent(id)}`, env);
  if (!Array.isArray(payload.flights)) throw new ProviderError(502);
  const flights = payload.flights.slice(0, LIMITS.normalizedRecords).map(normalizeFlight).filter(Boolean);
  if (!flights.length) return json({ error: "not_found" }, 404);
  return capabilityJSON({ flight: flights[0] }, {
    provider: "FlightAware AeroAPI",
    dataMode: "live",
    ttlSeconds: CACHE_TTLS.flightSeconds,
    policy: "flightaware"
  });
}

async function searchHotels(url, env) {
  const configurationError = requireAmadeus(env, "hotels");
  if (configurationError) return configurationError;
  const query = parseGeographicQuery(url);
  if (query.error) return json({ error: query.error }, 400);

  const adults = optionalInteger(url.searchParams.get("adults"), 1, 9, 1);
  const checkInDate = url.searchParams.get("checkInDate");
  const checkOutDate = url.searchParams.get("checkOutDate");
  if (adults === null || (checkInDate && !isISODate(checkInDate)) || (checkOutDate && !isISODate(checkOutDate))) {
    return json({ error: "invalid_query" }, 400);
  }
  if ((checkInDate && !checkOutDate) || (!checkInDate && checkOutDate) || (checkInDate && checkOutDate && checkInDate >= checkOutDate)) {
    return json({ error: "invalid_stay_dates" }, 400);
  }

  const hotelSearch = await amadeusFetch("/v1/reference-data/locations/hotels/by-geocode", {
    latitude: query.latitude,
    longitude: query.longitude,
    radius: query.radiusKm,
    radiusUnit: "KM",
    hotelSource: "ALL"
  }, env);
  const hotelRecords = Array.isArray(hotelSearch.data) ? hotelSearch.data.slice(0, LIMITS.hotelCandidates) : [];
  const hotelIDs = hotelRecords.map(record => boundedText(record.hotelId, 30)).filter(Boolean);

  let offerRecords = [];
  if (hotelIDs.length && checkInDate && checkOutDate) {
    const offerSearch = await amadeusFetch("/v3/shopping/hotel-offers", {
      hotelIds: hotelIDs.join(","),
      adults,
      checkInDate,
      checkOutDate,
      roomQuantity: 1,
      paymentPolicy: "NONE",
      bestRateOnly: true
    }, env);
    offerRecords = Array.isArray(offerSearch.data) ? offerSearch.data.slice(0, LIMITS.hotelCandidates) : [];
  }
  const offersByHotel = new Map(offerRecords.map(record => [record.hotel?.hotelId, record]));
  const hotels = hotelRecords.map(record => normalizeHotel(record, offersByHotel.get(record.hotelId))).filter(Boolean);
  return capabilityJSON({
    hotels,
    query: { ...query, adults, checkInDate: checkInDate || null, checkOutDate: checkOutDate || null },
    booking: { mode: "externalProvider", paymentsHandledByApp: false }
  }, amadeusSource(env, "amadeusHotels", CACHE_TTLS.hotelOffersSeconds));
}

async function searchActivities(url, env) {
  const configurationError = requireAmadeus(env, "activities");
  if (configurationError) return configurationError;
  const query = parseGeographicQuery(url);
  if (query.error) return json({ error: query.error }, 400);

  const payload = await amadeusFetch("/v1/shopping/activities", {
    latitude: query.latitude,
    longitude: query.longitude,
    radius: query.radiusKm
  }, env);
  const activities = (Array.isArray(payload.data) ? payload.data : [])
    .slice(0, LIMITS.normalizedRecords)
    .map(normalizeActivity)
    .filter(Boolean);
  return capabilityJSON({ activities, query }, amadeusSource(env, "amadeusActivities", CACHE_TTLS.activitiesSeconds));
}

function airportFacilities(rawCode) {
  const airportCode = rawCode.toUpperCase();
  if (!/^[A-Z0-9]{3,4}$/.test(airportCode)) return json({ error: "invalid_airport" }, 400);
  if (airportCode !== "HND") {
    return capabilityJSON({
      airportCode,
      facilities: [],
      availability: "registryUnavailable",
      advisory: "Use native MapKit discovery for public nearby places; airside claims require an airport or operator record."
    }, {
      provider: "Airport XR Companion facility registry",
      dataMode: "publicRegistry",
      ttlSeconds: CACHE_TTLS.facilitiesSeconds,
      policy: "hndOfficialRegistry"
    });
  }
  return capabilityJSON({
    airportCode,
    registryVersion: HND_REGISTRY_VERSION,
    facilities: HND_FACILITIES,
    availability: "officialRecordsIndexed",
    advisory: "Opening hours and access conditions must be rechecked against the linked official record before use."
  }, {
    provider: "Haneda Airport and facility operator records",
    dataMode: "publicRegistry",
    ttlSeconds: CACHE_TTLS.facilitiesSeconds,
    policy: "hndOfficialRegistry"
  });
}

const PROHIBITED_ENTRY_FIELDS = new Set([
  "passportnumber",
  "documentnumber",
  "passportscan",
  "passportimage",
  "mrz"
]);

async function entryRequirements(request, env) {
  let value;
  try {
    value = await readBoundedRequestJSON(request, LIMITS.entryRequestBytes);
  } catch (error) {
    if (error instanceof ReminderRequestError) return json({ error: error.code }, error.status);
    throw error;
  }
  if (containsProhibitedEntryField(value)) return json({ error: "sensitive_field_prohibited" }, 400);
  const query = normalizeEntryRequirementQuery(value);
  if (!query) return json({ error: "invalid_query" }, 400);
  query.fingerprint = await sha256Hex(JSON.stringify(query));
  return resolveEntryRequirements(query, env);
}

async function legacyEntryRequirements(url, env) {
  if ([...url.searchParams.keys()].some(key => PROHIBITED_ENTRY_FIELDS.has(normalizedFieldName(key)))) {
    return json({ error: "sensitive_field_prohibited" }, 400);
  }
  const destinationCountry = normalizedCountryCode(url.searchParams.get("destinationCountry"));
  const plannedEntry = parseBoolean(url.searchParams.get("plannedEntry"), false);
  if (!destinationCountry || plannedEntry === null) return json({ error: "invalid_query" }, 400);
  const query = {
    destinationCountry,
    plannedEntry,
    fingerprint: await sha256Hex(`legacy|${destinationCountry}|${plannedEntry}`)
  };
  // The legacy query lacks the ordered segments and local-time facts required
  // by structured providers, so it can return links but never an assessment.
  return entryDiscoveryResponse(query, env, ["Legacy query: structured assessment skipped"]);
}

function containsProhibitedEntryField(value) {
  if (Array.isArray(value)) return value.some(containsProhibitedEntryField);
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([key, child]) =>
    PROHIBITED_ENTRY_FIELDS.has(normalizedFieldName(key)) || containsProhibitedEntryField(child)
  );
}

function normalizedFieldName(value) {
  return String(value || "").toLowerCase().replace(/[^a-z]/g, "");
}

function normalizeEntryRequirementQuery(value) {
  const nationality = normalizedCountryCode(value.nationalityCountryCode);
  const residence = normalizedCountryCode(value.residenceCountryCode);
  const originCountry = normalizedCountryCode(value.originCountryCode);
  const destinationCountry = normalizedCountryCode(value.transitCountryCode);
  const onwardCountry = normalizedCountryCode(value.onwardCountryCode);
  const passportType = boundedText(value.passportType, 40);
  const purpose = boundedText(value.purpose, 30);
  const luggage = boundedText(value.luggage, 30);
  const originAirport = normalizedAirportCode(value.originAirportCode);
  const arrivalAirport = normalizedAirportCode(value.transitArrivalAirportCode);
  const onwardAirport = normalizedAirportCode(value.onwardDepartureAirportCode);
  const finalAirport = normalizedAirportCode(value.onwardDestinationAirportCode);
  const originDeparture = safeTimestamp(value.originDeparture);
  const arrival = safeTimestamp(value.arrival);
  const departure = safeTimestamp(value.departure);
  const onwardArrival = safeTimestamp(value.onwardArrival);
  const originTimeZone = boundedText(value.originTimeZoneIdentifier, 100);
  const transitTimeZone = boundedText(value.transitTimeZoneIdentifier, 100);
  const onwardTimeZone = boundedText(value.onwardTimeZoneIdentifier, 100);
  const plannedEntry = typeof value.plannedLandsideExit === "boolean" ? value.plannedLandsideExit : null;
  const passportTypes = new Set(["ordinary", "diplomatic", "official", "refugeeTravelDocument", "other"]);
  const purposes = new Set(["transit", "tourism", "business", "study", "work", "other"]);
  const luggagePlans = new Set(["cabinOnly", "checkedThrough", "collectAndRecheck", "unknown"]);
  const declaredAuthorizations = normalizeDeclaredAuthorizations(value.declaredAuthorizations);
  if (!nationality || !residence || !originCountry || !destinationCountry || !onwardCountry ||
      !passportTypes.has(passportType) || !purposes.has(purpose) || !luggagePlans.has(luggage) ||
      !originAirport || !arrivalAirport || !onwardAirport || !finalAirport ||
      !originDeparture || !arrival || !departure || !onwardArrival ||
      !validTimeZone(originTimeZone) || !validTimeZone(transitTimeZone) || !validTimeZone(onwardTimeZone) ||
      plannedEntry === null || declaredAuthorizations === null ||
      Date.parse(originDeparture) >= Date.parse(arrival) || Date.parse(arrival) >= Date.parse(departure) ||
      Date.parse(departure) >= Date.parse(onwardArrival)) return null;
  return {
    nationality,
    residence,
    passportType,
    declaredAuthorizations,
    originCountry,
    destinationCountry,
    onwardCountry,
    originAirport,
    arrivalAirport,
    onwardAirport,
    finalAirport,
    originDeparture,
    arrival,
    departure,
    onwardArrival,
    originTimeZone,
    transitTimeZone,
    onwardTimeZone,
    plannedEntry,
    luggage,
    purpose
  };
}

function normalizeDeclaredAuthorizations(value) {
  if (!Array.isArray(value) || value.length > LIMITS.declaredAuthorizations) return null;
  const records = [];
  for (const item of value) {
    const countryCode = normalizedCountryCode(item?.countryCode);
    const kind = boundedText(item?.kind, 100);
    const expiresAt = item?.expiresAt == null ? null : safeTimestamp(item.expiresAt);
    if (!countryCode || !kind || (item?.expiresAt != null && !expiresAt)) return null;
    records.push({ countryCode, kind, expiresAt });
  }
  return records.sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
}

function normalizedAirportCode(value) {
  const code = String(value || "").trim().toUpperCase();
  return /^[A-Z0-9]{3,4}$/.test(code) ? code : null;
}

async function resolveEntryRequirements(query, env) {
  const attempts = [];
  const providers = [];
  if (env.SHERPA_API_KEY) providers.push({ label: "Sherpa Requirements API", run: () => sherpaEntryResult(query, env) });
  if (env.TIMATIC_API_URL && env.TIMATIC_API_KEY) providers.push({ label: "IATA Timatic AutoCheck adapter", run: () => timaticEntryResult(query, env) });
  for (const provider of providers) {
    attempts.push(provider.label);
    try {
      const result = await provider.run();
      return structuredEntryResponse(query, result, attempts);
    } catch (error) {
      if (error instanceof ProviderError && error.status === 429) throw error;
      if (error instanceof ProviderError && error.upstreamStatus >= 400 && error.upstreamStatus < 500) throw error;
      if (!(error instanceof ProviderError)) throw error;
    }
  }
  return entryDiscoveryResponse(query, env, attempts);
}

async function sherpaEntryResult(query, env) {
  const passport = alpha3CountryCode(query.nationality);
  if (!passport) throw new ProviderError(502);
  const travelNodes = [
    {
      type: "ORIGIN",
      airportCode: query.originAirport,
      departure: sherpaTravelEvent(query.originDeparture, query.originTimeZone)
    },
    {
      type: "DESTINATION",
      airportCode: query.arrivalAirport,
      arrival: sherpaTravelEvent(query.arrival, query.transitTimeZone)
    },
    {
      type: "ORIGIN",
      airportCode: query.onwardAirport,
      departure: sherpaTravelEvent(query.departure, query.transitTimeZone)
    },
    {
      type: "DESTINATION",
      airportCode: query.finalAirport,
      arrival: sherpaTravelEvent(query.onwardArrival, query.onwardTimeZone)
    }
  ];
  const response = await providerFetch(PROVIDERS.sherpaRequirementsURL, {
    method: "POST",
    headers: {
      Accept: "application/vnd.api+json",
      "Content-Type": "application/vnd.api+json",
      "x-api-key": env.SHERPA_API_KEY
    },
    body: JSON.stringify({
      data: {
        type: "TRIP",
        attributes: {
          locale: "en-US",
          traveller: { passports: [passport] },
          currency: "USD",
          travelNodes
        }
      }
    }),
    cf: { cacheTtl: 0 }
  });
  const receivedAt = new Date().toISOString();
  const payload = await readBoundedJSON(response, LIMITS.providerResponseBytes);
  if (!payload?.data || typeof payload.data !== "object" || Array.isArray(payload.data) ||
      !payload.data.attributes || typeof payload.data.attributes !== "object" ||
      !Array.isArray(payload.data.attributes.informationGroups)) throw new ProviderError(502);
  const requirements = normalizeSherpaRequirements(payload);
  const officialVerificationLinks = mergeOfficialLinks(
    OFFICIAL_ENTRY_LINKS[query.destinationCountry] || [],
    sherpaGovernmentLinks(payload)
  );
  const expiresAt = boundedProviderExpiry(payload.meta?.expiresAt, response, receivedAt, CACHE_TTLS.entryRequirementsSeconds);
  return {
    provider: "Sherpa Requirements API",
    policy: "sherpa",
    recordID: boundedText(payload.data.id, 160) || `sherpa-${query.fingerprint}`,
    observedAt: latestSherpaObservation(payload) || receivedAt,
    receivedAt,
    expiresAt,
    requirements,
    officialVerificationLinks
  };
}

function alpha3CountryCode(value) {
  const code = String(value || "").toUpperCase();
  if (/^[A-Z]{2}$/.test(code)) return countries.alpha2ToAlpha3(code) || null;
  return /^[A-Z]{3}$/.test(code) && countries.isValid(code) ? code : null;
}

function sherpaTravelEvent(timestamp, timeZone) {
  return {
    date: localISODate(timestamp, timeZone),
    time: localISOTime(timestamp, timeZone),
    travelMode: "AIR"
  };
}

function localISOTime(timestamp, timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23"
  }).formatToParts(new Date(timestamp));
  const part = type => parts.find(candidate => candidate.type === type)?.value;
  return `${part("hour")}:${part("minute")}`;
}

function normalizeSherpaRequirements(payload) {
  const included = Array.isArray(payload.included) ? payload.included : [];
  return included
    .filter(record => record && typeof record === "object" && ["PROCEDURE", "RESTRICTION"].includes(record.type))
    .slice(0, LIMITS.normalizedRecords)
    .map((record, index) => {
      const attributes = record.attributes || {};
      const sourceURL = (Array.isArray(attributes.sources) ? attributes.sources : [])
        .map(source => safeExternalURL(source?.url))
        .find(Boolean) || null;
      return {
        id: boundedText(record.id, 160) || `requirement-${index + 1}`,
        category: boundedText(attributes.category || record.type, 60) || "unknown",
        status: boundedText(attributes.enforcement, 60) || "requiresVerification",
        summary: boundedText(attributes.description || attributes.title, 500) || "See provider and official authority guidance.",
        verificationURL: sourceURL
      };
    });
}

function sherpaGovernmentLinks(payload) {
  const included = Array.isArray(payload.included) ? payload.included : [];
  const links = [];
  for (const record of included) {
    for (const source of Array.isArray(record?.attributes?.sources) ? record.attributes.sources : []) {
      if (String(source?.type || "").toUpperCase() !== "GOVERNMENT") continue;
      const url = safeExternalURL(source?.url);
      if (url) links.push({ label: boundedText(source?.title, 160) || "Official government source", url });
    }
  }
  return links;
}

function latestSherpaObservation(payload) {
  const values = (Array.isArray(payload.included) ? payload.included : [])
    .map(record => safeTimestamp(record?.attributes?.lastUpdatedAt))
    .filter(Boolean)
    .sort();
  return values.at(-1) || null;
}

async function timaticEntryResult(query, env) {
  const endpoint = safeConfiguredHTTPSURL(env.TIMATIC_API_URL);
  if (!endpoint) throw new ProviderError(502);
  const response = await providerFetch(endpoint, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-api-key": env.TIMATIC_API_KEY,
      ...(env.TIMATIC_SERVICE_TOKEN ? { "x-service-token": env.TIMATIC_SERVICE_TOKEN } : {})
    },
    // Timatic account schemas are contract-specific. TIMATIC_API_URL must point
    // to the deployment's reviewed adapter exposing this normalized request.
    body: JSON.stringify({ schemaVersion: "airportxr-entry-query-v1", query }),
    cf: { cacheTtl: 0 }
  });
  const receivedAt = new Date().toISOString();
  const payload = await readBoundedJSON(response, LIMITS.providerResponseBytes);
  const assessment = payload?.assessment;
  if (!assessment || typeof assessment !== "object" || Array.isArray(assessment)) throw new ProviderError(502);
  const expiresAt = boundedProviderExpiry(assessment.expiresAt || payload.expiresAt, response, receivedAt, CACHE_TTLS.entryRequirementsSeconds);
  const recordID = boundedText(assessment.recordID || payload.recordID, 160);
  const requirements = normalizeAdapterRequirements(assessment.requirements);
  if (!recordID || !Array.isArray(assessment.requirements)) throw new ProviderError(502);
  return {
    provider: "IATA Timatic AutoCheck adapter",
    policy: "timatic",
    recordID,
    observedAt: safeTimestamp(assessment.observedAt) || receivedAt,
    receivedAt,
    expiresAt,
    requirements,
    officialVerificationLinks: mergeOfficialLinks(
      OFFICIAL_ENTRY_LINKS[query.destinationCountry] || [],
      normalizeOfficialLinks(assessment.officialVerificationLinks)
    )
  };
}

function normalizeAdapterRequirements(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, LIMITS.normalizedRecords).map((record, index) => ({
    id: boundedText(record?.id, 160) || `requirement-${index + 1}`,
    category: boundedText(record?.category, 60) || "unknown",
    status: boundedText(record?.status, 60) || "requiresVerification",
    summary: boundedText(record?.summary, 500) || "See provider and official authority guidance.",
    verificationURL: safeExternalURL(record?.verificationURL)
  }));
}

function boundedProviderExpiry(rawExpiry, response, receivedAt, maximumTTLSeconds) {
  const receivedMilliseconds = Date.parse(receivedAt);
  const cacheSeconds = cacheControlMaximumAge(response.headers.get("cache-control"));
  const ttlSeconds = Math.min(maximumTTLSeconds, cacheSeconds ?? maximumTTLSeconds);
  const conservativeExpiry = receivedMilliseconds + Math.max(0, ttlSeconds) * 1_000;
  const explicitExpiry = rawExpiry ? Date.parse(safeTimestamp(rawExpiry) || "") : null;
  if (explicitExpiry !== null && (!Number.isFinite(explicitExpiry) || explicitExpiry <= receivedMilliseconds)) {
    throw new ProviderError(502);
  }
  return new Date(explicitExpiry === null ? conservativeExpiry : Math.min(explicitExpiry, conservativeExpiry)).toISOString();
}

function cacheControlMaximumAge(value) {
  const match = String(value || "").match(/(?:^|,)\s*max-age=(\d+)\s*(?:,|$)/i);
  if (!match) return null;
  const seconds = Number(match[1]);
  return Number.isSafeInteger(seconds) ? seconds : null;
}

function safeConfiguredHTTPSURL(value) {
  try {
    const url = new URL(String(value || ""));
    return url.protocol === "https:" && !url.username && !url.password ? url.toString() : null;
  } catch {
    return null;
  }
}

function structuredEntryResponse(query, result, attempts) {
  const ttlSeconds = Math.max(
    0,
    Math.min(
      CACHE_TTLS.entryRequirementsSeconds,
      Math.floor((Date.parse(result.expiresAt) - Date.parse(result.receivedAt)) / 1_000)
    )
  );
  return capabilityJSON({
    queryFingerprint: query.fingerprint,
    assessment: {
      status: "requiresConfirmation",
      canEnter: null,
      decisionAuthority: "structuredGuidance",
      reason: result.requirements.length
        ? "Structured guidance was found. Verify the exact traveler, documents, itinerary, and purpose with the linked official authority before leaving the airport."
        : "The structured provider returned no normalized requirements. Official verification is required.",
      requirements: result.requirements,
      officialVerificationLinks: result.officialVerificationLinks
    },
    decisionSupportOnly: true
  }, {
    provider: result.provider,
    dataMode: "liveGuidance",
    ttlSeconds,
    policy: result.policy,
    recordID: result.recordID,
    observedAt: result.observedAt,
    receivedAt: result.receivedAt,
    expiresAt: result.expiresAt,
    evidenceKind: "structuredProvider",
    providerChain: attempts
  });
}

async function entryDiscoveryResponse(query, env, attempts) {
  const registryLinks = OFFICIAL_ENTRY_LINKS[query.destinationCountry] || [];
  let discoveredLinks = [];
  let usedGemini = false;
  if (env.GEMINI_API_KEY && officialDomainsFor(query.destinationCountry, env).length) {
    attempts.push("Gemini Google Search discovery");
    try {
      discoveredLinks = await discoverOfficialEntryLinks(query.destinationCountry, env);
      usedGemini = true;
    } catch {
      // Discovery is never a safety dependency; retain only the bundled links.
    }
  }
  const officialVerificationLinks = mergeOfficialLinks(registryLinks, discoveredLinks);
  const receivedAt = new Date().toISOString();
  const ttlSeconds = usedGemini ? CACHE_TTLS.activitiesSeconds : 0;
  return capabilityJSON({
    queryFingerprint: query.fingerprint,
    assessment: {
      status: "requiresConfirmation",
      canEnter: null,
      decisionAuthority: "discoveryOnly",
      reason: officialVerificationLinks.length
        ? "Structured providers were unavailable. These links are discovery aids only; no visa or entry conclusion was derived."
        : "Structured providers were unavailable and no allowlisted official source was found. Keep the plan airside and verify manually.",
      requirements: [],
      officialVerificationLinks
    },
    decisionSupportOnly: true
  }, {
    provider: usedGemini ? "Gemini Google Search official-link discovery" : "Bundled official-link registry",
    dataMode: usedGemini ? "liveDiscovery" : "publicRegistry",
    ttlSeconds,
    policy: usedGemini ? "geminiEntryDiscovery" : null,
    recordID: `entry-discovery-${query.fingerprint}`,
    observedAt: receivedAt,
    receivedAt,
    expiresAt: new Date(Date.parse(receivedAt) + ttlSeconds * 1_000).toISOString(),
    evidenceKind: usedGemini ? "officialSourceDiscovery" : "informationalFallback",
    providerChain: attempts
  });
}

async function discoverOfficialEntryLinks(destinationCountry, env) {
  const domains = officialDomainsFor(destinationCountry, env);
  const siteQuery = domains.map(domain => `site:${domain}`).join(" OR ");
  const response = await providerFetch(PROVIDERS.geminiInteractionsURL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": env.GEMINI_API_KEY
    },
    body: JSON.stringify({
      model: boundedText(env.GEMINI_ENTRY_DISCOVERY_MODEL, 80) || "gemini-3.5-flash",
      input: `Find current official national-government visa, transit, and entry-information pages for destination country ${destinationCountry}. Search only ${siteQuery}. Do not decide or state whether any traveler can enter.`,
      tools: [{ type: "google_search" }]
    }),
    cf: { cacheTtl: 0 }
  });
  const payload = await readBoundedJSON(response, LIMITS.providerResponseBytes);
  if (!Array.isArray(payload?.steps)) throw new ProviderError(502);
  const links = [];
  for (const step of payload.steps) {
    if (step?.type !== "model_output" || !Array.isArray(step.content)) continue;
    for (const block of step.content) {
      for (const annotation of Array.isArray(block?.annotations) ? block.annotations : []) {
        if (annotation?.type !== "url_citation") continue;
        const url = allowlistedOfficialURL(annotation.url, domains);
        if (url) links.push({ label: boundedText(annotation.title, 160) || new URL(url).hostname, url });
      }
    }
  }
  return mergeOfficialLinks([], links);
}

function officialDomainsFor(countryCode, env) {
  const defaults = OFFICIAL_ENTRY_DOMAINS[countryCode] || [];
  let configured = [];
  try {
    const value = JSON.parse(String(env.ENTRY_OFFICIAL_DOMAINS_JSON || "{}"));
    if (Array.isArray(value?.[countryCode])) {
      configured = value[countryCode]
        .map(domain => String(domain || "").trim().toLowerCase().replace(/^\.+/, ""))
        .filter(domain => /^[a-z0-9.-]+$/.test(domain) && domain.includes("."));
    }
  } catch {
    configured = [];
  }
  return [...new Set([...defaults, ...configured])].sort();
}

function allowlistedOfficialURL(value, domains) {
  const safe = safeExternalURL(value);
  if (!safe) return null;
  const hostname = new URL(safe).hostname.toLowerCase();
  return domains.some(domain => hostname === domain || hostname.endsWith(`.${domain}`)) ? safe : null;
}

function normalizeOfficialLinks(value) {
  if (!Array.isArray(value)) return [];
  return value.map(link => ({
    label: boundedText(link?.label || link?.title, 160) || "Official verification",
    url: safeExternalURL(link?.url)
  })).filter(link => link.url);
}

function mergeOfficialLinks(...groups) {
  const records = new Map();
  for (const link of groups.flat()) {
    const url = safeExternalURL(link?.url);
    if (!url || records.has(url)) continue;
    records.set(url, { label: boundedText(link?.label, 160) || "Official verification", url });
    if (records.size >= LIMITS.officialVerificationLinks) break;
  }
  return [...records.values()];
}

async function flightAwareFetch(path, env) {
  const response = await providerFetch(`${PROVIDERS.flightAwareBaseURL}${path}`, {
    headers: { Accept: "application/json", "x-apikey": flightAwareKey(env) },
    cf: { cacheTtl: 0 }
  });
  return readBoundedJSON(response, LIMITS.providerResponseBytes);
}

async function amadeusFetch(path, params, env) {
  const token = await amadeusAccessToken(env);
  const baseURL = amadeusBaseURL(env);
  const url = new URL(path, baseURL);
  for (const [key, value] of Object.entries(params)) {
    if (value !== null && value !== undefined) url.searchParams.set(key, String(value));
  }
  const response = await providerFetch(url.toString(), {
    headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    cf: { cacheTtl: 0 }
  });
  return readBoundedJSON(response, LIMITS.providerResponseBytes);
}

async function amadeusAccessToken(env) {
  const now = Date.now();
  const credentialMarker = `${amadeusBaseURL(env)}:${boundedText(env.AMADEUS_CLIENT_ID, 200)}`;
  if (amadeusTokenCache && amadeusTokenCache.credentialMarker === credentialMarker && amadeusTokenCache.expiresAtMilliseconds > now + 30_000) {
    return amadeusTokenCache.token;
  }

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: env.AMADEUS_CLIENT_ID,
    client_secret: env.AMADEUS_CLIENT_SECRET
  });
  const response = await providerFetch(`${amadeusBaseURL(env)}/v1/security/oauth2/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: body.toString(),
    cf: { cacheTtl: 0 }
  });
  const payload = await readBoundedJSON(response, LIMITS.tokenResponseBytes);
  const token = boundedText(payload.access_token, 4_096);
  const expiresIn = Number(payload.expires_in);
  if (!token || !Number.isFinite(expiresIn) || expiresIn <= 0) throw new ProviderError(502);
  amadeusTokenCache = {
    token,
    credentialMarker,
    expiresAtMilliseconds: now + Math.min(expiresIn, 86_400) * 1_000
  };
  return token;
}

async function providerFetch(url, init = {}) {
  let parsedURL;
  try {
    parsedURL = new URL(url);
  } catch {
    throw new ProviderError(502);
  }
  if (parsedURL.protocol !== "https:" || parsedURL.username || parsedURL.password) throw new ProviderError(502);
  let response;
  try {
    response = await fetch(parsedURL.toString(), { ...init, signal: AbortSignal.timeout(LIMITS.providerTimeoutMilliseconds) });
  } catch (error) {
    if (error?.name === "TimeoutError" || error?.name === "AbortError") throw new ProviderError(504);
    throw new ProviderError(502);
  }
  if (!response.ok) {
    const retryAfter = boundedText(response.headers.get("retry-after"), 120) || null;
    const status = response.status === 429 ? 429 : response.status === 408 || response.status === 504 ? 504 : 502;
    throw new ProviderError(status, retryAfter, response.status);
  }
  return response;
}

async function readBoundedJSON(response, maximumBytes) {
  const contentType = String(response.headers.get("content-type") || "").toLowerCase();
  if (!contentType.includes("application/json")) throw new ProviderError(502);
  const declaredLengthHeader = response.headers.get("content-length");
  const declaredLength = declaredLengthHeader === null ? null : Number(declaredLengthHeader);
  if (declaredLength !== null && (!Number.isFinite(declaredLength) || declaredLength < 0 || declaredLength > maximumBytes)) {
    throw new ProviderError(502);
  }

  const reader = response.body?.getReader?.();
  if (!reader) {
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length > maximumBytes) throw new ProviderError(502);
    return parseJSONBytes(bytes);
  }
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maximumBytes) {
      await reader.cancel();
      throw new ProviderError(502);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return parseJSONBytes(bytes);
}

function parseJSONBytes(bytes) {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new ProviderError(502);
  }
}

function normalizeFlight(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const origin = normalizeAirport(value.origin);
  const destination = normalizeAirport(value.destination);
  const scheduledDeparture = safeTimestamp(value.scheduled_out || value.scheduled_off);
  const providerRecordID = boundedText(value.fa_flight_id, 100) || null;
  const stableFallbackID = [
    "flightaware",
    boundedText(value.ident_iata || value.ident, 20) || "unknown",
    scheduledDeparture || "unknown-time",
    origin.iata,
    destination.iata
  ].join("-");
  return {
    id: providerRecordID || stableFallbackID,
    flightNumber: boundedText(value.ident_iata || value.ident, 20) || "Unknown",
    airlineCode: boundedText(value.operator_iata || value.operator, 20) || null,
    airlineName: boundedText(value.operator, 100) || null,
    origin,
    destination,
    status: normalizeStatus(value),
    scheduledDeparture,
    estimatedDeparture: safeTimestamp(value.estimated_out || value.estimated_off),
    actualDeparture: safeTimestamp(value.actual_out || value.actual_off),
    scheduledArrival: safeTimestamp(value.scheduled_in || value.scheduled_on),
    estimatedArrival: safeTimestamp(value.estimated_in || value.estimated_on),
    actualArrival: safeTimestamp(value.actual_in || value.actual_on),
    departureTerminal: boundedText(value.terminal_origin, 20) || null,
    arrivalTerminal: boundedText(value.terminal_destination, 20) || null,
    gate: boundedText(value.gate_origin, 20) || null,
    arrivalGate: boundedText(value.gate_destination, 20) || null,
    previousGate: null,
    boardingStatus: null,
    boardingGroup: null,
    delayMinutes: calculateDelay(value.scheduled_out, value.estimated_out),
    aircraftType: boundedText(value.aircraft_type, 50) || null,
    baggageClaim: boundedText(value.baggage_claim, 30) || null,
    providerUpdatedAt: safeTimestamp(value.updated),
    providerRecordID
  };
}

function normalizeAmadeusFlight(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const designator = value.flightDesignator || {};
  const carrierCode = boundedText(designator.carrierCode, 3);
  const flightNumberPart = boundedText(designator.flightNumber, 5);
  if (!carrierCode || !flightNumberPart) return null;
  const operationalSuffix = boundedText(designator.operationalSuffix, 1);
  const flightNumber = `${carrierCode}${flightNumberPart}${operationalSuffix}`;
  const points = Array.isArray(value.flightPoints) ? value.flightPoints : [];
  const departurePoint = points.find(point => point?.departure) || points[0];
  const arrivalPoint = [...points].reverse().find(point => point?.arrival) || points.at(-1);
  if (!departurePoint || !arrivalPoint) return null;

  const scheduledDeparture = amadeusTiming(departurePoint.departure, "STD");
  const scheduledArrival = amadeusTiming(arrivalPoint.arrival, "STA");
  const originCode = boundedText(departurePoint.iataCode, 4) || "---";
  const destinationCode = boundedText(arrivalPoint.iataCode, 4) || "---";
  const providerRecordID = [
    "amadeus",
    flightNumber,
    boundedText(value.scheduledDepartureDate, 10) || "unknown-date",
    originCode,
    destinationCode
  ].join("-");
  const actualDeparture = amadeusTiming(departurePoint.departure, "ATD");
  const actualArrival = amadeusTiming(arrivalPoint.arrival, "ATA");
  const estimatedDeparture = amadeusTiming(departurePoint.departure, "ETD");
  const estimatedArrival = amadeusTiming(arrivalPoint.arrival, "ETA");
  return {
    id: providerRecordID,
    flightNumber,
    airlineCode: carrierCode,
    airlineName: null,
    origin: { iata: originCode, icao: null, name: originCode, city: null, timeZone: null },
    destination: { iata: destinationCode, icao: null, name: destinationCode, city: null, timeZone: null },
    status: actualArrival ? "arrived" : actualDeparture ? "departed" : "scheduled",
    scheduledDeparture,
    estimatedDeparture,
    actualDeparture,
    scheduledArrival,
    estimatedArrival,
    actualArrival,
    departureTerminal: amadeusLocationCode(departurePoint.departure?.terminal),
    arrivalTerminal: amadeusLocationCode(arrivalPoint.arrival?.terminal),
    gate: amadeusLocationCode(departurePoint.departure?.gate),
    arrivalGate: amadeusLocationCode(arrivalPoint.arrival?.gate),
    previousGate: null,
    boardingStatus: null,
    boardingGroup: null,
    delayMinutes: calculateDelay(scheduledDeparture, estimatedDeparture || actualDeparture),
    aircraftType: boundedText(value.legs?.[0]?.aircraftEquipment?.aircraftType, 50) || null,
    baggageClaim: null,
    providerUpdatedAt: safeTimestamp(value.lastUpdate || value.updatedAt),
    providerRecordID
  };
}

function amadeusTiming(event, qualifier) {
  const timings = Array.isArray(event?.timings) ? event.timings : [];
  const timing = timings.find(candidate => candidate?.qualifier === qualifier);
  return safeTimestamp(timing?.value);
}

function amadeusLocationCode(value) {
  if (typeof value === "string") return boundedText(value, 20) || null;
  return boundedText(value?.code || value?.name, 20) || null;
}

function normalizeAirport(value) {
  if (!value) return { iata: "---", icao: null, name: "Unknown airport", city: null, timeZone: null };
  return {
    iata: boundedText(value.code_iata || value.code, 4) || "---",
    icao: boundedText(value.code_icao, 4) || null,
    name: boundedText(value.name, 150) || "Unknown airport",
    city: boundedText(value.city, 100) || null,
    timeZone: boundedText(value.timezone, 100) || null
  };
}

function normalizeHotel(record, offerRecord) {
  const hotelID = boundedText(record.hotelId || offerRecord?.hotel?.hotelId, 30);
  if (!hotelID) return null;
  const hotel = offerRecord?.hotel || {};
  const offers = Array.isArray(offerRecord?.offers) ? offerRecord.offers.slice(0, 10).map(normalizeHotelOffer) : [];
  return {
    id: hotelID,
    name: boundedText(record.name || hotel.name, 150) || "Hotel",
    coordinates: normalizeCoordinates(record.geoCode || hotel.latitude ? { latitude: hotel.latitude, longitude: hotel.longitude, ...record.geoCode } : null),
    distance: normalizeDistance(record.distance),
    address: normalizeAddress(record.address || hotel.address),
    availabilityKnown: Boolean(offerRecord),
    offers,
    dayRoomVerified: false,
    bookingURL: null,
    bookingMode: "externalProvider",
    providerRecordID: hotelID
  };
}

function normalizeHotelOffer(offer) {
  return {
    id: boundedText(offer.id, 100) || null,
    checkInDate: isISODate(offer.checkInDate) ? offer.checkInDate : null,
    checkOutDate: isISODate(offer.checkOutDate) ? offer.checkOutDate : null,
    roomDescription: boundedText(offer.room?.description?.text, 300) || null,
    currency: boundedText(offer.price?.currency, 3) || null,
    total: finiteNumber(offer.price?.total),
    cancellationDescription: boundedText(offer.policies?.cancellations?.[0]?.description?.text, 300) || null,
    dayRoomVerified: false
  };
}

function normalizeActivity(record) {
  const id = boundedText(record.id, 100);
  if (!id) return null;
  return {
    id,
    name: boundedText(record.name, 150) || "Activity",
    shortDescription: boundedText(record.shortDescription || record.description, 500) || null,
    coordinates: normalizeCoordinates(record.geoCode),
    price: { amount: finiteNumber(record.price?.amount), currency: boundedText(record.price?.currencyCode, 3) || null },
    rating: finiteNumber(record.rating),
    bookingURL: safeExternalURL(record.bookingLink),
    pictures: (Array.isArray(record.pictures) ? record.pictures : []).slice(0, 5).map(safeExternalURL).filter(Boolean),
    providerRecordID: id
  };
}

function normalizeCoordinates(value) {
  if (!value) return null;
  const latitude = finiteNumber(value.latitude);
  const longitude = finiteNumber(value.longitude);
  if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return { latitude, longitude };
}

function normalizeDistance(value) {
  const distance = finiteNumber(value?.value);
  if (distance === null) return null;
  return { value: distance, unit: boundedText(value?.unit, 10) || null };
}

function normalizeAddress(value) {
  if (!value) return null;
  return {
    lines: (Array.isArray(value.lines) ? value.lines : []).slice(0, 4).map(line => boundedText(line, 150)).filter(Boolean),
    cityName: boundedText(value.cityName, 100) || null,
    postalCode: boundedText(value.postalCode, 30) || null,
    countryCode: boundedText(value.countryCode, 3) || null
  };
}

function normalizeStatus(value) {
  if (value.cancelled) return "cancelled";
  if (value.diverted) return "diverted";
  const status = String(value.status || "").toLowerCase();
  if (status.includes("arrived")) return "arrived";
  if (status.includes("en route") || status.includes("airborne")) return "enRoute";
  if (status.includes("boarding")) return "boarding";
  if (status.includes("delay")) return "delayed";
  return "scheduled";
}

function calculateDelay(scheduled, estimated) {
  if (!safeTimestamp(scheduled) || !safeTimestamp(estimated)) return null;
  return Math.round((Date.parse(estimated) - Date.parse(scheduled)) / 60_000);
}

function parseGeographicQuery(url) {
  const latitude = finiteNumber(url.searchParams.get("latitude"));
  const longitude = finiteNumber(url.searchParams.get("longitude"));
  const radiusKm = finiteNumber(url.searchParams.get("radiusKm") || "5");
  if (latitude === null || longitude === null || radiusKm === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || radiusKm <= 0 || radiusKm > 50) {
    return { error: "invalid_geographic_query" };
  }
  return { latitude, longitude, radiusKm };
}

function sourceMetadata({
  provider,
  dataMode,
  ttlSeconds,
  policy,
  recordID = null,
  observedAt = null,
  receivedAt: suppliedReceivedAt = null,
  expiresAt = null,
  evidenceKind = null,
  providerChain = null
}) {
  const receivedAt = safeTimestamp(suppliedReceivedAt) || new Date().toISOString();
  const derivedExpiry = ttlSeconds > 0 ? new Date(Date.parse(receivedAt) + ttlSeconds * 1_000).toISOString() : receivedAt;
  return {
    provider,
    dataMode,
    recordID,
    observedAt: safeTimestamp(observedAt) || receivedAt,
    receivedAt,
    expiresAt: expiresAt || derivedExpiry,
    evidenceKind,
    providerChain: Array.isArray(providerChain) ? providerChain : [provider],
    cacheTTLSeconds: ttlSeconds,
    cacheStatus: "origin",
    providerPolicy: policy || null,
    providerPolicyVersion: PROVIDER_POLICY_VERSION,
    trainingAllowed: policy ? PROVIDER_POLICIES[policy]?.trainingAllowed === true : false,
    trainingPurposes: policy ? PROVIDER_POLICIES[policy]?.trainingPurposes || [] : []
  };
}

function capabilityJSON(body, sourceOptions) {
  const source = sourceMetadata(sourceOptions);
  const ttl = Math.max(0, Number(sourceOptions.ttlSeconds) || 0);
  const cacheControl = sourceOptions.policy === "hndOfficialRegistry"
    ? `public, max-age=${ttl}, stale-while-revalidate=${ttl}`
    : `private, max-age=${ttl}, must-revalidate`;
  return json({ ...body, source }, 200, { "cache-control": cacheControl, "x-data-mode": source.dataMode });
}

function amadeusSource(env, policy, ttlSeconds) {
  return {
    provider: "Amadeus Self-Service APIs",
    dataMode: amadeusEnvironment(env) === "production" ? "live" : "testCached",
    ttlSeconds,
    policy
  };
}

function requireFlightAware(env) {
  return flightAwareKey(env) ? null : notConfigured("flightStatus", "FlightAware AeroAPI");
}

function requireAmadeus(env, capability) {
  return env.AMADEUS_CLIENT_ID && env.AMADEUS_CLIENT_SECRET ? null : notConfigured(capability, "Amadeus Self-Service APIs");
}

function notConfigured(capability, provider, extra = {}) {
  return json({ error: "provider_not_configured", capability, provider, configured: false, ...extra }, 503);
}

function flightAwareKey(env) {
  return env.FLIGHTAWARE_AEROAPI_KEY || null;
}

function amadeusEnvironment(env) {
  return String(env.AMADEUS_ENVIRONMENT || "test").toLowerCase() === "production" ? "production" : "test";
}

function amadeusBaseURL(env) {
  return amadeusEnvironment(env) === "production" ? PROVIDERS.amadeusProductionBaseURL : PROVIDERS.amadeusTestBaseURL;
}

function normalizedCountryCode(value, optional = false) {
  if (!value && optional) return null;
  const normalized = String(value || "").trim().toUpperCase();
  return /^[A-Z]{2,3}$/.test(normalized) ? normalized : false;
}

function optionalInteger(value, minimum, maximum, fallback) {
  if (value === null || value === undefined || value === "") return fallback;
  if (!/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return parsed >= minimum && parsed <= maximum ? parsed : null;
}

function parseBoolean(value, fallback) {
  if (value === null || value === undefined || value === "") return fallback;
  if (value === "true") return true;
  if (value === "false") return false;
  return null;
}

function isISODate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function safeTimestamp(value) {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function safeExternalURL(value) {
  if (!value) return null;
  try {
    const parsed = new URL(String(value));
    return parsed.protocol === "https:" && !parsed.username && !parsed.password ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function boundedText(value, maximumLength) {
  return String(value || "").trim().slice(0, maximumLength);
}

function averageBlockConfidence(annotation) {
  const blocks = (annotation?.pages || []).flatMap(page => page.blocks || []);
  const values = blocks.map(block => Number(block.confidence)).filter(Number.isFinite);
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      ...extraHeaders
    }
  });
}

class ProviderError extends Error {
  constructor(status, retryAfter = null, upstreamStatus = null) {
    super("provider_error");
    this.status = status;
    this.retryAfter = retryAfter;
    this.upstreamStatus = upstreamStatus;
  }
}

class ReminderRequestError extends Error {
  constructor(status, code) {
    super("reminder_request_error");
    this.status = status;
    this.code = code;
  }
}

class GoogleAuthorizationError extends Error {
  constructor() {
    super("google_authorization_error");
  }
}

class GoogleTaskListScanError extends Error {
  constructor() {
    super("google_task_list_scan_error");
  }
}

class AuthenticationError extends Error {
  constructor() {
    super("authentication_error");
  }
}

// Native node:test uses this to isolate OAuth cache cases. It is not reachable over HTTP.
export function resetProviderStateForTesting() {
  amadeusTokenCache = null;
  accessKeyCache.clear();
}

export const backendTesting = Object.freeze({
  accessIssuer,
  calculateDelay,
  executeProviderFallback,
  isISODate,
  normalizeFlight,
  normalizeAmadeusFlight,
  normalizeHotel,
  normalizeActivity,
  normalizeGoogleTasksSyncPayload,
  googleTaskResource,
  parseGoogleTasksMarker,
  parseFlightDesignator,
  parseGeographicQuery,
  providerFetch,
  safeExternalURL,
  verifyCloudflareAccessAssertion
});
