# Airport XR Companion UI/UX review

Date: 2026-07-14  
Review scope: current SwiftUI implementation, BKK-HND-LAX long-haul flow, and HND-NRT inter-airport transfer  
Design target: iPhone, native SwiftUI, semantic system colors, Dynamic Type, VoiceOver, Reduce Motion  
Status: implementation-ready review; the Figma foundations page is editable, while the seven product screens are specified below because the authenticated Figma Starter plan reached its MCP call limit

## Executive outcome

The product has the right safety-oriented foundation: it labels demo data, leads with `Go to Gate` or the mandatory airport change, preserves unknown values, links to official entry sources, and keeps seatback OCR local. The interface will become substantially easier to use under travel stress if it follows one consistent rule:

> Show the safest next action, the reason it is safe or unresolved, and the deadline first. Put exploration, comparisons, formulas, and provider detail one level deeper.

The most important remaining UI work is:

1. Remove a nested `NavigationLink` from inside a plan-selection `Button` in the layover list.
2. Give HND-NRT a prominent transfer action and an explicit latest safe arrival/check-in target before showing optional stops.
3. Never label a demo inter-airport option “fastest.” Use “leading demo option” until a current, complete route snapshot supports that claim.
4. Make the four access layers and the two-column metric layouts adapt at accessibility text sizes.
5. Replace nationality and residence code text fields with searchable country pickers.

## Research basis

This review used primary or first-party sources and translated their recurring interaction patterns into the Airport XR context.

| Source | Observed pattern | Application here |
|---|---|---|
| [Apple, Behind the Design: Flighty](https://developer.apple.com/news/?id=970ncww4) | Key information is front and center; the interface borrows familiar airport visual conventions; live maps and glanceable system surfaces reduce effort. | Put the active layover, deadline, gate/airport, and one next action above the itinerary and discovery content. |
| [Apple Human Interface Guidelines: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) | Root destinations should remain stable and labels should clearly describe their content. | Preserve the six root destinations, but use a compact tab label such as `Transit` while keeping the full screen title `Layover & Transit`. Validate the resulting system “More” behavior on compact iPhone widths. |
| [Apple Human Interface Guidelines: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | The most likely action should receive the prominent treatment; iPhone targets should generally be at least 44 by 44 points. | Only `Go to Gate`, `Start HND → NRT transfer`, `Save and reassess`, or `Choose photo` is prominent on its screen. |
| [Apple Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/) | Interfaces should be perceivable without relying on one channel, support large text, use simple interactions, and respond to Reduce Motion. | Every status combines a word and symbol with color; grids become lists; moving route cues become static progress when Reduce Motion is enabled. |
| [Apple Human Interface Guidelines: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) | Ongoing tasks should be concise and glanceable, show only the essential state, and avoid sensitive information. | A future layover Live Activity should show airport/gate, time to act, and the next action—not passport, visa, hotel, or detailed itinerary data. |
| [Flighty product site](https://flighty.com/) and [Flighty feature list](https://flighty.com/help/why-subscribe) | A current flight timeline, connection assistant, explicit cause/state, offline access, and system-level updates are established patterns in successful travel tools. | Treat the active connection as a task state, not a generic dashboard. Explain why a plan changed and keep the last useful plan available offline. |
| [Fly Delta app](https://www.delta.com/us/en/delta-digital/mobile) | “Today” consolidates boarding pass, status, gate, maps, bags, and day-of-travel actions. | `Journey` is the day-of-travel home. Other tabs remain specialized tools, not competing dashboards. |
| [TripIt itinerary and navigation features](https://www.tripit.com/web/free) and [Go Now](https://help.tripit.com/en/support/solutions/articles/103000063349-go-now) | A unified itinerary, airport maps, nearby places, point-to-point navigation, and a contextual leave-now action are familiar travel patterns. | Use one ordered journey timeline and convert “return now” from a passive warning into a persistent, contextual action. |
| [Haneda Airport: From Haneda to Narita](https://tokyo-haneda.com/en/access/narita/index.html) | Haneda presents rail and bus as separate modes and explicitly warns that durations and fares can change. | Compare modes as ranges with source freshness; do not collapse them into a single hidden score or promise a fastest option without current data. |
| [Haneda work-pod listing](https://tokyo-haneda.com/en/service/facilities/work_box.html), [hotel listing](https://tokyo-haneda.com/en/service/facilities/hotel.html), and [facility directory](https://tokyo-haneda.com/en/service/facilities/index.html) | Official facility records establish identity and access context, while availability still needs confirmation. | Lead each facility card with access zone, terminal, current-hours state, and source; treat booking as an external secondary action. |

Research synthesis:

- Current-context home screens outperform feature menus during a travel day.
- A vertical timeline is the most legible representation of a multi-leg itinerary and an airport-change surface sector.
- A single prominent action lowers decision cost when a gate, boarding time, or return deadline is approaching.
- Confidence and freshness are user-facing content, not diagnostic metadata.
- Maps and nearby discovery are useful only after access, entry, baggage, and return constraints are clear.
- Formula detail builds trust when it is progressively disclosed instead of occupying the primary scan path.

### 2026-07-16 airline itinerary and indoor-guidance revision

Additional first-party research used [Apple Wallet's upgraded boarding-pass structure](https://developer.apple.com/videos/play/wwdc2025/202/), [British Airways' day-of-flight app description](https://apps.apple.com/gb/app/british-airways/id284793089), [Fly Delta's Today experience](https://content.delta.com/content/www/global/en/delta-digital/mobile.smt-member.html), [Emirates' real-time app fields](https://www.emirates.com/english/book/about-booking-online/emirates-app/), and [JAL's at-a-glance live flight information](https://apps.apple.com/jp/app/japan-airlines/id351785536?l=en-US).

The revised itinerary follows the shared hierarchy rather than copying one airline's branding:

- flight number and status appear first because they identify the operating event and current state;
- departure and arrival airport codes anchor the route, with large local gate times directly beneath them;
- each endpoint owns its own short local date, city, terminal, and gate, avoiding one ambiguous cross-time-zone sentence;
- a `+1 day` or negative-day marker makes overnight and date-line arrival explicit;
- boarding time, departure gate, and boarding group form the immediate action row;
- the same component appears on Journey and Flights so editing a leg does not change how its operational facts are read;
- the app keeps native Dynamic Type, semantic colors, system status symbols, and a textual route summary instead of imitating an airline logo or proprietary visual identity.

Indoor guidance now distinguishes three layers. `TerminalRouteLocationEmulator` provides repeatable local-map readings for simulator QA. ARKit provides camera-relative motion only on physical hardware. A future venue adapter can supply IMDF/indoor-positioning, beacon, UWB, or surveyed visual-anchor readings through the same local point/floor boundary. See [IndoorPositioningArchitecture.md](IndoorPositioningArchitecture.md).

## Information architecture

Keep the six stable root destinations:

| Root | Job to be done | First content |
|---|---|---|
| Journey | “What do I need to do now?” | Active airport/layover, deadline, safest action, itinerary |
| Flights | “What are my ordered legs and have they changed?” | Editable/reorderable legs, refresh state |
| AR Guide | “Guide me through this terminal.” | Current maneuver and remaining derived distance |
| Map | “Show the active terminal or transfer geography.” | Current route, disruptions, accessible alternatives |
| Transit | “What can I safely do between flights?” | Access layer, mandatory transfer if any, recommendation |
| Settings | “What facts and preferences shape advice?” | Minimal traveler profile, learning/privacy controls |

On iPhone, the full `Layover & Transit` label is likely to compete for tab-bar width. The recommended compromise is `Transit` in the tab bar and `Layover & Transit` as the navigation title. If the full tab label is a hard product requirement, test the system-generated `More` behavior and VoiceOver order rather than drawing a custom six-item bar.

## Screen wireframes and rationale

The following wireframes are the source of truth for the seven Figma screens that remain to be drawn when the Figma quota resets. All example times, ranges, and probabilities must carry the on-screen `DEMO · NOT LIVE` label unless they come from a current provider snapshot.

### 1. Journey — BKK-HND-LAX

```text
┌──────────────────────────────────────┐
│ Journey                       Refresh│
│ [DEMO · NOT LIVE] BKK-HND-LAX fixture│
├──────────────────────────────────────┤
│ ACTIVE LAYOVER             Gate 105  │
│ HND · Tokyo Haneda                   │
│ Gate-close window 6h 10m · JST       │
│                                      │
│ [      Go to Gate 105  →       ]     │
├──────────────────────────────────────┤
│ Your journey                          │
│ ● BKK  TG 660  Arrived               │
│ │ Bangkok time → Tokyo time          │
│ ◉ HND  Active layover                │
│ │ Airside plan available             │
│ ○ LAX  NH 106  Scheduled             │
├──────────────────────────────────────┤
│ Best current plan            [SAFE ✓]│
│ Work pod + shower, stay airside      │
│ Demo estimate · source snapshot      │
│ [Why this recommendation?]           │
├──────────────────────────────────────┤
│ Services   Rest & work   Entry check │
└──────────── system tab bar ──────────┘
```

Rationale:

- `Go to Gate` remains the only prominent control because it is the safest reversible action and matches Apple’s prominent-action guidance.
- The itinerary uses one continuous timeline. Local date, time, and zone belong on each leg; date-line changes should be called out inline rather than hidden in a detail view.
- The recommendation summary shows its classification and data mode before its probability. A passenger should understand “safe,” “tight,” or “requires confirmation” without interpreting statistics.
- Secondary actions are compact and appear after the gate action. At accessibility text sizes they become a single-column list.
- VoiceOver order: data mode → active layover and time zone → gate-close window → `Go to Gate` → ordered legs → recommendation → secondary actions.

### 2. Layover decision dashboard

```text
┌──────────────────────────────────────┐
│ Layover & Transit                    │
│ [Airside] [Landside] [Nearby] [City] │
├──────────────────────────────────────┤
│ RECOMMENDED NOW              [SAFE ✓]│
│ Work pod + shower, stay airside      │
│ Keeps border, queues, and return     │
│ transit out of the critical path.    │
│                                      │
│ 6h10 available   1h50 likely required│
│ Latest gate route start: 17:24 JST   │
│ [Use this plan] [Why this plan?]     │
├──────────────────────────────────────┤
│ Other layers                         │
│ Airport Garden   [CONFIRM ?]         │
│ Tokyo visit      [CONFIRM ?]         │
│ Missing: entry + queues + live return│
└──────────────────────────────────────┘
```

Rationale:

- Recommendations are compared across access zones, but only one is presented as current. This mirrors connection-assistant patterns without turning the screen into a booking marketplace.
- The explanation uses plain-language causal text first. Statistics and record-level provenance remain one tap deeper.
- A missing critical input is displayed next to the disabled or unresolved plan. Unknown is never rendered as zero.
- The four access layers may use a segmented control at standard sizes. At accessibility sizes, switch to an inline `Picker` or vertical list so labels are not truncated.
- `Use this plan` records a preference/outcome; it does not suppress later gate or return-now alerts.

### 3. Airport services, hotel, and work planning

```text
┌──────────────────────────────────────┐
│ Plan at HND                          │
│ Airside · Terminal 3                 │
│ [Work] [Rest] [Shower] [Food] [More] │
├──────────────────────────────────────┤
│ Work Pods                      [WORK] │
│ Official HND record                  │
│ T3 · Airside · Hours: confirm        │
│ Access: valid onward boarding pass   │
│ [Official details]                   │
├──────────────────────────────────────┤
│ Terminal 3 Transit Hotel       [REST] │
│ Official listing · availability open │
│ Day-room claim: not verified         │
│ [Check operator] [Open externally]   │
├──────────────────────────────────────┤
│ Nearby hotels                        │
│ MapKit discovery · not availability  │
│ [Refresh nearby]                     │
└──────────────────────────────────────┘
```

Rationale:

- Zone and terminal precede price or imagery because access is the first feasibility constraint in an airport.
- Official/operator evidence is visually distinct from MapKit discovery. A discovered hotel is not automatically a transit hotel or day room.
- Cards sort by: feasible access → open/current-hours state → terminal-route burden → traveler preference → name. Price is never the first sort key for a safety-oriented recommendation.
- Booking remains an external, secondary action. The primary action is source verification or route planning.
- VoiceOver card value includes category, zone, terminal, hours state, source type, and whether availability is confirmed.

### 4. Personalized entry check

```text
┌──────────────────────────────────────┐
│ Entry Check                          │
│ [INFORMATIONAL · VERIFY OFFICIALLY]  │
├──────────────────────────────────────┤
│ Japan transit / landside assessment  │
│ REQUIRES CONFIRMATION ?              │
│ Structured provider not configured.  │
│ [Open official Japan guidance ↗]     │
├──────────────────────────────────────┤
│ Traveler facts                       │
│ Nationality          [Choose country]│
│ Residence            [Choose country]│
│ Passport type        [Ordinary     ›]│
│ Purpose              [Transit      ›]│
│ Luggage              [Checked thru ›]│
│ Declared visas       [Add / review ›]│
│                                      │
│ No passport numbers or scans.        │
├──────────────────────────────────────┤
│ □ I reviewed current official rules  │
│ [        Save and reassess       ]   │
└──────────────────────────────────────┘
```

Rationale:

- Country search uses names and flags/region labels, storing normalized codes internally. Asking users to type ISO codes adds avoidable error during a high-consequence task.
- The outcome remains `Requires confirmation` until current structured guidance and user confirmation both support a landside plan. The checkbox can never weaken the safety floor.
- Official verification is near the assessment, not buried at the bottom.
- The privacy statement is short and concrete: the product never requests passport numbers or scans.
- VoiceOver announces `Informational entry assessment, requires confirmation, current/stale, provider, official link available` as one summary before the form.

### 5. Why this recommendation? — calculation trace

```text
┌──────────────────────────────────────┐
│ Why this plan?                       │
│ Work pod + shower           [SAFE ✓] │
├──────────────────────────────────────┤
│ Available window      370 min        │
│ Required, likely      110 min        │
│ Usable rest           350 min        │
│ On-time estimate      demo fixture   │
├──────────────────────────────────────┤
│ How it was calculated                │
│ 1 Available window                   │
│   gate close − inbound on-block      │
│ 2 Required time                      │
│   access + activity + return + safety│
│ 3 On-time probability                │
│   P(required ≤ available), 10k trials│
├──────────────────────────────────────┤
│ Sources & freshness              [›] │
│ Uncertainty and ranges           [›] │
│ Reproducibility                  [›] │
└──────────────────────────────────────┘
```

Rationale:

- Results precede derivation. The top section answers “what does this mean?”; subsequent disclosures answer “how do you know?”
- Monospaced typography is reserved for formulas, seeds, and record IDs. Raw provider record IDs should not appear in every default list row.
- Every step shows input range, source label, observation/expiry state, and derived result when expanded.
- Demo fixture values must be explicitly labeled; a live result must show the snapshot timestamp and provider freshness.
- VoiceOver reads each output as a label/value pair, then each derivation step as `step number, label, formula, result, source freshness`.

### 6. In-flight progress and offline seatback OCR

```text
┌──────────────────────────────────────┐
│ In-flight Progress       [OFFLINE ✓] │
├──────────────────────────────────────┤
│ Current leg · BKK → HND              │
│ BKK ●──────────✈────────────○ HND    │
│ Saved-time estimate · not live pos.  │
├──────────────────────────────────────┤
│ Seatback display OCR                 │
│ Read a cropped photo on this iPhone. │
│ The image is not uploaded.           │
│ [      Choose display photo      ]   │
│                                      │
│ After selection: Review crop → Read  │
│ Confidence 82% · cue only            │
├──────────────────────────────────────┤
│ This cue cannot change entry,        │
│ boarding, return-now, or city safety.│
└──────────────────────────────────────┘
```

Rationale:

- Progress is per active leg, not normalized across the first departure and last arrival of the whole itinerary. Whole-trip progress is misleading during a layover or date-line crossing.
- The privacy promise and offline state appear before photo selection.
- A crop-review step reduces accidental processing of unrelated cabin/passenger content.
- OCR confidence is a cue label, never a safety classification. A recognized value should require explicit confirmation before updating the low-confidence progress estimate.
- With Reduce Motion, the aircraft glyph remains static and the text value updates without animated travel along the path.

### 7. HND-NRT inter-airport transfer and optional interval visit

```text
┌──────────────────────────────────────┐
│ Airport change · Tokyo region        │
│ HND ───────── surface ───────── NRT  │
│ [DEMO · CURRENT LIVE TIMES MISSING]  │
├──────────────────────────────────────┤
│ ARRIVE AT NRT FIRST                  │
│ Target NRT check-in: 15:20 JST       │
│ Includes bags, entry, check-in,      │
│ security, terminal route, and margin.│
│ [       Start HND → NRT transfer ]   │
├──────────────────────────────────────┤
│ Compare modes                        │
│ Rail · official published range      │
│ 90–115 min · current service needed  │
│                                      │
│ Limousine bus · published range      │
│ 65–85 min · traffic/current service  │
│                                      │
│ “Fastest” unavailable without a      │
│ complete current route snapshot.     │
├──────────────────────────────────────┤
│ Places in the interval               │
│ [LOCKED] Secure NRT buffer first     │
│ Tokyo Station stop · confirm route,  │
│ entry, bags, weather, and last service│
└──────────────────────────────────────┘
```

Rationale:

- The airport change is rendered as an explicit itinerary sector, not as a longer layover at HND. This prevents the onward gate and terminal from being shown as though they are in the arrival airport.
- The screen leads with a derived NRT arrival/check-in target. Route comparison follows; attractions follow only after the mandatory transfer is feasible.
- Published static ranges are useful context but cannot support a current “fastest” claim. Live GTFS/route/traffic data, freshness, service coverage, and accessibility must be complete.
- Optional stops are evaluated as additional `PlanSegment`s on a route to NRT. They require current entry, baggage disposition, opening hours, weather, last service, onward check-in/security, and return-to-route facts. Missing any critical value keeps the stop locked or `Requires confirmation`.
- Each route row announces mode, low/most-likely/high duration, transfers, walking, accessibility, last service, and freshness. Cost and comfort can be secondary attributes.
- A `Return now` state becomes `Continue to NRT now`; it must override visit content and remain visible until the user arrives or dismisses it with an explicit reason.

## Visual system and rationale

| Choice | Specification | Rationale |
|---|---|---|
| Overall surface | `systemGroupedBackground` with `secondarySystemGroupedBackground` cards | Native adaptation to light/dark, Increased Contrast, and platform familiarity; calmer than a custom gradient-heavy travel dashboard. |
| Accent | Teal for interactive emphasis, route focus, and brand | Teal feels calm and distinct, but carries no safety meaning. Green, orange, red, blue, and purple remain semantic states. |
| Demo state | Purple word-and-symbol banner: `DEMO · NOT LIVE` | Separates development data from live/cached/stale states and cannot be mistaken for operational status. |
| Safety state | Word + SF Symbol + color | Supports Differentiate Without Color and VoiceOver; avoids red/green-only interpretation. |
| Typography | System text styles; large title → title 2 → headline → body → footnote | Dynamic Type and familiar iOS hierarchy. Monospaced digits only for times, ranges, probabilities, seeds, and formulas. |
| Card radius | 20 pt main surfaces; 14 pt notices; capsule statuses | Matches the current native SwiftUI vocabulary while preserving clear grouping. Decorative nesting should be limited to two levels. |
| Primary action | One full-width, at least 52 pt high | Fast acquisition under stress and comfortably above Apple’s 44 pt default target guidance. |
| Time | Local date/time plus a visible zone abbreviation | International trips and date-line crossings make unlabeled clock times unsafe and ambiguous. |
| Data freshness | Persistent near the top of task screens | Freshness changes the meaning of every downstream recommendation and must not be hidden in settings. |
| Unknown inputs | Question symbol and literal `Unknown` or `Requires confirmation` | Prevents accidental conversion of missing duration, visa, queue, or gate data to zero. |
| Motion | Short native transitions; static alternative under Reduce Motion | Directional movement is helpful in navigation but should never be required to understand progress or urgency. |

## Accessibility behavior

### Dynamic Type

- Support every iOS Dynamic Type size, including accessibility sizes.
- Replace two-column metrics and action grids with a vertical stack when `dynamicTypeSize.isAccessibilitySize`.
- Replace the four-item segmented access picker with an inline picker or vertical radio-style list at accessibility sizes.
- Avoid fixed line limits on safety messages, facility restrictions, or source freshness.
- Keep route durations and deadlines on their own line when text grows.

### VoiceOver

- Give the primary action the highest accessibility sort priority after the screen title and safety status.
- Combine read-only cards, but keep links and buttons as separate accessibility elements.
- Do not nest a `NavigationLink` inside a `Button` label.
- Announce local time zone, source mode, and freshness with every safety-critical deadline.
- Route option example: `Direct limousine bus, demo, 70 to 145 minutes, most likely 100, zero transfers, 180 meters walking, accessibility unconfirmed, last service 23:10 Japan Standard Time.`
- OCR example: `Seatback progress cue, 82 percent recognition confidence, advisory only, does not affect safety recommendations.`

### Contrast, color, and motion

- Test standard and Increased Contrast appearances; use the existing icon and text distinctions even when color is removed.
- Check all small status text against its tinted background; avoid reduced-opacity body text for essential instructions.
- Honor Reduce Motion in AR guidance, route progress, return-now transitions, and tab changes.
- Provide a list of route maneuvers as the non-AR and VoiceOver equivalent of spatial guidance.

## Prioritized implementation findings

### P0 — address before calling the flow intuitive

1. **Nested interactive controls in layover plan cards.** `TransitView` wraps the complete plan card in a `Button` and places a `NavigationLink` inside that button’s label ([TransitView.swift](../AirportXRCompanion/Views/Transit/TransitView.swift), lines 137-167). This creates ambiguous tap and assistive-technology behavior. Make the card a single `NavigationLink`, or use a noninteractive card with separate sibling actions for selection and trace.

2. **Mandatory inter-airport action is not prominent on the transit screen.** The HND-NRT card explains the requirement and compares options but has no `Start transfer` action or derived arrive-by target ([TransitView.swift](../AirportXRCompanion/Views/Transit/TransitView.swift), lines 35-85). Add a full-width primary action and show the deadline calculation immediately above it.

3. **A demo route can currently be labeled fastest.** The view uses `canClaimFastest` to render “Fastest in this demo snapshot” ([TransitView.swift](../AirportXRCompanion/Views/Transit/TransitView.swift), lines 51-58), while the planner excludes only stale/unavailable options and can select demo data ([InterAirportTransferModels.swift](../AirportXRCompanion/Models/LongHaul/InterAirportTransferModels.swift), lines 50-72). Require current non-demo data, complete provider coverage, and no critical unknowns before using “fastest”; otherwise say `Leading demo option` or `Current fastest cannot be verified`.

### P1 — high-value usability and accessibility fixes

4. **The six-tab information architecture needs compact labels.** The long `Layover & Transit` tab label sits beside five other roots ([RootTabView.swift](../AirportXRCompanion/App/RootTabView.swift), lines 7-30). Keep the full navigation title, but test `Transit` as the compact tab label and verify the system’s More behavior, compact width, localization, and VoiceOver order.

5. **The access picker is not adaptive.** `TransitView` reads `dynamicTypeSize` but the four-label segmented control remains unchanged ([TransitView.swift](../AirportXRCompanion/Views/Transit/TransitView.swift), lines 3-5 and 88-101). Use an inline or vertical picker at accessibility sizes.

6. **The active-layover metrics remain in a fixed horizontal pair.** The action grid adapts, but the gate-close and time-zone tiles do not ([JourneyDashboardView.swift](../AirportXRCompanion/Views/Journey/JourneyDashboardView.swift), lines 87-92 and 221-253). Use `ViewThatFits` or the same accessibility-size branching for metrics and recommendation feedback buttons.

7. **Country-code text fields are implementation-oriented.** Nationality and residence are free-form ISO code fields ([EntryCheckView.swift](../AirportXRCompanion/Views/Settings/EntryCheckView.swift), lines 35-50). Use searchable country pickers, display full localized country names, and normalize codes internally.

8. **Calculation provenance is too dense in the default scan path.** Every derivation row immediately shows formulas and joined record IDs ([JourneyDashboardView.swift](../AirportXRCompanion/Views/Journey/JourneyDashboardView.swift), lines 333-348). Keep results and unresolved inputs visible; move source record IDs, expiry, and seed into disclosure groups.

9. **In-flight progress spans the whole itinerary rather than the active leg.** The calculation uses the first trip departure and last trip arrival ([InFlightProgressView.swift](../AirportXRCompanion/Views/Journey/InFlightProgressView.swift), lines 94-100). During the HND layover this can imply an aircraft is still progressing. Compute the active leg independently and render ground/layover state between legs.

10. **Facility cards need decision-oriented ordering.** Current official records are rendered in provider order ([TransitView.swift](../AirportXRCompanion/Views/Transit/TransitView.swift), lines 173-223). Sort by feasible access, open/current status, terminal route, accessibility, preference, then name; expose distance and route action when available.

### P2 — polish and platform integration

11. Add a compact `Return now` / `Continue to NRT now` banner that persists across Journey, Map, and Transit when a threshold is crossed.
12. Offer a future Live Activity for gate/airport, deadline, and next action only; exclude traveler-profile and entry details.
13. Let the itinerary timeline collapse completed legs while preserving date-line and airport-change callouts.
14. Add an explicit crop-review step before OCR and an accessible “discard image” action after recognition.
15. In the plan list, replace `Not for me` with a short reason sheet (`too tiring`, `too expensive`, `too much walking`, `other`) so on-device learning receives interpretable user-owned outcomes.

## Current strengths to preserve

## 2026-07-16 passenger-copy and gate-route update

- A persistent red **Return to Gate** button now sits in each tab's content safe area and opens a full-screen route from the app root. It remains available when iOS places Layover & Transit or Settings under **More**.
- The full-screen route opens **AR Guide** first because the passenger's immediate goal is the next maneuver; **Open accessible directions** provides the ordered map/step fallback without losing the underlying tab.
- Explicit `walkthrough` and `ar-preview` terminal modes advance a named graph position and update the maneuver card. This makes motion, layout, and route progression demonstrable in the simulator while keeping synthetic movement out of normal launches.
- Red is an urgency cue, not a destructive button role. The text label and walking symbol carry the meaning without relying on color alone.
- The control uses a system prominent button with a minimum 44-point hit region. Apple recommends at least 44 by 44 points and a prominent style for the most likely action in a view.
- The terminal map's drawing remains hidden from VoiceOver because its geometry is not meaningful when spoken. An expanded route-step list, route summary, landmark picker, and accessible route-mode control provide the equivalent nonvisual path.
- Main-flow messages now state the passenger outcome in short language, including “We don't have enough information yet.” Detailed timing inputs and calculations remain available in **Why this plan?**

Sources: [Apple buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/), [Apple color](https://developer.apple.com/design/human-interface-guidelines/color), and [SwiftUI accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility).

- The primary gate/transfer action already comes before optional exploration ([JourneyDashboardView.swift](../AirportXRCompanion/Views/Journey/JourneyDashboardView.swift), lines 29-50).
- Demo, live, cached, stale, offline, and stochastic modes use explicit words and symbols ([LongHaulInterfaceComponents.swift](../AirportXRCompanion/Components/LongHaulInterfaceComponents.swift), lines 3-55).
- Feasibility status uses a label, SF Symbol, and color rather than color alone ([LongHaulInterfaceComponents.swift](../AirportXRCompanion/Components/LongHaulInterfaceComponents.swift), lines 58-87).
- The Journey action grid becomes one column at accessibility sizes ([JourneyDashboardView.swift](../AirportXRCompanion/Views/Journey/JourneyDashboardView.swift), lines 221-253).
- Entry guidance is explicitly informational, links to official verification, and excludes passport numbers/scans ([EntryCheckView.swift](../AirportXRCompanion/Views/Settings/EntryCheckView.swift), lines 8-52).
- Seatback OCR is local by default and its output is prevented from influencing safety decisions ([InFlightProgressView.swift](../AirportXRCompanion/Views/Journey/InFlightProgressView.swift), lines 34-63).
- Increased Contrast already strengthens `SurfaceCard` borders ([InterfaceComponents.swift](../AirportXRCompanion/Components/InterfaceComponents.swift), lines 3-16).
- The transfer planner uses Pareto filtering and a lexicographic route order rather than hidden scalar penalties ([InterAirportTransferModels.swift](../AirportXRCompanion/Models/LongHaul/InterAirportTransferModels.swift), lines 65-109).

## Figma artifact

- File: [Airport XR Companion — Long-Haul Transit Wireframes](https://www.figma.com/design/MgNQlseRuiBCZvDjXnsvHi)
- File key: `MgNQlseRuiBCZvDjXnsvHi`
- Editable foundations page: `01 — Foundations`
- Foundations root frame: [node `3:31`](https://www.figma.com/design/MgNQlseRuiBCZvDjXnsvHi?node-id=3-31)
- Semantic variable collection: `VariableCollectionId:3:2`
- Created assets: 21 semantic color/spacing/radius variables, seven SF Pro text styles, status examples, accessibility contract, and four design-principle cards.

Figma limitations encountered:

1. The file could discover Apple’s official `iOS and iPadOS 26` library, but importing its component sets failed with: `Not permitted to upsert from library ...` on the authenticated Starter plan. No canvas nodes were left by that failed call.
2. Immediately after creating and returning the foundations frame, the next structural-validation call failed with: `You've reached the Figma MCP tool call limit on the Starter plan.` The tool provided the upgrade URL `https://www.figma.com/files/team/1426376291951244830/all-projects?upgrade=mcp_rate_limit_paywall`.
3. Because the rate limit blocks both writes and validation, the seven phone frames were not created and the foundations page could not receive a final screenshot/metadata inspection. The file should therefore be treated as an editable foundations artifact, not a completed wireframe file.

Resume sequence after the quota resets or the plan is upgraded:

1. Inspect node `3:31` and the local semantic variables/styles.
2. Create `02 — Product Flow` with 402 by 874 iPhone frames.
3. Draw the seven screens in the order above, one screen per write call.
4. Add a rationale panel and accessibility annotation beside every screen.
5. Validate each frame with metadata, then a screenshot at full readable resolution.
6. Check text clipping, nested controls, 44-point targets, light/dark semantic mapping, and accessibility-size variants before sign-off.

## UI acceptance checklist

- [ ] Journey exposes exactly one prominent safest action.
- [ ] Every operational number is visibly live, cached, stale, demo, or unknown.
- [ ] Each leg displays local date, time, and zone; date-line changes are explicit.
- [ ] HND-NRT is a mandatory surface sector with a derived NRT target, not a normal HND layover.
- [ ] Attractions remain locked until the airport-transfer and onward-flight safety floor is satisfied.
- [ ] No demo or incomplete route is labeled fastest.
- [ ] Airside, landside, nearby, and city layers remain usable at accessibility text sizes.
- [ ] No interactive control contains another interactive control.
- [ ] VoiceOver reads status, deadline, source mode, and consequence before secondary detail.
- [ ] Differentiate Without Color and Increased Contrast preserve every state distinction.
- [ ] Reduce Motion has static route/progress alternatives.
- [ ] Country selection does not require ISO-code knowledge.
- [ ] Raw source IDs and simulation seeds are available but progressively disclosed.
- [ ] OCR remains local, crop-reviewed, erasable, and advisory only.
- [ ] External hotel/booking links are clearly external and never imply verified availability.
