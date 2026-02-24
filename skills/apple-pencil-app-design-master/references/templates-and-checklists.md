# Templates and Checklists

## Feature Spec Template

```md
# Feature Spec: <feature name>

## Problem
- Define user pain in current workflow.

## Target Users and Context
- Identify user segments and dominant tasks.
- Define expected session length and environment.

## Success Criteria
- Define measurable outcomes (speed, precision, error rate, comfort).

## Pencil-First Behavior
- Define Pencil responsibilities vs touch responsibilities.
- Define pressure/tilt/hover usage and fallback behavior.

## Risks and Constraints
- List hardware, OS, and accessibility constraints.
```

## Interaction Spec Template

```md
# Interaction Spec: <flow or screen>

## States
- List explicit states and entry/exit conditions.

## Input Mapping
- Map Pencil, touch, keyboard, and pointer actions.

## Gesture Conflict Rules
- Define gesture precedence and lock conditions.

## Error Recovery
- Define undo units, cancel paths, and revert behavior.

## Feedback and Discoverability
- Define hover previews, hints, and mode indicators.

## Latency and Performance
- Define acceptable perceived latency and fallback handling.
```

## Screen Review Checklist

- Verify mode clarity at a glance.
- Verify primary actions within low-reach zones.
- Verify left-handed and right-handed parity.
- Verify touch navigation remains intact during Pencil workflows.
- Verify accidental input recovery in one or two steps.
- Verify contrast, non-color cues, and scalable targets.

## Usability Test Plan Template

```md
# Usability Test Plan: <feature>

## Participants
- Recruit users matching target proficiency levels.

## Tasks
- Include drawing, annotation, handwriting, lasso/selection, and correction tasks.

## Metrics
- Record completion time, precision errors, undo frequency, and subjective fatigue.
- Segment results by handedness and hover availability.

## Failure Logging
- Capture gesture conflicts, palm rejection misses, and discoverability failures.

## Exit Interview
- Ask what felt slow, imprecise, or tiring.
- Ask whether control placement caused repeated reach strain.
```

## Pre-Ship Polish Checklist

- Validate perceived latency under realistic document/canvas load.
- Validate undo/redo confidence for all high-frequency actions.
- Validate hover and non-hover parity.
- Validate orientation and Split View resilience.
- Validate accessibility settings (contrast, target size, reduce motion, assistive tech).
- Validate that hints can be rediscovered without clutter.
- Validate that long-session fatigue risks are addressed or explicitly accepted.
