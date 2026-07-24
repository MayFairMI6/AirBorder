# Indoor positioning and AR test architecture

Updated: 2026-07-16

## What the app uses today

The `ar-preview` and `walkthrough` terminal modes use `TerminalRouteLocationEmulator` inside the app process. It generates a sequence of local `(x, y, level)` readings along the selected terminal graph, matches each reading to a named landmark, and feeds those readings into the same maneuver builder used by AR Guide. This is controlled indoor route replay, not GPS and not a claim that the simulator knows where a traveler is.

The independent option is `Scripts/indoor-signal-emulator.py`. It runs as a separate process and advances or pauses its own clock. In `http` transport, `ar-external` polls its loopback reading. In `core-location` transport, the process calls `simctl location set`; Apple Simulator then delivers the coordinate to the app through `CLLocationManager`, while loopback HTTP is used only for pause, resume, step, reset, and status controls. Both paths require an explicit UI-test launch.

```bash
python3 Scripts/indoor-signal-emulator.py
./Scripts/run-simulator.sh ar-external
```

To test Apple location delivery instead of app polling, boot the target simulator and run:

```bash
# Terminal 1
python3 Scripts/indoor-signal-emulator.py --transport core-location --device booted

# Terminal 2
./Scripts/run-simulator.sh ar-corelocation
```

`HNDCoreLocationQAFixture` projects the named test graph onto a small, versioned WGS84 footprint around the HND reference coordinate. The app reverses that projection and snaps only within the fixture's named distance limit. The floor comes from the matched test-graph node because Simulator latitude/longitude does not provide a reliable indoor `CLFloor`. These coordinates must not be treated as surveyed terminal geometry.

On a physical iPhone, ARKit supplies camera-relative motion and surface tracking. The current arrow remains camera-relative until a venue-quality position and coordinate transform are available. Apple documents that ARKit is unavailable in iOS Simulator, so simulator validation covers route progression and interface behavior, not camera tracking.

## Researched options

| Method | What it can test or provide | Airport limitation | Recommended role |
|---|---|---|---|
| Graph-route emulator | Repeatable `(x, y, level, heading)` readings, elevators, route changes, replay seeds, UI automation; may run in-app or as an independent localhost process | Synthetic unless backed by surveyed venue data | Required CI, simulator walkthrough, and parallel signal testing |
| `simctl location`, Xcode GPX, or `XCUILocation` | Latitude/longitude replay through Apple's Core Location delivery | Coordinates alone do not resolve a concourse, floor, or corridor | Test outdoor airport movement directly; test indoor UI only with an explicit synthetic or surveyed venue transform |
| IMDF plus venue indoor positioning | Venue-owned floors, units, openings, POIs, and a coordinate system suitable for indoor maps | Requires airport/property-owner data and deployment participation | Preferred production map/location foundation |
| iBeacon | Coarse proximity to deployed Bluetooth beacons | Apple says beacon ranging is proximity, not precise distance; RF attenuation and venue calibration matter | Landmark confirmation and zone/floor hints |
| UWB / Nearby Interaction | Precise relative distance and direction to a partnered device/accessory | Requires compatible hardware, permission, deployed accessories, and foreground sessions | High-precision confirmation near gates or decision points |
| Visual relocalization / saved `ARWorldMap` | Reconcile AR anchors with a previously scanned physical environment | Requires on-site surveying, stable visual features, device testing, and map lifecycle management | Partner pilot for a bounded terminal area |
| `ARGeoAnchor` | Outdoor geographic anchors where Apple geotracking is available | Not a general indoor-airport locator; availability is geographic and device-only | Outdoor terminal approaches and inter-airport wayfinding |

## Production fusion boundary

A production provider should emit the same `IndoorLocationReading` shape now produced by the emulator:

- local map point and floor;
- matched graph node or corridor;
- heading when available;
- observation time and source;
- accuracy/confidence supplied by the positioning system.

The route layer can then consume manual landmark confirmation, IMDF venue positioning, beacon proximity, UWB, or surveyed visual anchors without changing the passenger-facing maneuver model. Readings that cannot identify a floor or corridor must not silently snap across walls or levels.

## Sources

- [Apple: Simulating location in tests](https://developer.apple.com/documentation/xcode/simulating-location-in-tests)
- [Apple: XCUILocation](https://developer.apple.com/documentation/xcuiautomation/xcuilocation)
- [Apple: CLLocation floor](https://developer.apple.com/documentation/corelocation/cllocation/floor)
- [Apple: Core Location](https://developer.apple.com/documentation/corelocation)
- [Apple: Displaying an Indoor Map with IMDF](https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map)
- [Apple: IMDF community standard](https://developer.apple.com/news/?id=8lmz909p)
- [Apple: Determining proximity to an iBeacon](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)
- [Apple: Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
- [Apple: Tracking geographic locations in AR](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)
- [Apple: AR world-map anchors](https://developer.apple.com/documentation/arkit/arworldmap/anchors)
