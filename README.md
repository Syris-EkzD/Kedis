# Kedis

**Kedis by EkzD.dev** is a local-first Android task manager built with Flutter.

Kedis keeps task capture lightweight while organizing tasks into persistent categories. The Android home-screen widget remains a fast global checklist surface across categories.

## Status

The checklist foundation and Kedis V1 category system are implemented. Task acknowledgement, stale-task detection, and reminder notifications remain planned and are **not implemented yet**.

### Implemented now

- Create, edit, complete, and uncomplete tasks
- Move deleted tasks to recoverable Trash with immediate Undo
- Restore tasks from Trash or permanently delete them with confirmation
- Preserve active/completed ordering
- Persist tasks locally in SQLite
- User-created, color-coded task categories
- Built-in Inbox for zero-friction capture and migrated legacy tasks
- Grid and List category-home layouts with persisted selection
- Category cards with active and total non-deleted task counts plus compact active-task previews
- Full task lists inside categories
- Home quick capture with Inbox selected by default and optional category selection
- Create tasks directly in the current category
- Move existing tasks between categories without changing task state
- Recoverably delete custom categories with explicit move-tasks or grouped-Trash choices
- Selectively restore or permanently delete grouped and standalone trashed tasks
- Android home-screen widget showing tasks across all categories
- Complete and uncomplete tasks from the widget
- App/widget synchronization and lifecycle reload behavior
- System, Light, and Dark appearance in the application and widget

### Planned for Kedis V1

- Task acknowledgement separate from completion
- Stale-task detection derived from acknowledgement or meaningful activity
- Restrained local reminder notifications for stale tasks

Kedis V1 does not require mandatory due dates.

## Kedis V1 non-goals

Budget or transaction tracking, financial accounts or recommendations, AI/LLM features, cloud synchronization, user accounts, Google Sign-In, Google Calendar integration, collaboration, a web application, iOS-specific functionality, recurring tasks, complex priority systems, tags, subtasks, and mandatory due dates are outside the active Kedis V1 scope.

## Experimental companion direction

The companion M1 candidate adds an optional offline knowledge reader to the
existing application. Open the book icon on Home to import a local searchable
ZIM, search, and read excerpts. Native retrieval and physical-device acceptance
remain outstanding; conversational RAG and MCP are deferred. V1 commitments
remain unchanged. See [Companion M1](docs/COMPANION.md) for limits and gates.

## Tech stack

- Flutter and Dart
- Native Android widget code in Kotlin
- SQLite through `sqflite` and Android SQLite APIs
- `shared_preferences` for application appearance and home-layout preferences

Development currently targets Android. Core task management is offline-first and requires no backend.

## Category behavior

Inbox is a durable system category. Home quick capture starts with Inbox selected, but the user may choose any existing category before saving. Capture inside a category assigns that category automatically. Inbox cannot be renamed or deleted.

Deleting a custom category moves it to recoverable Trash. Users explicitly choose whether to move its normal tasks to another active category or group them with the deleted category. Previously deleted standalone tasks remain deleted.

The home screen defaults to the full-width List layout when no preference is stored and can be switched to the compact Grid layout from Settings. Existing saved layout preferences are respected across restarts. Category cards show active and total non-deleted task counts, up to three active-task previews, and a compact remainder indicator when needed. Completed tasks count toward the total but do not appear in previews; trashed tasks count toward neither value.

## Trash behavior

Deleting a task soft-deletes it into Trash and keeps the existing immediate Undo action. Trashed tasks remain stored indefinitely until explicitly restored or permanently deleted. Permanent deletion requires confirmation. Trash is available from Settings, separates deleted category groups from standalone tasks, and has no automatic cleanup or retention period. Category actions affect only explicitly selected grouped tasks; unselected tasks remain recoverable.

## Widget behavior

The Android widget remains category-agnostic for Kedis V1. It reads the same authoritative SQLite database and continues to display non-deleted tasks across all categories using the existing task ordering semantics. Trashed tasks are excluded from widget reads and direct widget completion actions.

## Compatibility note

The public product is Kedis, but these internal compatibility identifiers intentionally remain unchanged:

- SQLite database filename: `dewwit.db`
- Flutter/native widget channel: `dewwit/widget`
- Native widget theme preferences: `dewwit_widget_preferences`

## Run

Use Flutter 3.47.5, matching the pinned quality gate, and Java 17.

```bash
flutter pub get
flutter doctor
flutter devices
flutter run
```

## Validation

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
git diff --check
```

## Project documentation

- `docs/PRODUCT.md` — Kedis product scope and V1 direction
- `docs/ARCHITECTURE.md` — implemented architecture and compatibility boundaries
- `docs/BACKLOG.md` — implemented foundation, planned V1 work, and later ideas
- `AGENTS.md` — instructions for coding agents working in this repository

## Development principle

Kedis should stay fast to open, fast to capture into, and easy to understand. Reliability and maintainability take priority over feature quantity or speculative architecture.
