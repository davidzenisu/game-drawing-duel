#!/usr/bin/env bash
# Waits until the API at $API_URL reports $GITHUB_SHA as `version` on
# GET /health, polling every 15 seconds up to $ATTEMPTS times.
set -u

api="${API_URL%/}"
case "$api" in http://*|https://*) ;; *) api="https://$api" ;; esac
attempts="${ATTEMPTS:-20}"
body="${RUNNER_TEMP:-/tmp}/health.json"

for attempt in $(seq 1 "$attempts"); do
  status=$(curl -sS --max-time 10 -o "$body" -w '%{http_code}' "$api/health" || true)
  live=$(jq -r '.version // empty' "$body" 2>/dev/null || true)
  if [ "$live" = "$GITHUB_SHA" ]; then
    echo "The API serves $GITHUB_SHA."
    exit 0
  fi
  echo "Waiting for $GITHUB_SHA (attempt $attempt of $attempts): HTTP ${status:-none}, $(head -c 300 "$body" 2>/dev/null | tr -d '\n')"
  rm -f "$body"
  sleep 15
done
echo "The API still doesn't serve $GITHUB_SHA after $attempts checks."
exit 1
