import 'dart:io';

import 'package:kedis/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late TaskRepository repository;

  setUp(() {
    sqfliteFfiInit();
    repository = TaskRepository.atPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await repository.close();
  });

  test('creates and reads a task', () async {
    final task = await repository.createTask('  Buy groceries  ');
    final tasks = await repository.getTasks();

    expect(task.id, greaterThan(0));
    expect(task.title, 'Buy groceries');
    expect(task.isCompleted, isFalse);
    expect(task.completedAt, isNull);
    expect(task.deletedAt, isNull);
    expect(task.createdAt.isUtc, isTrue);
    expect(tasks, hasLength(1));
    expect(tasks.single.id, task.id);
    expect(tasks.single.title, task.title);
    expect(tasks.single.isCompleted, isFalse);
    expect(tasks.single.completedAt, isNull);
    expect(tasks.single.createdAt, task.createdAt);
  });

  test('rejects an empty task title', () async {
    expect(() => repository.createTask('   '), throwsA(isA<ArgumentError>()));
    expect(await repository.getTasks(), isEmpty);
  });

  test('updates only the title of an existing task', () async {
    final created = await repository.createTask('Original title');
    final completedAt = DateTime.utc(2026, 9, 3, 10, 30);
    final completed = await repository.setTaskCompletion(
      created.id,
      isCompleted: true,
      completedAt: completedAt,
    );

    final updated = await repository.updateTaskTitle(
      created.id,
      '  Updated title  ',
    );

    expect(updated?.title, 'Updated title');
    expect(updated?.id, completed?.id);
    expect(updated?.createdAt, completed?.createdAt);
    expect(updated?.isCompleted, completed?.isCompleted);
    expect(updated?.completedAt, completedAt);
  });

  test('rejects an empty updated title without changing the task', () async {
    final task = await repository.createTask('Keep title');

    expect(
      () => repository.updateTaskTitle(task.id, '  \n  '),
      throwsA(isA<ArgumentError>()),
    );
    expect((await repository.getTasks()).single.title, 'Keep title');
  });

  test('returns null when updating a title for a missing task', () async {
    expect(await repository.updateTaskTitle(999, 'New title'), isNull);
  });

  test('toggles task completion in both directions', () async {
    final task = await repository.createTask('Review networking');

    final completedTask = await repository.toggleTask(task.id);
    final incompleteTask = await repository.toggleTask(task.id);

    expect(completedTask?.isCompleted, isTrue);
    expect(completedTask?.completedAt, isNotNull);
    expect(completedTask?.completedAt?.isUtc, isTrue);
    expect(incompleteTask?.isCompleted, isFalse);
    expect(incompleteTask?.completedAt, isNull);
    expect((await repository.getTasks()).single.isCompleted, isFalse);
  });

  test('returns null when toggling a task that does not exist', () async {
    expect(await repository.toggleTask(999), isNull);
  });

  test('restores an explicit completion state and timestamp', () async {
    final task = await repository.createTask('Undo state');
    final originalCompletedAt = DateTime.utc(2026, 9, 2, 10, 30);

    final completed = await repository.setTaskCompletion(
      task.id,
      isCompleted: true,
      completedAt: originalCompletedAt,
    );
    final incomplete = await repository.setTaskCompletion(
      task.id,
      isCompleted: false,
      completedAt: null,
    );
    final restored = await repository.setTaskCompletion(
      task.id,
      isCompleted: true,
      completedAt: originalCompletedAt,
    );

    expect(completed?.completedAt, originalCompletedAt);
    expect(incomplete?.isCompleted, isFalse);
    expect(incomplete?.completedAt, isNull);
    expect(restored?.isCompleted, isTrue);
    expect(restored?.completedAt, originalCompletedAt);
  });

  test('soft delete hides a task and exposes it through Trash', () async {
    final task = await repository.createTask('Finish activity');

    expect(await repository.deleteTask(task.id), isTrue);
    expect(await repository.deleteTask(task.id), isFalse);
    expect(await repository.getTasks(), isEmpty);
    expect(await repository.getActiveTasks(), isEmpty);

    final trashed = (await repository.getDeletedTasks()).single;
    expect(trashed.id, task.id);
    expect(trashed.title, task.title);
    expect(trashed.createdAt, task.createdAt);
    expect(trashed.categoryId, task.categoryId);
    expect(trashed.deletedAt, isNotNull);

    expect(await repository.toggleTask(task.id), isNull);
    final stillTrashed = (await repository.getDeletedTasks()).single;
    expect(stillTrashed.isCompleted, task.isCompleted);
    expect(stillTrashed.completedAt, task.completedAt);
  });

  test('restores a deleted task with its original persisted values', () async {
    final created = await repository.createTask('Restore exact task');
    final completedAt = DateTime.utc(2026, 9, 3, 8, 15);
    final completed = await repository.setTaskCompletion(
      created.id,
      isCompleted: true,
      completedAt: completedAt,
    );

    await repository.deleteTask(created.id);
    final trashed = (await repository.getDeletedTasks()).single;
    final restored = await repository.restoreTask(created.id);
    final persisted = (await repository.getTasks()).single;

    expect(trashed.isCompleted, isTrue);
    expect(trashed.completedAt, completedAt);
    expect(restored?.id, completed?.id);
    expect(restored?.deletedAt, isNull);
    expect(persisted.id, created.id);
    expect(persisted.title, created.title);
    expect(persisted.isCompleted, isTrue);
    expect(persisted.createdAt, created.createdAt);
    expect(persisted.completedAt, completedAt);
  });

  test('permanently deletes only a task already in Trash', () async {
    final task = await repository.createTask('Delete forever');

    expect(await repository.permanentlyDeleteTask(task.id), isFalse);
    await repository.deleteTask(task.id);
    expect(await repository.permanentlyDeleteTask(task.id), isTrue);
    expect(await repository.getDeletedTasks(), isEmpty);
    expect(await repository.restoreTask(task.id), isNull);
  });

  test('keeps tasks after reopening the database', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kedis_test_',
    );
    final databasePath = '${temporaryDirectory.path}/dewwit.db';
    final firstRepository = TaskRepository.atPath(
      databasePath,
      factory: databaseFactoryFfi,
    );
    final secondRepository = TaskRepository.atPath(
      databasePath,
      factory: databaseFactoryFfi,
    );

    try {
      final task = await firstRepository.createTask('Persistent task');
      await firstRepository.close();

      final tasks = await secondRepository.getTasks();
      expect(tasks.single.id, task.id);
      expect(tasks.single.title, task.title);
    } finally {
      await firstRepository.close();
      await secondRepository.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('orders active tasks before recently completed tasks', () async {
    final oldest = await repository.createTask('Oldest active');
    final middle = await repository.createTask('Middle active');
    await repository.createTask('Newest active');

    await repository.toggleTask(oldest.id);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repository.toggleTask(middle.id);

    expect((await repository.getTasks()).map((task) => task.title), [
      'Newest active',
      'Middle active',
      'Oldest active',
    ]);
  });

  test(
    'migrates version 1 tasks and orders legacy completions safely',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'kedis_migration_test_',
      );
      final databasePath = '${temporaryDirectory.path}/dewwit.db';
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              is_completed INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
            await database.insert('tasks', {
              'title': 'Legacy completed',
              'is_completed': 1,
              'created_at': 1000,
            });
            await database.insert('tasks', {
              'title': 'Legacy active',
              'is_completed': 0,
              'created_at': 2000,
            });
          },
        ),
      );
      await oldDatabase.close();

      final migratedRepository = TaskRepository.atPath(
        databasePath,
        factory: databaseFactoryFfi,
      );
      try {
        final tasks = await migratedRepository.getTasks();
        expect(tasks.map((task) => task.title), [
          'Legacy active',
          'Legacy completed',
        ]);
        expect(tasks.last.completedAt, isNull);

        final recompleted = await migratedRepository.toggleTask(tasks.last.id);
        expect(recompleted?.isCompleted, isFalse);
        expect(recompleted?.completedAt, isNull);
      } finally {
        await migratedRepository.close();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );
}
