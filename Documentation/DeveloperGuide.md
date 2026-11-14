# AirBorder developer guide

Entry points and verification references updated November 8, 2026. The detailed native algorithm discussion and research roadmap are not production certification. See the [current verification snapshot](Verification-2026-11-08.md).

AirBorder includes a native SwiftUI research application for long-haul international connections, same-region airport changes, and conservative layover decision support. This document describes the current source, not a promised production service. No credential-backed live-provider run, physical-device AR result, cross-device reminder delivery, or airline capacity result is implied.

## Product invariants

1. Unknown inputs remain unknown. Never map a missing queue, gate close, border step, return service, accessibility fact, or transfer duration to zero.
2. Every operational number retains source, provider field, record ID, observation/receipt/expiry times, uncertainty, and derivation where applicable.
3. A stale or discovery-only entry result cannot authorize a landside or city recommendation.
4. Entry and visa rules are never learned into a native model.
5. Personalization may rank equally safe plans but cannot weaken the safety floor.
6. Demo and stochastic fixtures are never presented as live.
7. A transfer is called fastest only when a current live route record satisfies the domain gate.
8. AI can explain already-sourced facts; it cannot create facts, change feasibility, or decide entry eligibility.
9. Provider credentials stay in Worker secrets. The app receives only HTTPS service URLs and user-scoped OAuth tokens through their approved flows.
10. Booking and payment remain external.

## Repository map

| Area | Primary source |
|---|---|
| SwiftUI app shell and dependency composition | [`AirBorder/App`](../AirBorder/App) |
| Itinerary, entry, place, provenance, and recommendation domain | [`AirBorder/Models/LongHaul`](../AirBorder/Models/LongHaul) |
| Long-haul decision and reference providers | [`AirBorder/Services/LongHaul`](../AirBorder/Services/LongHaul) |
| Flight provider/repository/cache stack | [`AirBorder/Aviation`](../AirBorder/Aviation) |
| Terminal routing and AR | [`AirBorder/Routing`](../AirBorder/Routing), [`AirBorder/AR`](../AirBorder/AR) |
| On-device personalization | [`OnDevicePredictionService.swift`](../AirBorder/Services/OnDevicePredictionService.swift) |
| Cross-device reminder foundation | [`AirBorder/Reminders`](../AirBorder/Reminders) |
| Cloudflare Worker | [`Backend/src`](../Backend/src) |
| Deterministic unit and UI tests | [`AirportXRCompanionTests`](../AirportXRCompanionTests), [`AirportXRCompanionUITests`](../AirportXRCompanionUITests) |
| XcodeGen source of truth | [`project.yml`](../project.yml) |
| Deterministic report exporter | [`Scripts/reporting/export_report_pdf.py`](../Scripts/reporting/export_report_pdf.py) |

Do not hand-maintain generated project-file membership. Change `project.yml` when target configuration changes and run `./Scripts/generate.sh`.

## Browser and journey backend

`Web/` contains the original iPhone 13 browser interface, deterministic plan engine and synthetic driver. `Web/backend/index.mjs` exposes bounded public directory/timing routes and forwards protected routes to the canonical Worker. `Backend/src/journey-store.js` implements account/trip/leg-scoped durable progress; `Web/journey-sync.js` handles the client outbox, replay, conflicts, ownership changes and logout. See [Journey Integration](../Web/docs/journey-backend-integration.md) for activation and unresolved production boundaries.

Native and browser feature coverage differ. Keep their launch modes, authentication, persistence and verification claims separate. The [repository README](../README.md) provides current install and test commands for both.

## Architecture

```text
SwiftUI six-tab shell
  -> AppContainer
     -> LongHaulExperienceViewModel
        -> ItineraryCache / EntryRequirementCache
        -> provider-neutral flight, entry, facility, place,
           accommodation, queue, weather, and transfer boundaries
        -> MonteCarloLayoverRecommendationEngine + SafetyPolicy
        -> MetroAirportDatabase + InterAirportTransferPlanner
        -> TerminalRouter + RouteManeuverBuilder
        -> OnDevicePredictionService

iOS native adapters -> MapKit / Vision / EventKit
iOS HTTPS adapters  -> protected Cloudflare Worker
Worker               -> FlightAware / Amadeus / Sherpa / Timatic adapter /
                        Gemini official-link discovery / Google Vision /
                        Google Tasks / Workers AI
Direct feed boundary -> GTFS / GTFS-Realtime / WeatherKit
```

The six UI roots are Journey, Flights, AR Guide, Map, Layover & Transit, and Settings. `LongHaulExperienceViewModel` owns the visible itinerary, active layover, selected plan, facility records, entry state, route, and freshness. Journey leads with the safest immediate action: gate navigation for a same-airport connection, or the mandatory airport transfer for an inter-airport connection.

## Core domain and provider boundaries

### Domain types

| Type | Responsibility |
|---|---|
| `Itinerary` | Ordered flight legs, schema version, input revision, and derived adjacent layovers. |
| `ItineraryLeg` | Flight plus independently sourced on-block and gate-close metrics. |
| `LayoverContext` | Arrival airport, onward-departure airport, local time zone, absolute timing, and airport-change classification. |
| `TravelerProfile` | Nationality, residence, passport type, declared authorizations, purpose, luggage, budget, recovery, accessibility, and consent preferences. No document number or scan. |
| `EntryRequirementQuery` | Exact traveler and ordered journey facts sent to a structured provider. |
| `EntryAssessment` | Status, evidence class, source chain, expiry, and official verification links. |
| `LayoverPlace` / `AirportFacilityRecord` | Place identity, category, access zone, opening windows, restrictions, data mode, and official/operator source. |
| `SourcedMetric<Value>` | Value, unit, provider, provider field, source record, timestamps, expiry, uncertainty, and derivation. |
| `EstimateDistribution` | Lower, most-likely, and upper value; invalid or negative ranges are rejected. |
| `PlanSegment` / `PlanCandidate` | Required and optional work for a proposed layover plan. |
| `FeasibilityAssessment` / `CalculationTrace` | Classification, probability interval, latest return, policy, seed, sources, formulas, and unresolved inputs. |
| `ProviderPolicy` / `ProviderTrainingAuthorization` | Cache/licensing metadata and exact-purpose dual authorization for learning. |
| `InterAirportTransferOption` / `InterAirportTransferPlan` | Route range, transfers, walking, accessibility, last service, freshness, and Pareto-ranked result. |

### Provider protocols

- `FlightDataProvider`
- `EntryRequirementProvider`
- `AirportFacilityProvider`
- `PlaceProvider`
- `AccommodationProvider`
- `QueueTimeProvider`
- `WeatherContextProvider`, composed from `OpenMeteoWeatherContextProvider` and `AviationWeatherMETARContextProvider` for current airport conditions
- `InterAirportTransferProvider`
- `LayoverContextRepository`
- `LayoverRecommendationEngine`

Protocol conformance alone does not establish live availability. `AppContainer` uses keyless Open-Meteo and AviationWeather providers, with explicit QA and offline alternatives. The separate WeatherKit adapter requires its applicable signing capability; `QueueTimeProvider` remains a boundary without a live adapter.

## Launch modes and data truth

`AppLaunchContext` recognizes four modes:

| Mode | Composition behavior |
|---|---|
| `live` | Loads a cached itinerary if present; otherwise no itinerary. Uses the proxy flight provider only when a valid URL exists. It does not synthesize a long-haul timing candidate. |
| `demo` | Loads the named BKK-HND-LAX fixture, or HND-NRT when `--scenario interAirport` is supplied. |
| `offline` | Loads only saved itinerary/profile/entry data and marks operational state stale. It does not call providers. |
| `stochastic` | DEBUG-only named fixture whose segment ranges are jittered from an unseeded or supplied seed. Release builds downgrade a stochastic request to live. |

An identical production evidence snapshot is deterministic because the seed is derived from itinerary ID, input revision, snapshot revision, and policy version. A live launch remains naturally variable because its evidence can change. QA stochastic mode records a seed and supports exact replay.

`LIVE REQUESTED` describes launch intent, not result authority. Every result must still carry `live`, `cached`, `stale`, `demo`, or `unavailable` provenance.

### Current composition caveat

Debug configuration enables `ENABLE_DEMO_FALLBACK`. `AppContainer` can therefore include `DemoFlightDataProvider` for the Flights search/board surface when no live provider succeeds. That result is labeled development data. The long-haul view model is stricter: live/offline modes do not create the reference itinerary or named recommendation candidates.

## Safety mathematics

### Current calculation

For a candidate:

```text
available window = onward gate close - inbound on-block

required time = deplane
              + conditional border / baggage / customs
              + outbound travel
              + activity
              + return travel
              + re-entry / security
              + terminal route
              + safety components

success = required time <= available window
```

Each known duration is a triangular distribution with lower, most-likely, and upper values. The engine draws 10,000 trials, estimates the success probability, and calculates a Wilson 95% confidence interval. Missing or expired required metrics preempt simulation and return `Requires confirmation`.

The trial budget is derived, not guessed:

```text
n = ceil(z² × 0.25 / e²)
  = ceil(1.959963984540054² × 0.25 / 0.01²)
  = 9,604
```

The policy rounds upward to 10,000. `0.25` is the worst-case Bernoulli variance, and `e = 0.01` is the target maximum half-width.

### Why `0.90` and `0.70` are deterministic and hard-coded

`SafetyPolicy.current` currently classifies:

- `Safe` when the Wilson lower bound is at least `0.90`.
- `Not recommended` when the Wilson upper bound is below `0.70`.
- `Tight` for the resolved interval between those rules.
- `Requires confirmation` before all probability rules when a critical input is unresolved.

These two probability values are **provisional product risk-policy choices**, not values derived from a flight, visa, airport, or weather API. Provider APIs can supply evidence and uncertainty; they should not silently choose the application's acceptable missed-flight risk. The current thresholds came from the approved research plan and are centralized and versioned so behavior can be audited and replayed. They are not a certified aviation standard, and the repository does not contain empirical validation proving they are optimal.

Deterministic does not mean immutable forever. It means a named policy version gives the same answer to the same evidence. A future change should require:

1. a representative outcome dataset and explicit error-cost definition;
2. calibration and backtesting by scenario class;
3. human-factors and accessibility review;
4. a documented approval and migration plan;
5. a new policy version and boundary tests; and
6. trace disclosure of the selected context and threshold.

The exact boundary semantics are deliberate: `lower95 == 0.90` is Safe, while `upper95 == 0.70` remains Tight because the not-recommended check is strictly `< 0.70`.

### Should thresholds be nondeterministic?

No. A randomly changing safety threshold can make identical evidence alternate between Safe and Tight, frustrate replay, make a notification irreproducible, and conceal policy drift. It adds noise without adding knowledge.

A better evolution is a **contextual but deterministic** threshold policy:

```text
effective safe floor = max(global safety floor, reviewed context floor)
```

The context floor can be selected from a versioned table using observable facts such as same-airport airside, landside, inter-airport, cross-region surface sector, number of border/check-in transitions, overnight/last-service exposure, accessibility uncertainty, and consequence severity. It should never be selected by an unlogged random draw, and traveler preference should never lower the global floor. A learned model can improve the input distributions and their calibration; it should not autonomously relax the decision boundary.

Visa/entry permission remains a hard evidence gate, not a probability threshold. No probability score can turn `cannotDetermine`, expired, or discovery-only entry data into permission to enter.

## Advanced algorithm roadmap

The current methods favor transparency and testability. More advanced approaches can improve accuracy if their data, calibration, and traceability are strong enough.

| Technique | Use | Status and guardrail |
|---|---|---|
| Wilson interval | Monte Carlo sampling uncertainty | Implemented. It does not measure all model or real-world uncertainty. |
| Pareto frontier + lexicographic order | Keep duration, transfers, walking, levels, simplicity, and crowd trade-offs visible | Implemented for terminal and inter-airport routing. |
| Stable seeded Monte Carlo | Reproducible production snapshots and replayable QA | Implemented. |
| Running online statistics | Private local delay/walking/transit/preference residuals | Implemented; simple and data-efficient, but limited. |
| Empirical/quantile distributions with conformal calibration | Replace triangular assumptions with calibrated prediction intervals | Recommended future work; requires sufficient licensed outcomes and drift monitoring. |
| Hierarchical Bayesian delay model | Pool sparse airline/route/hour/airport evidence while preserving uncertainty | Recommended research path; never overwrite official status. |
| Correlated Monte Carlo or copula model | Represent weather/congestion causing several segment delays together | Recommended; current independent segments can underestimate tail risk. |
| Time-dependent multi-criteria shortest path | Account for departures, missed connections, service disruptions, elevators, and last service | Recommended for live regional transit. |
| Chance-constrained optimization | Choose activities subject to an explicit connection-risk constraint | Natural extension once distributions are calibrated. |
| Receding-horizon planning | Replan after gate, weather, queue, and transport updates | Recommended, with alert hysteresis to prevent UI thrash. |
| Contextual bandit | Rank equally safe recommendations from opt-in feedback | Possible, but exploration must occur only inside the safe set and remain erasable. |

Do not add sophistication merely to produce a score. Every new model needs freshness, provenance, calibration metrics, fallback behavior, versioning, disable/erase controls, and an explanation of what uncertainty it does not cover.

## Itineraries, time zones, and inter-airport transfers

`Itinerary.layovers` zips adjacent legs. It uses absolute `Date` values for duration and the inbound destination's IANA time zone for presentation. This handles overnight and date-line crossings without subtracting formatted local clock strings.

A layover records both `airport` and `onwardAirport`. When they differ, `MetroAirportDatabase.classify` returns:

- `sameAirport`;
- `sameMetroArea`; or
- `crossRegionSurfaceSector`.

The versioned registry contains 25 metro areas. Its grouping and OurAirports-seeded codes do not supply a travel time. A regional adapter must supply next usable departure, range, walking, transfers, accessibility, disruption, and last-service evidence.

`InterAirportTransferPlanner`:

1. removes wrong-direction, expired-last-service, and accessibility-ineligible options;
2. rejects stale, unavailable, expired, or invalid duration inputs;
3. computes a Pareto frontier over most-likely duration, transfers, and walking;
4. orders by duration, transfers, walking, and stable provider ID; and
5. permits `canClaimFastest` only for a selected `live` option with no unresolved input.

For HND-NRT, the fixture provider supplies research ranges only. `live` and `offline` composition uses `UnavailableInterAirportTransferProvider` until a current/cached adapter is implemented. Optional activities are appended after border/baggage and the mandatory transfer, never before it.

The onward-airport arrive-by target is calculated only when gate close and every required check-in, security, terminal-route, and safety distribution are current. Otherwise it is `Unknown`.

## Entry requirements: API, backup, search, AI, and cache

### What is and is not deterministic

Entry rules change and must come from a current structured source or the authority itself. The app's deterministic rules govern **how evidence is accepted**:

- exact normalized traveler/itinerary facts are required;
- prohibited document fields are rejected;
- source, evidence kind, timestamps, expiry, and official links are mandatory metadata;
- stale/discovery/fallback evidence cannot authorize a landside plan; and
- no entry content is learned.

The visa rule content is not hard-coded into the native model. The bundled Japan link is a last-resort verification pointer, not a rule engine.

### Current Worker resolution chain

The structured request is `POST /v1/entry-requirements`. It contains nationality, residence, passport type, declared authorization types, ordered airport/country/time-zone facts, exact trip timestamps, planned landside exit, luggage plan, and purpose. It rejects passport number, document number, scan/image, and MRZ fields recursively.

Resolution order:

```text
Sherpa Requirements API, if configured
  -> Timatic deployment adapter, if separately configured
     -> Gemini Google Search official-link discovery, if configured
        -> bundled official-link registry
```

An upstream `429` propagates and stops fallback. Other normalized provider failures may continue to the next independent provider. An explicitly stale structured response is rejected before fallback.

Sherpa and Timatic results are normalized as structured guidance with a bounded maximum expiry. The current Worker deliberately returns `requiresConfirmation` and `canEnter: null`; it does not promise admission. Every response includes official verification links when available.

Gemini is **not** a backup visa decision engine. Its prompt contains only the destination country and an allowlisted set of official government domains. The Worker ignores generated prose, accepts only URL citations whose host matches that country allowlist, returns no requirements, and marks the response `officialSourceDiscovery`. Discovery can never support a positive landside decision.

The legacy `GET /v1/entry-requirements` accepts only a minimal country query. It can return links but never a structured assessment. New clients should use POST.

### Entry cache behavior

`EntryRequirementCache` stores a protected local result under a SHA-256 fingerprint of the complete normalized query, including authorization declarations, airports, absolute times, time zones, purpose, luggage, and planned exit. It stores no readable query key.

- Normal mode: refresh upstream, save success, otherwise return the exact cached match.
- Offline mode: return only the exact cached match or fail unavailable.
- Expired cache: may remain visible with provenance, but `EntryAssessment.canSupportLandsideRecommendation` returns false.
- User acknowledgement: necessary for a positive path where supported, but never sufficient to override status/evidence/expiry.

Because rule changes can be abrupt, do not extend entry expiry using a generic app constant, AI confidence, or learned historical stability. Respect the provider-bounded expiry and force official re-verification.

## Caching and persistence

| Data | Current store/policy | Safety behavior |
|---|---|---|
| Itinerary and traveler profile | `itinerary-cache-v2.json`, complete-until-first-authentication, excluded from backup | Schema/provider/model versions recorded; legacy linked journey migrates. |
| Flight search/status | `journey-cache-v1.json`; repository marks cached/stale at a 15-minute default | Production retention must still comply with the purchased provider license. |
| Entry assessment | Protected exact-query cache | Expired results are display-only and cannot authorize landside/city. |
| HND facility registry | Versioned source records in code/Worker | Facility existence can persist; variable hours, access, and availability still require confirmation. |
| GTFS static | Provider policy permits versioned persistence | Feed version and agency license required. |
| GTFS-Realtime and WeatherKit | Memory policy | Expire from source metadata; neither is wired end to end. |
| Hotel offers | Memory/short offer expiry | Never invent price or availability; current adapter is not wired into screens. |
| MapKit / Google Places | No app persistence for MapKit discovery; Google Places policy is memory-only | Discovery never proves eligibility/opening/availability. |
| Learned model | `on-device-prediction-v2.json`, protected and excluded from backup | Disableable and erasable; no entry rules or raw commercial payloads. |
| Apple Calendar bindings | Versioned EventKit IDs in UserDefaults; actual events in EventKit | Only app-marker events are updated/deleted after consent. Settings/AppContainer wiring is implemented and locally tested; cross-device delivery requires real-account acceptance. |

`Delete journey and offline data` currently clears the long-haul cache and entry cache. It does not erase the learned model, which has its own button. It also does not currently clear the legacy `FlightCache`; fix the implementation or narrow the Settings copy before privacy acceptance.

Provider policy must be enforced before persistence. The present normalized flight cache is a prototype and does not dynamically reject storage by purchased license; a production adapter must add that enforcement.

## Authorized live-data learning

The on-device model can learn from live data, but live does not automatically mean licensed for training. Provider observations require dual authorization:

1. The local `ProviderPolicyRegistry` permits the exact `ProviderTrainingPurpose`.
2. Normalized source metadata names the same policy version and purpose.
3. The adapter provider ID is non-empty.
4. The record is live, non-demo, resolved, and has a stable provider record ID.
5. Personalization is enabled.

For delay learning, resolved means both scheduled and actual departure exist. The model persists an aggregate residual and a deterministic one-way observation ID, not the provider payload or raw provider record ID. Repeated refreshes deduplicate.

Shipped commercial policies are deny-by-default. A deployment operator may enable a narrow purpose only after verifying the actual account contract and updating both local and normalized policy catalogs. A server response alone cannot enable learning.

User-owned walking/transit duration, reported delay, plan acceptance, and explicit feedback remain independently eligible. `OnDevicePredictionService` uses running statistics and versioned sample/age thresholds. It can be disabled and erased. Entry and visa requirements have no training-purpose enum case by design.

## Flight-delay prediction

### Current implementation

- `Flight` supports scheduled, estimated, and actual times plus a normalized delay field.
- `FlightRepository` refreshes provider status and records gate changes.
- Exact-purpose authorized, resolved departures can update the on-device model.
- `OnDevicePredictionService` groups delay residuals by airline, origin-destination route, airport-local weekday, and hour, with a route-only fallback.
- Confidence is based on versioned sample-count and age rules.

The native UI includes a delay outlook when sufficient historical evidence is available, alongside sourced airport weather. These are bounded estimates, not a complete weather/congestion forecasting system. A comprehensive runway, air-traffic-flow, rotation, crew, NOTAM, or airport-demand pipeline is not established by this implementation.

### Recommended delay architecture

Add a provider-neutral `DelayFeatureSnapshot` containing sourced, expiring features such as:

- official current flight status and estimated times;
- inbound aircraft/rotation only when licensed and identity is reliable;
- origin/destination weather and forecast uncertainty;
- airport arrival/departure demand and congestion proxy;
- runway/flow restrictions and service disruption where an authoritative feed permits use;
- airline/route/local-time/season context; and
- the user's local residual model as a separate feature, never as official status.

Prefer calibrated quantile or survival outputs over a single delay minute:

```text
P(delay > 15 min), P(delay > 30 min), and delay quantiles
```

Evaluate temporal holdouts, Brier score/log loss, reliability diagrams, interval coverage, route/airport slices, and drift. Feed the resulting distribution into layover uncertainty only after calibration; never replace provider actual/estimated facts or loosen policy thresholds. Preserve a no-model fallback.

## Overbooking, seats, and luggage capacity

The current app has no `FlightCapacityProvider`, seat-inventory model, overbooking assessment, standby list, bag-acceptance status, or overhead-bin capacity source. `TravelerProfile.luggage` describes the traveler's handling plan; it is not capacity evidence. `baggageClaim` is an arrival field, not available bag space.

Do not infer capacity from:

- a public seat map;
- the number of selectable seats;
- check-in position;
- aircraft type alone;
- an AI/search answer; or
- the absence of an alert.

Seat maps can omit blocked, held, assigned, and operational seats and do not reveal the airline's authorized oversell or standby process. Overhead-bin availability changes during boarding and is rarely exposed through a public operational API.

If a contracted airline source becomes available, add explicit types such as `FlightCapacitySnapshot` and `BaggageCapacityAssessment` with evidence state (`confirmed`, `estimated`, `unknown`), observed/expiry times, source authority, and a clear scope. Keep passenger-specific status opt-in and protected. The safe default remains `Unknown — verify with the operating airline or gate agent`. Capacity must never authorize a connection or city plan.

## Cross-device reminders

### Implemented foundation

`CrossDeviceReminderPlanner` emits stable intents only from known future values:

- go-to-gate from `JourneyAssessment.leaveBy`;
- gate close from a current sourced `gateCloseTime`; and
- latest return only from a Safe assessment with no unresolved inputs.

There is no fixed lead-time magic number. Stable IDs omit changing action time and input revision so a live update replaces an existing event/task instead of duplicating it.

`AppleCalendarReminderAdapter`:

- requires explicit versioned consent and full EventKit calendar access;
- never prompts during background/routine sync;
- uses an `airportxr://reminders/<id>` marker;
- upserts one-minute action-marker events with an alarm at the derived time;
- deletes only marked events in the itinerary scope; and
- relies on the selected iCloud/CalDAV account for cross-device propagation.

The one-minute event duration is an EventKit structural marker, not a time estimate.

`GoogleTasksProxyReminderAdapter`:

- requires explicit consent and the user OAuth scope `https://www.googleapis.com/auth/tasks`;
- passes a short-lived token in the Bearer header, never in the body or logs;
- uses a bounded complete marker scan before mutation;
- updates/consolidates by stable marker and deletes only stale Airport XR tasks; and
- converts action time to a due date in the airport time zone.

Google Tasks discards time-of-day in `due`. The Worker puts the exact intended instant and time zone in notes, but Google controls reminder timing. Apple Calendar is the current exact-time design; Google Calendar would be a separate provider, scope, and consent review.

### Runtime work still required

1. Add separate default-off Settings controls and versioned consent persistence.
2. Implement `GoogleOAuthAccessTokenProviding` with Google's supported iOS sign-in/PKCE flow and Keychain-backed refresh state.
3. Instantiate both adapters in `AppContainer`.
4. After an itinerary/safety snapshot changes, debounce, re-plan, and sync the current scope.
5. On revocation, delete managed records while authorization remains, then disconnect/revoke.
6. Surface provider state, last sync, exact-time/date-only limitation, and retry action.
7. Add a push/background update strategy if reminders must change while the app is suspended.
8. Test two signed-in physical devices for each provider. Simulator contract tests cannot prove account synchronization or alert delivery.

The Google OAuth client ID is configuration, not a secret. No iOS client secret is required. Access and refresh tokens belong in Google Sign-In/Keychain storage, not `Secrets.xcconfig`, UserDefaults, analytics, or Worker persistence.

## Optional AI and free/trial integrations

### Implemented Workers AI explainer

`POST /v1/ai/explain` accepts a strict calculation-trace or facility schema. The model sees opaque fact IDs and minimized descriptors. It can only order each input ID exactly once and choose a presentation focus. Deterministic Worker code renders all values, formulas, sources, hours, and URLs.

Guardrails:

- arbitrary prompts are rejected;
- entry/visa/passport/nationality/immigration domains are rejected before inference;
- traveler profile fields and precise location history are outside the schema;
- malformed, missing, duplicated, or invented IDs cause deterministic fallback order;
- raw model prose is never returned;
- responses are `no-store`; and
- AI cannot affect feasibility, entry, or training authorization.

The backend is implemented and tested with a mock `AI` binding. No iOS explanation affordance or request mapping is wired.

### Optional provider selection

The implemented Workers AI explanation and Gemini official-link discovery paths have bounded roles described in [AI Integrations](AIIntegrations.md). Provider pricing, quotas, model availability and data terms require deployment-specific review; this guide does not promise a free tier. Additional inference providers remain proposed work until an adapter and acceptance evidence exist.

## Secrets, entitlements, and authentication

### iOS configuration

Copy the ignored example or run the helper:

```bash
# From the repository root
AVIATION_PROXY_BASE_URL=https://your-worker.example.workers.dev \
  ./Scripts/configure-secrets.sh
```

`Config/Secrets.xcconfig` may contain only service URLs:

- `AVIATION_PROXY_BASE_URL`
- `CLOUD_VISION_PROXY_BASE_URL`

Do not put commercial keys, Google OAuth tokens, Cloudflare Access assertions, or provider secrets in Swift, Info.plist, app environment arguments, or xcconfig.

MapKit needs no app API key. The separate WeatherKit adapter requires its capability/entitlement; current AppContainer composition uses keyless weather providers. EventKit requires explicit user authorization at runtime.

### Worker secrets

Set only integrations that are actually enabled:

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

`TIMATIC_API_URL` must point to the deployment's reviewed normalized adapter because account schemas are contract-specific. `TIMATIC_SERVICE_TOKEN` is optional. `GEMINI_ENTRY_DISCOVERY_MODEL` and `ENTRY_OFFICIAL_DOMAINS_JSON` are non-secret deployment configuration, but every domain must still pass the Worker's hostname allowlist logic.

Reserved-but-unused names in the current Worker:

- `GOOGLE_PLACES_API_KEY`
- `TRANSITLAND_API_KEY`
- `HUGGINGFACE_TOKEN`

Do not provision unused secrets. Workers AI uses the `AI` binding and no application secret. Google Tasks uses the person's short-lived OAuth token and must not have an API-key fallback.

### Worker request authentication

Production uses Cloudflare Access RS256 JWT verification plus a fail-closed rate-limit binding. Configure the non-secret Access team domain and audience in `wrangler.toml`. `REQUEST_AUTH_MODE=none` is accepted only outside production for local tests.

The iOS client does not yet acquire/attach a Cloudflare Access session, and App Attest is not implemented. A production-protected Worker should therefore return `401` to the current client until that integration is built. Do not weaken Worker authentication to make the prototype appear live.

## Worker route inventory

| Method | Route | Current role |
|---|---|---|
| `GET`, `POST` | `/v1/journeys/:trip/:leg` | Revisioned account-scoped journey confirmations. |
| `GET` | `/health` | Public liveness and configured-provider booleans. |
| `GET` | `/v1/provider-policies` | Versioned cache/training metadata. |
| `GET` | `/v1/flights/search` | FlightAware search with bounded Amadeus fallback. |
| `GET` | `/v1/flights/:id` | FlightAware status by provider record ID. |
| `GET` | `/v1/airports/:iata/departures` | FlightAware departure board. |
| `GET` | `/v1/airports/:iata/arrivals` | FlightAware arrival board. |
| `GET` | `/v1/hotels/search` | Amadeus nearby hotels/offers. iOS adapter exists but is not wired into UI. |
| `GET` | `/v1/activities` | Amadeus activities. No active iOS adapter. |
| `GET` | `/v1/facilities/airports/:iata` | Versioned official/operator facility registry. |
| `POST` | `/v1/entry-requirements` | Full structured entry query and fallback chain. |
| `GET` | `/v1/entry-requirements` | Legacy country-link discovery only. |
| `POST` | `/v1/scene-ocr` | Explicit-consent, bounded JPEG still to Google Vision. iOS upload not wired. |
| `POST` | `/v1/reminders/google-tasks/sync` | User-OAuth Google Tasks scoped synchronization. iOS OAuth/runtime not wired. |
| `POST` | `/v1/ai/explain` | Optional grounded fact ordering. iOS affordance not wired. |

All `/v1` routes are protected. Provider 429 responses propagate with bounded `Retry-After`; the flight search does not use fallback to bypass rate limiting. Error responses are bounded and omit credentials, provider payloads, queries, and profiles.

## Setup, build, test, and launch

### Toolchain setup

```bash
# From the repository root
./Scripts/bootstrap.sh
./Scripts/generate.sh
SIMULATOR_NAME='iPhone 13' ./Scripts/build.sh
```

The scripts retain an `iPhone 17 Pro` default; use `SIMULATOR_NAME='iPhone 13'` for the approved design target. Keep at least 5 GB free. `./Scripts/clean.sh` removes only this project's `build/` directory.

### iOS tests

Full unit and UI suite:

```bash
# From the repository root
SIMULATOR_NAME='iPhone 13' ./Scripts/test.sh
```

Deterministic unit target only:

```bash
# From the repository root
xcodebuild \
  -project AirBorder.xcodeproj \
  -scheme AirBorder \
  -destination 'platform=iOS Simulator,name=iPhone 13' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:AirportXRCompanionTests
```

Reminder foundation only:

```bash
xcodebuild \
  -project AirBorder.xcodeproj \
  -scheme AirBorder \
  -destination 'platform=iOS Simulator,name=iPhone 13' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:AirportXRCompanionTests/CrossDeviceReminderTests
```

Test counts can change as coverage is added. Treat only the current command and retained xcresult/log as evidence.

### Worker tests

```bash
cd Backend
npm ci
npm test
npm run check
npx wrangler deploy --dry-run
```

Tests mock upstream services and AI. They validate schemas, auth/rate boundaries, fallback, entry-chain safety, Google Tasks idempotency, and grounded AI invariants without real credentials. Credential-gated live contract tests must remain opt-in and must not log private payloads.

### Simulator modes and replay tests

For the rebuilt app, use the standalone HTTP replay described below. The other
simulator examples in this section (including in-process and Core Location
replay) describe the earlier prototype.

```bash
# From the repository root
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh live
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh offline
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh ar-preview
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh ar-corelocation
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh walkthrough
```

Ordinary launches do not pass `--uitesting`. Physical-device AR, account synchronization, background delivery, and real provider data need separate acceptance evidence.

For an indoor signal source that runs independently of the app:

```bash
# Terminal 1
python3 Scripts/indoor-signal-emulator.py

# Terminal 2
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh ar-external
```

`IndoorReplayQA` in the rebuilt app accepts only loopback HTTP and requires an
explicit `--uitesting --qa-indoor-feed` launch of a Debug Simulator build. The
server exposes `GET /reading`, `GET /status`, and
`POST /control/pause|resume|next|previous|reset`. Use
`python3 Scripts/tests/test_indoor_signal_emulator.py` to test the driver alone
and `./Scripts/test.sh` to run the simulator suite with the driver available.
See [indoor replay architecture](IndoorPositioningArchitecture.md) for the
implemented test boundary.

For Apple Core Location delivery, boot the simulator and start the same process with `--transport core-location --device booted`, then launch `ar-corelocation`. The runner grants when-in-use location permission to the installed QA app. `CoreLocationIndoorQAService` receives `CLLocationManager` updates and `HNDCoreLocationQAFixture` maps the versioned synthetic coordinate footprint to the test graph. This path is unavailable in ordinary launches. Use `--dry-run` on the emulator to inspect the exact `simctl location` command without changing Simulator state.

`RouteManeuverBuilder` calculates the signed angle between graph edges, classifies it using `RouteTurnPresentationPolicy`, and derives the outgoing eight-way `CompassHeading`. The same semantic maneuver drives the passenger instruction, SF Symbol, accessibility label, route-step list, and RealityKit arrow rotation. Tests cover the angle boundaries and all requested compass-style headings.

### Local Worker development

```bash
cd Backend
npx wrangler dev --var DEPLOYMENT_ENVIRONMENT:development --var REQUEST_AUTH_MODE:none --var REQUIRE_RATE_LIMITER:false
```

Use unauthenticated mode only for explicit local development. Workers AI bindings can consume Cloudflare account usage even during local `wrangler dev`; automated tests mock the binding.

## Adding a provider

1. Choose or add the narrow provider-neutral protocol; do not leak vendor DTOs into views.
2. Normalize optional fields without substituting zero, empty strings, or fixture values.
3. Populate `ProviderMetadata`/`SourcedMetric` with record identity, timestamps, expiry, field name, uncertainty, and data mode.
4. Add a versioned `ProviderPolicy` that reflects the actual contract. Default training to denied.
5. Enforce persistence, redistribution, attribution, and expiry at the cache boundary.
6. Put credentials only in Worker secrets. Reject unsafe external URLs and oversized/malformed payloads.
7. Define error-class fallback. Do not bypass 401/403/429 with a provider storm.
8. Add deterministic mapping, missing-field, stale, 429, malformed, fallback, cache-policy, and unauthorized-learning tests.
9. Add an opt-in live contract test that logs only redacted schema evidence.
10. Expose accurate UI state and source details. AI or cache availability must not masquerade as live provider evidence.

For a provider to authorize model learning, both local and response policy catalogs must name the same version and exact purpose. Never add an entry/visa training purpose.

## Adding a metro area or transfer adapter

### Metro grouping

1. Add a `MetroAirportRecord` in `MetroAirportDatabase.records` with a stable ID, official name, country codes, airport codes, IANA time zone, verification date, and source.
2. Verify airport codes against the dated source snapshot.
3. Add an `AirportReferencePoint` separately when nearby discovery or entry-country resolution needs that airport. Never fall back to another airport's coordinates.
4. Add same-airport, same-metro, and cross-region classification tests.

Metro grouping is a planning taxonomy. It must never provide route time or imply that a transfer is feasible.

### Regional routing

1. Implement `InterAirportTransferProvider` for the region.
2. Include origin/destination terminal or conservative uncertainty, wait time, next usable departure, missed-service behavior, disruption, last service, transfers, walking, accessibility, luggage notes, timestamps, and expiry.
3. Label static published ranges as context, not current fastest routes.
4. Keep duration as a distribution.
5. Run Pareto and accessibility tests and verify `canClaimFastest` remains false for cached/stale/demo records.
6. Add entry, baggage, check-in, security, terminal-route, and safety segments before allowing an arrive-by target or optional visit.

## UI and accessibility development

- Use semantic Dynamic Type styles and adaptive stacks/grids.
- Keep status in words and symbols, not color alone.
- Maintain at least the shared minimum touch target.
- Do not nest controls inside other controls.
- Keep the primary action conservative and visible.
- Preserve calculation detail through progressive disclosure.
- VoiceOver labels should state data mode, route trade-offs, and whether timing is exact, date-only, stale, or unknown.
- Respect Reduce Motion; camera/AR needs a non-camera Map path.
- Test accessibility at large sizes with the current UI audit, then manually review dark mode and VoiceOver order.

The HND terminal graph is synthetic. Never present its geometry or accessibility as an airport-validated map.

## Report reproduction

The canonical report is [`Documentation/Reports/2026-07-14-airportxr-long-haul-layover.md`](Reports/2026-07-14-airportxr-long-haul-layover.md). The exporter creates a canonical Markdown/PDF/provenance trio and rendered page PNGs.

One-time local tools:

```bash
# From the repository root
python3 -m venv build/reporting-venv
build/reporting-venv/bin/pip install reportlab
brew install poppler
```

Deterministic export with a fixed timestamp:

```bash
# From the repository root
build/reporting-venv/bin/python Scripts/reporting/export_report_pdf.py \
  Documentation/Reports/2026-07-14-airportxr-long-haul-layover.md \
  --output-root output/pdf \
  --report-id 2026-07-14-airportxr-long-haul-layover \
  --render-check require \
  --generated-at 2026-07-14T00:00:00Z
```

The expected directory is:

```text
output/pdf/2026-07-14-airportxr-long-haul-layover/
  2026-07-14-airportxr-long-haul-layover.md
  2026-07-14-airportxr-long-haul-layover.pdf
  2026-07-14-airportxr-long-haul-layover.provenance.json
  rendered/page-*.png
```

Re-export to a separate temporary root with the same timestamp and compare SHA-256 hashes. Inspect every rendered page for clipping and layout defects; a successful PNG render is not a visual inspection.

## Repository continuity

`.codex/project-context.md` preserves implementation constraints and verification leads for development sessions. Read the latest checkpoint alongside current source, PR checks, and the acceptance contract. Older entries are dated evidence, not current completion claims. This file does not configure the platform conversation compactor or require a separate locally installed skill.

## Current known limitations

- No credential-backed live provider response has been accepted as project evidence.
- The current iOS client cannot acquire the Cloudflare Access session required by the protected production Worker.
- No App Attest/device-attestation integration exists.
- HND-NRT has demo transfer ranges only; no live Tokyo journey planner is wired.
- Current airport weather is composed from keyless providers. Verified regional routing, live queues, congestion and operational-feed acceptance remain separate work.
- The independent triangular duration model does not represent correlated disruption or heavy tails.
- The `0.90`/`0.70` thresholds are provisional research policy, not empirically certified.
- Structured entry providers return guidance and official links, not admission guarantees; search/AI fallback discovers links only.
- Hotel offers and activities have Worker routes but are not wired into the current app experience.
- Cloud Vision consent/configuration exists, but the iOS OCR screen remains local-only.
- Workers AI explanation has no iOS affordance.
- Apple Calendar is wired into Settings/AppContainer and locally tested; Google Tasks remains disabled because Google OAuth is not configured.
- Google Tasks cannot express an exact due time through its API.
- Delay learning is a simple local historical baseline; weather/congestion prediction is not implemented.
- Overbooking, seat inventory, bag-acceptance capacity, and overhead-bin space are unavailable.
- The in-flight progress presentation is still reference-route-specific.
- The Settings journey-data deletion action does not clear the separate learned model or legacy flight cache.
- Simulator AR does not validate physical-device tracking or real terminal geometry.
- Real cross-device notification delivery requires two-device and suspended-app testing.
- Provider licensing, retention, attribution, regional processing, and free-tier terms require release-time review.

## Related documents

- [User and demo guide](UserDemoGuide.md)
- [Architecture](Architecture.md)
- [Data sources](DataSources.md)
- [Live data and freshness](LiveDataPlan.md)
- [Cross-device reminders](CrossDeviceReminders.md)
- [Optional AI integrations](AIIntegrations.md)
- [Security review](SecurityReview.md)
- [Privacy and security](PrivacyAndSecurity.md)
