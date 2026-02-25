#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$(dirname "$ROOT_DIR")"
ARCHIVE="$OUT_DIR/file-drop-installer-v1.1.0.zip"

cd "$OUT_DIR"
rm -f "$ARCHIVE"
zip -r "$ARCHIVE" "file-drop-installer" -x "*.DS_Store"

echo "Created: $ARCHIVE"
