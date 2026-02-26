# Lectra Pencil Blur When Zoomed In — Root Cause Analysis

## What the screenshots strongly indicate

Your PDF content stays sharp while ink becomes soft/pixelated when pinch-zooming. That pattern almost always means:

1. **PDF is rendered as vector/tile-backed content** and re-rasterized at higher zoom.
2. **Ink is rendered from a cached bitmap layer** (or snapshot texture) at a fixed base scale and then magnified.

So the issue is likely **not stroke smoothing quality itself**. It is usually a **rendering pipeline mismatch**: vector/tiled PDF + rasterized ink overlay.

## Most likely technical causes

### 1) Ink is flattened into `UIImage` (or texture) and scaled by the scroll view
Common anti-pattern:
- Draw strokes once into an offscreen image (`UIGraphicsImageRenderer` / CoreGraphics bitmap).
- Put that image in a `UIImageView` above the PDF.
- Zooming scales the image view instead of redrawing strokes at current zoom.

Result: crisp at 100%, blurry beyond.

### 2) Offscreen backing scale is fixed to `UIScreen.main.scale`
If rendering uses only device scale (2x/3x), it still blurs at 4x, 6x, 8x canvas zoom.

### 3) Layer rasterization is forced
If `shouldRasterize = true` on the ink container or parent, Core Animation caches a bitmap and scales it.

### 4) `draw(_:)` output is cached and not invalidated on zoom
If zoom changes but stroke layer is not invalidated/re-rendered at the new transform scale, old pixels get stretched.

### 5) Missing tiled rendering for large canvases
For heavy docs, a single huge bitmap is often used for “performance”, but this guarantees blur during zoom.

## Why GoodNotes looks smooth

Apps like GoodNotes keep ink as **vector stroke data** and redraw with zoom-aware sampling/tessellation (often tile-based). They avoid permanently flattening visible ink into one low-resolution bitmap.

## High-confidence fix direction

1. **Keep source-of-truth as vector stroke model** (points, pressure, width, color, tool).
2. **Render ink in a zoom-aware layer**:
   - Prefer `CAShapeLayer`/Metal path rendering or a tile renderer.
   - If bitmap cache is needed, make it **per tile + per effective zoom bucket**, not global.
3. **On zoom changes, redraw ink at effective scale**:
   - `effectiveScale = contentScaleFactor * scrollView.zoomScale` (clamped).
4. **Disable unwanted rasterization** on ink layers.
5. **Use `CATiledLayer` (or equivalent)** for large pages.

## Quick code audit checklist (search targets)

- `UIGraphicsImageRenderer`, `UIGraphicsBeginImageContext`
- `UIImageView` used as ink overlay
- `layer.shouldRasterize = true`
- `contentsScale` never updated during zoom
- `scrollViewDidZoom` not triggering stroke redraw/retile
- one giant canvas bitmap instead of tiles

## Practical acceptance criteria

- At 1x, 2x, 4x, 8x zoom, stroke edges stay comparably crisp.
- Diagonal strokes do not show obvious bilinear blur/pixel stair expansion when zooming.
- Zooming latency stays stable (<16ms frame budget on common iPad targets) via tiling/caching.

## If you need the minimal immediate patch

If the current architecture already has bitmap caching and you need a short-term fix:

- Re-render the visible ink cache whenever zoom crosses thresholds (e.g., 1.0, 1.5, 2.0, 3.0, 4.0).
- Set renderer scale to `UIScreen.main.scale * zoomScale` for that cache.
- Cache by tile+zoom bucket to avoid continuous full redraw.

This won’t be as ideal as a fully vector/tiled renderer, but it removes the obvious blur quickly.
