# Wireframe Spec: Capture-First Organizer (iOS)

## Design Direction
- Theme: dark mode first.
- Accent: red for primary actions and highlights.
- Style: clean, minimal, low-clutter, high readability.
- Motion: smooth but subtle transitions, no distracting effects.

## Navigation Model
- Default entry point: `Capture` screen (full-page input).
- Secondary navigation: bottom tab bar with:
  - `Capture`
  - `All`
  - `Categories`
  - `Settings`

## Global UI Rules
- Primary CTA uses red accent (`Done`, `Save`, `Complete`).
- Tap targets minimum 44x44 pt.
- Keyboard-aware bottom action bar so `Done` stays reachable.
- System font with clear hierarchy (`Title`, `Headline`, `Body`, `Caption`).
- Empty states always provide one clear action.

## Screen Specs

### 1) Capture Screen (Home)
Purpose:
- Fast input with zero friction.

Layout:
- Top: small header (`New Entry`) and optional timestamp.
- Center: full-height multiline text editor with placeholder text.
- Bottom fixed bar:
  - Left: optional quick actions (`Voice`, `Attach` for future)
  - Right primary button: `Done` (red)

Behavior:
- Opens focused in editor when app launches.
- `Done` disabled for empty input.
- On tap `Done`: save draft, run classification, show confirmation sheet.

Animation:
- Soft button press scale.
- Quick fade/slide for confirmation sheet.

### 2) Classification Confirmation Sheet
Purpose:
- Show auto-category and allow correction.

Layout:
- Title: `Saved`.
- Row: `Detected Category: [Category Chip]`.
- Dropdown or chip list to change category.
- Conditional fields area:
  - Reminder fields when `Reminders` selected.
  - Emotion fields when `Emotion Tracker` selected.
- Buttons:
  - `Confirm` (red)
  - `Edit Entry` (secondary)

Behavior:
- Defaults to classifier result.
- User can override before final commit.

### 3) All Timeline
Purpose:
- Unified feed of all entries.

Layout:
- Search bar at top.
- Filter chips: `All`, `Tasks`, `Reminders`, `Grocery`, `Emotion`, etc.
- Chronological list cards:
  - Entry text preview
  - Category chip
  - Date/time
  - Status icon (pending/completed)

Behavior:
- Tap card opens item detail/edit.
- Swipe actions: `Complete`, `Edit`, `Delete`.

### 4) Categories Hub
Purpose:
- Jump to category-specific views.

Layout:
- Grid or list of category cards with counts.
- Cards: Grocery, Reminders, Tasks, Work/School, Health/Fitness, Finance/Bills, Notes/Ideas, Emotion Tracker.

Behavior:
- Tap card opens category list with relevant fields and sort options.

### 5) Category List Screen (Shared Pattern)
Purpose:
- Focused management per category.

Layout:
- Header with category title and item count.
- Sort control (recent, priority, due date).
- List with category-specific metadata:
  - Grocery: checkboxes
  - Reminders: next trigger time
  - Emotion: mood score and tags

### 6) Item Detail / Edit
Purpose:
- Full editing and status management.

Layout:
- Editable text area.
- Category selector.
- Metadata modules based on type:
  - Reminder module
  - Emotion module
  - Generic notes/task fields
- Footer actions:
  - `Save`
  - `Mark Complete`
  - `Delete`

### 7) Reminder Advanced Settings
Purpose:
- Configure non-default reminder behavior.

Layout:
- Toggle: `Repeat Daily` (default ON).
- Toggle: `Advanced`.
- If advanced ON:
  - Custom days selector
  - Time picker
  - Location trigger selector
  - Snooze options

Behavior:
- Keep daily default for simple cases.
- Persist advanced rules only when enabled.

### 8) Emotion Entry Module
Purpose:
- Structured emotional journaling.

Layout:
- Multiline text input.
- Mood slider 1-10.
- Tag chips multi-select (`happy`, `anxious`, `tired`, etc.).
- Optional note prompt (e.g., `What triggered this?`).

### 9) Emotion Trends Screen
Purpose:
- Show progress over time.

Layout:
- Time range picker: week / month.
- Line chart for mood score over time.
- Top tags summary.
- Recent entries list.

### 10) Settings
Purpose:
- Account, sync, permissions, and app preferences.

Layout:
- iCloud sync status.
- Notification permissions + test ping.
- Location permissions + geofence diagnostics.
- Theme controls (dark default).
- Data export and delete options.

## States and Edge Cases
- Empty `All` screen: CTA `Create your first entry`.
- Classification uncertain: default to `Notes/Ideas` and ask user to choose.
- Notification denied: show inline banner with `Open Settings`.
- Sync conflict: keep latest edit but allow `View previous version`.

## Accessibility Requirements
- Dynamic Type support across all screens.
- VoiceOver labels for chips, sliders, and status icons.
- High contrast red shades that pass WCAG in dark mode.
- Haptic feedback for save, complete, and error actions.
