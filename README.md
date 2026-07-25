# Airport XR Companion

Airport XR Companion is a native iPhone research prototype for long-haul international layovers, including same-airport planning and automatic multi-airport metro transfers such as HND to NRT.

> Research prototype - simulated or research data.

## What is implemented

- timezone-aware ordered itineraries and independently derived layovers;
- BKK-HND-LAX and HND-NRT named demo scenarios;
- a versioned offline registry of 25 multi-airport metro areas;
- conservative probability-based recommendations with complete calculation traces;
- HND facilities, MapKit nearby discovery, entry guidance, in-flight OCR, terminal routing, AR/map fallback, and traveler/accessibility settings;
- live/cached/stale/demo/offline labels and license-aware on-device learning;
- a secret-holding Cloudflare Worker with normalized provider endpoints.

No configured credential-backed live-provider run is bundled. A `live` launch never invents an itinerary or layover duration: without a configured Worker or policy-permitted cache it shows unavailable inputs. Use `demo` explicitly for the named reference experience; `offline` requires a prior cached itinerary. MapKit needs no API key.

## Prerequisites

- macOS with Xcode command-line tools and an iOS 18-or-newer simulator;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for regenerating the project;
- Node.js for Worker tests;
- optional Cloudflare/Apple/provider accounts for live adapters.

Keep at least 5 GB free before building. The scripts use only project-owned `build/` artifacts.

## Build and test from the terminal

```bash
cd /Users/anony/Downloads/AirportXRCompanion
./Scripts/generate.sh
./Scripts/build.sh
./Scripts/test.sh
```

To run only the deterministic unit target:

```bash
xcodebuild \
  -project AirBorder.xcodeproj \
  -scheme AirBorder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:AirportXRCompanionTests
```

## Launch the UI

Ordinary script launches do not pass `--uitesting`.

```bash
./Scripts/run-simulator.sh offline
./Scripts/run-simulator.sh live
```

### Practice drivers (no API key)

These commands use test-only fixtures; they never alter a live trip. They let
you review the green, amber, and red return-to-gate states and the weather-card
presentation without depending on a network response.

```bash
./Scripts/run-simulator.sh time-green
./Scripts/run-simulator.sh time-amber
./Scripts/run-simulator.sh time-red
./Scripts/run-simulator.sh weather-clear
./Scripts/run-simulator.sh weather-disruption
```

For any middle or edge case, choose the exact number of minutes to advance
the practice clock, or a weather state:

```bash
./Scripts/run-simulator.sh time 285
./Scripts/run-simulator.sh time -20
./Scripts/run-simulator.sh weather rain
./Scripts/run-simulator.sh weather fog
```

For a city-scale airport-transfer review, launch the map driver with a traffic
level. It opens the Map tab, where you can also search for a terminal landmark
to set your exact starting point. Use the existing **Walking pace** setting to
compare extra-time, typical, and faster walking profiles.

```bash
./Scripts/run-simulator.sh city-map light faster
./Scripts/run-simulator.sh city-map normal typical
./Scripts/run-simulator.sh city-map heavy slower
```

For normal use, weather remains keyless: the app requests Open-Meteo and
AviationWeather.gov when network access is available.

## Configure the app proxy URL

Copy `Config/Secrets.xcconfig.example` to ignored `Config/Secrets.xcconfig`, or use:

```bash
AVIATION_PROXY_BASE_URL=https://your-worker.example.workers.dev \
  ./Scripts/configure-secrets.sh
```

The app receives only the HTTPS Worker URL. Do not put provider keys in Swift, an xcconfig, Info.plist, or simulator arguments.

## Put API keys in Cloudflare Worker secrets

From `Backend/`, set only the services you actually enable:

```bash
npx wrangler secret put AMADEUS_CLIENT_ID
npx wrangler secret put AMADEUS_CLIENT_SECRET
npx wrangler secret put FLIGHTAWARE_AEROAPI_KEY
npx wrangler secret put SHERPA_API_KEY
npx wrangler secret put TIMATIC_API_URL
npx wrangler secret put TIMATIC_API_KEY
npx wrangler secret put TIMATIC_SERVICE_TOKEN
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put GOOGLE_PLACES_API_KEY
npx wrangler secret put TRANSITLAND_API_KEY
npx wrangler secret put GOOGLE_VISION_API_KEY
```

Timatic and Gemini credentials also belong only in Worker secrets. `TIMATIC_API_URL` points to the deployment's contract-reviewed normalized Timatic adapter; `GEMINI_API_KEY` is an optional discovery-only fallback and never produces entry authorization. Native WeatherKit uses the app entitlement. See [Backend/README.md](Backend/README.md) for Worker authentication, rate limiting, endpoints, tests, and deployment limitations.

## Learning and caching

The local model automatically learns from user-owned walking/transit outcomes and feedback. Live provider fields can also train it when both the local policy registry and the normalized provider metadata explicitly permit the exact purpose. The shipped commercial policies remain deny-by-default until the deployment operator records contractual permission. The model stores aggregate residuals and a one-way deduplication ID, not raw provider payloads. Entry/visa rules are never learned.

Caching is provider-specific: versioned official/static registries may persist; realtime, weather, availability, entry, and restricted POI data expire according to their source and license. Unknown or expired critical inputs cannot become a positive city recommendation.

## Project evidence

- Durable project state: [.codex/project-context.md](.codex/project-context.md)
- UI/UX research and wireframes: [Documentation/UIUXReview.md](Documentation/UIUXReview.md)
- Architecture: [Documentation/Architecture.md](Documentation/Architecture.md)
- Data and licensing: [Documentation/DataSources.md](Documentation/DataSources.md)
- Privacy/security: [Documentation/PrivacyAndSecurity.md](Documentation/PrivacyAndSecurity.md)
- Figma foundations: [editable Figma file](https://www.figma.com/design/MgNQlseRuiBCZvDjXnsvHi?node-id=3-31)

Simulator results do not validate camera tracking. Physical-device AR remains a separate acceptance test.

## Run builds in the cloud

The repository includes two ready-to-enable cloud paths. Neither path sends provider keys to the build service; fixture-based build and test runs require no secrets.

- **GitHub Actions:** [`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml) builds, runs the unit and UI suites, and uploads `.xcresult` artifacts on a macOS runner. Push the repository to GitHub and enable Actions. The hosted runner must provide an Xcode version compatible with the `26.0` project requirement and the selected simulator; update `SIMULATOR_NAME` in the workflow only if that runner's simulator inventory differs.
- **Xcode Cloud:** `ci_scripts/ci_post_clone.sh` installs XcodeGen and regenerates the project; `ci_scripts/ci_pre_xcodebuild.sh` verifies that the generated project exists. In App Store Connect, connect the Git repository, select **AirportXRCompanion** and its shared scheme, choose an Xcode version compatible with project.yml, and create a Test workflow for pull requests and branch changes. Xcode Cloud enrollment, Apple Developer membership, App Store Connect access, and connecting the remote repository must be performed by the account owner.

Cloud CI is useful for clean, repeatable verification and avoids local derived-data pressure. It does not replace a physical-device AR test or credential-gated provider contract tests.
