# Airport XR Companion security review

Date: 2026-07-14  
Scope: iOS client, local persistence/learning, normalized Cloudflare Worker, configuration, and deterministic tests. This is a code review of the research prototype, not a penetration test or deployment certification.

## Executive summary

The prototype has a sound default-deny boundary: provider credentials stay in Worker secrets; production cannot select unauthenticated mode; Cloudflare Access JWTs are verified cryptographically; request/response sizes and URLs are bounded; errors and logs exclude payloads; rate limiting fails closed when required; local travel/model files use iOS data protection; and entry rules cannot train the model or weaken safety.

The most important release blocker is integration rather than a bypass: the production Worker correctly requires Cloudflare Access, but the iOS client does not yet acquire an Access session/assertion. A production live client therefore receives `401`. Device/app attestation and provider-specific spend controls also remain incomplete. Demo/offline simulator use is unaffected.

## Findings

### AXR-SEC-001 - High - Protected live client cannot authenticate

**Evidence:** Production defaults to Cloudflare Access and fails closed in [Backend/src/index.js](../Backend/src/index.js) lines 228-264. The required native Access session is explicitly absent in [Backend/README.md](../Backend/README.md) lines 25-34. The iOS proxy request sets only `Accept` and no Access assertion/session in `AirportXRCompanion/Aviation/Providers/ProxyFlightDataProvider.swift` lines 53-61.

**Impact:** A correctly protected deployment is unavailable to the current iOS live mode. Disabling authentication to make it work would expose billable/provider-backed routes.

**Recommendation:** Before any production live launch, implement an approved native Cloudflare Access login/session flow, securely manage the session, attach the assertion/cookie, handle expiry/revocation, and add end-to-end tests that prove both authorization and denial. Keep `REQUEST_AUTH_MODE=cloudflare-access` and the production fail-closed check.

### AXR-SEC-002 - Medium - No app/device attestation or per-install binding

**Evidence:** Cloudflare Access validates issuer, audience, signature, temporal claims, and subject in `Backend/src/index.js` lines 240-264 and 288 onward. [Backend/README.md](../Backend/README.md) lines 34 and 85-90 accurately state that Apple App Attest/device attestation is not implemented.

**Impact:** A valid user session authenticates the principal but does not prove that requests originate from an untampered Airport XR Companion installation. Stolen/replayed session material could consume provider quota within its validity window.

**Recommendation:** Add App Attest (or an equivalent deployment-approved device proof), server-issued one-time challenges, replay prevention, and a binding between the authenticated principal and app assertion. Treat this as defense in depth after AXR-SEC-001, not as a substitute for user/service authorization.

### AXR-SEC-003 - Medium - Rate limit is not a billing/provider quota controller

**Evidence:** The Worker hashes the principal and applies a route bucket in `Backend/src/index.js` lines 371-397. `Backend/wrangler.toml` configures 60 requests per 60 seconds with an explicit rationale. [Backend/README.md](../Backend/README.md) lines 36-40 and 85-90 state that the binding is coarse and there is no durable circuit breaker/cross-request provider-health store.

**Impact:** Abuse bursts are bounded, but a permitted client population can still exhaust a smaller upstream quota or generate unexpected cost. Fallback can amplify use during provider degradation if it is not budget-aware.

**Recommendation:** Derive per-provider budgets from purchased quotas, add durable counters/circuit breakers, cap fallback attempts by endpoint/error class, alert on spend/error thresholds, and return a cached/limited state before quota exhaustion. Keep the checked-in rule as an abuse floor, not a claimed optimal value.

### AXR-SEC-004 - Low - Local protection is post-first-unlock, not locked-device-only

**Evidence:** Itinerary/profile and model files use `.completeFileProtectionUntilFirstUserAuthentication` and are excluded from backup in `AirportXRCompanion/Persistence/ItineraryCache.swift` lines 82-91 and `AirportXRCompanion/Services/OnDevicePredictionService.swift` lines 246-252.

**Impact:** After the first device unlock following boot, files remain accessible to the app while the device is locked. The stored fields are intentionally minimal but can still reveal travel plans, nationality/residence preferences, or inferred routines.

**Recommendation:** Confirm the required background/offline behavior. If locked-device access is unnecessary, move the most sensitive profile/itinerary material to `.completeFileProtection`; consider Keychain for narrowly sensitive flags. Keep erase behavior and backup exclusion tested.

## Positive controls verified

- `/health` is public and contains no secrets; all `/v1/*` routes authenticate before quota/provider work (`Backend/src/index.js` lines 179-214).
- Production refuses `REQUEST_AUTH_MODE=none` (`Backend/src/index.js` lines 228-238).
- Access team domain is HTTPS-only and constrained to `cloudflareaccess.com` (`Backend/src/index.js` lines 275-285).
- Rate-limiter absence/failure returns safe `503`; rejection returns `429` (`Backend/src/index.js` lines 371-389).
- Surfaced/provider URLs require HTTPS and reject embedded credentials (`Backend/src/index.js` lines 1175-1182).
- Upstream bodies, credentials, query/profile details, and provider payloads are not logged (`Backend/src/index.js` lines 215-223).
- Sensitive passport/document fields are rejected at the entry route and no passport number/scan field exists in the traveler model.
- Provider training requires matching local/source policy and exact purpose; commercial policies are deny-by-default; entry/visa has no training purpose.
- Local model persistence stores aggregate statistics and one-way observation IDs, not raw provider payloads.
- Worker tests cover JWT acceptance/denial, production fail-closed behavior, rate limiting, sensitive entry fields, 429, fallback, malformed/oversized responses, timeouts, redaction, HTTPS, and provider policy.

## Verification observed

```text
cd Backend && npm test
20 tests, 20 pass, 0 fail

cd Backend && npm run check
node --check src/index.js: passed

npx --yes wrangler@4.36.0 deploy --dry-run --outdir /tmp/airportxr-worker-dry-run
passed; bindings and variables recognized
```

No real credentials, live provider payloads, or production Cloudflare Access session were used. Deployment-specific licensing, privacy notices, regional processing, incident response, and credential rotation still require operator review.
