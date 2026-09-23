# Kedis Architecture

## Architecture status

This document describes the architecture implemented today. Kedis now includes the original local checklist/widget foundation plus the Kedis V1 category system.

Task acknowledgement, stale-task calculations, and local reminder scheduling remain planned and are **not implemented yet**.

---

# System overview

Kedis is a local-first Flutter Android application with a native Android home-screen widget.

```text
┌──────────────────────────────┐
│          Flutter UI          │
│ Category home / task screens │
└──────────────┬───────────────┘
               │
        ┌──────┴──────┐
        ▼             ▼
┌───────────────┐ ┌──────────────────┐
│TaskRepository │ │CategoryRepository│
└───────┬───────┘ └────────┬─────────┘
        └──────────┬────────┘
                   ▼
          ┌─────────────────┐
          │  KedisDatabase  │
          │   dewwit.db     │
          └────────┬────────┘
                   │
             ┌─────┴─────┐
             ▼           ▼
       Flutter app   Android widget
```

There is one authoritative SQLite database. Categories and tasks are not duplicated in UI state or a second widget store.

---

# Platform and identity

Primary platform: Android

Application framework: Flutter

Application language: Dart

Native widget language: Kotlin

Flutter package name: `kedis`

Android namespace/application ID: `dev.ekzd.kedis`

---

# Domain models

```text
Task
├── id: int
├── title: String
├── isCompleted: bool
├── createdAt: DateTime
├── completedAt: DateTime?
├── categoryId: int?
├── deletedAt: DateTime?
└── deletedGroupCategoryId: int?

TaskCategory
├── id: int
├── name: String
├── colorValue: int
├── isSystem: bool
├── createdAt: DateTime
└── deletedAt: DateTime?
```

Category colors are stored as stable integer ARGB values. Flutter `Color` objects are not serialized into SQLite.

No acknowledgement timestamp, stale flag, due date, notification metadata, finance field, AI field, or cloud-sync field exists.

---

# Persistence

`KedisDatabase` owns SQLite opening and schema migration. `TaskRepository` and `CategoryRepository` share it in the application process.

The compatibility database filename remains:

```text
dewwit.db
```

Current schema version: **5**.

```text
categories
├── id INTEGER PRIMARY KEY AUTOINCREMENT
├── name TEXT NOT NULL
├── color_value INTEGER NOT NULL
├── is_system INTEGER NOT NULL
├── system_key TEXT UNIQUE NULL
├── created_at INTEGER NOT NULL
└── deleted_at INTEGER NULL

tasks
├── id INTEGER PRIMARY KEY AUTOINCREMENT
├── title TEXT NOT NULL
├── is_completed INTEGER NOT NULL
├── created_at INTEGER NOT NULL
├── completed_at INTEGER NULL
├── category_id INTEGER NULL
│   REFERENCES categories(id) ON DELETE RESTRICT
├── deleted_at INTEGER NULL
└── deleted_group_category_id INTEGER NULL
    REFERENCES categories(id) ON DELETE RESTRICT
```

A case-insensitive unique index prevents duplicate category names across active and deleted categories. Task indexes support filtering by `category_id` and `deleted_group_category_id`.

Schema v5 supports recoverable category deletion. Active categories have `deleted_at = NULL`. Deleted tasks may have a nullable `category_id`, and `deleted_group_category_id` independently records association with a deleted category group.

Foreign keys are enabled when the database opens.

## Inbox identity

Inbox is identified durably by the category `system_key` value `inbox`; code must not assume a numeric Inbox ID.

The Inbox row is a system category. Fresh database creation inserts it once. Migration inserts it once before existing tasks are copied into the v3 task table.

## Version 2 to version 3 migration

The migration does not destroy or recreate the database file.

For pre-category tasks it:

1. Creates the categories table and unique name index.
2. Inserts the system Inbox.
3. Renames the v2 task table temporarily.
4. Creates the v3 task table with the category foreign key.
5. Copies every existing task with its original ID, title, completion state, creation timestamp, and completion timestamp while assigning Inbox.
6. Removes the temporary v2 table.

Version 1 databases still receive the existing `completed_at` migration before the category migration.

## Version 3 to version 4 migration

Schema v4 adds nullable `tasks.deleted_at`. Existing v3 rows migrate in place with `deleted_at = NULL`, preserving task IDs, titles, completion state, creation/completion timestamps, and category assignments. Fresh databases create the v4 task table directly.

## Version 4 to version 5 migration

Schema v5 adds nullable `categories.deleted_at`, rebuilds `tasks` so `category_id` is nullable, and adds nullable `tasks.deleted_group_category_id`. The migration preserves every category and task row, keeps existing task category assignments and deletion timestamps, and initializes both new fields to `NULL`. The rebuilt task table retains restrictive foreign keys and does not cascade task deletion.

---

# Category repositories and behavior

`CategoryRepository` keeps deleted category rows out of existing Home and task-capture flows. In addition to active category CRUD, its repository API supports:

- Inbox lookup.
- Category ordering.
- Trimmed/validated category creation.
- Case-insensitive duplicate-name prevention.
- Custom-category rename and color updates.
- Listing deleted custom categories.
- Soft-deleting an empty category.
- Moving active tasks to an explicit active destination before soft-deleting their source category.
- Soft-deleting a category and grouping its currently active tasks.
- Selectively restoring or permanently deleting grouped tasks while detaching unselected tasks as standalone Trash entries.

Inbox is ordered first. User categories follow creation order with ID as a deterministic fallback.

All multi-row category operations run in SQLite transactions. Deleted category names remain reserved until permanent deletion. Inbox itself cannot be renamed, recolored, or deleted.

The former UI-facing physical deletion method remains only as a deprecated compatibility API and has no user-facing route. Home uses the transactional recoverable-category operations.

`TaskRepository` handles task assignment by persistent category ID. Creating a task without a category resolves the current Inbox through its durable system key. Explicit category destinations for creation, movement, and restoration must exist and be active.

Ordinary task reads and mutations exclude rows with non-null `deleted_at`. The repository exposes separate queries for grouped deleted tasks and standalone deleted tasks while retaining the existing broad Trash query for UI compatibility. Individual restoration preserves a retained active category; categoryless or grouped tasks require an explicit active destination. Permanent task deletion removes only the selected deleted row.

## Trash integration

The grouped Trash interface exposes deleted category groups separately from standalone deleted tasks. Selecting a category does not imply selection of its grouped tasks: selections start empty, and unselected grouped tasks remain deleted, become categoryless, and move to the standalone deleted-task collection when their category is restored or permanently deleted.

Individual grouped or categoryless task restoration requires an explicit active destination. Expanded deleted-category groups support scoped selection and transactional restore-to-destination or permanent deletion for only those selected tasks, without changing the category. Selected standalone tasks can likewise be restored or permanently deleted in validated transactions. UI mutations reload Trash and request an Android widget refresh.

---

# Flutter presentation

The home screen loads categories and all non-deleted tasks once each, then groups tasks in memory for card counts and previews. This avoids per-card N+1 queries.

The home screen contains:

- Inbox-first category cards.
- List by default when no preference is stored, with a persisted masonry Grid alternative controlled from Settings.
- Active and total non-deleted task counts.
- Up to three active-task previews per category in List, or two in Grid.
- Home-level quick capture with Inbox preselected and a simple category selector.
- Lightweight category create/edit/delete actions.

Tapping a category opens `CategoryTaskScreen`, which preserves the existing checklist interactions inside that category: inline creation/editing, completion, deletion, undo, active/completed ordering, and lifecycle reload.

Task moving uses a simple destination dialog and does not change task timestamps or completion state.

Settings links to the grouped Trash screen for category and task restoration, scoped selection, and confirmed permanent deletion. Immediate task-delete Undo restores the same soft-deleted row rather than reinserting a stale task object.

No external state-management or navigation framework is used.

---

# Application settings and theme

Flutter's `ThemeData`, `ColorScheme`, and `ThemeMode` provide System, Light, and Dark appearance. Category colors are accents rather than full-card fills and use normal Material surfaces for readable light/dark presentation.

`shared_preferences` also stores the home-layout choice. `HomeLayoutController` exposes Grid/List changes to the home screen, with List as the default when no preference exists; existing saved layout preferences are respected.

The native Android widget cannot consume Flutter `ThemeData` directly. Kedis mirrors only the stable theme mode through the retained `dewwit/widget` platform channel and retained `dewwit_widget_preferences` native preference store.

---

# Android home-screen widget

The native widget uses `AppWidgetProvider`, `RemoteViewsService`, and `RemoteViews`.

Its SQLiteOpenHelper matches schema version 5 so either Flutter or the widget can open/create/upgrade the shared database safely.

The widget remains intentionally category-agnostic:

- It reads non-deleted tasks across all categories.
- It preserves the existing global active/completed ordering.
- Direct task completion still updates the same task row, but only while `deleted_at` is null.
- It does not display category cards, filters, or management controls.

The widget broadcast action remains `dev.ekzd.kedis.TOGGLE_TASK`.

---

# Planned Kedis V1 architecture work

Acknowledgement, stale-task derivation, and restrained local reminders remain future implementation tasks. That work should define activity timestamps, staleness calculation, notification scheduling/throttling, and cancellation based on concrete product requirements.

Do not add those fields or services speculatively during unrelated work.

---

# Networking and authentication

Current Kedis task/category management requires no backend, remote API, user account, or network connection.

Cloud synchronization, authentication, Google integrations, collaboration, and AI functionality remain outside Kedis V1 scope.

---

# Architectural principle

Keep Kedis proportional to what is actually implemented. Prefer explicit Flutter/native boundaries, one authoritative database, small focused repositories/screens, and understandable code over speculative abstractions.
