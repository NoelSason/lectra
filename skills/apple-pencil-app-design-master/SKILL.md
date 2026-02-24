---
name: apple-pencil-app-design-master
description: Expert UX and product design guidance for iPad apps centered on Apple Pencil workflows. Design and critique precision input systems including pressure, tilt, hover, palm rejection, handedness, gesture conflict resolution, discoverability, latency perception, and long-session ergonomics. Cover drawing, annotation, handwriting, lasso/selection, shape correction, mixed touch+Pencil interactions, tool palettes, canvas states, undo/redo, zoom/pan, Split View behavior, orientation changes, and accessibility. Use when drafting feature specs, interaction specs, screen/flow reviews, usability test plans, or pre-ship polish passes for Apple Pencil-first experiences.
---

# Apple Pencil App Design Master

## Execute Workflow

1. Frame product intent and constraints.
- Capture user type, primary Pencil tasks, session length, error cost, and collaboration needs.
- Declare hardware assumptions: Pencil generation, hover support, and external keyboard usage.
2. Load only the references needed for the request.
- Use [concrete-examples.md](references/concrete-examples.md) to ground the task in comparable scenarios.
- Use [pencil-interaction-guidelines.md](references/pencil-interaction-guidelines.md) for precision input, palm rejection, handedness, gesture conflicts, discoverability, latency perception, and ergonomics.
- Use [workflow-patterns.md](references/workflow-patterns.md) for drawing, annotation, handwriting, lasso/selection, shape correction, and mixed touch+Pencil workflows.
- Use [ipad-layout-and-system-guidance.md](references/ipad-layout-and-system-guidance.md) for tool palettes, canvas states, undo/redo, zoom/pan, Split View, orientation, and accessibility decisions.
3. Produce structured outputs with [templates-and-checklists.md](references/templates-and-checklists.md).
- Deliver the feature spec and interaction spec before proposing UI details.
- Add a screen review, usability test plan, and pre-ship polish checklist.
4. Critique the result using [critique-rubric.md](references/critique-rubric.md).
- Score clarity, speed, precision, error recovery, fatigue, and accessibility.
- Report highest-risk failures first, then propose the smallest high-impact fixes.
5. Finish with prioritized next steps.
- Include instrumentation points and usability-test metrics for unresolved risk.
- Flag dependencies on OS behavior, hardware capabilities, and accessibility settings.

## Guardrails

- Prefer explicit interaction states over hidden gesture behavior.
- Preserve touch navigation while making Pencil actions precise and predictable.
- Design left-handed and right-handed parity in controls, palm rejection, and edge gestures.
- Provide graceful fallback when hover, pressure, or tilt signals are unavailable.
- Treat perceived latency and fatigue as core UX quality metrics.
