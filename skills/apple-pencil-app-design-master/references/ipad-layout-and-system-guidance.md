# iPad Layout and System Guidance

## Tool Palettes

- Keep primary tools persistent and secondary controls collapsible.
- Support movable palettes with magnetic safe zones that avoid hand rest areas.
- Offer compact and expanded palette densities for different canvas sizes.
- Keep undo/redo available without forcing mode exits.

## Canvas States

- Define explicit states: browse, annotate, draw, select, transform, review.
- Expose state changes with subtle but clear UI confirmation.
- Preserve user context when switching states (selection, zoom, active layer/tool).
- Prevent destructive state transitions without a reversible path.

## Undo and Redo

- Implement low-latency local undo stacks for inking actions.
- Group micro-edits into meaningful undo units.
- Preserve undo history across lightweight mode changes.
- Expose visual feedback for the action being undone or redone.

## Zoom and Pan

- Keep zoom centered on intent point when possible.
- Maintain stable stroke rendering and handle sizes across zoom levels.
- Provide quick return-to-fit and return-to-last-focus actions.
- Avoid accidental pan while drawing; gate movement during active stroke.

## Split View and Multitasking

- Keep palettes dock-aware so controls remain reachable after resize.
- Reflow side panels and inspector content for narrow widths.
- Preserve mode and selection when app width changes.
- Protect performance when two active canvases are visible.

## Orientation Changes

- Persist tool positions and user preferences per orientation.
- Recompute safe zones after rotation to avoid hand-occluded controls.
- Keep active interaction context intact through rotation events.
- Verify transform handles remain reachable in both portrait and landscape.

## Accessibility

- Provide high-contrast modes and clear non-color status indicators.
- Support adjustable hit targets and stroke preview amplification.
- Expose all core actions through alternative input paths.
- Include screen reader labels for tool, state, and mode changes.
- Respect reduce-motion and bold-text settings without breaking hierarchy.
