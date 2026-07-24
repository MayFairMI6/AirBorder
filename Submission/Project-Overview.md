# AirBorder: Airport XR Companion

## Project Overview

AirBorder is an iOS travel-planning prototype for long-haul layovers and airport changes. It combines itinerary timing, flight-status context, airport facilities, weather, baggage/connection details from a scanned ticket, and terminal-map/AR proof-of-concept guidance in one passenger-facing experience.

The app supports both same-airport connections and multi-airport transfers, including the BKK → HND → NRT → LAX reference scenario. Its ticket scanner extracts airport codes, flight numbers, baggage instructions, and separate-ticket indicators so the app can identify standard connections, self-transfers, and airport changes without asking the passenger to select a connection type.

## Key Takeaways

- Connection planning is strongest when it explains the timing inputs behind a result rather than presenting an unexplained answer.
- Ticket details can simplify passenger input: a scanned ticket provides the route, flight numbers, baggage signals, and transfer context used in the trip plan.
- The project distinguishes live, saved, stale, example, and unavailable data so data status is visible throughout the journey.
- Privacy-sensitive features are designed to remain on device where possible, including personal timing insights and the on-device Journey overview feature on compatible Apple devices.
- The terminal map and AR route experience are a proof of concept built with a bundled demonstration graph.

## Application Link

GitHub repository: https://github.com/MayFairMI6/AirBorder

TestFlight beta: _To be added after an App Store Connect build is uploaded and approved for testing._

## Submission Contents

- `airborder-long-haul-layover-companion.pptx` — project presentation
- `Project-Overview.md` — this project overview and takeaway summary
