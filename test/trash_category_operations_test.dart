import 'package:flutter_test/flutter_test.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/kedis_database.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late KedisDatabase database;
  late CategoryRepository categories;
  late TaskRepository tasks;

  setUp(() {
    sqfliteFfiInit();
    database = KedisDatabase.atPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    categories = CategoryRepository.withDatabase(database);
    tasks = TaskRepository.withDatabase(database);
  });

  tearDown(() => database.close());

  test('soft-deletes an empty category and reserves its name', () async {
    final category = await categories.createCategory('School', 0xFF6750A4);

    final result = await categories.softDeleteEmptyCategory(category.id);
    final deleted = (await categories.getDeletedCategories()).single;

    expect(result.categoryId, category.id);
    expect(result.movedTaskCount, 0);
    expect(result.deletedTaskCount, 0);
    expect(result.detachedTaskCount, 0);
    expect(deleted.id, category.id);
    expect(deleted.name, category.name);
    expect(deleted.colorValue, category.colorValue);
    expect(deleted.createdAt, category.createdAt);
    expect(deleted.deletedAt, result.deletedAt);
    expect(
      () => categories.createCategory(' school ', 0xFF006C4C),
      throwsStateError,
    );
    await _expectForeignKeysValid(database);

    await categories.permanentlyDeleteCategory(category.id, const []);
    final replacement = await categories.createCategory('school', 0xFF006C4C);
    expect(replacement.name, 'school');
    await _expectForeignKeysValid(database);
  });

  test('soft deletion detaches an individually deleted task', () async {
    final category = await categories.createCategory('School', 0xFF6750A4);
    final task = await tasks.createTask(
      'Already deleted',
      categoryId: category.id,
    );
    await tasks.deleteTask(task.id);
    final originalDeletedAt = (await tasks.getDeletedTasks()).single.deletedAt;

    final result = await categories.softDeleteEmptyCategory(category.id);
    final standalone = (await tasks.getStandaloneDeletedTasks()).single;

    expect(result.detachedTaskCount, 1);
    expect(standalone.id, task.id);
    expect(standalone.categoryId, isNull);
    expect(standalone.deletedAt, originalDeletedAt);
    expect(standalone.deletedGroupCategoryId, isNull);
    await _expectForeignKeysValid(database);
  });

  test(
    'moves active tasks to an explicit destination before deletion',
    () async {
      final source = await categories.createCategory('Source', 0xFF6750A4);
      final destination = await categories.createCategory('Target', 0xFF006C4C);
      final active = await tasks.createTask('Active', categoryId: source.id);
      final completed = await tasks.createTask(
        'Completed',
        categoryId: source.id,
      );
      final completedAt = DateTime.utc(2026, 9, 20, 8, 30);
      await tasks.setTaskCompletion(
        completed.id,
        isCompleted: true,
        completedAt: completedAt,
      );
      final individuallyDeleted = await tasks.createTask(
        'Standalone',
        categoryId: source.id,
      );
      await tasks.deleteTask(individuallyDeleted.id);
      final standaloneDeletedAt =
          (await tasks.getDeletedTasks()).single.deletedAt;

      final result = await categories.softDeleteCategoryMovingTasks(
        source.id,
        destination.id,
      );
      final moved = await tasks.getTasks(categoryId: destination.id);
      final standalone = (await tasks.getStandaloneDeletedTasks()).single;

      expect(result.movedTaskCount, 2);
      expect(result.detachedTaskCount, 1);
      expect(
        moved.map((task) => task.id),
        containsAll([active.id, completed.id]),
      );
      final persistedCompleted = moved.singleWhere(
        (task) => task.id == completed.id,
      );
      expect(persistedCompleted.createdAt, completed.createdAt);
      expect(persistedCompleted.isCompleted, isTrue);
      expect(persistedCompleted.completedAt, completedAt);
      expect(standalone.categoryId, isNull);
      expect(standalone.deletedAt, standaloneDeletedAt);
      expect((await categories.getDeletedCategories()).single.id, source.id);
      await _expectForeignKeysValid(database);
    },
  );

  test(
    'trashes active tasks as a group without capturing deleted tasks',
    () async {
      final category = await categories.createCategory('Project', 0xFF6750A4);
      final other = await categories.createCategory('Other', 0xFF006C4C);
      final active = await tasks.createTask('Active', categoryId: category.id);
      final completed = await tasks.createTask(
        'Completed',
        categoryId: category.id,
      );
      final completedAt = DateTime.utc(2026, 9, 20, 9);
      await tasks.setTaskCompletion(
        completed.id,
        isCompleted: true,
        completedAt: completedAt,
      );
      final standalone = await tasks.createTask(
        'Deleted first',
        categoryId: category.id,
      );
      await tasks.deleteTask(standalone.id);
      final standaloneBefore = (await tasks.getDeletedTasks()).single;
      final untouched = await tasks.createTask(
        'Untouched',
        categoryId: other.id,
      );

      final result = await categories.softDeleteCategoryWithTasks(category.id);
      final grouped = await tasks.getDeletedTasksForCategoryGroup(category.id);
      final standaloneAfter = (await tasks.getStandaloneDeletedTasks()).single;

      expect(result.deletedTaskCount, 2);
      expect(result.detachedTaskCount, 1);
      expect(
        grouped.map((task) => task.id),
        containsAll([active.id, completed.id]),
      );
      expect(grouped.every((task) => task.categoryId == null), isTrue);
      expect(
        grouped.every((task) => task.deletedAt == result.deletedAt),
        isTrue,
      );
      final groupedCompleted = grouped.singleWhere(
        (task) => task.id == completed.id,
      );
      expect(groupedCompleted.createdAt, completed.createdAt);
      expect(groupedCompleted.isCompleted, isTrue);
      expect(groupedCompleted.completedAt, completedAt);
      expect(standaloneAfter.id, standalone.id);
      expect(standaloneAfter.deletedAt, standaloneBefore.deletedAt);
      expect(standaloneAfter.deletedGroupCategoryId, isNull);
      expect(
        (await tasks.getTasks(categoryId: other.id)).single.id,
        untouched.id,
      );
      expect(
        (await tasks.getStandaloneDeletedTasks())
            .map((task) => task.id)
            .toSet()
            .intersection(grouped.map((task) => task.id).toSet()),
        isEmpty,
      );
      await _expectForeignKeysValid(database);
    },
  );

  test('restores a category with zero selected tasks', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);
    final before = await tasks.getDeletedTasksForCategoryGroup(
      setup.categoryId,
    );

    final result = await categories.restoreDeletedCategory(
      setup.categoryId,
      const [],
    );

    expect(result.selectedTaskCount, 0);
    expect(result.detachedTaskCount, 2);
    expect(await categories.getDeletedCategories(), isEmpty);
    expect(
      await tasks.getDeletedTasksForCategoryGroup(setup.categoryId),
      isEmpty,
    );
    final standalone = await tasks.getStandaloneDeletedTasks();
    expect(standalone.map((task) => task.id), containsAll(setup.taskIds));
    for (final task in standalone) {
      expect(task.categoryId, isNull);
      expect(
        task.deletedAt,
        before.singleWhere((item) => item.id == task.id).deletedAt,
      );
    }
    await _expectForeignKeysValid(database);
  });

  test(
    'restores only selected grouped tasks with their state intact',
    () async {
      final setup = await _createDeletedGroup(categories, tasks, taskCount: 3);
      final selectedId = setup.taskIds[1];
      final before = (await tasks.getDeletedTasksForCategoryGroup(
        setup.categoryId,
      )).singleWhere((task) => task.id == selectedId);

      final result = await categories.restoreDeletedCategory(setup.categoryId, [
        selectedId,
      ]);
      final restored = (await tasks.getTasks(categoryId: setup.categoryId))
          .single;
      final standalone = await tasks.getStandaloneDeletedTasks();

      expect(result.selectedTaskCount, 1);
      expect(result.detachedTaskCount, 2);
      expect(restored.id, selectedId);
      expect(restored.createdAt, before.createdAt);
      expect(restored.isCompleted, before.isCompleted);
      expect(restored.completedAt, before.completedAt);
      expect(restored.deletedAt, isNull);
      expect(restored.deletedGroupCategoryId, isNull);
      expect(
        standalone.map((task) => task.id),
        containsAll(setup.taskIds.where((id) => id != selectedId)),
      );
      await _expectForeignKeysValid(database);
    },
  );

  test('restores a category with all grouped tasks selected', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);

    await categories.restoreDeletedCategory(setup.categoryId, setup.taskIds);

    expect(
      (await tasks.getTasks(categoryId: setup.categoryId))
          .map((task) => task.id),
      containsAll(setup.taskIds),
    );
    expect(await tasks.getStandaloneDeletedTasks(), isEmpty);
    expect(
      await tasks.getDeletedTasksForCategoryGroup(setup.categoryId),
      isEmpty,
    );
    await _expectForeignKeysValid(database);
  });

  test('permanently deletes a category with zero selected tasks', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);
    final before = await tasks.getDeletedTasksForCategoryGroup(
      setup.categoryId,
    );

    final result = await categories.permanentlyDeleteCategory(
      setup.categoryId,
      const [],
    );
    final standalone = await tasks.getStandaloneDeletedTasks();

    expect(result.selectedTaskCount, 0);
    expect(result.detachedTaskCount, 2);
    expect(await categories.getDeletedCategories(), isEmpty);
    expect(standalone.map((task) => task.id), containsAll(setup.taskIds));
    for (final task in standalone) {
      expect(
        task.deletedAt,
        before.singleWhere((item) => item.id == task.id).deletedAt,
      );
    }
    await _expectForeignKeysValid(database);
  });

  test('permanently deletes only selected grouped tasks', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 3);
    final selectedId = setup.taskIds.first;

    await categories.permanentlyDeleteCategory(setup.categoryId, [selectedId]);
    final deleted = await tasks.getDeletedTasks();

    expect(deleted.any((task) => task.id == selectedId), isFalse);
    expect(
      deleted.map((task) => task.id),
      containsAll(setup.taskIds.where((id) => id != selectedId)),
    );
    expect(
      deleted.every((task) => task.deletedGroupCategoryId == null),
      isTrue,
    );
    await _expectForeignKeysValid(database);
  });

  test(
    'permanently deletes a category and all selected grouped tasks',
    () async {
      final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);

      await categories.permanentlyDeleteCategory(
        setup.categoryId,
        setup.taskIds,
      );

      expect(await categories.getDeletedCategories(), isEmpty);
      expect(await tasks.getDeletedTasks(), isEmpty);
      await _expectForeignKeysValid(database);
    },
  );

  test('restores one grouped task to an explicit active destination', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);
    final destination = await categories.createCategory('Target', 0xFF006C4C);
    final selectedId = setup.taskIds.first;

    final restored = await tasks.restoreTask(
      selectedId,
      destinationCategoryId: destination.id,
    );

    expect(restored?.categoryId, destination.id);
    expect(restored?.deletedAt, isNull);
    expect(restored?.deletedGroupCategoryId, isNull);
    expect(
      (await categories.getDeletedCategories()).single.id,
      setup.categoryId,
    );
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId)).single.id,
      setup.taskIds.last,
    );
    await _expectForeignKeysValid(database);
  });

  test(
    'restores standalone tasks according to category availability',
    () async {
      final retained = await categories.createCategory('Retained', 0xFF6750A4);
      final destination = await categories.createCategory('Target', 0xFF006C4C);
      final retainedTask = await tasks.createTask(
        'Retained',
        categoryId: retained.id,
      );
      await tasks.deleteTask(retainedTask.id);

      final restoredRetained = await tasks.restoreTask(retainedTask.id);
      expect(restoredRetained?.categoryId, retained.id);

      final categorylessId = await _insertDeletedTask(
        database,
        title: 'Detached',
      );
      await expectLater(tasks.restoreTask(categorylessId), throwsArgumentError);
      expect(
        (await tasks.getStandaloneDeletedTasks()).any(
          (task) => task.id == categorylessId,
        ),
        isTrue,
      );
      final restoredDetached = await tasks.restoreTask(
        categorylessId,
        destinationCategoryId: destination.id,
      );
      expect(restoredDetached?.categoryId, destination.id);
      expect(restoredDetached?.deletedGroupCategoryId, isNull);
      await _expectForeignKeysValid(database);
    },
  );

  test('rejects invalid destinations without changing data', () async {
    final source = await categories.createCategory('Source', 0xFF6750A4);
    final deletedDestination = await categories.createCategory(
      'Deleted',
      0xFF006C4C,
    );
    final task = await tasks.createTask('Keep', categoryId: source.id);
    await categories.softDeleteEmptyCategory(deletedDestination.id);

    for (final destinationId in [9999, deletedDestination.id]) {
      await expectLater(
        categories.softDeleteCategoryMovingTasks(source.id, destinationId),
        throwsStateError,
      );
      expect((await tasks.getTasks(categoryId: source.id)).single.id, task.id);
      expect(
        (await categories.getCategories()).any(
          (category) => category.id == source.id,
        ),
        isTrue,
      );
      await expectLater(
        tasks.moveTaskToCategory(task.id, destinationId),
        throwsStateError,
      );
      await expectLater(
        tasks.createTask('Invalid', categoryId: destinationId),
        throwsStateError,
      );
    }
    expect(
      (await tasks.getTasks()).where((item) => item.title == 'Invalid'),
      isEmpty,
    );
    await _expectForeignKeysValid(database);
  });

  test('rejects invalid category states and restore destinations', () async {
    final source = await categories.createCategory('Source', 0xFF6750A4);
    final deletedDestination = await categories.createCategory(
      'Deleted destination',
      0xFF006C4C,
    );
    final activeTask = await tasks.createTask(
      'Still active',
      categoryId: source.id,
    );

    await expectLater(
      categories.softDeleteEmptyCategory(source.id),
      throwsStateError,
    );
    expect(
      (await tasks.getTasks(categoryId: source.id)).single.id,
      activeTask.id,
    );
    await expectLater(
      categories.softDeleteCategoryMovingTasks(source.id, source.id),
      throwsArgumentError,
    );
    await expectLater(
      categories.softDeleteEmptyCategory(99999),
      throwsStateError,
    );

    await categories.softDeleteEmptyCategory(deletedDestination.id);
    await expectLater(
      categories.softDeleteEmptyCategory(deletedDestination.id),
      throwsStateError,
    );
    final categorylessId = await _insertDeletedTask(
      database,
      title: 'Needs destination',
    );
    for (final destinationId in [99999, deletedDestination.id]) {
      await expectLater(
        tasks.restoreTask(categorylessId, destinationCategoryId: destinationId),
        throwsStateError,
      );
      expect(
        (await tasks.getStandaloneDeletedTasks()).any(
          (task) => task.id == categorylessId,
        ),
        isTrue,
      );
    }
    await _expectForeignKeysValid(database);
  });

  test('invalid grouped selections roll back the entire operation', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);
    final other = await _createDeletedGroup(categories, tasks, taskCount: 1);
    final activeCategory = await categories.createCategory(
      'Active',
      0xFF426A5A,
    );
    final activeTask = await tasks.createTask(
      'Active',
      categoryId: activeCategory.id,
    );
    final invalidSelections = <List<int>>[
      [setup.taskIds.first, setup.taskIds.first],
      [other.taskIds.first],
      [activeTask.id],
      [99999],
    ];

    for (final selection in invalidSelections) {
      await expectLater(
        categories.restoreDeletedCategory(setup.categoryId, selection),
        throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
      );
      expect(
        (await categories.getDeletedCategories()).any(
          (category) => category.id == setup.categoryId,
        ),
        isTrue,
      );
      expect(
        (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId))
            .map((task) => task.id),
        containsAll(setup.taskIds),
      );
      await expectLater(
        categories.permanentlyDeleteCategory(setup.categoryId, selection),
        throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
      );
    }
    await _expectForeignKeysValid(database);
  });

  test('repository operations cannot delete Inbox', () async {
    final inbox = await categories.getInbox();

    await expectLater(
      categories.softDeleteEmptyCategory(inbox.id),
      throwsStateError,
    );
    await expectLater(
      categories.softDeleteCategoryWithTasks(inbox.id),
      throwsStateError,
    );
    await expectLater(
      categories.softDeleteCategoryMovingTasks(inbox.id, inbox.id + 1000),
      throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
    );
    expect((await categories.getInbox()).deletedAt, isNull);
    await _expectForeignKeysValid(database);
  });

  test('permanently deleting one grouped task changes nothing else', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 2);
    final selectedId = setup.taskIds.first;

    expect(await tasks.permanentlyDeleteTask(selectedId), isTrue);

    expect(
      (await categories.getDeletedCategories()).single.id,
      setup.categoryId,
    );
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId)).single.id,
      setup.taskIds.last,
    );
    await _expectForeignKeysValid(database);
  });

  test(
    'batch restore preserves valid categories and assigns categoryless tasks',
    () async {
      final inbox = await categories.getInbox();
      final retained = await categories.createCategory('Retained', 0xFF6750A4);
      final retainedTask = await tasks.createTask(
        'Retained task',
        categoryId: retained.id,
      );
      await tasks.deleteTask(retainedTask.id);

      final deletedCategory = await categories.createCategory(
        'Deleted group',
        0xFF006C4C,
      );
      final categorylessTask = await tasks.createTask(
        'Categoryless task',
        categoryId: deletedCategory.id,
      );
      await categories.softDeleteCategoryWithTasks(deletedCategory.id);
      await categories.restoreDeletedCategory(deletedCategory.id, const []);

      final restoredCount = await tasks.restoreStandaloneTasks([
        retainedTask.id,
        categorylessTask.id,
      ], destinationCategoryId: inbox.id);
      final restored = await tasks.getTasks();

      expect(restoredCount, 2);
      expect(
        restored.singleWhere((task) => task.id == retainedTask.id).categoryId,
        retained.id,
      );
      expect(
        restored
            .singleWhere((task) => task.id == categorylessTask.id)
            .categoryId,
        inbox.id,
      );
      expect(restored.every((task) => task.deletedAt == null), isTrue);
      await _expectForeignKeysValid(database);
    },
  );

  test('invalid standalone batch selection changes no tasks', () async {
    final deleted = await tasks.createTask('Deleted');
    final active = await tasks.createTask('Active');
    await tasks.deleteTask(deleted.id);

    await expectLater(
      tasks.restoreStandaloneTasks([deleted.id, active.id]),
      throwsStateError,
    );
    expect((await tasks.getStandaloneDeletedTasks()).single.id, deleted.id);
    expect((await tasks.getTasks()).single.id, active.id);

    await expectLater(
      tasks.permanentlyDeleteStandaloneTasks([deleted.id, active.id]),
      throwsStateError,
    );
    expect((await tasks.getStandaloneDeletedTasks()).single.id, deleted.id);
    await _expectForeignKeysValid(database);
  });

  test(
    'batch permanent deletion removes only selected standalone tasks',
    () async {
      final first = await tasks.createTask('First');
      final second = await tasks.createTask('Second');
      await tasks.deleteTask(first.id);
      await tasks.deleteTask(second.id);

      expect(await tasks.permanentlyDeleteStandaloneTasks([first.id]), 1);

      expect((await tasks.getStandaloneDeletedTasks()).single.id, second.id);
      expect(await tasks.restoreTask(first.id), isNull);
      await _expectForeignKeysValid(database);
    },
  );

  test('batch restores only selected grouped tasks', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 5);
    final destination = await categories.createCategory(
      'Destination',
      0xFF006C4C,
    );
    final selected = setup.taskIds.take(2).toList(growable: false);
    final unselected = setup.taskIds.skip(2).toSet();

    expect(
      await tasks.restoreGroupedTasks(
        setup.categoryId,
        selected,
        destinationCategoryId: destination.id,
      ),
      2,
    );

    expect(
      (await tasks.getTasks(categoryId: destination.id)).map((task) => task.id),
      containsAll(selected),
    );
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId))
          .map((task) => task.id)
          .toSet(),
      unselected,
    );
    expect(
      (await categories.getDeletedCategories()).single.id,
      setup.categoryId,
    );
    await _expectForeignKeysValid(database);
  });

  test('batch permanently deletes only selected grouped tasks', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 5);
    final selected = setup.taskIds.take(2).toList(growable: false);
    final unselected = setup.taskIds.skip(2).toSet();

    expect(
      await tasks.permanentlyDeleteGroupedTasks(setup.categoryId, selected),
      2,
    );

    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId))
          .map((task) => task.id)
          .toSet(),
      unselected,
    );
    expect(
      (await categories.getDeletedCategories()).single.id,
      setup.categoryId,
    );
    for (final id in selected) {
      expect(await tasks.restoreTask(id), isNull);
    }
    await _expectForeignKeysValid(database);
  });

  test('invalid grouped batch selections cause no partial changes', () async {
    final setup = await _createDeletedGroup(categories, tasks, taskCount: 3);
    final other = await _createDeletedGroup(categories, tasks, taskCount: 1);
    final destination = await categories.createCategory(
      'Destination',
      0xFF006C4C,
    );
    final before = setup.taskIds.toSet();
    final invalid = [setup.taskIds.first, other.taskIds.first];

    await expectLater(
      tasks.restoreGroupedTasks(
        setup.categoryId,
        invalid,
        destinationCategoryId: destination.id,
      ),
      throwsStateError,
    );
    expect(await tasks.getTasks(categoryId: destination.id), isEmpty);
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId))
          .map((task) => task.id)
          .toSet(),
      before,
    );

    await expectLater(
      tasks.permanentlyDeleteGroupedTasks(setup.categoryId, invalid),
      throwsStateError,
    );
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(setup.categoryId))
          .map((task) => task.id)
          .toSet(),
      before,
    );
    await _expectForeignKeysValid(database);
  });
}

Future<_DeletedGroup> _createDeletedGroup(
  CategoryRepository categories,
  TaskRepository tasks, {
  required int taskCount,
}) async {
  final category = await categories.createCategory(
    'Group ${DateTime.now().microsecondsSinceEpoch}',
    0xFF6750A4,
  );
  final taskIds = <int>[];
  for (var index = 0; index < taskCount; index += 1) {
    final task = await tasks.createTask('Task $index', categoryId: category.id);
    taskIds.add(task.id);
    if (index.isOdd) {
      await tasks.setTaskCompletion(
        task.id,
        isCompleted: true,
        completedAt: DateTime.utc(2026, 9, 20, 10, index),
      );
    }
  }
  await categories.softDeleteCategoryWithTasks(category.id);
  return _DeletedGroup(category.id, taskIds);
}

Future<int> _insertDeletedTask(
  KedisDatabase kedisDatabase, {
  required String title,
}) async {
  final database = await kedisDatabase.database;
  return database.insert(KedisDatabase.tasksTable, {
    'title': title,
    'is_completed': 0,
    'created_at': 1000,
    'completed_at': null,
    'category_id': null,
    'deleted_at': 2000,
    'deleted_group_category_id': null,
  });
}

Future<void> _expectForeignKeysValid(KedisDatabase kedisDatabase) async {
  final database = await kedisDatabase.database;
  expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
}

class _DeletedGroup {
  const _DeletedGroup(this.categoryId, this.taskIds);

  final int categoryId;
  final List<int> taskIds;
}

final throwsStateError = throwsA(isA<StateError>());
final throwsArgumentError = throwsA(isA<ArgumentError>());
