#!/bin/bash
#
# fetch-pyodide.sh — re-download the pinned Pyodide runtime bundled with Lectra.
# Run from this directory. Downloads the core kernel files plus the scientific
# wheels (numpy / pandas / matplotlib and their full dependency closure) so the
# notebook can `import` them fully offline. The wheel list is the dependency
# closure resolved from pyodide-lock.json for VERSION below — re-resolve it if
# you bump the version or add packages.
#
set -euo pipefail

VERSION="v0.26.4"
BASE="https://cdn.jsdelivr.net/pyodide/${VERSION}/full"

CORE=(pyodide.js pyodide.asm.js pyodide.asm.wasm python_stdlib.zip pyodide-lock.json)

# Dependency closure for numpy + pandas + matplotlib (pyodide ${VERSION}).
WHEELS=(
  numpy-1.26.4-cp312-cp312-pyodide_2024_0_wasm32.whl
  pandas-2.2.0-cp312-cp312-pyodide_2024_0_wasm32.whl
  matplotlib-3.5.2-cp312-cp312-pyodide_2024_0_wasm32.whl
  matplotlib_pyodide-0.2.2-py3-none-any.whl
  kiwisolver-1.4.5-cp312-cp312-pyodide_2024_0_wasm32.whl
  pillow-10.2.0-cp312-cp312-pyodide_2024_0_wasm32.whl
  fonttools-4.51.0-py3-none-any.whl
  cycler-0.12.1-py3-none-any.whl
  pyparsing-3.1.2-py3-none-any.whl
  packaging-23.2-py3-none-any.whl
  python_dateutil-2.9.0.post0-py2.py3-none-any.whl
  pytz-2024.1-py2.py3-none-any.whl
  six-1.16.0-py2.py3-none-any.whl
)

cd "$(dirname "$0")"
for f in "${CORE[@]}" "${WHEELS[@]}"; do
  echo "downloading $f"
  curl -fSL -o "$f" "${BASE}/${f}"
done
echo "done — Pyodide ${VERSION} core + scientific wheels in $(pwd)"
