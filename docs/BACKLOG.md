# Kedis Backlog

This file separates working behavior from approved Kedis V1 work and later ideas. An item being listed does not mean it is already implemented.

## Implemented foundation

- [x] Create and view tasks
- [x] Edit task titles
- [x] Complete and uncomplete tasks
- [x] Soft-delete tasks into recoverable Trash
- [x] Undo supported completion and deletion actions
- [x] Restore individual tasks from Trash
- [x] Permanently delete individual trashed tasks with confirmation
- [x] Preserve active/completed task ordering
- [x] Persist tasks locally in SQLite
- [x] Android home-screen widget
- [x] Complete and uncomplete tasks from the widget
- [x] Synchronize application and widget through the same task database
- [x] Reload task state when the application resumes
- [x] System, Light, and Dark appearance support
- [x] Mirror application appearance to the native widget
- [x] User-created task categories
- [x] Rename custom categories
- [x] User-selected persistent category colors
- [x] Safe category deletion that moves tasks to Inbox
- [x] Durable Inbox/default category
- [x] Migrate existing tasks into Inbox without data loss
- [x] Create tasks within the current category
- [x] Home quick capture with Inbox default and selectable destination category
- [x] Persistent masonry Grid/List home-layout preference with List default when no preference is stored
- [x] Category cards with active and total non-deleted counts
- [x] Compact active-task previews with a maximum of three entries in List and two in Grid
- [x] Move tasks between existing categories
- [x] Keep the Android widget global across categories
- [x] Exclude trashed tasks from normal views, category counts/previews, and widget reads/actions
- [x] Move trashed tasks to Inbox when deleting their custom category

## Planned Kedis V1

These items are active product direction but are not implemented yet.

- [ ] Task acknowledgement separate from completion
- [ ] Track appropriate acknowledgement or meaningful activity for active tasks
- [ ] Derive stale-task attention state from activity/acknowledgement
- [ ] Provide restrained local reminder notifications for stale tasks
- [ ] Preserve low-friction capture as acknowledgement/reminders are added

Kedis V1 stale-task reminders do not require mandatory due dates.

## Outside Kedis V1

Potential future work may be reconsidered after real use creates a concrete need. It is not active Kedis V1 implementation scope.

- Budget tracking
- Financial accounts
- Transaction tracking
- Financial recommendations
- AI or LLM functionality
- Cloud synchronization
- User accounts
- Google Sign-In
- Google Calendar integration
- Collaboration
- Web application
- iOS-specific functionality
- Recurring tasks
- Complex priority systems
- Tags
- Subtasks
- Mandatory due dates
- Drag-and-drop category or task ordering
- Category nesting
- Category icons
- Widget category filtering or category cards
- Additional advanced widget configuration without a concrete requirement

## Rule

Do not implement planned or future items during an unrelated task simply because they appear here. Move one requirement at a time into an explicit implementation task, preserve the working task/category/widget foundation, and update the documentation when behavior actually changes.
