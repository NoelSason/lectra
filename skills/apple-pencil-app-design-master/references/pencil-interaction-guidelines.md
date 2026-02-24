# Pencil Interaction Guidelines

## Define Input Roles

- Assign Pencil to precise authoring actions (draw, write, select region, manipulate handles).
- Assign touch to navigation and viewport controls by default (scroll, pan, pinch).
- Require explicit mode transitions for ambiguous actions.

## Design Precision Input

- Set minimum target sizes for handles and anchors at each zoom tier.
- Map pressure to one meaningful parameter per tool; avoid overloaded mappings.
- Clamp and smooth pressure curves to prevent noisy stroke-width jumps.
- Use tilt only where it improves intent clarity (shading, brush angle), not globally.

## Design Hover Behavior

- Use hover to preview placement, snap targets, and tool effects before contact.
- Keep hover previews subtle and reversible; never commit changes on hover alone.
- Provide equivalent fallback when hover is unavailable.

## Handle Palm Rejection and Handedness

- Reserve a palm-safe margin near common resting zones.
- Ignore broad low-velocity contacts while Pencil is active.
- Mirror critical edge controls for left-handed and right-handed comfort.
- Avoid placing destructive actions where the hand naturally rests.

## Resolve Gesture Conflicts

- Separate draw and navigate interactions with explicit state or gesture gating.
- Prevent accidental canvas moves during active strokes.
- Define precedence rules: active Pencil stroke > touch gestures > passive hover.
- Offer a visible mode lock when conflict risk is high.

## Configure Pencil Gesture Channels

- Map double tap or squeeze to one reversible high-frequency action.
- Avoid mapping gesture channels to destructive actions without confirmation.
- Keep gesture mappings visible in settings and first-run coaching.
- Support user remapping when hardware exposes multiple gesture channels.

## Improve Discoverability

- Introduce advanced gestures progressively after first successful baseline task.
- Show micro-coaching the first time users access lasso, shape correction, or hold-to-straighten.
- Keep hint text task-based and dismissible.

## Manage Latency Perception

- Render predicted stroke paths and reconcile smoothly with final samples.
- Keep toolbar reactions lightweight during active inking.
- Prioritize stroke rendering over non-critical UI updates.
- Communicate expensive operations with clear progress states.

## Optimize Ergonomics for Long Sessions

- Minimize required reach for primary tools and undo/redo.
- Support quick posture shifts (resting hand, standing, keyboard attached).
- Reduce repetitive precision strain via snap assists and adjustable sensitivity.
- Insert lightweight checkpointing to reduce anxiety before complex edits.
