# Airport XR Companion user and demo guide

Last source review: 2026-07-16

Airport XR Companion is a research prototype for long-haul international layovers. Its screens show whether data is live, cached, stale, unavailable, or a demo fixture so each scenario can be evaluated against its actual source state.

This guide deliberately separates what can be demonstrated in the iPhone UI from foundations that exist only in source or automated tests. A visible value is not live merely because the simulator has internet access.

## Status labels used in this guide

| Label | Meaning |
|---|---|
| **UI demo** | Implemented and directly exercisable in the current iPhone simulator app. |
| **Live-capable boundary** | An adapter or proxy route exists, but a credential-backed end-to-end run has not been verified. |
| **Cached/offline** | Uses a previously stored record, retaining its freshness and provenance. |
| **Fixture/test only** | Implemented for repeatable research or automated testing, not current operations. |
| **Foundation only** | Domain/backend code exists, but Settings or runtime synchronization is not wired into the app. |
| **Unavailable** | The current build does not implement or expose the capability. |

The app itself uses these data badges:

- `DEMO FIXTURE`: named research values; not live.
- `QA STOCHASTIC`: randomly generated DEBUG fixture with a recorded replay seed; not live.
- `OFFLINE REPLAY`: previously cached data; time-sensitive facts are stale.
- `LIVE REQUESTED`: live mode was requested. This badge does **not** prove that credentials, authentication, or an upstream result succeeded.
- `LIVE`, `CACHED`, `STALE`, and `UNAVAILABLE`: the state of the corresponding result, not of the whole device.

## Prerequisites

- macOS with Xcode and an iOS 18-or-newer simulator.
- XcodeGen. `./Scripts/bootstrap.sh` installs it through Homebrew if Homebrew is available.
- At least 5 GB of free disk space before building.
- Node.js only for backend tests.
- A cropped seatback-display photo in the simulator Photos library only if testing OCR.
- No provider credentials are required for the named demo scenarios.

From Terminal:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
./Scripts/bootstrap.sh
./Scripts/build.sh
```

`run-simulator.sh` rebuilds and launches ordinary `live` and `offline` modes without the UI-test flag. The AR preview modes explicitly enable QA fixtures. Override the simulator only when needed:

```bash
SIMULATOR_NAME="iPhone 17 Pro" ./Scripts/run-simulator.sh live
```

Launch the hands-free feature tour, including populated traveler details and simulated terminal movement:

```bash
./Scripts/run-simulator.sh walkthrough
```

Launch only the repeating mapped-position AR preview:

```bash
./Scripts/run-simulator.sh ar-preview
```

Run the indoor signal generator independently from the app:

```bash
# Terminal 1 - keep this running
python3 Scripts/indoor-signal-emulator.py

# Terminal 2
./Scripts/run-simulator.sh ar-external
```

The first process advances a localhost indoor signal every 1.5 seconds. The app polls it independently and shows **Indoor test signal connected** in AR Guide. Pause and step the signal without touching the app:

```bash
curl -X POST http://127.0.0.1:8765/control/pause
curl -X POST http://127.0.0.1:8765/control/next
curl -X POST http://127.0.0.1:8765/control/previous
curl -X POST http://127.0.0.1:8765/control/resume
curl -X POST http://127.0.0.1:8765/control/reset
```

Set a different loopback endpoint with `INDOOR_FEED_URL`. Non-loopback URLs and ordinary app launches reject this QA feed. These commands explicitly enable QA behavior; normal `live` and `offline` launches never simulate a traveler position.

To make Apple Simulator itself deliver the movement through Core Location:

```bash
# Boot the simulator first, then in Terminal 1:
python3 Scripts/indoor-signal-emulator.py --transport core-location --device booted

# Terminal 2:
./Scripts/run-simulator.sh ar-corelocation
```

Use the same `curl` controls while the app runs. The maneuver card and **Route steps** list distinguish straight, slight, standard, sharp, and U-turn movements and name the outgoing compass direction, such as **Continue northwest**. The floor shown in this QA mode is matched from the test terminal graph, not supplied by GPS.

## Recommended 20-minute demo

Use this order so an itinerary-editing experiment does not replace the named fixture before the main walkthrough.

1. Launch the BKK-HND-LAX demo.
2. Inspect Journey and the calculation trace.
3. Open the terminal Map and AR fallback.
4. Explore airside, landside, nearby, and city layers.
5. Review the personalized entry check and local OCR boundary.
6. Relaunch with the HND-NRT inter-airport scenario.
7. Test Flights add/edit/reorder/refresh last, then relaunch `demo` to reset.
8. Show offline and stochastic/replay modes.
9. Explain the tested-but-not-wired reminders and AI features using their status sections below.

## Scenario 1: BKK-HND-LAX long-haul layover

**Status:** UI demo; named fixture; not live.

Launch:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
./Scripts/run-simulator.sh demo
```

### Journey dashboard

Actions:

1. Open the **Journey** tab.
2. Confirm the `DEMO FIXTURE` banner.
3. Read the ordered BKK-HND and HND-LAX timeline and active HND layover.
4. Confirm that **Go to Gate 105** is the prominent first action.
5. Scroll to **Layover decision**.

Expected result:

- The named fixture contains TG 660 from BKK to HND and NH 106 from HND to LAX.
- Times are shown using each airport's time zone.
- The active layover uses inbound on-block and onward gate-close facts rather than subtracting two wall-clock labels.
- The selected airside candidate shows a classification, probability estimate, Wilson 95% interval, and 10,000 trials when all required fixture inputs are present.
- Landside and city candidates remain `Requires confirmation` when entry, border, queue, return, or other critical inputs are missing.

Do not describe TG 660, NH 106, Gate 105, or any displayed timing as today's flight information.

### Why this recommendation?

Actions:

1. On Journey, tap **Why this recommendation?**.
2. Review **Calculated outputs**.
3. Expand source records under **Step-by-step derivation**.
4. Expand **Policy, seed, and generated time** under **Reproducibility**.

Expected result:

- Available window, required most-likely time, usable rest, and latest return are shown as values or `Unknown`.
- Every known duration includes a formula or fixture derivation and source record.
- Missing critical inputs are listed instead of becoming zero.
- The policy version and simulation seed make the same evidence snapshot replayable.

The `0.90` safe floor and `0.70` not-recommended boundary are provisional, versioned research policy values. They are not supplied by an airline API and are not certified aviation standards. See the developer guide for their rationale and the safer contextual-threshold design.

### Terminal map and AR guide

**Status:** UI demo using a named synthetic HND Terminal 3 graph. Physical-device AR is a separate test.

Actions:

1. Tap the red **Return to Gate** button. The app opens **AR Guide** over the current screen.
2. Open **Route mode** and compare Fastest, Accessible, Least walking, Fewest levels, Simplest, and Low crowd where available.
3. Tap **Choose known landmark** and choose a mapped landmark.
4. Expand **Route steps**.
5. Open the **AR Guide** tab.
6. Test **Pause**, **Recenter**, **Open accessible directions**, and the route-step disclosure.
7. Relaunch with `./Scripts/run-simulator.sh ar-preview` to watch the named terminal position and maneuver advance automatically.

Expected result:

- Distance, duration, maneuver, and step count are derived from the selected graph route.
- Accessible routing avoids disallowed graph edges when current graph metadata supports that decision.
- The simulator can demonstrate changing route guidance against the mapped test graph, but it cannot validate camera tracking, spatial anchoring, or real terminal geometry.
- If a gate is absent or unmapped, the app withholds AR rather than guessing.

### Airport services, hotels, work pods, and city layers

**Status:** UI demo for the HND official-reference registry; native MapKit discovery may return current nearby candidates; hotel availability is not wired into this screen.

Actions:

1. On Journey, tap **Airport services** or open **Layover & Transit**.
2. Switch among **Airside**, **Airport Landside**, **Nearby**, and **City**.
3. Toggle filters for Hotels, Transit hotels, Day rooms, Work pods, Lounges, Showers, Charging, Food, Facilities, and Attractions.
4. For a source-backed record, tap **Official record**.
5. Return to Journey and tap **Landside work pods**.
6. Confirm **Terminal 3 Work Cubicles** appears under **Airport Landside**, not Airside.
7. In Airside, find **The Royal Park Hotel Tokyo Haneda (Transit)**.
8. In Airport Landside, find the Terminal 3 shower, Observation Deck, Edo Koji, and Haneda Airport Garden records as filters permit.
9. In Nearby, use the refresh button to run MapKit discovery.
10. In City, inspect the short-Tokyo research candidate and its missing-input warning.

### Affordability layer

**Status:** UI demo with an independent, keyless foreign-exchange refresh.

1. In **Layover & Transit**, scroll to **Plan your spend**.
2. Confirm that free choices (for example, Observation Deck), transport, activities, food, and shopping are grouped separately.
3. Read a price band in airport-local currency first, then its approximate display-currency conversion and the quote date.
4. Tap refresh to request a newer exchange quote. Turn off connectivity and confirm the local bands remain visible while no fresh conversion is claimed.

The HND amounts are named preview bands, not merchant quotes. They help compare a plan's likely spend without asserting that a restaurant, shop, taxi, or attraction currently charges that amount. Exact live fare, inventory, and venue pricing require an authorized provider or official operator record; an unknown airport intentionally receives no invented price band.

Expected result:

- Facility existence, access zone, recorded hours, and current availability are separate facts.
- Work cubicles are landside; the transit hotel is airside; the Terminal 3 shower is landside.
- Links open externally. There are no in-app payments.
- A transit-hotel or day-room claim requires an explicit official/operator record. The current hotel-offer adapter is not connected to this UI, so no room or day-use availability should be claimed.
- MapKit requires no app API key. A nearby result is discovery, not proof of opening hours, eligibility, price, booking availability, or safe return.
- The city plan should remain blocked while current entry, queue, transit, last-service, weather, security, terminal-route, or gate-close evidence is missing.

### Personalized entry check

**Status:** UI demo with an immediately expired informational fallback unless a proxy and a structured provider are configured. The current product does not declare a traveler visa-eligible.

Actions:

1. On Journey, tap **Entry check**, or open **Settings** and tap **Nationality / residence**.
2. Enter two-letter nationality and residence country codes.
3. Select passport type, purpose, and luggage handling.
4. Add only the country and kind of a declared visa or permit if relevant.
5. Optionally enable **I reviewed current official rules** after reviewing the linked authority.
6. Tap **Save and reassess**.
7. Open each **Official verification** link.

Expected result:

- The app never requests a passport number, scan, MRZ, or payment detail.
- The assessment shows source, evidence type, and whether it is current.
- The bundled fallback says it cannot determine eligibility and expires immediately.
- A stale, discovery-only, conditional, missing, or negative result cannot unlock a landside or city recommendation.
- Checking the official-review toggle does not override an unresolved or expired provider result.

The live-capable backend order is Sherpa, then a separately contracted Timatic adapter, then official-link discovery. Gemini search, when configured, contributes only allowlisted government links; its prose is discarded and it never returns an eligibility conclusion. An exact-query cached result can be displayed after a failure, but an expired result cannot authorize leaving the airport.

### In-flight progress, local OCR, and window-view research

**Status:** local OCR is a UI demo. Cloud OCR has a backend route and consent preference but is not connected to this screen. Window-view geolocation is research-only.

Actions:

1. On Journey, tap **In-flight progress**.
2. Review the saved itinerary progress visualization.
3. Tap **Choose display photo** and select a cropped seatback-display image.
4. Review recognition confidence, detected progress, and recognized text.
5. Tap **Record a research-only cue** to inspect the experimental-state UI.
6. In Settings, inspect **Allow cloud sign recognition** and its consent dialog.

Expected result:

- Apple Vision reads the selected image locally and works without a network connection.
- OCR output is advisory. It cannot change a gate, visa assessment, boarding deadline, latest-return alert, or city recommendation without a separate confirmed workflow.
- Enabling Cloud Vision Assist records a preference and explains the one-still boundary; the current iOS OCR screen still uses only the local service.
- The optional backend accepts at most one consent-marked, cropped/re-encoded JPEG still and does not accept video, but that end-to-end upload is not wired into the app.
- The route labels in the current progress canvas are fixed to the reference BKK-HND-LAX presentation; this screen is not yet generalized for arbitrary itineraries.
- A window cue never feeds visa, boarding, return-now, or city-safety decisions.

## Scenario 2: mandatory HND-NRT inter-airport transfer

**Status:** UI demo; transfer times are fixtures, not current Tokyo transport data.

Launch:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
AIRPORTXR_SCENARIO=interAirport ./Scripts/run-simulator.sh demo
```

Actions:

1. On Journey, confirm the active layover says HND to NRT in the Tokyo metro area.
2. Confirm the primary action says **Start HND → NRT transfer** rather than Go to Gate.
3. Tap that action.
4. Inspect **Mandatory HND → NRT transfer** in Layover & Transit.
5. Expand **Compare transfer options**.
6. Review rail, airport bus, and road research ranges, walking, transfers, luggage notes, and accessibility state.
7. Find the NRT arrive-by card.
8. Tap **Start HND → NRT transfer** in the card.
9. Inspect the optional post-transfer Narita-area candidate.
10. Open AR Guide and Map to verify that terminal guidance pauses until the onward airport is reached.

Expected result:

- The offline metro registry automatically classifies HND and NRT as airports in the Tokyo metro area. It does not provide travel time.
- The leading route is labeled **Leading demo option · not live**. The UI must not say `Fastest` for the fixture.
- A safe NRT arrive-by target remains unknown because onward check-in, bag-acceptance, security, terminal route, or safety distributions are unresolved.
- Border and baggage handling remain confirmation items.
- The mandatory surface transfer is modeled before any optional activity.
- AR and indoor Map guidance are paused for the airport-change segment.

The registry contains 25 multi-airport metro areas, but only HND-NRT has a populated transfer demo provider. Other pairs can be classified automatically; current route options remain unavailable until a regional route adapter is configured.

## Scenario 3: four legs, time zones, overnight travel, and the date line

**Status:** fixture/test only. There is no named four-leg launch screen or fixture editor in the current UI.

Run the exact domain test:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
xcodebuild \
  -project AirportXRCompanion.xcodeproj \
  -scheme AirportXRCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:AirportXRCompanionTests/LongHaulExpansionTests/testFourLegItineraryBuildsOrderedLayoversAcrossTimeZonesAndDateLine
```

Expected result:

- `TEST SUCCEEDED`.
- Four ordered legs create three adjacent layovers.
- Absolute `Date` values remain ordered across airport-local time zones and the international date line.

Do not try to reproduce this by merely editing IATA codes in the UI: the current leg editor preserves the original source-controlled timestamps and airport metadata, so it is not a complete arbitrary-itinerary builder.

## Flights: search, boards, add, edit, reorder, remove, and refresh

**Status:** UI demo. Secure live-provider boundaries exist, but no credential-backed run is bundled.

Actions:

1. Launch `demo`, then open **Flights**.
2. Leave the seeded `AX` / `204` values and tap **Search live flights**.
3. Confirm the result is AX 204 and is labeled development data.
4. Open the result and inspect source, provider update, terminals, gate, and missing-field labels.
5. Return and tap **Add to itinerary**.
6. In **Ordered itinerary**, use **Earlier** and **Later** to reorder legs.
7. Tap the pencil to edit flight number, IATA codes, terminal, and gate; tap **Save leg**.
8. Use **Remove** on a test leg.
9. Switch to **Airport board**, enter an airport code, select Arrivals or Departures, and load the board.
10. Test **Refresh all itinerary legs** last.

Expected result:

- Search and board results show their source and freshness.
- The bundled provider returns a clearly labeled AX 204 demo record even for another requested identifier; it must never be presented as the requested live flight.
- Add, reorder, edit, and remove increment the itinerary revision and rebuild adjacent layovers.
- Editing does not let the user change provider-owned scheduled/actual times.
- In the named demo, refresh uses the bundled development status provider and can replace each fixture leg with its AX 204 status record. Relaunch `./Scripts/run-simulator.sh demo` after this experiment to restore BKK-HND-LAX.
- In offline mode, refresh performs no provider request and reports that cached facts are read-only.

For real use, the Worker URL, Cloudflare Access session flow, and upstream credentials must all work. The current iOS prototype does not yet acquire the Cloudflare Access session required by the production Worker, so a protected deployment is not end-to-end live-ready.

## Traveler preferences and accessibility

**Status:** UI demo; terminal behavior uses a synthetic graph.

Actions:

1. Open **Settings**.
2. Change Budget, Recovery preference, and Accessibility needs.
3. Toggle Wheelchair routes, Avoid stairs, Prefer elevators, Avoid escalators, Reduce walking, and Simplified directions.
4. Increase the extra boarding buffer.
5. Toggle larger AR indicators, spoken navigation, haptic turns, and high-contrast overlays.
6. Return to Map and compare route mode and route availability.
7. Test the app with iOS Dynamic Type, Reduce Motion, dark appearance, and VoiceOver.

Expected result:

- Traveler preferences can rank equally safe options but cannot weaken the safety floor.
- Wheelchair and stair preferences alter graph eligibility and routing.
- Spoken navigation and haptic controls are stored preferences; a complete turn-by-turn speech/haptic runtime is not demonstrated by this build.
- An elevator outage can make an accessible route unavailable; the app should not silently use stairs.

## Cache, offline mode, learning, and erase controls

### Prepare and test offline replay

**Status:** cached/offline.

Actions:

1. Launch `demo` once so the named itinerary is saved.
2. Terminate the app.
3. Run:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
./Scripts/run-simulator.sh offline
```

4. Pull to refresh Journey or tap refresh in Flights.

Expected result:

- The banner says `OFFLINE REPLAY` and the itinerary is marked stale.
- No provider request is made.
- The saved itinerary remains visible, but production timing candidates are not synthesized from demo numbers.
- If no itinerary was cached first, the app correctly shows **No itinerary**.

Entry records are keyed by a one-way fingerprint of the complete normalized traveler/itinerary query. Offline mode uses only an exact cached match. An expired record can be displayed for provenance but cannot support a positive landside or city result.

### Local learning

**Status:** on-device service implemented; only recommendation feedback is directly exercisable in the current UI.

Actions:

1. In Settings, confirm **Learn from resolved journey data** is enabled.
2. On Journey or Layover & Transit, tap **Use this plan** or **Not for me**.
3. Return to Settings and disable learning.
4. Tap **Erase learned model**.

Expected result:

- Feedback is stored on this device and can rank equally safe candidates.
- Disabling learning prevents new samples; it does not reinterpret visa rules or relax safety policy.
- Erasing removes the learned model file.
- Commercial live payloads train only when both a versioned local policy and the normalized source metadata authorize the exact use. All shipped commercial policies deny training by default. User-owned outcomes are separate.
- Visa and entry rules are never learned.

### Delete journey and offline data

Actions:

1. In Settings, tap **Delete journey and offline data**.
2. Confirm deletion.

Expected result:

- The current implementation clears the long-haul itinerary/profile cache and entry-requirement cache.
- Learned model data requires the separate **Erase learned model** action.
- The legacy flight-search cache is not currently cleared by this Settings action even though the dialog copy is broader. Treat this as a known issue before privacy acceptance.

## Live, demo, offline, stochastic, and replay launches

| Command | Expected behavior |
|---|---|
| `./Scripts/run-simulator.sh demo` | Named BKK-HND-LAX fixture and `DEMO FIXTURE`. |
| `AIRPORTXR_SCENARIO=interAirport ./Scripts/run-simulator.sh demo` | Named HND-NRT transfer fixture. |
| `./Scripts/run-simulator.sh live` | Loads only a saved itinerary or shows none; it does not synthesize the named long-haul fixture. `LIVE REQUESTED` is intent, not proof of live data. |
| `./Scripts/run-simulator.sh offline` | Loads only saved data and marks time-sensitive facts stale. |
| `./Scripts/run-simulator.sh stochastic` | DEBUG-only unseeded fixture; the UI shows the generated replay seed. |
| `./Scripts/run-simulator.sh stochastic 7141337` | Replays the exact generated fixture inputs for seed `7141337`. |

To test replay:

1. Run `./Scripts/run-simulator.sh stochastic 7141337`.
2. Record the selected plan, probability interval, and trace seed.
3. Terminate and run the same command again.
4. Confirm those fixture-derived outputs match.

Live launches remain naturally variable because time, network state, provider data, location, cache, and learned state can change. The safety policy itself should not randomly change; stochastic launch mode is a QA tool.

## Cross-device reminders

**Status:** foundation only. The planner, EventKit adapter, Google Tasks Worker route, and deterministic tests exist. Settings controls, adapter instantiation, Google OAuth, and automatic runtime synchronization are not wired.

Implemented reminder intents:

- Go to gate, only when a derived future `leaveBy` exists.
- Gate close, only from a current sourced gate-close metric.
- Latest return, only for a `Safe` candidate with no unresolved trace inputs.

There is no hidden “10 minutes before” value. Unknown, expired, unsafe, or past inputs create no reminder.

Run the iOS foundation tests:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
xcodebuild \
  -project AirportXRCompanion.xcodeproj \
  -scheme AirportXRCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:AirportXRCompanionTests/CrossDeviceReminderTests
```

Run the mocked Google Tasks contract tests:

```bash
cd /Users/anony/Downloads/AirportXRCompanion/Backend
npm test
```

Expected result:

- Tests prove stable IDs, update-not-duplicate behavior, consent gates, local airport-date conversion, OAuth token exclusion from the body, and scoped deletion.
- They do not create a real calendar event or Google task and do not prove delivery on another device.

Apple Calendar can provide an exact-time alarm only after explicit full-calendar permission and selection of a calendar account that syncs to the user's other devices. Google Tasks requires user OAuth, not an API key. Its API preserves only a due date, so Airport XR writes the exact intended instant into notes while Google controls notification timing. A physical two-device test is required after configuring real accounts and permissions.

## Optional AI and free/trial services

**Status:** backend-only grounded AI explainer; no iOS button or renderer is wired. Entry-link discovery is backend-capable when Gemini is configured.

The safest demo is the deterministic Worker test suite:

```bash
cd /Users/anony/Downloads/AirportXRCompanion/Backend
npm install
npm test
npm run check
```

Expected result:

- The Cloudflare Workers AI adapter can only reorder already-sourced fact IDs.
- Deterministic Worker code renders values, formulas, sources, hours, and URLs.
- Malformed or unavailable AI output falls back to the original deterministic order.
- Entry, visa, passport, nationality, and immigration content is rejected before inference.
- No raw model prose can change a safety or entry decision.

Options considered as of 2026-07-14:

- **Cloudflare Workers AI:** implemented through an `AI` binding; Cloudflare currently documents a limited daily free allowance. Quotas and model availability can change.
- **Gemini Developer API:** a free tier may be available. The current Worker uses it only for Google Search citations on allowlisted government domains when `GEMINI_API_KEY` is configured. Unpaid-service data terms require extra caution; do not send traveler profiles or documents.
- **Apple Foundation Models:** future on-device option on supported Apple Intelligence devices; no API key or metered web call, but not available on every supported iPhone and not wired here.
- **Hugging Face Inference Providers:** useful for experiments with a small changing starter credit; not integrated into this build.

AI availability is never evidence that flight, visa, queue, weather, hotel, or transport data is live.

## Delay prediction and flight/baggage capacity

### Delay prediction

**Status:** implemented research outlook with live keyless weather context and local historical observations; airport-congestion feeds remain provider-dependent.

The Journey screen shows a short passenger-facing delay outlook. It combines the route/time running statistic with the current weather state when enough matching historical observations exist. The keyless weather path prefers the latest AviationWeather.gov airport observation and falls back to Open-Meteo. Refresh bypasses the URL cache and shows separate observation and check times. An unchanged temperature after refresh can be correct because the upstream station/model has not issued a newer observation.

Therefore, during a demo:

- describe the value as an outlook learned from matching route/time and weather history, not an airline guarantee;
- say “We don't have enough information yet” when the model lacks matching observations;
- do not claim live runway congestion, inbound-aircraft state, or news sentiment unless a configured provider supplied those inputs.

### Overbooking and luggage space

**Status:** unavailable.

The traveler profile distinguishes cabin-only, checked-through, collect-and-recheck, and unknown baggage handling. That is not aircraft capacity data. The current model and providers do not know whether a flight is overbooked, whether standby passengers will clear, whether checked-bag acceptance has closed, or whether overhead-bin space remains. Seat-map gaps are not treated as proof of unsold capacity.

The correct demo result for these questions is `Unknown — verify with the operating airline or gate agent`.

## Automated acceptance commands

The 2026-07-14 synchronized local snapshot passed a clean application build, 78 unit tests, 13 UI tests, 37 Worker tests, the Worker check, and a Wrangler dry run. Ordinary simulator launches were also reviewed in demo, offline, stochastic, live-requested, and HND-to-NRT modes. The evidence logs and screenshots are listed in the canonical report.

Run all iOS unit and UI tests:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
./Scripts/test.sh
```

Run only deterministic unit tests:

```bash
cd /Users/anony/Downloads/AirportXRCompanion
xcodebuild \
  -project AirportXRCompanion.xcodeproj \
  -scheme AirportXRCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:AirportXRCompanionTests
```

Run the Worker tests:

```bash
cd /Users/anony/Downloads/AirportXRCompanion/Backend
npm test
npm run check
```

Check the command output from the current checkout; do not repeat a historical pass count as proof for changed source.

## Demo caveats and acceptance checklist

- [x] The visible mode and freshness badges match the actual source.
- [x] No demo route is called live or fastest.
- [x] Missing critical inputs remain `Unknown` or `Requires confirmation`.
- [x] Entry guidance links to official sources and never promises admission.
- [x] City and inter-airport activities never displace the mandatory transfer/gate plan.
- [x] Work pods, hotel, shower, and lounge records show the correct access zone.
- [x] Hotel/day-room availability is not inferred from a nearby POI result.
- [x] AR simulator behavior is separated from physical-device tracking evidence.
- [x] Local OCR remains advisory; cloud OCR is described as not wired.
- [x] Reminder and AI surfaces accurately distinguish local runtime and backend-only behavior.
- [x] Weather-aware delay outlook and overbooking/luggage-capacity limitations are described accurately.
- [x] VoiceOver, Dynamic Type, contrast, and reduced-motion paths are covered by the current automated UI suite; ordinary screenshots were visually reviewed.
- [ ] A physical-device camera/AR test and a two-device calendar/task synchronization test remain separate acceptance work.

## Where to learn more

- [Developer guide](DeveloperGuide.md)
- [Architecture](Architecture.md)
- [Live data and freshness plan](LiveDataPlan.md)
- [Data sources and licensing](DataSources.md)
- [Cross-device reminder design](CrossDeviceReminders.md)
- [Optional AI integrations](AIIntegrations.md)
- [Privacy and security](PrivacyAndSecurity.md)
