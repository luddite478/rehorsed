#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_NUMBER_FILE="$SCRIPT_DIR/.ios_build_number"

# Required App Store Connect credentials must be provided via environment.
API_KEY="${APP_STORE_CONNECT_API_KEY:-}"
API_ISSUER="${APP_STORE_CONNECT_API_ISSUER:-}"
UPLOAD_TIMEOUT_SEC="${UPLOAD_TIMEOUT_SEC:-300}"
AUTO_SKIP_STUCK_UPLOAD="${AUTO_SKIP_STUCK_UPLOAD:-true}"

if [[ -z "$API_KEY" || -z "$API_ISSUER" ]]; then
  echo "Missing required environment variables:"
  echo "  APP_STORE_CONNECT_API_KEY"
  echo "  APP_STORE_CONNECT_API_ISSUER"
  exit 1
fi

if [[ ! -f "$BUILD_NUMBER_FILE" ]]; then
  echo "3" > "$BUILD_NUMBER_FILE"
fi

LAST_BUILD_NUMBER="$(tr -d '[:space:]' < "$BUILD_NUMBER_FILE")"
if ! [[ "$LAST_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number in $BUILD_NUMBER_FILE: '$LAST_BUILD_NUMBER'"
  exit 1
fi

NEXT_BUILD_NUMBER=$((LAST_BUILD_NUMBER + 1))
echo "$NEXT_BUILD_NUMBER" > "$BUILD_NUMBER_FILE"

echo "Building IPA with build number: $NEXT_BUILD_NUMBER"
flutter build ipa --release --build-number="$NEXT_BUILD_NUMBER"

shopt -s nullglob
IPA_FILES=(build/ios/ipa/*.ipa)
shopt -u nullglob

if [[ "${#IPA_FILES[@]}" -eq 0 ]]; then
  echo "No IPA found in build/ios/ipa after build."
  exit 1
fi

IPA_PATH="${IPA_FILES[0]}"
echo "Uploading IPA: $IPA_PATH"

UPLOAD_LOG="$(mktemp)"

xcrun altool \
  --upload-app \
  --type ios \
  -f "$IPA_PATH" \
  --apiKey "$API_KEY" \
  --apiIssuer "$API_ISSUER" \
  >"$UPLOAD_LOG" 2>&1 &
UPLOAD_PID=$!

START_TS="$(date +%s)"
LAST_LOG_LINE=0

while kill -0 "$UPLOAD_PID" 2>/dev/null; do
  NOW_TS="$(date +%s)"
  ELAPSED=$((NOW_TS - START_TS))

  CURRENT_LOG_LINES="$(wc -l < "$UPLOAD_LOG" | tr -d '[:space:]')"
  if [[ "$CURRENT_LOG_LINES" -gt "$LAST_LOG_LINE" ]]; then
    sed -n "$((LAST_LOG_LINE + 1)),$((CURRENT_LOG_LINES))p" "$UPLOAD_LOG"
    LAST_LOG_LINE="$CURRENT_LOG_LINES"
  else
    echo "Upload in progress... ${ELAPSED}s elapsed"
  fi

  if [[ "$ELAPSED" -ge "$UPLOAD_TIMEOUT_SEC" ]]; then
    echo "Upload timeout reached (${UPLOAD_TIMEOUT_SEC}s)."
    kill "$UPLOAD_PID" 2>/dev/null || true
    wait "$UPLOAD_PID" 2>/dev/null || true
    if [[ "$AUTO_SKIP_STUCK_UPLOAD" == "true" ]]; then
      echo "Auto-skip enabled. Build is done, upload was skipped."
      rm -f "$UPLOAD_LOG"
      exit 0
    fi
    echo "Auto-skip disabled. Failing due to stuck upload."
    rm -f "$UPLOAD_LOG"
    exit 1
  fi

  sleep 5
done

if wait "$UPLOAD_PID"; then
  CURRENT_LOG_LINES="$(wc -l < "$UPLOAD_LOG" | tr -d '[:space:]')"
  if [[ "$CURRENT_LOG_LINES" -gt "$LAST_LOG_LINE" ]]; then
    sed -n "$((LAST_LOG_LINE + 1)),$((CURRENT_LOG_LINES))p" "$UPLOAD_LOG"
  fi
  rm -f "$UPLOAD_LOG"
  echo "Done. Uploaded build number $NEXT_BUILD_NUMBER"
else
  echo "Upload failed. altool output:"
  cat "$UPLOAD_LOG"
  rm -f "$UPLOAD_LOG"
  exit 1
fi
