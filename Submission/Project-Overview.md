# AirBorder: Airport XR Companion

## Project Overview

AirBorder is an iOS travel-planning prototype for long-haul layovers and airport changes. It combines itinerary timing, flight-status context, airport facilities, weather, baggage/connection details from a scanned ticket, and terminal-map/AR proof-of-concept guidance in one passenger-facing experience.

The app supports both same-airport connections and multi-airport transfers, including the BKK → HND → NRT → LAX reference scenario. Its ticket scanner extracts airport codes, flight numbers, baggage instructions, and separate-ticket indicators so the app can identify standard connections, self-transfers, and airport changes without asking the passenger to select a connection type.

## Key Takeaways

- A ticket can be treated as structured travel input rather than a document to read manually. AirBorder extracts route, airport changes, flight references, transfer type, and baggage direction, then turns those facts into the connection plan without asking the passenger to classify the connection.
- A useful connection decision is an auditable feasibility calculation. The core quantity is connection slack: `S = T_board − (T_transfer + T_bags + T_entry + T_security + T_walk + B)`, where `B` is a conservative buffer. A city or airport activity is suitable only when its expected duration fits within the available slack.
- The present route planner already uses a transparent multi-factor score: travel duration plus transfer, walking, and disruption penalties. This makes accessibility preferences and the quickest inter-airport option expressible as clear, testable trade-offs instead of opaque recommendations.
- The BKK → HND → NRT → LAX fixture demonstrates that airport changes are not a variation of an ordinary layover. A self-transfer introduces additional baggage, entry, check-in, and surface-transfer constraints that must be added to the itinerary model.
- Global airport coverage can grow incrementally: the bundled airport registry provides stable offline behaviour, while MapKit search resolves airports not yet represented in the local dataset. This separates dependable local data from broader geographic discovery.
- AR, map, and globe guidance share one routing intent: guide the passenger through a terminal, between airports, or through a city stop while preserving the path back to boarding.
- The project is reproducible: it can be downloaded from GitHub and run in Xcode on Simulator or a reviewer’s own iPhone, with an importable ticket fixture and automated tests.

## Research and Development Pathway

AirBorder provides a foundation for a research-oriented connection-assistance system. A next study can estimate each component of the slack equation as a probability distribution rather than a single number: for example, walking time, immigration time, security time, baggage reclaim time, and ground-transfer time. The model can then report the probability of reaching the next boarding point on time:

`P(on time) = P(T_transfer + T_bags + T_entry + T_security + T_walk + B ≤ T_board)`.

This enables several measurable research questions:

- **Calibration:** compare predicted and observed transfer times by airport, time of day, traveller accessibility needs, baggage status, and disruption conditions.
- **Decision quality:** evaluate whether a risk-aware recommendation reduces missed-connection exposure compared with fixed-buffer rules.
- **Personalisation with privacy:** learn a traveller’s walking-speed range and preferred buffer on device, while keeping the global model based on de-identified aggregate observations.
- **Multi-objective optimisation:** rank plans by reliability, walking effort, cost, accessibility, and traveller value. A future objective can minimise risk and effort while maximising the usefulness of the available layover time.
- **Network and map research:** represent terminals, inter-airport links, and city access as a time-dependent graph. Shortest-path and robust-routing methods can then update routes when gates, queues, or transit services change.

The current prototype deliberately keeps the terminal graph and ticket fixtures deterministic for testing. The next engineering step is to collect consented, privacy-preserving observations that can validate the timing distributions and improve recommendations across airports.

## Application Link

GitHub repository: https://github.com/MayFairMI6/AirBorder

Build and device-test instructions: https://github.com/MayFairMI6/AirBorder/blob/main/Documentation/Build-and-Device-Test.md

Reviewers can use Xcode with their Apple Account Personal Team to install and test AirBorder on their own iPhone. TestFlight is not required for this submission.

## Submission Contents

- `airborder-long-haul-layover-companion.pptx` — project presentation
- `Project-Overview.md` — this project overview and takeaway summary
- `Build-and-Device-Test.md` — GitHub build, Simulator, and iPhone testing instructions
- `sample-self-transfer-ticket.txt` — importable BKK → HND → NRT → LAX test ticket
