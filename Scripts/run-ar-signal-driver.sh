#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRANSPORT="${1:-http}"
PORT="${INDOOR_SIGNAL_PORT:-8765}"
HOST="${INDOOR_SIGNAL_HOST:-127.0.0.1}"
INTERVAL="${INDOOR_SIGNAL_INTERVAL:-1.5}"

case "$TRANSPORT" in
  http|core-location) ;;
  *)
    echo "Usage: $0 [http|core-location]" >&2
    exit 64
    ;;
esac

EMULATOR_ARGS=(
  "$ROOT/Scripts/indoor-signal-emulator.py"
  --host "$HOST"
  --port "$PORT"
  --interval "$INTERVAL"
)

RUN_MODE="ar-external"
if [[ "$TRANSPORT" == "core-location" ]]; then
  EMULATOR_ARGS+=(--transport core-location --device booted)
  RUN_MODE="ar-corelocation"
fi

python3 "${EMULATOR_ARGS[@]}" &
EMULATOR_PID="$!"
cleanup() {
  kill "$EMULATOR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..30}; do
  if curl --silent --fail "http://$HOST:$PORT/status" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

export INDOOR_FEED_URL="http://$HOST:$PORT/reading"
"$ROOT/Scripts/run-simulator.sh" "$RUN_MODE"

cat <<EOF
AR signal driver is running.

Controls from another terminal:
  curl -X POST http://$HOST:$PORT/control/next
  curl -X POST http://$HOST:$PORT/control/previous
  curl -X POST http://$HOST:$PORT/control/pause
  curl -X POST http://$HOST:$PORT/control/resume
  curl -X POST http://$HOST:$PORT/control/reset

Press Ctrl-C here to stop the signal driver.
EOF

wait "$EMULATOR_PID"
