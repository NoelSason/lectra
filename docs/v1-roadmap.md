# Capture-First Organizer iOS v1 Roadmap

## Product Goal
Ship an iOS app that opens directly to a blank capture screen, auto-categorizes entries, supports reminders and emotion logging, and syncs across Apple devices.

## v1 Success Criteria
- User can capture an entry in under 5 seconds from app launch.
- Auto-categorization is correct at least 80% of the time for common inputs.
- User can always override category and metadata.
- Daily reminders work reliably and can be completed/snoozed.
- Emotion logs support text, mood score, and tags.
- Data syncs with iCloud across signed-in devices.

## Out of Scope for v1
- Shared lists with other users.
- AI chat interface.
- Cross-platform Android/Web clients.
- Advanced analytics beyond simple emotion trends.

## Milestones (6 Sprints)

### Sprint 1: Foundation and Capture
- Create SwiftUI app skeleton.
- Set up local persistence with SwiftData.
- Build launch screen that is immediately a blank full-page input.
- Add bottom `Done` action to save entries.
- Build `All` timeline with newest-first sorting.

Exit criteria:
- Entry can be created, stored, and viewed after app restart.

### Sprint 2: Classification and Sections
- Implement local rule-based classifier.
- Create default categories: Grocery, Reminders, Tasks, Work/School, Health/Fitness, Finance/Bills, Notes/Ideas, Emotion Tracker.
- Build category override flow after save.
- Add section screens for each category.

Exit criteria:
- New entries auto-route and user can correct category in one tap flow.

### Sprint 3: Reminder Core
- Add reminder-specific model fields.
- Schedule default daily notifications for reminder entries.
- Add complete/snooze actions.
- Add reminder detail/edit screen.

Exit criteria:
- Reminder notifications fire and stop when marked complete.

### Sprint 4: Advanced Reminder + Emotion Tracker
- Add advanced reminder settings:
  - Custom day/time schedule
  - Location-based triggers
- Add emotion log fields:
  - Free text
  - Mood score (1-10)
  - Tag selection
- Add basic emotion trend chart (weekly/monthly).

Exit criteria:
- Emotion logs and advanced reminder settings are fully editable.

### Sprint 5: Cloud Sync and Reliability
- Enable CloudKit sync for SwiftData store.
- Add sync status and conflict resolution behavior.
- Add onboarding permissions flow (notifications + location).
- Add migration support for model updates.

Exit criteria:
- Data appears on second device signed into same Apple ID.

### Sprint 6: Polish, QA, and Beta
- Dark mode-first visual polish with red accent system.
- Add subtle animation set (save confirmation, transitions, list updates).
- Accessibility pass (Dynamic Type, VoiceOver labels, contrast, tap targets).
- Unit tests and UI smoke tests.
- TestFlight beta build.

Exit criteria:
- TestFlight-ready build with critical flows tested.

## QA Checklist for Release
- Capture flow works from fresh install and after relaunch.
- Auto-category can be overridden for every entry type.
- Reminder default daily rule is correctly applied.
- Location reminders trigger correctly in real-world tests.
- Emotion logs save score and tags correctly.
- Offline edits merge correctly after reconnect.
- No data loss during update/migration.

## v1.1 Backlog (After Launch)
- Better classifier using on-device ML/LLM heuristics.
- Smart recurring task suggestions.
- Shared grocery lists.
- Widgets and Siri/App Intents.
