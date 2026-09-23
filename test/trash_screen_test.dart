import 'package:kedis/screens/trash_screen.dart';
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

  Future<void> pumpTrash(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrashScreen(
          categoryRepository: categories,
          taskRepository: tasks,
          widgetRefresh: () async {
            widgetRefreshCount += 1;
          },
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.text('Trash is empty').evaluate().isNotEmpty ||
          find.byType(ListTile).evaluate().isNotEmpty,
      'Trash screen did not finish loading.',
    );
  }

  testWidgets('shows an empty state when Trash has no tasks', (
    WidgetTester tester,
  ) async {
    await pumpTrash(tester);

    expect(find.text('Trash is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores an individual task from Trash', (
    WidgetTester tester,
  ) async {
    final task = await tasks.createTask('Restore me');
    await tasks.deleteTask(task.id);
    await pumpTrash(tester);

    expect(find.text('Restore me'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore Restore me'));
    await pumpUntil(
      tester,
      () => find.text('Trash is empty').evaluate().isNotEmpty,
      'Restored task did not leave Trash.',
    );

    expect((await tasks.getTasks()).single.id, task.id);
    expect(await tasks.getDeletedTasks(), isEmpty);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('requires confirmation before permanent deletion', (
    WidgetTester tester,
  ) async {
    final task = await tasks.createTask('Delete forever');
    await tasks.deleteTask(task.id);
    await pumpTrash(tester);

    await tester.tap(find.byTooltip('Permanently delete Delete forever'));
    await pumpUntil(
      tester,
      () => find.text('Permanently delete task?').evaluate().isNotEmpty,
      'Permanent-delete confirmation did not appear.',
    );
    expect((await tasks.getDeletedTasks()).single.id, task.id);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await tasks.getDeletedTasks()).single.id, task.id);

    await tester.tap(find.byTooltip('Permanently delete Delete forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await pumpUntil(
      tester,
      () => find.text('Trash is empty').evaluate().isNotEmpty,
      'Permanently deleted task remained in Trash.',
    );

    expect(await tasks.getDeletedTasks(), isEmpty);
    expect(await tasks.restoreTask(task.id), isNull);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('shows grouped and standalone tasks without duplication', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    final grouped = await tasks.createTask('Grouped', categoryId: category.id);
    final standalone = await tasks.createTask(
      'Standalone',
      categoryId: category.id,
    );
    await tasks.deleteTask(standalone.id);
    await categories.softDeleteCategoryWithTasks(category.id);

    await pumpTrash(tester);

    expect(find.text('Deleted Categories'), findsOneWidget);
    expect(find.text('Deleted Tasks'), findsOneWidget);
    expect(find.text('Project'), findsOneWidget);
    expect(find.text('1 grouped task'), findsOneWidget);
    expect(find.text('Standalone'), findsOneWidget);
    expect(find.text('Grouped'), findsNothing);

    await tester.tap(find.byKey(ValueKey('deleted-category-${category.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Grouped'), findsOneWidget);
    expect(find.byKey(ValueKey('deleted-task-${grouped.id}')), findsOneWidget);
    expect(find.text('Standalone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores a category with empty selection and detaches tasks', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    final task = await tasks.createTask(
      'Keep deleted',
      categoryId: category.id,
    );
    await categories.softDeleteCategoryWithTasks(category.id);
    await pumpTrash(tester);

    await tester.tap(find.byTooltip('Deleted category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore category'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey('category-dialog-task-${task.id}')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-category-restore')));
    await pumpUntil(
      tester,
      () => find.text('Project').evaluate().isEmpty,
      'Restored category remained in Deleted Categories.',
    );

    expect(
      (await categories.getCategories()).any((item) => item.id == category.id),
      isTrue,
    );
    final remaining = (await tasks.getStandaloneDeletedTasks()).single;
    expect(remaining.id, task.id);
    expect(remaining.categoryId, isNull);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('restores only explicitly selected grouped tasks', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    final first = await tasks.createTask('First', categoryId: category.id);
    final second = await tasks.createTask('Second', categoryId: category.id);
    await categories.softDeleteCategoryWithTasks(category.id);
    await pumpTrash(tester);

    await tester.tap(find.byTooltip('Deleted category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('category-dialog-task-${first.id}')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-category-restore')));
    await tester.pumpAndSettle();

    expect((await tasks.getTasks()).single.id, first.id);
    expect((await tasks.getStandaloneDeletedTasks()).single.id, second.id);
  });

  testWidgets('select all and deselect all are scoped to a category dialog', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    await tasks.createTask('First', categoryId: category.id);
    await tasks.createTask('Second', categoryId: category.id);
    await categories.softDeleteCategoryWithTasks(category.id);
    await pumpTrash(tester);

    await tester.tap(find.byTooltip('Deleted category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Deselect All'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-category-permanent-delete')),
    );
    await tester.pumpAndSettle();

    expect(await categories.getDeletedCategories(), isEmpty);
    expect(await tasks.getStandaloneDeletedTasks(), hasLength(2));
  });

  testWidgets(
    'grouped task restore requires an Inbox-preselected destination',
    (WidgetTester tester) async {
      final category = await categories.createCategory('Project', 0xFF6750A4);
      final task = await tasks.createTask('Grouped', categoryId: category.id);
      await categories.softDeleteCategoryWithTasks(category.id);
      await pumpTrash(tester);
      await tester.tap(find.byKey(ValueKey('deleted-category-${category.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Restore Grouped'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(const ValueKey('trash-restore-destination')),
            )
            .initialValue,
        (await categories.getInbox()).id,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-trash-destination')));
      await tester.pumpAndSettle();

      expect((await tasks.getTasks()).single.id, task.id);
      expect(await tasks.getDeletedTasksForCategoryGroup(category.id), isEmpty);
      expect((await categories.getDeletedCategories()).single.id, category.id);
    },
  );

  testWidgets('categoryless standalone restore requires a destination', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    final task = await tasks.createTask('Detached', categoryId: category.id);
    await categories.softDeleteCategoryWithTasks(category.id);
    await categories.restoreDeletedCategory(category.id, const []);
    await pumpTrash(tester);

    await tester.tap(find.byTooltip('Restore Detached'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('trash-restore-destination')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-trash-destination')));
    await tester.pumpAndSettle();

    final restored = (await tasks.getTasks()).single;
    expect(restored.id, task.id);
    expect(restored.categoryId, (await categories.getInbox()).id);
  });

  testWidgets('batch restores selected standalone tasks', (
    WidgetTester tester,
  ) async {
    final first = await tasks.createTask('First');
    final second = await tasks.createTask('Second');
    await tasks.deleteTask(first.id);
    await tasks.deleteTask(second.id);
    await pumpTrash(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('deleted-task-${first.id}')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Restore selected tasks'));
    await tester.pumpAndSettle();

    expect((await tasks.getTasks()).single.id, first.id);
    expect((await tasks.getStandaloneDeletedTasks()).single.id, second.id);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('batch permanent deletion can be cancelled or confirmed', (
    WidgetTester tester,
  ) async {
    final task = await tasks.createTask('Selected');
    await tasks.deleteTask(task.id);
    await pumpTrash(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('deleted-task-${task.id}')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Permanently delete selected tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await tasks.getStandaloneDeletedTasks(), hasLength(1));

    await tester.tap(find.byTooltip('Permanently delete selected tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-batch-delete')));
    await tester.pumpAndSettle();
    expect(await tasks.getStandaloneDeletedTasks(), isEmpty);
  });
}
