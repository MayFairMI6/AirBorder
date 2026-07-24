# Airport XR Companion UX plan

## Product promise

Give a long-haul international traveler one defensible next action while making uncertainty, source freshness, access zone, and the return deadline visible. The experience remains useful with no network, weak localization, accessibility needs, and airport changes.

The detailed research review, rationale matrix, accessibility contract, and seven annotated wireframes are in [UIUXReview.md](UIUXReview.md). Editable Figma foundations are at [Airport XR Companion wireframes](https://www.figma.com/design/MgNQlseRuiBCZvDjXnsvHi?node-id=3-31); the seven phone frames remain pending because the Figma Starter MCP quota was exhausted.

## Six-tab information architecture

1. **Journey** - ordered multi-leg timeline, active layover, current data mode, safest action, decision status, and trace.
2. **Flights** - add, edit, reorder, remove, and refresh itinerary legs.
3. **AR Guide** - active-airport route maneuver, progress, recovery, and map fallback.
4. **Map** - terminal graph, route mode, level, current node, gate, and confidence.
5. **Layover & Transit** - Airside, Airport Landside, Nearby, and City layers; facilities, accommodation discovery, HND-NRT transfer, and visit feasibility.
6. **Settings** - minimal traveler profile, accessibility, personalization, privacy, learning controls, and data erasure.

Six roots are retained because each is an explicitly required product surface. Native `TabView` behavior may place an item under More on compact devices; labels and navigation titles remain stable and accessible.

## Decision hierarchy

Every time-critical screen follows this order:

1. safest action;
2. consequence and deadline;
3. status plus source mode/freshness;
4. primary action;
5. alternatives and facilities;
6. formula, provenance, and limitations on demand.

This reflects the successful pattern documented by travel products such as Flighty: the changing flight fact and next action stay front and center, while details remain available without overwhelming the first scan.

## Principal flows

### Long-haul itinerary

Add or find each leg, then reorder/edit it in Flights. Journey shows local departure/arrival times and explicitly inserts airport-change sectors. Overnight and date-line transitions are represented by absolute dates plus airport timezones, not by subtracting clock labels.

### Same-airport layover

Journey leads with Go to Gate. Layover & Transit separates airside facilities from landside/nearby/city plans. A city result cannot be positive without current entry, border, queue, outbound/return transit, last service, weather, security, terminal-route, and gate-close inputs.

### HND to NRT airport change

Journey and Layover & Transit lead with Start HND to NRT transfer. The screen says “arrive at NRT first,” shows a derived arrive-by target only when every post-arrival component is sourced, ranks complete transfer options, and places visits after the transfer. Demo results say “Leading demo option - not live,” never “fastest.”

### Facility and hotel planning

Official/operator HND records remain visually distinct from MapKit discovery and optional hotel availability. Terminal 3 work cubicles are Airport Landside; the transit hotel is Airside; Terminal 3 showers are Airport Landside. Day-room/transit claims need an explicit record. Booking opens an external link; the app does not take payment.

### Entry check

The traveler supplies nationality, residence, passport type, declared visas/permits, purpose, luggage, and accessibility needs—never a passport number or scan. The result is informational, shows its expiry and provider, and links to official verification. Expired/unknown results cannot authorize a landside or city recommendation.

### In-flight progress and OCR

Saved itinerary time estimates work offline. A traveler may select a seatback-display still for local Vision OCR. Window-view geolocation remains experimental and low-confidence; neither signal can drive entry, boarding, city, or navigation safety.

### Why this recommendation?

The trace explains available window, every required-time segment, source record, uncertainty, simulation seed, Wilson interval, latest return, unresolved values, and policy version. It is progressive disclosure, not the first screen.

## State and copy rules

- `Live`: current provider result with receipt/source times.
- `Cached`: retained within policy; show age.
- `Stale`: visible but cannot satisfy a current safety prerequisite.
- `Demo`: named fixture; never imply live availability or fastest route.
- `Unknown`: keep absent; provide the exact confirmation needed.
- `Offline`: preserve itinerary, official registry, terminal graph, and local model while suppressing live claims.
- `Stochastic`: DEBUG QA scenario with a recorded replay seed.

## Accessibility contract

- Use text and symbols in addition to color.
- Keep primary targets at least 44 by 44 points.
- Reflow metrics/actions vertically at accessibility Dynamic Type sizes.
- Use an inline access-layer picker when a segmented control would truncate.
- Combine related status text in VoiceOver order: action, deadline, state, source.
- Respect Reduce Motion; do not require animation to understand progress.
- Apply accessibility constraints to routing and timing, not only presentation.
- If elevator/accessibility status is unknown, do not claim an accessible transfer.

## Acceptance tasks

1. Identify the current data mode and safest action on Journey.
2. Add and reorder three or more international legs across timezones.
3. Explain why a landside/city plan is safe, tight, not recommended, or unknown.
4. Find HND work cubicles, transit hotel, showers, lounge, Airport Garden, and nearby discovery with correct zones.
5. Complete a personalized entry check without entering document identifiers.
6. Start HND-NRT transfer before considering a post-transfer visit.
7. Replay a stochastic scenario from its logged seed.
8. Complete the principal flow with VoiceOver, accessibility text, Reduce Motion, and offline mode.
