#!/bin/bash
#
# fetch-pyodide.sh — re-download the pinned Pyodide core runtime bundled with
# Lectra. Run from this directory. Keeps only the core files needed to start a
# kernel (no scientific wheels); those can be added later alongside the
# matching pyodide-lock.json.
#
set -euo pipefail

VERSION="v0.26.4"
BASE="https://cdn.jsdelivr.net/pyodide/${VERSION}/full"
FILES=(pyodide.js pyodide.asm.js pyodide.asm.wasm python_stdlib.zip pyodide-lock.json)

cd "$(dirname "$0")"
for f in "${FILES[@]}"; do
  echo "downloading $f"
  curl -fSL -o "$f" "${BASE}/${f}"
done
echo "done — Pyodide ${VERSION} core in $(pwd)"
