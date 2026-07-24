# Airport XR Companion provider proxy

This Cloudflare Worker keeps provider credentials out of the iOS application, validates requests, enforces a configurable quota, and normalizes provider responses. It never returns or logs upstream payloads on failure.

## Routes

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/health` | Public liveness and provider-configuration booleans |
| `GET` | `/v1/provider-policies` | Versioned cache/training policy metadata |
| `GET` | `/v1/flights/search` | Flight-number/date search; FlightAware with Amadeus fallback |
| `GET` | `/v1/flights/:id` | FlightAware status by provider record ID |
| `GET` | `/v1/airports/:iata/departures` | FlightAware departure board |
| `GET` | `/v1/airports/:iata/arrivals` | FlightAware arrival board |
| `GET` | `/v1/hotels/search` | Amadeus nearby hotel discovery and optional availability |
| `GET` | `/v1/activities` | Amadeus nearby activities |
| `GET` | `/v1/facilities/airports/:iata` | Versioned official/operator facility registry |
| `POST` | `/v1/entry-requirements` | Sherpa v3 trip guidance, Timatic adapter fallback, then official-link discovery |
| `POST` | `/v1/scene-ocr` | Explicit-consent JPEG still sent to Google Cloud Vision |
| `POST` | `/v1/reminders/google-tasks/sync` | Idempotent Google Tasks upsert/delete using the person's short-lived OAuth token |
| `POST` | `/v1/ai/explain` | Optional grounded ordering of already-sourced calculation/facility facts |

All `/v1/*` routes are protected. `/health` is intentionally public and contains no credentials.

## Authentication

The production configuration uses `REQUEST_AUTH_MODE = "cloudflare-access"`. The Worker cryptographically verifies the `Cf-Access-Jwt-Assertion` RS256 signature against the configured Cloudflare Access JWKS, then checks issuer, audience, expiry, not-before time, and subject. This does not require a shared API secret in the iOS bundle.

Before deployment:

1. Create a Cloudflare Access application and policy for the Worker route.
2. Replace `CF_ACCESS_TEAM_DOMAIN` and `CF_ACCESS_AUD` in `wrangler.toml` with that application’s non-secret values.
3. Ensure the iOS client obtains an Access session or assertion through an approved sign-in flow.
4. Keep `REQUEST_AUTH_MODE = "cloudflare-access"` in production.

`REQUEST_AUTH_MODE = "none"` exists only for local development and deterministic tests; the Worker refuses that mode when `DEPLOYMENT_ENVIRONMENT = "production"`. The current iOS prototype does not yet implement Cloudflare Access login/session acquisition or Apple App Attest. Therefore a protected live deployment will correctly return `401` until that client integration is completed. The Worker does not claim App Attest, device attestation, or anonymous per-install authentication.

## Rate limiting

`wrangler.toml` defines the `API_RATE_LIMITER` binding and sets `REQUIRE_RATE_LIMITER = "true"`. The Worker hashes the authenticated Access subject before combining it with a route category, so the binding key does not expose the subject. The checked-in 60-request/60-second rule is an abuse guardrail, not a statement about any provider’s quota. Tune it to the lowest purchased upstream quota and expected client refresh pattern.

If a required binding is missing or unavailable, the Worker fails closed with `503`. A rejected request returns `429` and `Retry-After: 60`. An upstream `429` and its bounded `Retry-After` value propagate to the client and do not trigger provider fallback.

## Secrets and non-secret configuration

Set only the providers you use:

```bash
cd Backend
npx wrangler secret put FLIGHTAWARE_AEROAPI_KEY
npx wrangler secret put AMADEUS_CLIENT_ID
npx wrangler secret put AMADEUS_CLIENT_SECRET
npx wrangler secret put SHERPA_API_KEY
npx wrangler secret put TIMATIC_API_URL
npx wrangler secret put TIMATIC_API_KEY
npx wrangler secret put TIMATIC_SERVICE_TOKEN
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put GOOGLE_VISION_API_KEY
```

- `FLIGHTAWARE_AEROAPI_KEY` enables flight status, boards, and the preferred flight search.
- `AMADEUS_CLIENT_ID` and `AMADEUS_CLIENT_SECRET` enable hotels, activities, and the flight-search fallback.
- `SHERPA_API_KEY` enables the primary structured entry adapter through Sherpa's current `/v3/trips` POST endpoint.
- `TIMATIC_API_URL` and `TIMATIC_API_KEY` enable an independent IATA Timatic fallback. IATA publishes that AutoCheck is an API but supplies implementation details during customer onboarding, so `TIMATIC_API_URL` must point to the deployment's reviewed adapter for the documented `airportxr-entry-query-v1` normalized contract. Set `TIMATIC_SERVICE_TOKEN` only when that contract requires it.
- `GEMINI_API_KEY` optionally enables Gemini Google Search grounding after both structured providers are unavailable. The Worker discards model prose, accepts citation URLs only from a destination-specific official-government allowlist, and always returns `discoveryOnly`; this path can never authorize entry or a landside/city plan. Google currently marks Search grounding unavailable on the API free tier, even though paid projects include a limited monthly allowance, so it is not treated as a guaranteed free dependency.
- `GOOGLE_VISION_API_KEY` is optional and enables consented cloud OCR.
- The optional AI explainer uses the configured Cloudflare Workers AI `AI` binding. It needs no app API key and accepts no traveler-profile or entry-requirement fields.
- `AMADEUS_ENVIRONMENT` is a non-secret `test`/`production` variable. Amadeus test flight-status data can be cached test data rather than live operations.
- `GOOGLE_PLACES_API_KEY` and `TRANSITLAND_API_KEY` are reserved names for optional future adapters. The current Worker does not read them, so do not provision them until those routes and their provider-policy tests exist.

Never put secrets in `wrangler.toml` or commit `Backend/.dev.vars`. `AEROAPI_KEY` is not used; the canonical name is `FLIGHTAWARE_AEROAPI_KEY`.

### Google Tasks authorization

Google Tasks is user data, so an API key or Worker secret cannot authorize this route. The iOS app must use Google's installed-app OAuth flow (prefer the current Google Sign-In iOS SDK with PKCE) and request only `https://www.googleapis.com/auth/tasks` after the person explicitly opts in. The app passes a short-lived access token in the standard `Authorization: Bearer …` header and an explicit versioned consent header. The Worker forwards that access token in memory; it never accepts a refresh token, stores the token, returns it, or puts it in a request body or log. Refresh credentials belong in Google Sign-In/Keychain storage on the device.

The Worker performs a complete bounded scan for its stable marker before mutating the task list. That makes replay an update rather than a duplicate and confines deletion to the same Airport XR itinerary scope. If the scan exceeds the named limit, the route returns `409` before any write; using a dedicated Airport XR task list avoids that edge case.

Google Tasks retains only the due date and ignores a task's time. Airport XR therefore stores the exact derived action time and airport time zone in task notes without inventing a replacement alert time. Google controls notification timing and cross-device delivery. For precise time-based alerts, the EventKit Apple Calendar adapter is the primary path.

## Local verification

```bash
cd Backend
npm install
npm test
npm run check
npx wrangler dev --var REQUEST_AUTH_MODE:none --var REQUIRE_RATE_LIMITER:false
```

Tests use Node’s built-in test runner and mocked upstream responses; they make no live provider calls and contain no real credentials.

Workers AI is the exception during an actual `wrangler dev` session: Cloudflare documents that its binding reaches the account even from local development and consumes account usage. The automated tests replace the binding with an in-memory mock.

## Data and failure behavior

- Outbound provider and surfaced booking/verification URLs must use HTTPS. URLs with embedded credentials are rejected.
- Provider JSON must have the expected content type, stay within byte limits, and have the expected record shape.
- Provider calls time out after the named limit in `src/index.js`; timeout, malformed, oversized, and unexpected failures become bounded JSON errors.
- The optional OCR route accepts one consent-marked JPEG still up to 512 KB. It does not accept video or queue failed images.
- The optional AI route cannot generate operational facts. The model only orders validated fact IDs; Worker code renders all values and provenance, preserves every input fact, rejects entry/visa domains, and falls back to the original order when model output is malformed. See [`Documentation/AIIntegrations.md`](../Documentation/AIIntegrations.md).
- Flight search can fall back from transient FlightAware failure to Amadeus. It never falls back after an upstream `429`, and boards/status-by-ID remain FlightAware-only because their provider identifiers/contracts are not interchangeable.
- Provider policy metadata is versioned. All currently configured commercial policies deny model training; changing a response alone cannot authorize iOS learning.
- Entry responses are keyed locally by a one-way fingerprint of the complete normalized traveler/itinerary query. An unexpired structured result may support a recommendation only after explicit official confirmation; an expired cache record remains displayable with its original provider, record ID, observation/receipt/expiry times, and provider chain, but cannot authorize a landside or city plan.
- Sherpa recommends no more than one hour of caching for `/trips`; the Worker caps structured entry expiry at that interval even if an upstream response requests longer storage. Malformed or explicitly stale Sherpa data falls through to the independently configured Timatic adapter. Search/AI output is never converted into a visa rule.

Current provider references: [Sherpa Requirements API](https://docs.joinsherpa.io/requirements-api/index.html), [Sherpa Trips](https://docs.joinsherpa.io/requirements-api/endpoints/trips.html), [IATA Timatic AutoCheck](https://www.iata.org/en/services/compliance/timatic/autocheck/), and [Gemini Grounding with Google Search](https://ai.google.dev/gemini-api/docs/google-search).

## Remaining production limitations

- Apple App Attest and a native Cloudflare Access sign-in/session flow are not implemented.
- The rate-limit binding is a coarse abuse control, not provider-specific quota accounting or a billing budget.
- There is no durable circuit breaker, cross-request fallback cache, or multi-region provider health store.
- Live provider contract tests are credential-gated and must remain separate from deterministic CI.
- Google Tasks requires an iOS OAuth consent integration before it can be enabled in the UI; the Worker route intentionally has no API-key fallback.
- Provider licensing, regional processing, retention, and end-user privacy disclosures still require deployment-specific legal review.
