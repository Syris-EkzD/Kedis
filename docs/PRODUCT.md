# Kedis Product Specification

## Product identity

**Name:** Kedis

**Producer:** EkzD.dev

**Primary platform:** Android

**Type:** Local-first personal task manager

Kedis may be described as **Kedis by EkzD.dev** where producer identity is useful. The producer name does not need to appear throughout the application UI.

## Purpose

Kedis should make capturing and managing tasks lightweight while helping surface tasks that have gone too long without acknowledgement.

The application should still feel useful as a simple checklist. Opening Kedis, creating a task, checking a task, or viewing a category must not become heavy just because more organizational features are introduced.

The Android home-screen widget remains a core part of the product rather than an optional side feature.

---

# Current implemented foundation

The following behavior is implemented today and must remain reliable as Kedis V1 expands:

- Create, view, and edit tasks.
- Complete and uncomplete tasks.
- Move deleted tasks to recoverable Trash and undo supported task actions immediately.
- Restore tasks from Trash or permanently delete them with confirmation.
- Persist task data locally in SQLite.
- Keep active tasks in creation order.
- Keep completed tasks in reverse completion order, including safe handling for legacy rows without completion timestamps.
- Add and use an Android home-screen widget backed by the same SQLite database.
- Complete and uncomplete tasks from the widget.
- Refresh the widget after application-side task mutations.
- Reload task state when the app resumes.
- Select System, Light, or Dark application appearance and mirror it to the widget.
- Select Grid or List category-home layout and persist that preference.

## Custom categories

Kedis supports persistent user-created task categories.

Users can:

- Create categories.
- Rename custom categories.
- Choose and change a category color from a small palette.
- Delete custom categories safely.
- Create and manage tasks inside categories.
- Move existing tasks between categories.

Category names are trimmed before persistence and duplicate names are prevented case-insensitively.

## Inbox

Kedis always has a system category named **Inbox**.

Inbox exists automatically on fresh databases and after migration from pre-category schema versions. Existing tasks are migrated into Inbox without changing their IDs, titles, completion state, creation timestamps, or completion timestamps.

Home-level quick capture starts with Inbox selected and allows choosing any existing category before saving. Creating a task while viewing another category assigns that task directly to the current category.

Inbox cannot be renamed, recolored, or deleted in Kedis V1.

## Safe category deletion

Deleting a custom category never deletes its tasks. Kedis first moves every normal and trashed task from that category to Inbox and then removes the category. A trashed task restored after its original category was deleted therefore returns to Inbox. The UI confirms category deletion behavior before deletion.

## Category home

The Kedis home screen primarily displays category cards. List is the default layout when no preference is stored; Settings can switch to the compact Grid layout, and existing saved layout preferences are respected across restarts.

Each card shows:

- Category name.
- Category color accent.
- Active non-deleted task count.
- Total non-deleted task count.
- Up to three active-task previews.
- A compact `+N more` indicator when additional active tasks exist.

Completed tasks count toward the total but do not appear in category-card previews. Trashed tasks count toward neither active nor total values. Tapping a card opens the full normal task list for that category.

## Category task screen

Inside a category, the existing checklist behavior is preserved:

- Active tasks first.
- Completed tasks after active tasks.
- Inline task creation.
- Inline task-title editing.
- Completion and uncompletion.
- Deletion and supported undo behavior.
- Moving a task to another existing category.

Task moves change only category assignment; task identity, completion state, and timestamps remain unchanged.

## Trash

Deleting a task sets a recoverable Trash state rather than physically removing the row. Normal category views, home counts/previews, and the Android widget exclude trashed tasks. Trash is available through Settings and supports restoring individual tasks or permanently deleting them after explicit confirmation. Trash contents are retained indefinitely; Kedis does not automatically empty Trash or implement age-based Trash reminders in this batch.

Immediate deletion Undo remains available and restores the same soft-deleted task row.

## Android widget

The Android widget remains a global checklist surface.

It continues to show non-deleted tasks across all categories and preserves the existing global task ordering and direct completion behavior. It does not show category cards, category-management controls, category filters, or Trash. Direct widget completion does not mutate a task that has already been moved to Trash.

---

# Kedis V1 planned scope

The following product goals are approved but **not implemented yet**.

## Task acknowledgement

Kedis will distinguish acknowledgement from completion.

Acknowledgement means, conceptually:

> I know this task is still here and I still intend to deal with it.

A reminder should not force the user to mark a task complete just to stop treating it as forgotten.

## Stale tasks

Kedis V1 will identify active tasks that have gone an appropriate amount of time without acknowledgement or meaningful interaction.

Staleness should be derived state, not a permanent manually maintained flag. Mandatory due dates are not required for this system.

## Reminder pings

Kedis should eventually send restrained local notifications for stale tasks that may have been forgotten. The goal is useful resurfacing, not notification spam.

---

# Kedis V1 non-goals

The following remain outside active Kedis V1 scope:

- Budget tracking.
- Financial accounts.
- Transaction tracking.
- Financial recommendations.
- AI or LLM functionality.
- Cloud synchronization.
- User accounts.
- Google Sign-In.
- Google Calendar integration.
- Collaboration.
- Web application functionality.
- iOS-specific functionality.
- Recurring tasks.
- Complex priority systems.
- Tags.
- Subtasks.
- Mandatory due dates.
- Drag-and-drop ordering or category reordering.
- Category nesting or category icons.
- Widget category filtering or category cards.

---

# Product principles

## Reliability before feature quantity

Existing task, category, migration, and widget behavior must stay dependable as Kedis grows.

## Local-first operation

Core task management must remain useful without an internet connection.

## Fast interaction

Quick capture should remain lightweight. Category context should reduce work rather than turn task creation into a form.

## Progressive complexity

New functionality should not prevent someone from using Kedis as a straightforward checklist.

## Real usage drives development

Observed friction from day-to-day use may legitimately change priorities. Planned features are direction, not an excuse to overbuild.

## Architecture follows implemented requirements

Acknowledgement, stale detection, and reminders will require deliberate implementation work later. Their future presence does not justify adding unused fields, services, dependencies, or abstractions today.
