import 'package:kedis/screens/trash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_repositories.dart';

void main() {
  late FakeTaskRepository tasks;
  late int widgetRefreshCount;

  setUp(() {
    final repositories = FakeRepositories();
    tasks = repositories.tasks;
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
}
