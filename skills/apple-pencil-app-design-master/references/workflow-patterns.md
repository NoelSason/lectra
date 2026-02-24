# Workflow Patterns

## Drawing Workflow

- Start in a low-friction draw-ready state.
- Keep tool switching within thumb reach.
- Provide shape correction as opt-in or hold-to-correct.
- Preserve stroke continuity across moderate zoom changes.

## Annotation Workflow

- Keep document navigation touch-first and annotation Pencil-first.
- Support highlight, underline, margin note, and freehand mark with clear visual distinction.
- Auto-anchor notes to content ranges to survive reflow.
- Enable quick accept/reject for accidental marks.

## Handwriting Workflow

- Optimize baseline stroke latency and palm rejection before adding conversion features.
- Allow writing zones that expand naturally without forced modal transitions.
- Offer on-demand handwriting-to-text conversion, never forced replacement.
- Keep line spacing and contrast tuned for sustained legibility.

## Selection and Lasso Workflow

- Start lasso from any canvas region without requiring precise icon targeting.
- Show selected-set boundaries, handles, and transformation constraints immediately.
- Support add-to-selection and subtract-from-selection with simple, visible modifiers.
- Provide one-tap deselect and restore-last-selection actions.

## Shape Correction Workflow

- Trigger correction with an intentional gesture (hold, double tap, or explicit toggle).
- Display candidate corrections before commit when ambiguity is high.
- Preserve the raw stroke so users can revert or blend corrected and freeform results.
- Prevent correction from changing unrelated nearby elements.

## Mixed Touch + Pencil Workflow

- Keep touch pan/zoom active while Pencil is authoring.
- Disable conflicting touch gestures only during active stroke windows.
- Surface current interaction mode with compact, persistent status cues.
- Define and document fallback behavior for keyboard shortcuts and external pointer input.
