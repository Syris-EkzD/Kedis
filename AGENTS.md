# Kedis — Agent Instructions

## Project overview

Kedis by EkzD.dev is a local-first Android task manager built with Flutter. It is the renamed continuation of the existing Dewwit application.

The current codebase provides a working checklist, persistent custom categories, a built-in Inbox, Android home-screen widget interaction, theme/settings behavior, and app/widget synchronization. Kedis V1 will later add acknowledgement, stale-task detection, and restrained reminder notifications.

Reliability, maintainability, and ease of use take priority over feature quantity.

---

## Product-state rule

Always distinguish between:

1. **Implemented foundation** — behavior that exists and must be preserved.
2. **Planned Kedis V1** — approved direction that has not yet been implemented.
3. **Outside Kedis V1** — ideas that must not influence current architecture unless separately approved.

Do not claim a planned feature works merely because it is documented.

---

## Implemented foundation

Unless a task explicitly changes this behavior, preserve:

- Task creation and display.
- Inline task-title editing.
- Completion and uncompletion.
- Recoverable task deletion through Trash with immediate Undo.
- Explicit restore and confirmed permanent deletion from Trash.
- Active/completed ordering.
- SQLite persistence.
- User-created, color-coded categories.
- Durable system Inbox.
- Grid/List category-card home layouts with persisted preference.
- Category cards with active and total non-deleted task counts plus compact active-task previews.
- Home quick capture with Inbox preselected and optional category selection.
- Category-specific task capture.
- Task movement between categories.
- Safe custom-category deletion that moves tasks to Inbox.
- Android home-screen widget display and task completion interaction across all categories.
- Shared application/widget task state.
- Widget refresh after Flutter-side mutations.
- Task reload when the application resumes.
- System, Light, and Dark application appearance.
- Native widget appearance mirroring.

---

## Planned Kedis V1

The following are product goals, not currently implemented behavior:

- Task acknowledgement separate from completion.
- Stale-task detection derived from acknowledgement or meaningful activity.
- Restrained local notifications that resurface stale tasks.

Implement these only through an explicit future task. Do not add their database fields, dependencies, services, or architectural layers speculatively.

---

## Category rules

- Inbox is identified by durable system key `inbox`, never by a magic numeric ID.
- Inbox cannot be renamed, recolored, or deleted unless product scope changes deliberately.
- Tasks store category IDs, not category names.
- Category deletion must move both normal and trashed tasks to Inbox before deleting the category.
- Category colors are stable integer ARGB values in SQLite.
- Home previews show active non-deleted tasks only and stay compact.
- Home counts include active plus total non-deleted tasks; completed tasks count toward total, while trashed tasks do not.
- The Android widget remains a global cross-category checklist unless a separate task changes that product decision.

---

## Outside Kedis V1

Do not implement or design around budget/finance features, AI/LLM features, cloud sync, user accounts, Google Sign-In, Google Calendar, collaboration, web functionality, iOS-specific functionality, recurring tasks, complex priorities, tags, subtasks, mandatory due dates, drag-and-drop ordering, category nesting, category icons, or widget category filtering unless product scope is explicitly changed.

---

## Compatibility boundaries

Some internal values intentionally retain the former Dewwit name. Do not treat these as missed search-and-replace results:

- SQLite database filename: `dewwit.db`
- Flutter/native widget platform channel: `dewwit/widget`
- Native widget theme preference store: `dewwit_widget_preferences`

These values are compatibility details, not public branding. Renaming them requires a deliberate migration task.

Current public/project identity:

- Flutter package: `kedis`
- Android namespace/application ID: `dev.ekzd.kedis`
- Product label: `Kedis`

Android is the current product target. Do not broaden an Android task into inactive desktop, web, or iOS scaffolding without a concrete requirement.

---

## Persistence boundaries

`KedisDatabase` owns SQLite lifecycle and schema migration. `TaskRepository` and `CategoryRepository` share the same database in the application process.

Current schema version is 4. Tasks use nullable `deleted_at` for recoverable Trash state. Both Flutter and native Kotlin database helpers must stay schema-compatible because either side may open the authoritative database.

Foreign-key behavior must never silently delete tasks when a category is removed. Normal task queries and Android widget reads must exclude rows with non-null `deleted_at`. Ordinary deletion must soft-delete by setting `deleted_at`; permanent row deletion is reserved for an explicit confirmed Trash action.

---

## Engineering principles

1. Prefer the smallest clear solution that satisfies the active requirement.
2. Do not rewrite working code without a concrete reason.
3. Avoid premature abstraction and speculative architecture.
4. Introduce dependencies only when they solve an implemented requirement.
5. Keep Flutter/native boundaries explicit.
6. Keep SQLite authoritative; do not create duplicate task/category stores.
7. Avoid N+1 category-card queries when a bounded aggregate/in-memory grouping is sufficient.
8. Keep files and classes reasonably small and focused.
9. Preserve comments that explain non-obvious synchronization or compatibility behavior.
10. Do not suppress failures merely to make checks pass.
11. Do not silently expand product scope.
12. Keep task capture and common interactions lightweight.
13. Prefer boring, understandable code over clever code.

---

## Workflow

For substantial work:

1. Read this file and the relevant documents under `docs/`.
2. Inspect the implementation before changing behavior.
3. Identify Flutter, Android widget, persistence, migration, resource, and test dependencies affected by the task.
4. Make the smallest coherent change.
5. Keep database migrations independently reviewable where practical.
6. Update tests without deleting meaningful coverage.
7. Run focused checks during development and the complete quality gate before merge.
8. Report exactly what changed and what could not be verified.

---

## Validation

For changes affecting Flutter, Dart, persistence, categories, or the native widget, run where applicable:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
git diff --check
```

The repository also has a required GitHub Actions `quality-gate`. Do not weaken or bypass it.

If the environment supports runtime testing, smoke-check application launch, migration, category CRUD, task movement, task edit/completion/deletion/undo, Settings, persistence, and the Android widget. Never claim a command or manual check succeeded unless it was actually performed.

---

## Git practices

Keep changes focused and use milestone commits for substantial features. Do not commit generated build output, secrets, credentials, or unrelated refactors.

Use Conventional Commit style where practical.

---

## Documentation authority

`docs/PRODUCT.md` defines current product scope. `docs/ARCHITECTURE.md` describes implemented technical boundaries. `docs/BACKLOG.md` distinguishes implemented behavior, planned Kedis V1 work, and later ideas.

Agents may identify risks and recommend changes, but must not silently turn planned behavior into implemented scope or design architecture for excluded features.
