# Critique Rubric

Score each dimension from 1 to 5.

- `1`: Fails core task reliability.
- `3`: Acceptable with clear friction.
- `5`: Fast, precise, robust, and comfortable under realistic load.

## 1. Clarity

- Check whether modes, tool states, and next actions are obvious.
- Fail if users must guess whether they are drawing, selecting, or navigating.

## 2. Speed

- Check time-to-first-mark, time-to-correct, and time-to-complete frequent tasks.
- Fail if common tasks require repeated context switches or deep menu travel.

## 3. Precision

- Check stroke fidelity, selection accuracy, hit-target reliability, and zoom behavior.
- Fail if users frequently overshoot targets or accidental gestures alter content.

## 4. Error Recovery

- Check undo/redo confidence, accidental mark removal, and reversible corrections.
- Fail if mistakes require complex manual cleanup.

## 5. Fatigue

- Check reach distance, repetitive strain, posture flexibility, and long-session comfort.
- Fail if sustained use causes avoidable hand travel or fine-motor strain.

## 6. Accessibility

- Check contrast, non-color cues, adjustable targets, alternative inputs, and assistive tech support.
- Fail if core flows depend on a single sensory or motor ability.

## Risk Interpretation

- Treat any dimension scored `1` or `2` as a release blocker.
- Treat average score below `3.5` as a pre-ship risk.
- Prioritize fixes in this order: precision failures, recovery failures, fatigue failures, then speed/clarity tuning.
