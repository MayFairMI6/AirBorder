# Data Sources

## Provider matrix

The client is provider-agnostic. Secret-bearing services are normalized by the Worker; native and public-feed adapters remain direct. A bundled provider is a named demo fixture, never a live result.

| Source | Product use | Access and retention decision | Current implementation truth |
|---|---|---|---|
| [Amadeus Self-Service](https://developers.amadeus.com/self-service/apis-docs/guides/developer-guides/test-data/) | flight search/status, hotel offers, activities | credentials in Worker; short availability cache; test data is limited/cached; training denied unless the deployment contract explicitly grants it | normalized Worker routes exist; no credential-backed run is recorded |
| [FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) | optional higher-grade flight adapter | Worker secret; storage/derivative use follows purchased license; training default-deny | optional adapter/fallback path exists; no account permission is assumed |
| [MapKit POI search](https://developer.apple.com/documentation/mapkit/mklocalpointsofinterestrequest) | nearby discovery | no app API key; results are discovery candidates, not official access/availability claims | native adapter implemented |
| [GTFS Schedule / Realtime](https://gtfs.org/documentation/overview/) | schedules, disruptions, accessibility, last service | static by feed version; realtime by source timestamp; each agency license still applies | protocol/parser and demo hooks exist; HND-NRT live agency feeds are not configured |
| [WeatherKit](https://developer.apple.com/weatherkit/) | current airport weather | app entitlement; 30-minute in-memory freshness window; not a secondary database or training set | native live adapter; requires a WeatherKit-enabled signed device build |
| [Open-Meteo](https://open-meteo.com/en/docs) | keyless current airport conditions | 30-minute in-memory freshness window; no training use | wired default for non-offline launches |
| [AviationWeather.gov](https://aviationweather.gov/data/api/) | keyless METAR terminal observations where available | 30-minute in-memory freshness window; rate-limited, no training use | wired alongside Open-Meteo; raw observation is retained as source text |
| [Google Places](https://developers.google.com/maps/documentation/places/web-service/policies) | optional richer POIs | billing/attribution required; ephemeral except where terms permit; Google Maps Content is not used to train the app model | optional policy/secret slot only |
| [Sherpa Requirements API](https://docs.joinsherpa.io/requirements-api/index.html) with [IATA Timatic AutoCheck](https://www.iata.org/en/services/compliance/timatic/autocheck/) backup | structured entry guidance | exact-query protected cache capped at provider expiry/one hour; stale records display-only; never learned into a rule | Sherpa v3 trip adapter and contract-specific Timatic normalized adapter implemented; no credential-backed run |
| [Gemini Grounding with Google Search](https://ai.google.dev/gemini-api/docs/google-search) | optional official entry-source discovery after structured-provider failure | model prose discarded; citation URLs accepted only from deployment-allowlisted government domains; never authorizes entry | adapter implemented but optional; Google Search grounding is not available on the Gemini API free tier |
| Official airport/operator records | work pods, hotels, showers, lounges, facilities | versioned registry; distinguish fixed record from variable availability | HND reference registry implemented |
| [OurAirports](https://ourairports.com/data/) | airport codes/reference coordinates | public-domain snapshot; metro grouping remains a curated planning index | 25 multi-airport metro records implemented |

All status/timing sources must tolerate missing fields and preserve scheduled, estimated, actual, cancellation/diversion, terminals, gates, provider timestamps, stable IDs where permitted, quota errors, and attribution.

## Transit sources

- Static schedules follow GTFS Schedule files (`stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`, `calendar*.txt`).
- Realtime extensions follow GTFS Realtime protocol buffers for trip updates, vehicle positions, and service alerts.
- Airport rail/metro/bus sources are configured per airport and normalized by `TransitDataProvider`.
- Elevator outages and accessibility fields are preserved when a source supplies them; absence is shown as unknown.
- Bundled sample schedule data provides deterministic offline routes and tests, clearly labeled as sample data.

## Indoor airport data

The bundled Terminal 2 graph is synthetic development data. Production airport graphs require a licensed airport/CAD/GIS source, versioning, closure updates, level/elevator metadata, and an operational validation process. Routes must not imply authoritative accessibility when infrastructure status is unknown.

## Vision sources

Apple Vision text/barcode recognition is the offline, local default. An optional consented Cloud Assist adapter sends one re-encoded, cropped still through the backend to Google Cloud Vision `TEXT_DETECTION`; it never streams camera video. Cloud output is advisory and a navigation-changing gate/sign result requires user confirmation. The normalized protocol allows AWS Rekognition `DetectText` or another provider to replace it without changing AR views.

## Provenance rules

Every live/cached object records source, source record ID where permitted, provider update time, receipt time, and whether it is demo data. Provider content is retained only as licensing permits; the normalized cache defaults to the minimum needed for an active journey.

Entry provenance additionally records the provider chain and evidence kind. Only a current `structuredProvider` assessment can proceed to the user's separate official-confirmation checkpoint. `officialSourceDiscovery`, bundled informational links, missing results, malformed payloads, and expired cache records always remain display-only.

## License-aware on-device learning

Live data is eligible for on-device learning, but it is not an automatic training set. The default is deny. A resolved provider observation reaches the model only when all of these conditions hold:

1. the bundled, versioned provider registry permits the exact training purpose;
2. the normalized response names the same policy ID and version and declares the same purpose;
3. the record is live, non-demo, resolved, and has a stable provider record ID; and
4. the traveler has not disabled personalization.

For flight-delay learning, “resolved” means both scheduled and actual departure are present. Repeated refreshes of the same provider record are deduplicated using a deterministic one-way observation ID. The persisted model contains aggregate residual statistics and the one-way ID, not the commercial response payload.

The current production registry does not assert training permission for FlightAware, Amadeus, Google Places, WeatherKit, GTFS, facility, hotel, activity, or entry-requirement payloads. A deployment may enable a purpose only after its operator verifies and records the applicable contract. User-owned outcomes—such as measured walking/transit time and explicit feedback—remain independently eligible for local learning. Entry and visa requirements never have a model-training purpose and can never be learned into a rule or used to weaken the safety policy.
