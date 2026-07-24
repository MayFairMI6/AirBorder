#!/usr/bin/env python3
"""Independent localhost indoor-position signal emulator for simulator QA."""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROUTE_NODES = (
    ("t3-transfer-security", 0.10, 0.55, 3),
    ("t3-departures-center", 0.30, 0.55, 3),
    ("t3-elevator-north", 0.46, 0.72, 3),
    ("t3-gates-center", 0.65, 0.55, 4),
    ("gate-105", 0.87, 0.34, 4),
)
SAMPLES_PER_SEGMENT = 3
HND_QA_ANCHOR_LATITUDE = 35.549678
HND_QA_ANCHOR_LONGITUDE = 139.786958
HND_QA_EAST_WEST_EXTENT_METERS = 240.0
HND_QA_NORTH_SOUTH_EXTENT_METERS = 180.0
METERS_PER_LATITUDE_DEGREE = 111_320.0


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def route_samples() -> list[dict[str, object]]:
    samples: list[dict[str, object]] = []
    for start, end in zip(ROUTE_NODES, ROUTE_NODES[1:]):
        start_id, start_x, start_y, start_level = start
        _, end_x, end_y, end_level = end
        heading = math.degrees(math.atan2(end_x - start_x, end_y - start_y))
        for sample_index in range(SAMPLES_PER_SEGMENT):
            progress = sample_index / SAMPLES_PER_SEGMENT
            samples.append(
                {
                    "point": {
                        "x": start_x + ((end_x - start_x) * progress),
                        "y": start_y + ((end_y - start_y) * progress),
                    },
                    "level": start_level if progress < 0.5 else end_level,
                    "matchedNodeID": start_id,
                    "headingDegrees": heading,
                    "source": "externalSignalReplay",
                }
            )
    final_id, final_x, final_y, final_level = ROUTE_NODES[-1]
    samples.append(
        {
            "point": {"x": final_x, "y": final_y},
            "level": final_level,
            "matchedNodeID": final_id,
            "headingDegrees": samples[-1]["headingDegrees"],
            "source": "externalSignalReplay",
        }
    )
    return samples


def core_location_coordinate(reading: dict[str, object]) -> tuple[float, float]:
    point = reading["point"]
    assert isinstance(point, dict)
    north_meters = (float(point["y"]) - 0.5) * HND_QA_NORTH_SOUTH_EXTENT_METERS
    east_meters = (float(point["x"]) - 0.5) * HND_QA_EAST_WEST_EXTENT_METERS
    latitude = HND_QA_ANCHOR_LATITUDE + north_meters / METERS_PER_LATITUDE_DEGREE
    longitude_scale = METERS_PER_LATITUDE_DEGREE * math.cos(math.radians(HND_QA_ANCHOR_LATITUDE))
    longitude = HND_QA_ANCHOR_LONGITUDE + east_meters / longitude_scale
    return latitude, longitude


class SignalPublisher:
    def __init__(self, transport: str, device: str, dry_run: bool) -> None:
        self.transport = transport
        self.device = device
        self.dry_run = dry_run
        self.delivery_count = 0
        self.last_error: str | None = None
        self.lock = threading.Lock()

    def publish(self, reading: dict[str, object]) -> None:
        if self.transport != "core-location":
            return
        latitude, longitude = core_location_coordinate(reading)
        command = [
            "xcrun", "simctl", "location", self.device, "set",
            f"{latitude:.8f},{longitude:.8f}",
        ]
        if self.dry_run:
            print(" ".join(command), flush=True)
            return
        try:
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)
            with self.lock:
                self.delivery_count += 1
                self.last_error = None
        except (OSError, subprocess.SubprocessError) as error:
            with self.lock:
                self.last_error = str(error)

    def status(self) -> dict[str, object]:
        with self.lock:
            return {
                "transport": self.transport,
                "device": self.device if self.transport == "core-location" else None,
                "coreLocationDeliveries": self.delivery_count,
                "coreLocationLastError": self.last_error,
            }


class SignalState:
    def __init__(self, interval: float, paused: bool, loops: bool, publisher: SignalPublisher) -> None:
        self.samples = route_samples()
        self.interval = interval
        self.paused = paused
        self.loops = loops
        self.index = 0
        self.sequence = 0
        self.observed_at = iso_now()
        self.lock = threading.Lock()
        self.publisher = publisher

    def reading(self) -> dict[str, object]:
        with self.lock:
            reading = dict(self.samples[self.index])
            reading["observedAt"] = self.observed_at
            return reading

    def status(self) -> dict[str, object]:
        with self.lock:
            status = {
                "paused": self.paused,
                "loops": self.loops,
                "sequence": self.sequence,
                "sampleIndex": self.index,
                "sampleCount": len(self.samples),
                "intervalSeconds": self.interval,
                "matchedNodeID": self.samples[self.index]["matchedNodeID"],
            }
        status.update(self.publisher.status())
        return status

    def control(self, action: str) -> None:
        with self.lock:
            if action == "pause":
                self.paused = True
            elif action == "resume":
                self.paused = False
            elif action == "reset":
                self.index = 0
            elif action == "next":
                self._move(1)
            elif action == "previous":
                self._move(-1)
            else:
                raise ValueError(action)
            self.sequence += 1
            self.observed_at = iso_now()
            reading = dict(self.samples[self.index])
        self.publisher.publish(reading)

    def tick(self) -> None:
        with self.lock:
            if self.paused:
                return
            self._move(1)
            self.sequence += 1
            self.observed_at = iso_now()
            reading = dict(self.samples[self.index])
        self.publisher.publish(reading)

    def _move(self, delta: int) -> None:
        candidate = self.index + delta
        if self.loops:
            self.index = candidate % len(self.samples)
        else:
            self.index = max(0, min(len(self.samples) - 1, candidate))


def handler_type(state: SignalState) -> type[BaseHTTPRequestHandler]:
    class SignalHandler(BaseHTTPRequestHandler):
        server_version = "AirportXRIndoorSignal/1.0"

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/reading":
                self._json(200, state.reading())
            elif self.path == "/status":
                self._json(200, state.status())
            else:
                self._json(404, {"error": "not_found"})

        def do_POST(self) -> None:  # noqa: N802
            prefix = "/control/"
            if not self.path.startswith(prefix):
                self._json(404, {"error": "not_found"})
                return
            action = self.path[len(prefix) :]
            try:
                state.control(action)
            except ValueError:
                self._json(400, {"error": "unknown_control"})
                return
            self._json(200, state.status())

        def _json(self, status: int, payload: dict[str, object]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format_string: str, *args: object) -> None:
            return

    return SignalHandler


def run_clock(state: SignalState, stop: threading.Event) -> None:
    while not stop.wait(state.interval):
        state.tick()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve independent indoor QA signals through HTTP or Apple Simulator Core Location."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--interval", type=float, default=1.5)
    parser.add_argument("--paused", action="store_true")
    parser.add_argument("--no-loop", action="store_true")
    parser.add_argument("--transport", choices=("http", "core-location"), default="http")
    parser.add_argument("--device", default="booted")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost"}:
        parser.error("--host must remain on loopback")
    if args.interval <= 0:
        parser.error("--interval must be positive")
    if args.transport == "core-location" and not (
        args.device == "booted" or re.fullmatch(r"[0-9A-Fa-f-]{36}", args.device)
    ):
        parser.error("--device must be 'booted' or a simulator UUID")

    publisher = SignalPublisher(args.transport, args.device, args.dry_run)
    state = SignalState(
        interval=args.interval,
        paused=args.paused,
        loops=not args.no_loop,
        publisher=publisher,
    )
    publisher.publish(state.reading())
    if args.dry_run:
        return
    stop = threading.Event()
    clock = threading.Thread(target=run_clock, args=(state, stop), daemon=True)
    clock.start()
    server = ThreadingHTTPServer((args.host, args.port), handler_type(state))
    print(f"Indoor signal emulator: http://{args.host}:{args.port}/reading", flush=True)
    print(f"App signal transport: {args.transport}", flush=True)
    print("Controls: POST /control/pause|resume|next|previous|reset", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()


if __name__ == "__main__":
    main()
