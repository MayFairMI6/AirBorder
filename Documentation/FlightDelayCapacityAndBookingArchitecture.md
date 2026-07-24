# Flight delay, airline capacity, booking, and connection-baggage architecture

Status: implemented provider-neutral iOS domain/service contracts plus an honest Flights `Book & bags` surface and deterministic fixtures; no production provider adapter or in-app ticketing is enabled.

Date: 2026-07-14

## Product truth rules

1. **Official status remains authoritative.** A delay prediction is optional scenario context. It never overwrites a `Flight.status`, gate, airline estimate, cancellation, or airport display.
2. **No model means no prediction.** Missing, invalid, stale, identity-mismatched, or untraceable inputs return `unavailable`; they are not replaced with zero or a bundled average.
3. **A distribution replaces a made-up point value.** A model returns ordered delay quantiles and, when supplied by that model, exceedance probabilities. This layer contains no universal “delay minutes” constant.
4. **Commercial facts have evidence levels.** An airline order/PNR, airline operations record, current airline/NDC offer, fare-inventory signal, and seat map are not interchangeable.
5. **A seat map is not a load sheet.** Open, blocked, or occupied seats do not prove that a flight is or is not oversold and do not establish overhead-bin capacity.
6. **Through-check is connection-specific.** Only a current airline operations/order/PNR/airline-offer/NDC-offer record may assert `throughChecked`. Matching carriers, an alliance, fare inventory, or a seat map is downgraded to `confirmationRequired`.
7. **Booking stays external.** The app may display a current verified priced offer and open a validated HTTPS handoff. It does not collect payment, issue a ticket, or claim that an expiring offer is a reservation.

## Implemented contracts

The implementation is in:

- `Models/FlightOperationalIntelligenceModels.swift`
- `Services/FlightOperationalIntelligenceService.swift`
- `Services/LongHaul/FlightOperationalReferenceFixtures.swift`
- `Views/Flights/FlightsView.swift`
- `AirportXRCompanionTests/FlightOperationalIntelligenceTests.swift`
- `AirportXRCompanionUITests/FlightBookAndBagsUITests.swift`

### Delay context

`FlightDelayFeatureProvider` assembles a `FlightDelayFeatureSnapshot`. Every `SourcedFlightDelayFeature` records:

- feature kind and physical unit;
- provider and exact provider field;
- source-record identifier;
- observed, received, and provider-policy expiry times;
- uncertainty and derivation steps.

Weather, airport congestion, inbound rotation, and schedule features are separate categories. Examples include wind gust, visibility, ceiling, precipitation, convective probability, observed airport delay, demand-to-capacity ratio, traffic-management indicators, inbound-aircraft arrival delay, turn slack, aircraft swap, and scheduled block time. Provider adapters should populate only fields they actually receive or derive with a trace.

`FlightDelayModel` exposes a versioned `FlightDelayModelDescriptor` with its target, required features, algorithm family, training-policy version, and calibration dates. `FlightDelayContextService` rejects:

- an absent model;
- provider failure or a snapshot for the wrong flight;
- missing, invalid, stale, or freshness-unknown required features;
- output that uses missing/stale features or drops declared required features;
- crossing/non-monotone quantiles, invalid probabilities, the wrong target, or an already expired prediction.

An accepted `FlightDelayPrediction` carries its distribution, exact model version, feature revision, source record IDs, trace, and expiry. `layoverScenarioInput(officialFlight:)` preserves the official status and effective arrival beside an optional arrival-delay distribution. A departure-only model is not silently converted into arrival uncertainty.

### Capacity and baggage facts

`AirlineCommercialFactsProvider` can return traveler baggage allowance, seat availability, an explicit overbooking observation, and cabin-bin context. `AirlineCapacityNormalizer` applies the following matrix:

| Claim | Evidence that may support it | Evidence that remains a proxy |
|---|---|---|
| Ticketed traveler's baggage allowance | current airline order or PNR | general airline policy or NDC offer can describe an allowance but is not promoted to the ticketed traveler |
| Traveler has a confirmed seat/reservation | current airline order or PNR | seat map, NDC shopping response, or fare availability |
| Airline confirms flight oversold/not oversold | current airline operational-control fact | PNR, seat map, fare inventory, third-party estimate |
| Airline guarantees bin space for traveler | explicit current airline operational fact | boarding group, seat map, fare inventory, load estimate |

An estimate may still be displayed as an estimate, with its probability and provenance, but cannot become a guarantee. If no suitable provider is configured, all four facts are explicitly unknown.

### Priced offers and booking handoff

`PricedFlightOfferProvider` returns current airline/NDC offer facts. Offers retain exact decimal price text and ISO currency, ordered flight legs, quoted baggage information, provider expiry, and `externalHandoffOnly` role. The catalog rejects stale facts, unverified sources, invalid legs/prices, and an offer whose own expiry exceeds its source fact's permitted lifetime.

`ExternalBookingHandoffProvider` returns a current source-bound handoff for the same offer. The handoff must be HTTPS, unexpired, identity-matched, and explicitly external. There is deliberately no payment or ticket-issuance protocol in the app domain.

### Connection baggage and additive timing

`ConnectionBaggageProvider` returns one of:

- `throughChecked`;
- `reclaimImmigrationCustomsRecheck`;
- `selfTransferSeparateTicket`;
- `confirmationRequired`;
- `unknown`.

`ConnectionTransferPlanBuilder` translates verified connection handling and independently sourced timing inputs into additive segments:

```text
baggage wait
+ immigration / border processing when required
+ customs processing when required
+ landside connection movement
+ bag drop / check-in work, constrained by its actual cutoff
+ security screening
+ inter-airport travel when arrival and onward airports differ
```

The reclaim state explicitly requires baggage, border, customs, landside, recheck, and security components. A separate-ticket self-transfer requires baggage, landside, recheck, and security; border/customs can be added from the connection's entry/access-zone context. HND-to-NRT automatically requires a separately sourced `interAirportTravel` segment because the airport codes differ. No duration is generated by the builder. A required missing/stale duration or missing bag-drop cutoff remains unresolved and prevents a positive recommendation.

Each connection-specific segment also maps to an existing `PlanSegment`, so the layover probability engine can consume it immediately while the more precise connection kind remains in the calculation trace.

## Flights UI handoff per connection

The Flights itinerary now renders one connection card between each adjacent leg in its third `Book & bags` mode, keyed by itinerary ID plus inbound/outbound leg IDs. It does not collapse baggage state into a generic “bags” checkmark.

| State | Primary UI treatment | Required detail |
|---|---|---|
| `throughChecked` | “Through-checked” with a verified-source badge | bag-tag destination when supplied, operating source, observed/expiry time, and “confirm printed tag at check-in” |
| `reclaimImmigrationCustomsRecheck` | “Reclaim and recheck” action sequence | baggage reclaim → immigration/border → customs → landside → recheck cutoff → security; include inter-airport step when airports differ |
| `selfTransferSeparateTicket` | “Self-transfer / separate ticket” high-consequence label | no protected rebooking or through-bag assumption; show every known cutoff, missing input, and operating-airline verification link |
| `confirmationRequired` | “Confirm baggage handling” warning | explain why a carrier/alliance/seat-map proxy was insufficient and link to the operating airline |
| `unknown` | “Baggage handling unknown” blocking state | do not show a positive connection/city recommendation; list the exact missing provider/session fact |

Every card exposes verification, provider, observed time, bag-tag destination, separate-ticket flag, instructions, data-mode badge, exact segment list, bag-drop cutoff, and unresolved facts. The seeded `FlightOperationalReferenceFixtures.bkkHndLax(...)` fixture supplies a `.demo`-labeled through-check fact with a demo LAX bag tag. The seeded `hndToNrt(...)` fixture supplies a `.demo`-labeled reclaim/recheck HND→NRT card, sourced segment distributions, bag-drop cutoff, and external offer. Their recorded seeds support exact replay and none of their numbers are production claims. Live/offline cards remain unknown because no production connection-baggage provider is configured.

The same mode includes route, date, and adult-traveler offer inputs. Demo search returns only the exactly matching named fixture and labels it `NOT LIVE OR BOOKABLE`; any other demo query is unavailable. Live mode is explicitly unavailable until a current verified airline/NDC offer adapter exists, and offline mode refuses to present cached short-lived pricing as current. The only continuation control is an HTTPS external handoff; payment and ticket issuance remain outside Airport XR Companion.

The third mode keeps operational connection work visible without overloading flight search or the airport board. Cards follow itinerary order because baggage handling is a property of a specific adjacent-leg connection, not of an airport in isolation. Text, symbols, and provenance accompany color so the state remains understandable with color-vision differences and assistive technology. Required components are expanded rather than compressed into a risk score because passengers need to see exactly which physical steps and airline cutoff drive feasibility.

The risk engine receives these fields as follows:

- official estimated/actual inbound arrival remains the timeline authority;
- optional calibrated **arrival-delay distribution** perturbs inbound arrival in correlated scenarios only;
- `baggageWait`, `borderProcessing`, `customsProcessing`, `landsideTransfer`, `bagDropAndCheckIn`, `securityScreening`, and `interAirportTravel` distributions add to required time;
- the bag-drop/check-in deadline and onward airline operational cutoff are hard constraints, not average-duration terms;
- source expiry and `unresolvedInputs` block a positive result;
- separate-ticket status increases consequence/tail-loss inputs (for example CVaR), but never fabricates extra minutes by itself.

## Provider adapters and source boundaries

These are integration candidates, not claims that every field is available in every plan, region, or contract.

| Need | Candidate official source | Boundary and rationale |
|---|---|---|
| General current/forecast weather | [Apple WeatherKit REST API](https://developer.apple.com/documentation/weatherkitrestapi) | Provides general weather context. It is not an aviation operational source; retain field timestamps and attribution. |
| Aviation observations and forecasts | [AviationWeather.gov Data API](https://aviationweather.gov/data/api/) | Official machine interface for products including METAR and TAF. Raw aviation fields should be normalized, never converted to a hidden severity score without a derivation trace. |
| U.S. airport congestion/events | [FAA NAS Status](https://nasstatus.faa.gov/) and [FAA TFMData service description](https://cdm.fly.faa.gov/faq) | NAS Status exposes current airport events; TFMData includes near-real-time flight and traffic-management information for authorized consumers. FAA airport status is general rather than flight-specific, so airline status still wins. |
| Licensed operational flight context | [FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) | Official product documentation lists flight status, ETAs, positions, historical data, and alerts. Use only licensed fields and retention/training rights. |
| Flight status/delay model candidate | [Amadeus flight APIs guide](https://developers.amadeus.com/self-service/apis-docs/guides/developer-guides/resources/flights/) | The current catalog documents on-demand flight status and flight-delay prediction. Normalize returned probabilities rather than relabeling them as certainty. |
| Test versus live behavior | [Amadeus test-data guide](https://developers.amadeus.com/self-service/apis-docs/guides/developer-guides/test-data/) | The official guide states that test flight-status data is a copy and does not receive real-time updates. Test responses must be labeled fixture/test, not live. |
| Offers, orders, seats, baggage | [IATA NDC overview](https://www.iata.org/en/programs/airline-distribution/retailing/ndc/) | NDC is an Offer/Order data-exchange standard, not a universal public airline API. Access still requires an airline/aggregator relationship. |
| Flight offers, order flow, baggage quote, seat maps | [Amadeus flight APIs guide](https://developers.amadeus.com/self-service/apis-docs/guides/developer-guides/resources/flights/) | The guide documents flight offers, orders, baggage allowances, and seat-map availability states. A shopping offer is not a ticketed order. |
| Seat-map interpretation limits | [Amadeus API FAQ](https://developers.amadeus.com/self-service/apis-docs/guides/developer-guides/faq/) | The official FAQ distinguishes available, blocked, and occupied, and notes carrier/codeshare data gaps. Therefore treating seat-map counts as aircraft load or oversale proof would be an unsupported inference. |

No verified public, universal API was found that guarantees aircraft overbooking status or remaining overhead-bin space to consumer apps. Production support therefore requires a specific operating-airline/authorized distribution integration; otherwise the app reports proxy/unknown and links to the airline.

## Preferred advanced algorithms

The domain accepts several model families without embedding one unvalidated model.

### 1. Quantile and survival models

Train quantiles directly for arrival delay (D_a):

```text
q_tau(x) = model_tau(weather, congestion, inbound rotation, schedule, route)
```

Gradient-boosted quantile regression is a strong tabular baseline because it produces asymmetric p10/p50/p90 values without assuming a Gaussian tail. A survival or accelerated-failure-time model is useful while a flight is unresolved, but cancellations/diversions should be modeled as competing events rather than quietly treated as ordinary censored delays.

### 2. Hierarchical partial pooling

Sparse route/hour combinations should shrink toward carrier, airport, region, and season effects instead of memorizing tiny samples. This is particularly valuable for global long-haul routes with infrequent service.

### 3. Conformal calibration

Apply rolling, horizon-aware conformal correction to the base quantiles. The correction is learned from held-out residuals and versioned by calibration window. Coverage is measured after deployment by airport, route, carrier, prediction horizon, and disruption regime. If drift breaks coverage, widen or withdraw the interval rather than displaying false precision.

### 4. Correlated operational scenarios

Connection components are not independent: the same storm can affect inbound arrival, airport queues, surface transport, and onward operations. Sample a shared weather/congestion/rotation factor or fit a copula/factor residual model, then evaluate:

```text
P(
  official/predicted inbound arrival
  + deplane + baggage + border + customs
  + landside/inter-airport travel
  + bag drop + security + terminal route
  <= onward operational cutoff
)
```

This avoids the optimistic result produced by independently sampling every segment.

### 5. Tail-risk optimization

Rank plans using both success probability and conditional value at risk (CVaR) of missed-connection loss:

```text
CVaR_alpha(L) = E[L | L is in the worst (1 - alpha) tail]
```

CVaR can account for separate-ticket replacement cost, overnight exposure, accessibility impact, and checked-bag consequences. It should be Pareto/lexicographic decision support, not an unexplained scalar score.

### 6. Time-dependent multimodal routing

Use time-dependent RAPTOR/connection-scan for public transport and time-dependent A* for road/terminal graphs. Preserve last-service, service-calendar, elevator outage, bag-carrying accessibility, and transfer-cutoff constraints. HND-to-NRT should compare feasible departure-time-specific alternatives, not a static “fastest minutes” number.

### 7. Calibration and drift metrics

Monitor pinball loss for quantiles, CRPS for the full distribution, Brier/reliability curves for exceedance probabilities, probability-integral-transform diagnostics, and conformal empirical coverage. Track data/schema drift separately from outcome drift. A model that lacks recent calibration evidence returns unavailable or wider uncertainty.

This delay layer emits a calibrated distribution; it does not hard-code the product's `0.90` or `0.70` action thresholds. Those belong to a versioned, reviewable safety/decision policy and can be evaluated against risk tolerance, consequence severity, and calibration evidence without retraining the forecast model.

## Learning, privacy, and license constraints

- Provider payloads may train a model only when the exact contract permits that exact purpose. A generic API key or caching right is not ML-training authorization.
- Keep the existing dual authorization: bundled provider policy and normalized response metadata must agree on provider, policy version, and training purpose.
- Use finalized official departure/arrival outcomes as labels only when licensed. Prevent time leakage by reconstructing the features that were actually known at the prediction timestamp.
- Store aggregate residual/model state rather than raw commercial payloads whenever the contract requires it.
- User-reported outcomes and device-measured connection residuals can support private on-device personalization. They cannot rewrite visa, baggage, airline cutoff, or overbooking facts.
- Order-session handles are short-lived and intentionally non-Codable. Do not persist or log raw PNRs, airline session credentials, passenger names, or ticket numbers.
- Offers, handoffs, capacity facts, and predictions are usable from cache only until their recorded provider expiry. Absence of an expiry is unknown freshness and is rejected for these operational decisions.
- Model erase/disable controls and anonymous-sharing consent remain independent. No commercial-provider training occurs merely because personalization is enabled.

## Verification coverage

Deterministic tests cover:

- unavailable delay behavior without a model;
- stale required features;
- weather + congestion + inbound-rotation provenance;
- valid arrival distribution handoff while preserving official status;
- rejection of crossing quantiles and departure-only layover substitution;
- seat-map/fare proxies unable to confirm oversale or guarantee bin space;
- PNR baggage facts versus unknown capacity;
- NDC quote not promoted to a ticketed-traveler allowance;
- verified priced offer and HTTPS-only external handoff;
- carrier matching unable to assert through-check;
- verified PNR through-check acceptance;
- sourced reclaim/recheck HND-to-NRT segments;
- missing bag-drop cutoff blocking a positive connection recommendation; and
- seeded BKK-HND-LAX through-check/LAX bag-tag data that cannot masquerade as live.

Focused UI coverage checks the demo BKK→HND→LAX through-check/LAX bag tag and external-offer preview, plus HND→NRT reclaim, border, customs, recheck, security, inter-airport, and cutoff presentation.

The entire iOS app source, including the new Flights surface, type-checks against the iPhone Simulator SDK. Test sources parse, but a full XCTest run requires regenerating the project so the new globbed files enter the project; that regeneration is intentionally left to the coordinating build step to avoid racing concurrent project-file work.

## Limitations

- No production weather, congestion, rotation, capacity, order, NDC, or booking adapter is implemented in this change.
- No live credentials were used, so no live contract test was run.
- A model trained elsewhere still needs a signed/versioned artifact loader, calibration report, drift monitor, rollback path, and license review.
- Airline commercial facts vary by operating carrier, codeshare, region, fare, loyalty status, and distribution agreement. Unknown is an expected product state.
- External booking availability can change after handoff. The provider/airline remains responsible for price confirmation, payment, fulfillment, ticketing, and post-booking service.
