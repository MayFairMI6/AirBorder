# Airport XR Companion architecture

## System shape

Airport XR Companion is a native SwiftUI application with provider-neutral domain models, conservative decision services, actor-backed protected persistence, and a Cloudflare Worker that keeps commercial credentials off-device.

```text
SwiftUI six-tab shell
  -> @MainActor LongHaulExperienceViewModel
     -> ItineraryCache / on-device personalization
     -> flight, facility, entry, place, accommodation, transit, queue, weather providers
     -> LayoverRecommendationEngine + SafetyPolicy
     -> MetroAirportDatabase + InterAirportTransferPlanner
     -> TerminalRouter + RouteManeuverBuilder

iOS HTTPS client -> Cloudflare Worker -> Amadeus / FlightAware / Sherpa or Timatic / optional services
Native adapters  -> MapKit / Vision / WeatherKit
Direct adapters  -> agency-specific GTFS and GTFS-Realtime feeds
```

The Worker returns normalized data and provider-policy metadata. It never returns provider credentials. The app can operate in `live`, `demo`, `offline`, or DEBUG-only `stochastic` mode; every user-visible value retains a live/cached/stale/demo/unknown state.

## Domain model

`Itinerary` owns ordered `ItineraryLeg` values. Adjacent legs create timezone-aware `LayoverContext` values from actual or estimated on-block time and the onward gate-close fact. A layover records both the arrival airport and onward-departure airport, so airport changes are explicit rather than inferred in the UI.

Decision data is represented by:

- `SourcedMetric<Value>`: value, unit, provider field, record ID, observation/receipt/expiry time, uncertainty, and derivation steps;
- `EstimateDistribution`: lower, most-likely, and upper values, never a hidden point estimate;
- `PlanSegment` and `PlanCandidate`: the ordered work required by a proposed layover plan;
- `FeasibilityAssessment` and `CalculationTrace`: classification, probability interval, latest-return result, policy version, seed, unresolved inputs, and source records.

Unknown critical values remain absent. They are not converted to zero. A missing or expired entry rule, gate close, queue, security, return service, accessibility fact, or transfer duration prevents a positive landside/city result.

## Safety decision flow

```text
available window = onward gate close - inbound on-block

required time = deplane
              + conditional border / bags / customs
              + outbound travel + activity + return travel
              + re-entry / security + terminal route + safety components

Monte Carlo simulation -> Wilson 95% interval -> SafetyPolicy classification
```

`SafetyPolicy.current` is the only source of deterministic probability thresholds and simulation precision. Identical itinerary revision, snapshot revision, and policy version derive the same seed. DEBUG stochastic mode generates and logs an unseeded seed for exact replay. User preference can order plans only after safety rank and cannot weaken the policy floor.

## Same-metro and inter-airport transfers

`MetroAirportDatabase` is a versioned offline index of 25 multi-airport regions. Airport codes are seeded from the public-domain OurAirports dataset; metro grouping is a curated planning classification, not a source of travel time. `classify(from:to:)` returns same-airport, same-metro, or cross-region surface-sector state.

`AirportReferencePointRegistry` separately stores sourced BKK, HND, NRT, and LAX coordinates and country codes from dated OurAirports records. Coordinates only center a discovery request; MapKit or another current provider still derives candidates and distance. Missing airport metadata remains unknown and blocks entry queries or discovery instead of falling back to a hard-coded location.

For HND to NRT, the active layover requires the surface transfer before optional activities. `InterAirportTransferProvider` supplies route distributions, accessibility, transfers, last service, walking, cost, and freshness. `InterAirportTransferPlanner` Pareto-filters the options and then uses a visible lexicographic ordering. It may call a result fastest only when current, complete route evidence supports that claim; demo results use “Leading demo option - not live.”

The onward-airport arrival target is derived from onward gate close minus the upper estimates for check-in/bag acceptance, security, terminal route, and safety margin. If any component is absent or expired, the target is Unknown.

## Routing and AR

Indoor routing uses multi-label Pareto filtering plus lexicographic cost vectors for fastest, accessible, least-walking, fewest-level, simplest, and low-crowd modes. No scalar penalty hides trade-offs. Closure, stairs, elevator, narrow-passage, level, distance, duration, crowd, and direction-complexity fields remain separate.

`RouteManeuverBuilder` derives the displayed instruction, direction, segment distance, and step count from the selected graph edge and geometry. The HND graph is a named demo fixture. Production indoor guidance requires a licensed, versioned airport graph and current infrastructure status. Inter-airport transfers pause indoor AR until the traveler reaches the onward airport.

## Providers and fallback

Each external category has a boundary protocol. The default flight path is secure proxy followed by a clearly labeled demo provider only when fallback is enabled. HND official facilities and the informational entry provider remain separate from commercial discovery. MapKit supplies nearby discovery; accommodation availability is an optional provider result and booking opens externally.

Entry requirements are a stricter chain: a bounded normalized itinerary/profile request reaches Sherpa v3 first and an independently configured Timatic contract adapter second. Malformed or explicitly stale structured data is rejected before fallback. Optional Gemini Google Search grounding can discover only allowlisted official-government URLs; model prose is discarded and the response is typed `officialSourceDiscovery`, which cannot authorize entry or positive landside/city feasibility.

Provider fallback cannot convert an authentication failure, rate limit, malformed record, stale record, discovery-only result, or unknown field into a live success. Cache policy is provider-specific through `ProviderPolicyRegistry`.

Named recommendation and HND-to-NRT duration fixtures are injected only in `demo` or DEBUG `stochastic` mode. `live` and `offline` do not synthesize an itinerary, same-airport duration, optional activity, or transfer option. Until a current/cached layover snapshot adapter is configured, those modes keep the recommendation unresolved. A demo transfer can be Pareto-ranked for QA but can never set `canClaimFastest`.

## License-aware local learning

Provider payloads can improve the on-device model only through dual authorization:

1. the versioned local provider policy permits the exact purpose;
2. normalized source metadata identifies the same policy version and purpose;
3. the observation is live, non-demo, resolved, and has a stable provider record ID; and
4. personalization remains enabled.

The current commercial policies are deny-by-default because no account contract has been recorded as granting model training. A licensed deployment can enable a narrowly named purpose in both catalogs. Eligible flight outcomes persist only aggregate residual statistics and a deterministic one-way deduplication ID. User-owned walking/transit outcomes and explicit feedback remain independently eligible. Entry/visa data has no training purpose.

## Persistence and migration

- `ItineraryCache` stores schema/version metadata, itinerary, traveler profile, provider cache version, and prediction model version under iOS data protection and excludes the files from backup.
- `EntryRequirementCache` stores the provider result under a one-way fingerprint of the complete normalized query. Exact-query stale records remain available with source/observation/receipt/expiry/provider-chain provenance, but `EntryAssessment` blocks them from authorizing landside access.
- Legacy `journey-cache-v1.json` can migrate its linked flight into the itinerary schema without deleting the old record.
- The learning model is versioned separately and is disableable and erasable.
- Google Places and other restricted provider content is not persisted beyond its policy.

## UI architecture

The six roots are Journey, Flights, AR Guide, Map, Layover & Transit, and Settings. The active itinerary, safety decision, transfer plan, facility state, route, traveler profile, and source freshness come from `LongHaulExperienceViewModel`. Journey always leads with the safest current action. Detailed formulas and source records are progressively disclosed through the calculation trace.

## Verification boundary

Deterministic unit tests cover domain boundaries, timezones/date line, HND-NRT, safety intervals, replay, stale/unknown values, routing, provider policy, cache migration, learning, and failure fallback. UI tests use named fixtures and remain distinct from normal simulator acceptance. Credential-gated live contract tests are opt-in and never gate CI or log private payloads. Physical-device AR remains a separate acceptance surface.
