# Live data and freshness plan

## Normalized boundaries

The app depends on provider-neutral interfaces for flights, entry requirements, airport facilities, nearby places, accommodation, queues, weather, and inter-airport transfer. The iOS app calls native frameworks directly where appropriate and calls a Cloudflare Worker for secret-bearing commercial providers.

The Worker exposes normalized routes for flight search/boards/status, hotels, activities, facilities, entry requirements, provider policies, and optional OCR. Every result carries provider identity, source/receipt/expiry time, data mode, stable record ID where permitted, and provider-policy metadata.

## Key placement

Provider values are Worker secrets only: `AMADEUS_CLIENT_ID`, `AMADEUS_CLIENT_SECRET`, optional `FLIGHTAWARE_AEROAPI_KEY`, `SHERPA_API_KEY`, `TIMATIC_API_URL`, `TIMATIC_API_KEY`, `TIMATIC_SERVICE_TOKEN`, `GEMINI_API_KEY`, `GOOGLE_PLACES_API_KEY`, `TRANSITLAND_API_KEY`, and `GOOGLE_VISION_API_KEY`. The app receives only an HTTPS proxy URL through ignored `Config/Secrets.xcconfig`. MapKit has no app API key; native WeatherKit uses the application entitlement.

## Dynamic freshness

Source timestamps and provider policy control expiry. The UI does not apply one universal age:

- flight status follows the purchased license and source timestamp;
- GTFS static persists by feed version;
- GTFS-Realtime and WeatherKit expire from source metadata;
- hotel price/availability is short-lived and revalidated;
- facility registry persists by registry version while variable hours/availability require confirmation;
- entry results use a protected one-way fingerprint of the exact normalized query; stale records keep provenance for display but cannot authorize a city visit;
- Google Places remains ephemeral except where its terms permit storage.

HTTP `Retry-After` is authoritative when present. Provider authentication/rate-limit failures do not trigger a fallback storm. Live, cached, stale, demo, unavailable, and unknown states remain distinct.

## Failure behavior

- Network loss: use policy-permitted cache and offline registries; retain age and suppress live claims.
- Authentication failure: stop automatic retries and show configuration/support state.
- Rate limit: honor retry metadata and retain the last permitted snapshot.
- Not found: show no matching record, not a generic outage.
- Timeout/5xx: bounded fallback to another authorized provider or cache.
- Malformed/oversized/non-JSON response: reject it, keep the last valid snapshot, and log only a redacted diagnostic.
- Partial response: preserve supplied fields and keep missing values unknown.
- Expired critical field: it may be displayed as stale context but cannot satisfy a positive layover decision.

## Provider fallback

Fallback is explicit by endpoint and error class. A demo provider is a development experience, not a live fallback masquerading as current data. FlightAware/Amadeus adapter ordering does not bypass an upstream 429. Entry uses Sherpa's current v3 trip endpoint, then an independently contracted Timatic adapter on malformed, stale, timeout, or compatible upstream failure. If both are unavailable, Gemini Google Search may discover links only from a deployment-controlled official-government domain allowlist. Search/AI prose is discarded, the result is marked `discoveryOnly`, and it can never promise admission or unlock landside/city feasibility.

## License-aware learning

Live data may train the on-device model when the exact provider contract permits the exact purpose. Both the local versioned policy catalog and normalized source metadata must grant that purpose. Eligible observations must be live, non-demo, resolved, and stable-ID-bearing. Duplicate refreshes are ignored through a deterministic one-way identifier. Only aggregate residuals persist.

The shipped commercial policies remain deny until the deployment operator records actual permission. User-owned measurements and feedback remain independently eligible. Entry/visa data cannot be a training target, and learned state cannot weaken deterministic safety.

## Live contract tests

Credential-gated contract tests are opt-in and never gate CI. They verify schema, policy metadata, timestamps, status handling, fallback, and redaction without logging private payloads. A local demo run is not evidence that live credentials are configured.
