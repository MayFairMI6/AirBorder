#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/Config/Secrets.xcconfig"

if [[ -z "${AVIATION_PROXY_BASE_URL:-}" ]]; then
  echo "Set AVIATION_PROXY_BASE_URL to your HTTPS proxy URL before running this script." >&2
  echo "Example: AVIATION_PROXY_BASE_URL=https://proxy.example.com Scripts/configure-secrets.sh" >&2
  exit 1
fi
if [[ "$AVIATION_PROXY_BASE_URL" != https://* ]]; then
  echo "AVIATION_PROXY_BASE_URL must use HTTPS." >&2
  exit 1
fi

escaped_url="${AVIATION_PROXY_BASE_URL/https:\/\//https:\/\$()\/}"
cloud_url="${CLOUD_VISION_PROXY_BASE_URL:-$AVIATION_PROXY_BASE_URL}"
if [[ "$cloud_url" != https://* ]]; then
  echo "CLOUD_VISION_PROXY_BASE_URL must use HTTPS when provided." >&2
  exit 1
fi
escaped_cloud_url="${cloud_url/https:\/\//https:\/\$()\/}"
umask 077
printf 'AVIATION_PROXY_BASE_URL = %s\nCLOUD_VISION_PROXY_BASE_URL = %s\n' "$escaped_url" "$escaped_cloud_url" > "$TARGET"
echo "Wrote ignored local aviation and vision proxy configuration to Config/Secrets.xcconfig (URLs not printed)."
