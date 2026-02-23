# Lectra Figma Sketches

Clean starting sketches for Lectra are generated from local project assets (Lectra logo, Canvascope logo, and local image exports).

## Current Default Pack

- Folder: `v3-production/`
- Board preview: `v3-production/lectra-v3-production-board.png`
- Individual screens:
  - `v3-production/capture-dark-v3-production.png`
  - `v3-production/saved-sheet-dark-v3-production.png`
  - `v3-production/today-dark-v3-production.png`
  - `v3-production/all-timeline-dark-v3-production.png`
  - `v3-production/weekly-review-dark-v3-production.png`
  - `v3-production/settings-dark-v3-production.png`

## Regenerate

From repo root:

```bash
python3 "02-Subsidiaries/lectra [IN PROGRESS]/design/figma-sketches/generate_v3_production_sketches.py"
```

Previous clean pass is still available:

```bash
python3 "02-Subsidiaries/lectra [IN PROGRESS]/design/figma-sketches/generate_v2_clean_sketches.py"
```

## Figma Import Flow

1. Create a new Figma file named `Lectra Sketches v3 Production`.
2. Drag `v3-production/lectra-v3-production-board.png` into the canvas as the overview board.
3. Drag each individual `v3-production/*.png` screen into its own frame for iteration.
4. Use these as visual baselines, then rebuild with editable Figma components/tokens.

## Notes

- Style direction follows Lectra docs: dark-first, red accent, minimal density, trust-state visibility.
- `v3-production` is a higher-fidelity visual baseline aimed to look production-ready.
- Generated screens are still references, not shipping UI assets.
