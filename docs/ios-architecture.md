# iOS Architecture: Capture-First Organizer

## 1) Architecture Principles
- Capture speed first: the initial screen must be instantly usable.
- Offline-first: local save before any network/sync operation.
- Explainable classification: start rule-based so users can trust and override.
- Modular features: each feature has isolated UI, logic, and tests.
- Safe defaults: reminders are daily by default unless user opts into advanced settings.

## 2) Recommended Stack
- UI: SwiftUI
- Local persistence: SwiftData
- Cloud sync: CloudKit-backed SwiftData store
- Notifications: UserNotifications
- Location reminders: CoreLocation geofencing
- Charts: Swift Charts (emotion trends)
- Concurrency: Swift async/await
- Testing: XCTest + XCUITest

## 3) High-Level App Layers
- Presentation layer: SwiftUI views + view models.
- Domain layer: use-case services (classification, reminder scheduling).
- Data layer: SwiftData repository + CloudKit sync coordinator.

## 4) Suggested Project Structure
```txt
App/
  CaptureOrganizerApp.swift
  AppEnvironment.swift
Features/
  Capture/
  Timeline/
  Categories/
  Reminders/
  Emotion/
  Settings/
Domain/
  Models/
  Enums/
  Services/
Data/
  Persistence/
  Repositories/
  Sync/
Platform/
  Notifications/
  Location/
  Permissions/
Shared/
  Components/
  Theme/
  Utilities/
Tests/
  Unit/
  UI/
```

## 5) Core Domain Models

### Entry
- `id: UUID`
- `createdAt: Date`
- `updatedAt: Date`
- `rawText: String`
- `category: EntryCategory`
- `status: EntryStatus` (`active`, `completed`, `archived`)
- `source: EntrySource` (`manual`, `imported`)

### ReminderConfig (optional on entry)
- `isEnabled: Bool`
- `repeatMode: RepeatMode` (`dailyDefault`, `custom`, `location`)
- `timeOfDay: DateComponents?`
- `weekdays: [Int]?`
- `locationTrigger: LocationTrigger?`
- `snoozeMinutes: Int`
- `untilCompleted: Bool`

### EmotionData (optional on entry)
- `moodScore: Int` (1-10)
- `tags: [String]`
- `note: String`

### Category Enum
- `grocery`
- `reminders`
- `tasks`
- `workSchool`
- `healthFitness`
- `financeBills`
- `notesIdeas`
- `emotionTracker`

## 6) Classification Service (v1)
Use a local rule engine first.

Input:
- Raw text entry.

Output:
- Predicted category + confidence score.

v1 logic:
- Keyword dictionaries per category (e.g., `buy`, `store`, `milk` => grocery).
- Reminder intent detection (`remind`, `every day`, `tomorrow at`, `notify`).
- Emotion signals (`feel`, `anxious`, `sad`, `happy`, etc.).
- Fallback to `notesIdeas` when confidence is low.

Behavior:
- Always show predicted category with manual override control.
- Log user overrides to improve rules later.

## 7) Capture Save Flow
1. User enters text on capture screen.
2. Tap `Done`.
3. Save draft entry locally immediately.
4. Run classifier and present confirmation sheet.
5. User confirms/overrides category and metadata.
6. Commit final entry update.
7. Trigger reminder scheduler if needed.
8. Queue sync update to CloudKit.

## 8) Reminder System Design

### Default Path
- Every reminder entry gets daily recurring notification until completed.

### Advanced Path
- User enables advanced settings:
  - Custom days/times
  - Location geofence trigger
  - Snooze behavior

### Notification IDs
- Use deterministic identifiers per entry ID so edits replace schedules safely.

### Completion Handling
- Marking complete cancels all pending notifications for that entry.

## 9) Cloud Sync Strategy
- SwiftData + CloudKit private database.
- Sync happens automatically; expose status in Settings.
- Last-write-wins for simple fields.
- Keep lightweight edit history (timestamp + previous text) for manual recovery.
- On merge conflicts, surface non-blocking notice in item detail.

## 10) Permissions Strategy
- Notifications: request after first reminder entry, not at first launch.
- Location: request only when user turns on location reminders.
- Explain why each permission is needed in pre-permission screen.

## 11) Theming and UI System
- Default color scheme: dark.
- Red accent tokens with contrast-safe variants.
- Centralized spacing, radius, and typography tokens in `Shared/Theme`.
- Reusable components:
  - Category chip
  - Entry card
  - Empty state panel
  - Bottom action bar

## 12) Test Strategy

Unit tests:
- Classification rules and fallback behavior.
- Reminder schedule creation and cancellation.
- Category override persistence.
- Emotion score/tag validation.

UI tests:
- Launch lands on capture screen.
- Full capture -> classify -> confirm flow.
- Reminder complete stops notifications.
- Cloud sync smoke test (where supported in CI/local setups).

Regression focus:
- Data integrity after app relaunch.
- No duplicate reminders after edits.
- Offline edits sync correctly when network returns.

## 13) Observability
- Lightweight analytics events:
  - `capture_saved`
  - `category_overridden`
  - `reminder_scheduled`
  - `emotion_logged`
- Error logging for notification and sync failures.
- Local debug panel in dev builds for classifier output.

## 14) Incremental Implementation Order
1. Data models + SwiftData persistence.
2. Capture screen + `Done` save.
3. All timeline.
4. Rule-based classifier + override sheet.
5. Category lists and item detail.
6. Reminder default daily scheduling.
7. Advanced reminder settings (custom + location).
8. Emotion fields and trends chart.
9. CloudKit sync and conflict handling.
10. Polish: animations, accessibility, tests, TestFlight.
