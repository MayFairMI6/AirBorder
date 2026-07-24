#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
BUNDLE_ID="com.example.AirportXRCompanion"
MODE="${1:-live}"
PARAMETER="${2:-}"
PACE="${3:-}"

case "$MODE" in
  live|offline|demo|stochastic|ar-preview|ar-external|ar-corelocation|signal-http|signal-location|walkthrough|notifications|time|time-green|time-amber|time-red|weather|weather-clear|weather-disruption|city-map) ;;
  *)
    echo "Usage: $0 [live|offline|demo|stochastic|ar-preview|ar-external|ar-corelocation|signal-http|signal-location|walkthrough|notifications|time <minutes>|time-green|time-amber|time-red|weather <clear|rain|fog|disruption>|weather-clear|weather-disruption|city-map <light|normal|heavy>]" >&2
    exit 64
    ;;
esac

if [[ -n "$PARAMETER" && "$MODE" != "time" && "$MODE" != "weather" && "$MODE" != "city-map" ]]; then
  echo "Replay seeds are not supported." >&2
  exit 64
fi

UDID="$(xcrun simctl list devices available | awk -v name="$DEVICE_NAME" 'index($0, name " (") {gsub(/[()]/, ""); print $(NF-1); exit}')"
if [[ -z "$UDID" ]]; then
  echo "Could not find simulator '$DEVICE_NAME'. Set SIMULATOR_NAME to an installed iPhone." >&2
  exit 1
fi

if [[ "$MODE" == "signal-http" ]]; then
  MODE="ar-external"
elif [[ "$MODE" == "signal-location" ]]; then
  MODE="ar-corelocation"
fi

if [[ "$MODE" == "ar-external" || "$MODE" == "ar-corelocation" ]]; then
  FEED_URL="${INDOOR_FEED_URL:-http://127.0.0.1:8765/reading}"
  if ! curl --silent --show-error --fail "$FEED_URL" >/dev/null; then
    echo "Indoor signal emulator is not reachable at $FEED_URL" >&2
    echo "Start it first: python3 Scripts/indoor-signal-emulator.py" >&2
    exit 1
  fi
fi
if [[ "$MODE" == "ar-corelocation" ]]; then
  STATUS_URL="${FEED_URL%/reading}/status"
  if ! curl --silent --show-error --fail "$STATUS_URL" | grep -q '"transport":"core-location"'; then
    echo "The emulator at $STATUS_URL is not using Apple Core Location transport." >&2
    echo "Start it with: python3 Scripts/indoor-signal-emulator.py --transport core-location --device $UDID" >&2
    exit 1
  fi
fi

"$ROOT/Scripts/build.sh"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

APP_PATH="$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/AirBorder.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl install "$UDID" "$APP_PATH"
if [[ "$MODE" == "ar-corelocation" ]]; then
  xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
fi
if [[ "$MODE" == "ar-preview" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-simulated-walk)
elif [[ "$MODE" == "ar-external" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-indoor-feed "$FEED_URL")
elif [[ "$MODE" == "ar-corelocation" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-core-location-indoor)
elif [[ "$MODE" == "walkthrough" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-walkthrough)
elif [[ "$MODE" == "notifications" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo)
elif [[ "$MODE" == "time-green" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-clock-offset-minutes 0)
elif [[ "$MODE" == "time-amber" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-clock-offset-minutes 270)
elif [[ "$MODE" == "time-red" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-clock-offset-minutes 330)
elif [[ "$MODE" == "time" ]]; then
  if [[ ! "$PARAMETER" =~ ^-?[0-9]+$ ]]; then
    echo "Time driver needs an integer number of minutes, for example: $0 time 285" >&2
    exit 64
  fi
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-clock-offset-minutes "$PARAMETER")
elif [[ "$MODE" == "weather-clear" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-weather clear)
elif [[ "$MODE" == "weather-disruption" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-weather disruption)
elif [[ "$MODE" == "weather" ]]; then
  case "$PARAMETER" in
    clear|rain|fog|disruption) ;;
    *)
      echo "Weather driver needs one of: clear, rain, fog, disruption" >&2
      exit 64
      ;;
  esac
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --qa-weather "$PARAMETER")
elif [[ "$MODE" == "city-map" ]]; then
  TRAFFIC="${PARAMETER:-normal}"
  case "$TRAFFIC" in light|normal|heavy) ;; *) echo "City-map driver needs: light, normal, or heavy" >&2; exit 64 ;; esac
  PACE="${PACE:-typical}"
  case "$PACE" in slower|typical|faster) ;; *) echo "Walking pace needs: slower, typical, or faster" >&2; exit 64 ;; esac
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode demo --scenario interAirport --qa-traffic "$TRAFFIC" --qa-walking-pace "$PACE")
elif [[ "$MODE" == "demo" || "$MODE" == "stochastic" ]]; then
  LAUNCH_ARGUMENTS=(--uitesting --launch-mode "$MODE")
else
  LAUNCH_ARGUMENTS=(--launch-mode "$MODE")
fi
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${LAUNCH_ARGUMENTS[@]}"
echo "Launched AirBorder in '$MODE' mode on $DEVICE_NAME ($UDID)."
