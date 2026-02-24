# Concrete Examples

Use these examples to anchor decisions before writing specs.

## Example 1: Sketch App for Industrial Design

- Goal: Create fast concept sketching with smooth line quality and low cognitive load.
- Priority: Speed, low latency perception, fast undo/redo, and shape correction confidence.
- Key constraints: Heavy one-handed use while standing, frequent zoom/pan transitions.

## Example 2: PDF Annotation for Legal Review

- Goal: Mark up long documents with highlights, margin notes, and signatures.
- Priority: Precision, palm rejection reliability, conflict-free scrolling while annotating.
- Key constraints: Mixed input (touch scroll, Pencil annotate), long sessions, high error cost.

## Example 3: Classroom Handwriting Notebook

- Goal: Replace paper notes with fluid handwriting and quick organization.
- Priority: Handwriting comfort, latency masking, easy page navigation, low fatigue.
- Key constraints: Rapid context switching across sections, split-screen with reference material.

## Example 4: Medical Image Review with Lasso Selection

- Goal: Select and label small regions quickly and accurately.
- Priority: Pixel-level precision, robust lasso editing, explicit error recovery.
- Key constraints: Zoomed canvas, edge-proximate gestures, strict auditability.

## Example 5: Whiteboard Collaboration App

- Goal: Support brainstorming with freeform drawing, typing, and object manipulation.
- Priority: Discoverability, shape correction, and predictable mixed touch+Pencil behavior.
- Key constraints: Frequent transitions between draw mode and object selection mode.

## Example 6: Architecture Markup in Split View

- Goal: Annotate plans while referencing specs side-by-side.
- Priority: Stable palettes, orientation-safe layouts, and efficient undo stacks.
- Key constraints: Split View resizing, orientation changes, handedness differences in tool reach.
