#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: scripts/run-codex-parent.sh deep|balanced|fast|auto "task prompt"' \
    '' \
    'deep      gpt-5.6 / xhigh' \
    'balanced  gpt-5.6 / high' \
    'fast      gpt-5.6-terra / medium' \
    'auto      conservative keyword routing; ambiguous tasks use deep'
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 64
fi

profile="$1"
shift
task_text="$*"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$profile" == "auto" ]]; then
  normalized="$(printf '%s' "$task_text" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    *visa*|*immigration*|*entry\ requirement*|*safety*|*probab*|*uncertaint*|*algorithm*|*architect*|*security*|*privacy*|*license*|*legal*|*learning\ policy*|*model\ training*|*migration*|*cache\ authority*)
      profile="deep"
      ;;
    *implement*|*feature*|*fix*|*refactor*|*swiftui*|*ui*|*backend*|*api*|*database*)
      profile="balanced"
      ;;
    *test*|*build*|*log*|*search*|*scan*|*document*|*report*|*format*|*summar*)
      profile="fast"
      ;;
    *)
      profile="deep"
      ;;
  esac
fi

case "$profile" in
  deep)
    model="gpt-5.6"
    effort="xhigh"
    ;;
  balanced)
    model="gpt-5.6"
    effort="high"
    ;;
  fast)
    model="gpt-5.6-terra"
    effort="medium"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

printf 'AirportXR parent profile: %s (%s / %s)\n' "$profile" "$model" "$effort" >&2
if [[ "${AIRPORTXR_CODEX_DRY_RUN:-0}" == "1" ]]; then
  exit 0
fi
exec codex \
  --strict-config \
  -C "$project_root" \
  -c "model=\"$model\"" \
  -c "model_reasoning_effort=\"$effort\"" \
  "$task_text"
