import 'package:kedis/main.dart';
import 'package:kedis/settings/home_layout_controller.dart';
import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:kedis/settings/theme_controller.dart';
import 'package:kedis/settings/theme_preference_store.dart';
import 'package:kedis/widgets/editing_task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_repositories.dart';

void main() {
  late FakeTaskRepository tasks;
  late FakeCategoryRepository categories;
  late int widgetRefreshCount;

  setUp(() {
    final repositories = FakeRepositories();
    tasks = repositories.tasks;
    categories = repositories.categories;
    widgetRefreshCount = 0;
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
    String failureMessage,
  ) async {
    await tester.pump();
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail(failureMessage);
  }

  Future<void> waitForUndo(WidgetTester tester, String failureMessage) async {
    await pumpUntil(
      tester,
      () => find.text('UNDO').hitTestable().evaluate().isNotEmpty,
      failureMessage,
    );
  }

  Future<void> pumpKedis(WidgetTester tester) async {
    await tester.pumpWidget(
      KedisApp(
        taskRepository: tasks,
        categoryRepository: categories,
        themeController: ThemeController(_FakeThemePreferenceStore()),
        homeLayoutController: HomeLayoutController(HomeLayoutPreferenceStore()),
        widgetRefresh: () async {
          widgetRefreshCount += 1;
        },
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('Inbox').evaluate().isNotEmpty,
      'Kedis category home did not finish loading.',
    );
  }

  Future<void> openInbox(WidgetTester tester) async {
    await tester.tap(find.text('Inbox').first);
    await pumpUntil(
      tester,
      () => find.byTooltip('Add task').evaluate().isNotEmpty,
      'Inbox task screen did not finish loading.',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('multiline draft grows to keep its text visible', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);
    await openInbox(tester);
    await tester.tap(find.byTooltip('Add task'));
    await pumpUntil(tester, () {
      final draftInput = find.byKey(const ValueKey('task-draft-input'));
      return draftInput.evaluate().isNotEmpty;
    }, 'Task draft editor did not appear.');

    final input = find.byKey(const ValueKey('task-draft-input'));
    final initialHeight = tester.getSize(input).height;
    final textField = tester.widget<TextField>(input);
    expect(textField.minLines, 1);
    expect(textField.maxLines, isNull);

    await tester.enterText(
      input,
      'First part of a long task\nSecond part\nThird part',
    );
    await tester.pump();

    expect(tester.getSize(input).height, greaterThan(initialHeight));
  });

  testWidgets('cancels an edit without changing the title', (
    WidgetTester tester,
  ) async {
    await tasks.createTask('Unchanged title');
    await pumpKedis(tester);
    await openInbox(tester);

    await tester.tap(find.text('Unchanged title'));
    await pumpUntil(
      tester,
      () => find.byType(EditingTaskItem).evaluate().isNotEmpty,
      'Task editor did not appear.',
    );
    await tester.enterText(find.byType(TextField), 'Discard this');
    await tester.tap(find.byTooltip('Cancel editing'));
    await pumpUntil(
      tester,
      () =>
          find.text('Unchanged title').evaluate().isNotEmpty &&
          find.byType(EditingTaskItem).evaluate().isEmpty,
      'Task edit did not finish cancelling.',
    );

    expect(find.text('Unchanged title'), findsOneWidget);
    expect(find.byType(EditingTaskItem), findsNothing);
    expect((await tasks.getTasks()).single.title, 'Unchanged title');
    expect(widgetRefreshCount, 0);
  });

  testWidgets('allows only one task to be edited at a time', (
    WidgetTester tester,
  ) async {
    await tasks.createTask('First task');
    await tasks.createTask('Second task');
    await pumpKedis(tester);
    await openInbox(tester);

    await tester.tap(find.text('First task'));
    await pumpUntil(
      tester,
      () => find.byType(EditingTaskItem).evaluate().isNotEmpty,
      'First task editor did not appear.',
    );
    expect(find.byType(EditingTaskItem), findsOneWidget);

    await tester.tap(find.text('Second task'));
    await pumpUntil(tester, () {
      final fields = find.byType(TextField);
      if (fields.evaluate().isEmpty) return false;
      final editor = tester.widget<TextField>(fields);
      return editor.controller?.text == 'Second task';
    }, 'Second task did not become the active editor.');

    expect(find.byType(EditingTaskItem), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Second task',
    );
    expect((await tasks.getTasks()).map((task) => task.title), [
      'First task',
      'Second task',
    ]);
  });

  testWidgets('edits a completed task without changing its state or order', (
    WidgetTester tester,
  ) async {
    final older = await tasks.createTask('Older completed');
    final newer = await tasks.createTask('Newer completed');
    final olderCompletedAt = DateTime.utc(2026, 9, 16, 8);
    final newerCompletedAt = DateTime.utc(2026, 9, 16, 9);
    await tasks.setTaskCompletion(
      older.id,
      isCompleted: true,
      completedAt: olderCompletedAt,
    );
    final original = await tasks.setTaskCompletion(
      newer.id,
      isCompleted: true,
      completedAt: newerCompletedAt,
    );
    await pumpKedis(tester);
    await openInbox(tester);

    await tester.tap(find.text('Newer completed'));
    await pumpUntil(
      tester,
      () => find.byType(EditingTaskItem).evaluate().isNotEmpty,
      'Completed task editor did not appear.',
    );
    await tester.enterText(find.byType(TextField), 'Renamed completed');
    await tester.tap(find.byTooltip('Save changes'));
    await pumpUntil(
      tester,
      () =>
          find.text('Renamed completed').evaluate().isNotEmpty &&
          find.byType(EditingTaskItem).evaluate().isEmpty,
      'Completed task edit did not finish saving.',
    );

    final persisted = await tasks.getTasks();
    final updated = persisted.first;
    expect(updated.title, 'Renamed completed');
    expect(updated.id, original?.id);
    expect(updated.createdAt, original?.createdAt);
    expect(updated.isCompleted, isTrue);
    expect(updated.completedAt, newerCompletedAt);
    expect(persisted.last.id, older.id);
    expect(
      tester.getTopLeft(find.text('Renamed completed')).dy,
      lessThan(tester.getTopLeft(find.text('Older completed')).dy),
    );
  });

  testWidgets('leaves a task in Trash after the Undo snackbar expires', (
    WidgetTester tester,
  ) async {
    await tasks.createTask('Delete permanently');
    await pumpKedis(tester);
    await openInbox(tester);

    await tester.tap(find.byTooltip('Delete Delete permanently'));
    await pumpUntil(
      tester,
      () =>
          find.text('Delete permanently').evaluate().isEmpty &&
          find.text('UNDO').evaluate().isNotEmpty,
      'Deleted task did not leave the list or expose Undo.',
    );
    await waitForUndo(tester, 'Delete Undo action was not tappable.');
    await pumpUntil(tester, () {
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      return snackBar.animation?.status == AnimationStatus.completed;
    }, 'Delete Undo snackbar did not finish appearing.');
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    await tester.pump(snackBar.duration);
    await pumpUntil(
      tester,
      () => find.text('UNDO').evaluate().isEmpty,
      'Undo snackbar did not expire.',
    );

    expect(find.text('Delete permanently'), findsNothing);
    expect(await tasks.getTasks(), isEmpty);
    expect((await tasks.getDeletedTasks()).single.title, 'Delete permanently');
    expect(widgetRefreshCount, 1);
  });

  testWidgets('undoes uncompletion with the original completion timestamp', (
    WidgetTester tester,
  ) async {
    final task = await tasks.createTask('Restore completion');
    final completed = await tasks.toggleTask(task.id);
    final originalCompletedAt = completed!.completedAt;
    await pumpKedis(tester);
    await openInbox(tester);

    await tester.tap(find.byType(Checkbox));
    await pumpUntil(
      tester,
      () =>
          find.text('Task marked incomplete').evaluate().isNotEmpty &&
          find.text('UNDO').evaluate().isNotEmpty,
      'Uncompletion did not expose its Undo action.',
    );

    expect(find.text('Completed'), findsNothing);
    await waitForUndo(tester, 'Uncompletion Undo action was not tappable.');

    await tester.tap(find.text('UNDO').hitTestable());
    await pumpUntil(
      tester,
      () =>
          find.text('Completed').evaluate().isNotEmpty &&
          tester.widget<Checkbox>(find.byType(Checkbox)).value == true,
      'Undo did not restore the completed task UI.',
    );

    final restored = (await tasks.getTasks()).single;
    expect(restored.isCompleted, isTrue);
    expect(restored.completedAt, originalCompletedAt);
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(widgetRefreshCount, 2);
  });
}

class _FakeThemePreferenceStore extends ThemePreferenceStore {
  @override
  Future<void> save(ThemeMode themeMode) async {}
}
