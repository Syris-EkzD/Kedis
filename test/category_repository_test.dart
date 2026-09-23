import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/kedis_database.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('creates custom categories after the system Inbox', () async {
    final inbox = await categories.getInbox();
    final school = await categories.createCategory('  School  ', 0xFF6750A4);
    final programming = await categories.createCategory(
      'Programming',
      0xFF006C4C,
    );

    final allCategories = await categories.getCategories();
    final persistedSchool = allCategories.singleWhere(
      (category) => category.id == school.id,
    );
    expect(inbox.isSystem, isTrue);
    expect(inbox.name, 'Inbox');
    expect(school.name, 'School');
    expect(school.colorValue, 0xFF6750A4);
    expect(school.createdAt.microsecondsSinceEpoch % 1000, 0);
    expect(persistedSchool.createdAt, school.createdAt);
    expect(programming.name, 'Programming');
    expect(allCategories.map((category) => category.id), [
      inbox.id,
      school.id,
      programming.id,
    ]);
  });

  test('rejects empty and normalized duplicate category names', () async {
    await categories.createCategory('School', 0xFF6750A4);

    expect(
      () => categories.createCategory('   ', 0xFF006C4C),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => categories.createCategory('  school  ', 0xFF006C4C),
      throwsA(isA<StateError>()),
    );
  });

  test('renames and recolors a custom category', () async {
    final category = await categories.createCategory('Code', 0xFF6750A4);

    final renamed = await categories.renameCategory(
      category.id,
      ' Programming ',
    );
    final recolored = await categories.updateCategoryColor(
      category.id,
      0xFF006C4C,
    );

    expect(renamed?.name, 'Programming');
    expect(renamed?.id, category.id);
    expect(recolored?.colorValue, 0xFF006C4C);
    expect(recolored?.createdAt, category.createdAt);
  });

  test('prevents changes that would alter the system Inbox', () async {
    final inbox = await categories.getInbox();

    expect(
      () => categories.renameCategory(inbox.id, 'Other'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => categories.updateCategoryColor(inbox.id, 0xFF6750A4),
      throwsA(isA<StateError>()),
    );
    expect(
      () => categories.deleteCategory(inbox.id),
      throwsA(isA<StateError>()),
    );
  });

  test('deleting a custom category moves its tasks to Inbox', () async {
    final inbox = await categories.getInbox();
    final category = await categories.createCategory('Programming', 0xFF006C4C);
    final task = await tasks.createTask(
      'Build category screen',
      categoryId: category.id,
    );

    final movedCount = await categories.deleteCategory(category.id);
    final remainingCategories = await categories.getCategories();
    final remainingTasks = await tasks.getTasks();

    expect(movedCount, 1);
    expect(remainingCategories.any((item) => item.id == category.id), isFalse);
    expect(remainingTasks.single.id, task.id);
    expect(remainingTasks.single.categoryId, inbox.id);
  });

  test('deleting a category moves its trashed tasks to Inbox', () async {
    final inbox = await categories.getInbox();
    final category = await categories.createCategory('School', 0xFF6750A4);
    final task = await tasks.createTask(
      'Restore later',
      categoryId: category.id,
    );
    await tasks.deleteTask(task.id);

    final movedCount = await categories.deleteCategory(category.id);
    final trashed = (await tasks.getDeletedTasks()).single;

    expect(movedCount, 1);
    expect(trashed.id, task.id);
    expect(trashed.categoryId, inbox.id);

    final restored = await tasks.restoreTask(task.id);
    expect(restored?.categoryId, inbox.id);
    expect((await tasks.getTasks(categoryId: inbox.id)).single.id, task.id);
  });
}
