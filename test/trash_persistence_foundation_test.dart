import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/kedis_database.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates the complete schema v5 foundation', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kedis_schema_v5_',
    );
    final databasePath = '${temporaryDirectory.path}/dewwit.db';
    final kedisDatabase = KedisDatabase.atPath(
      databasePath,
      factory: databaseFactoryFfi,
    );

    try {
      final database = await kedisDatabase.database;
      expect(await database.getVersion(), 5);

      final categoryColumns = await database.rawQuery(
        'PRAGMA table_info(${KedisDatabase.categoriesTable})',
      );
      final taskColumns = await database.rawQuery(
        'PRAGMA table_info(${KedisDatabase.tasksTable})',
      );
      expect(
        categoryColumns.map((column) => column['name']),
        contains('deleted_at'),
      );
      expect(
        taskColumns.map((column) => column['name']),
        containsAll(['category_id', 'deleted_at', 'deleted_group_category_id']),
      );
      expect(
        taskColumns.singleWhere(
          (column) => column['name'] == 'category_id',
        )['notnull'],
        0,
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final inbox = (await database.query(
        KedisDatabase.categoriesTable,
        where: 'system_key = ?',
        whereArgs: [KedisDatabase.inboxSystemKey],
      )).single;
      expect(inbox['deleted_at'], isNull);
      await _expectSystemCategoryDeletionRejected(database);
    } finally {
      await kedisDatabase.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('upgrades v4 data to v5 without changing persisted values', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kedis_v4_to_v5_',
    );
    final databasePath = '${temporaryDirectory.path}/dewwit.db';

    try {
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (database, version) async {
            await database.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                color_value INTEGER NOT NULL,
                is_system INTEGER NOT NULL DEFAULT 0
                  CHECK(is_system IN (0, 1)),
                system_key TEXT UNIQUE,
                created_at INTEGER NOT NULL,
                CHECK(
                  (is_system = 1 AND system_key IS NOT NULL) OR
                  (is_system = 0 AND system_key IS NULL)
                )
              )
            ''');
            await database.execute('''
              CREATE UNIQUE INDEX categories_name_nocase_unique
              ON categories(name COLLATE NOCASE)
            ''');
            await database.execute('''
              CREATE TABLE tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                is_completed INTEGER NOT NULL DEFAULT 0
                  CHECK(is_completed IN (0, 1)),
                created_at INTEGER NOT NULL,
                completed_at INTEGER,
                category_id INTEGER NOT NULL
                  REFERENCES categories(id) ON DELETE RESTRICT,
                deleted_at INTEGER
              )
            ''');
            await database.execute('''
              CREATE INDEX tasks_category_id_idx ON tasks(category_id)
            ''');
          },
        ),
      );
      await oldDatabase.insert('categories', {
        'id': 1,
        'name': 'Inbox',
        'color_value': 0xFF426A5A,
        'is_system': 1,
        'system_key': 'inbox',
        'created_at': 0,
      });
      await oldDatabase.insert('categories', {
        'id': 7,
        'name': 'School',
        'color_value': 0xFF6750A4,
        'is_system': 0,
        'system_key': null,
        'created_at': 700,
      });
      await oldDatabase.insert('tasks', {
        'id': 10,
        'title': 'Active',
        'is_completed': 0,
        'created_at': 1000,
        'completed_at': null,
        'category_id': 7,
        'deleted_at': null,
      });
      await oldDatabase.insert('tasks', {
        'id': 11,
        'title': 'Completed',
        'is_completed': 1,
        'created_at': 1100,
        'completed_at': 1200,
        'category_id': 7,
        'deleted_at': null,
      });
      await oldDatabase.insert('tasks', {
        'id': 12,
        'title': 'Already deleted',
        'is_completed': 1,
        'created_at': 1300,
        'completed_at': 1400,
        'category_id': 7,
        'deleted_at': 1500,
      });
      await oldDatabase.close();

      final kedisDatabase = KedisDatabase.atPath(
        databasePath,
        factory: databaseFactoryFfi,
      );
      try {
        final database = await kedisDatabase.database;
        await _expectSystemCategoryDeletionRejected(database);
        final categories = await database.query(
          KedisDatabase.categoriesTable,
          orderBy: 'id ASC',
        );
        final tasks = await database.query(
          KedisDatabase.tasksTable,
          orderBy: 'id ASC',
        );

        expect(await database.getVersion(), 5);
        expect(categories, hasLength(2));
        expect(categories[0], containsPair('id', 1));
        expect(categories[0], containsPair('name', 'Inbox'));
        expect(categories[0], containsPair('color_value', 0xFF426A5A));
        expect(categories[0], containsPair('created_at', 0));
        expect(categories[0]['deleted_at'], isNull);
        expect(categories[1], containsPair('id', 7));
        expect(categories[1], containsPair('name', 'School'));
        expect(categories[1], containsPair('color_value', 0xFF6750A4));
        expect(categories[1], containsPair('created_at', 700));
        expect(categories[1]['deleted_at'], isNull);

        expect(tasks.map((task) => task['id']), [10, 11, 12]);
        expect(tasks.map((task) => task['title']), [
          'Active',
          'Completed',
          'Already deleted',
        ]);
        expect(tasks.map((task) => task['category_id']), [7, 7, 7]);
        expect(tasks[0]['is_completed'], 0);
        expect(tasks[1]['is_completed'], 1);
        expect(tasks[1]['completed_at'], 1200);
        expect(tasks[2]['is_completed'], 1);
        expect(tasks[2]['completed_at'], 1400);
        expect(tasks[2]['deleted_at'], 1500);
        expect(
          tasks.map((task) => task['deleted_group_category_id']),
          everyElement(isNull),
        );
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await kedisDatabase.close();
      }
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists categoryless and grouped deleted tasks', () async {
    final kedisDatabase = KedisDatabase.atPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final categories = CategoryRepository.withDatabase(kedisDatabase);
    final tasks = TaskRepository.withDatabase(kedisDatabase);

    try {
      final deletedCategory = await categories.createCategory(
        'Archived project',
        0xFF6750A4,
      );
      final database = await kedisDatabase.database;
      await database.update(
        KedisDatabase.categoriesTable,
        {'deleted_at': 2000},
        where: 'id = ?',
        whereArgs: [deletedCategory.id],
      );
      await database.insert(KedisDatabase.tasksTable, {
        'id': 21,
        'title': 'Individually deleted',
        'is_completed': 0,
        'created_at': 1000,
        'completed_at': null,
        'category_id': null,
        'deleted_at': 3000,
        'deleted_group_category_id': null,
      });
      await database.insert(KedisDatabase.tasksTable, {
        'id': 22,
        'title': 'Deleted with category',
        'is_completed': 1,
        'created_at': 1100,
        'completed_at': 1200,
        'category_id': null,
        'deleted_at': 4000,
        'deleted_group_category_id': deletedCategory.id,
      });

      final deletedTasks = await tasks.getDeletedTasks();
      final groupedTask = deletedTasks.singleWhere((task) => task.id == 22);
      final categorylessTask = deletedTasks.singleWhere(
        (task) => task.id == 21,
      );
      final categoryRow = (await database.query(
        KedisDatabase.categoriesTable,
        where: 'id = ?',
        whereArgs: [deletedCategory.id],
      )).single;
      final persistedCategory = TaskCategory.fromMap(categoryRow);

      expect(categorylessTask.categoryId, isNull);
      expect(categorylessTask.deletedGroupCategoryId, isNull);
      expect(groupedTask.categoryId, isNull);
      expect(groupedTask.deletedGroupCategoryId, deletedCategory.id);
      expect(
        groupedTask.deletedAt,
        DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
      );
      expect(
        persistedCategory.deletedAt,
        DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );
      expect(
        (await categories.getCategories()).any(
          (category) => category.id == deletedCategory.id,
        ),
        isFalse,
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await kedisDatabase.close();
    }
  });

  test(
    'keeps category names unique when a category is marked deleted',
    () async {
      final kedisDatabase = KedisDatabase.atPath(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final categories = CategoryRepository.withDatabase(kedisDatabase);

      try {
        final category = await categories.createCategory('School', 0xFF6750A4);
        final database = await kedisDatabase.database;
        await database.update(
          KedisDatabase.categoriesTable,
          {'deleted_at': 1000},
          where: 'id = ?',
          whereArgs: [category.id],
        );

        expect(
          () => categories.createCategory('  school  ', 0xFF006C4C),
          throwsA(isA<StateError>()),
        );
      } finally {
        await kedisDatabase.close();
      }
    },
  );
}

Future<void> _expectSystemCategoryDeletionRejected(Database database) async {
  await expectLater(
    database.update(
      KedisDatabase.categoriesTable,
      {'deleted_at': 9999},
      where: 'system_key = ?',
      whereArgs: [KedisDatabase.inboxSystemKey],
    ),
    throwsA(isA<DatabaseException>()),
  );

  final inbox = (await database.query(
    KedisDatabase.categoriesTable,
    where: 'system_key = ?',
    whereArgs: [KedisDatabase.inboxSystemKey],
  )).single;
  expect(inbox['deleted_at'], isNull);
}
