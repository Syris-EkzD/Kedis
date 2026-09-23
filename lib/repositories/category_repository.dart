import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/kedis_database.dart';
import 'package:sqflite/sqflite.dart';

class CategoryRepository {
  CategoryRepository({DatabaseFactory? factory})
    : _database = KedisDatabase(factory: factory),
      _ownsDatabase = true;

  CategoryRepository.atPath(String databasePath, {DatabaseFactory? factory})
    : _database = KedisDatabase.atPath(databasePath, factory: factory),
      _ownsDatabase = true;

  CategoryRepository.withDatabase(this._database) : _ownsDatabase = false;

  final KedisDatabase _database;
  final bool _ownsDatabase;

  Future<List<TaskCategory>> getCategories() async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      where: 'deleted_at IS NULL',
      orderBy: 'is_system DESC, created_at ASC, id ASC',
    );
    return rows.map(TaskCategory.fromMap).toList(growable: false);
  }

  Future<List<TaskCategory>> getDeletedCategories() async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      where: 'is_system = 0 AND deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC, id DESC',
    );
    return rows.map(TaskCategory.fromMap).toList(growable: false);
  }

  Future<TaskCategory> getInbox() async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      where: 'system_key = ? AND deleted_at IS NULL',
      whereArgs: [KedisDatabase.inboxSystemKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Kedis Inbox is missing from the database.');
    }
    return TaskCategory.fromMap(rows.single);
  }

  Future<TaskCategory> createCategory(String name, int colorValue) async {
    final normalizedName = _normalizeName(name);
    _validateColorValue(colorValue);

    final database = await _database.database;
    await _ensureNameAvailable(database, normalizedName);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    final id = await database.insert(KedisDatabase.categoriesTable, {
      'name': normalizedName,
      'color_value': colorValue,
      'is_system': 0,
      'system_key': null,
      'created_at': createdAt.millisecondsSinceEpoch,
      'deleted_at': null,
    });

    return TaskCategory(
      id: id,
      name: normalizedName,
      colorValue: colorValue,
      isSystem: false,
      createdAt: createdAt,
      deletedAt: null,
    );
  }

  Future<TaskCategory?> renameCategory(int id, String name) async {
    final normalizedName = _normalizeName(name);
    final database = await _database.database;
    final current = await _getCategory(database, id);
    if (current == null) return null;
    _ensureActiveCustomCategory(current);
    await _ensureNameAvailable(database, normalizedName, excludingId: id);

    await database.update(
      KedisDatabase.categoriesTable,
      {'name': normalizedName},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return _getCategory(database, id);
  }

  Future<TaskCategory?> updateCategoryColor(int id, int colorValue) async {
    _validateColorValue(colorValue);
    final database = await _database.database;
    final current = await _getCategory(database, id);
    if (current == null) return null;
    _ensureActiveCustomCategory(current);

    await database.update(
      KedisDatabase.categoriesTable,
      {'color_value': colorValue},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return _getCategory(database, id);
  }

  Future<int?> deleteCategory(int id) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final current = await _getCategory(transaction, id);
      if (current == null) return null;
      _ensureActiveCustomCategory(current);

      final inboxId = await KedisDatabase.getInboxId(transaction);
      final movedTasks = await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': inboxId},
        where: 'category_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        KedisDatabase.categoriesTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      return movedTasks;
    });
  }

  Future<CategoryDeletionResult> softDeleteEmptyCategory(int id) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireActiveCustomCategory(transaction, id);
      final activeTaskCount = Sqflite.firstIntValue(
        await transaction.rawQuery(
          '''
          SELECT COUNT(*)
          FROM ${KedisDatabase.tasksTable}
          WHERE category_id = ? AND deleted_at IS NULL
          ''',
          [id],
        ),
      )!;
      if (activeTaskCount != 0) {
        throw StateError('Category $id still has active tasks.');
      }

      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      final detachedTaskCount = await _detachStandaloneTasks(transaction, id);
      await transaction.update(
        KedisDatabase.categoriesTable,
        {'deleted_at': deletedAt},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      return CategoryDeletionResult(
        categoryId: id,
        movedTaskCount: 0,
        deletedTaskCount: 0,
        detachedTaskCount: detachedTaskCount,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
      );
    });
  }

  Future<CategoryDeletionResult> softDeleteCategoryMovingTasks(
    int sourceCategoryId,
    int destinationCategoryId,
  ) async {
    if (sourceCategoryId == destinationCategoryId) {
      throw ArgumentError('Source and destination categories must differ.');
    }

    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireActiveCustomCategory(transaction, sourceCategoryId);
      await _requireActiveCategory(transaction, destinationCategoryId);
      final movedTaskCount = await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': destinationCategoryId},
        where: 'category_id = ? AND deleted_at IS NULL',
        whereArgs: [sourceCategoryId],
      );
      final detachedTaskCount = await _detachStandaloneTasks(
        transaction,
        sourceCategoryId,
      );
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      await transaction.update(
        KedisDatabase.categoriesTable,
        {'deleted_at': deletedAt},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [sourceCategoryId],
      );
      return CategoryDeletionResult(
        categoryId: sourceCategoryId,
        movedTaskCount: movedTaskCount,
        deletedTaskCount: 0,
        detachedTaskCount: detachedTaskCount,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
      );
    });
  }

  Future<CategoryDeletionResult> softDeleteCategoryWithTasks(int id) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireActiveCustomCategory(transaction, id);
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      await transaction.update(
        KedisDatabase.categoriesTable,
        {'deleted_at': deletedAt},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      final deletedTaskCount = await transaction.update(
        KedisDatabase.tasksTable,
        {
          'category_id': null,
          'deleted_at': deletedAt,
          'deleted_group_category_id': id,
        },
        where: 'category_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      final detachedTaskCount = await _detachStandaloneTasks(transaction, id);
      return CategoryDeletionResult(
        categoryId: id,
        movedTaskCount: 0,
        deletedTaskCount: deletedTaskCount,
        detachedTaskCount: detachedTaskCount,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
      );
    });
  }

  Future<CategorySelectionResult> restoreDeletedCategory(
    int categoryId,
    Iterable<int> selectedTaskIds,
  ) async {
    final selectedIds = selectedTaskIds.toList(growable: false);
    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireDeletedCustomCategory(transaction, categoryId);
      await _validateGroupedTaskSelection(transaction, categoryId, selectedIds);

      await transaction.update(
        KedisDatabase.categoriesTable,
        {'deleted_at': null},
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [categoryId],
      );
      final detachedTaskCount = await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': null, 'deleted_group_category_id': null},
        where: 'deleted_group_category_id = ?',
        whereArgs: [categoryId],
      );
      if (selectedIds.isNotEmpty) {
        await transaction.update(
          KedisDatabase.tasksTable,
          {
            'category_id': categoryId,
            'deleted_at': null,
            'deleted_group_category_id': null,
          },
          where: 'id IN (${_placeholders(selectedIds.length)})',
          whereArgs: selectedIds,
        );
      }
      return CategorySelectionResult(
        categoryId: categoryId,
        selectedTaskCount: selectedIds.length,
        detachedTaskCount: detachedTaskCount - selectedIds.length,
      );
    });
  }

  Future<CategorySelectionResult> permanentlyDeleteCategory(
    int categoryId,
    Iterable<int> selectedTaskIds,
  ) async {
    final selectedIds = selectedTaskIds.toList(growable: false);
    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireDeletedCustomCategory(transaction, categoryId);
      await _validateGroupedTaskSelection(transaction, categoryId, selectedIds);

      if (selectedIds.isNotEmpty) {
        await transaction.delete(
          KedisDatabase.tasksTable,
          where: 'id IN (${_placeholders(selectedIds.length)})',
          whereArgs: selectedIds,
        );
      }
      final detachedTaskCount = await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': null, 'deleted_group_category_id': null},
        where: 'deleted_group_category_id = ?',
        whereArgs: [categoryId],
      );
      await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': null},
        where: 'category_id = ? AND deleted_at IS NOT NULL',
        whereArgs: [categoryId],
      );
      await transaction.delete(
        KedisDatabase.categoriesTable,
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [categoryId],
      );
      return CategorySelectionResult(
        categoryId: categoryId,
        selectedTaskCount: selectedIds.length,
        detachedTaskCount: detachedTaskCount,
      );
    });
  }

  Future<void> close() async {
    if (_ownsDatabase) {
      await _database.close();
    }
  }

  Future<TaskCategory?> _getCategory(DatabaseExecutor database, int id) async {
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TaskCategory.fromMap(rows.single);
  }

  Future<TaskCategory> _requireActiveCategory(
    DatabaseExecutor database,
    int id,
  ) async {
    final category = await _getCategory(database, id);
    if (category == null || category.deletedAt != null) {
      throw StateError('Active category $id does not exist.');
    }
    return category;
  }

  Future<TaskCategory> _requireActiveCustomCategory(
    DatabaseExecutor database,
    int id,
  ) async {
    final category = await _requireActiveCategory(database, id);
    _ensureCustomCategory(category);
    return category;
  }

  Future<TaskCategory> _requireDeletedCustomCategory(
    DatabaseExecutor database,
    int id,
  ) async {
    final category = await _getCategory(database, id);
    if (category == null || category.deletedAt == null) {
      throw StateError('Deleted category $id does not exist.');
    }
    _ensureCustomCategory(category);
    return category;
  }

  Future<int> _detachStandaloneTasks(
    DatabaseExecutor database,
    int categoryId,
  ) {
    return database.update(
      KedisDatabase.tasksTable,
      {'category_id': null},
      where: '''
        category_id = ?
        AND deleted_at IS NOT NULL
        AND deleted_group_category_id IS NULL
      ''',
      whereArgs: [categoryId],
    );
  }

  Future<void> _validateGroupedTaskSelection(
    DatabaseExecutor database,
    int categoryId,
    List<int> selectedIds,
  ) async {
    if (selectedIds.toSet().length != selectedIds.length) {
      throw ArgumentError('Selected task IDs must not contain duplicates.');
    }
    if (selectedIds.isEmpty) return;

    final rows = await database.query(
      KedisDatabase.tasksTable,
      columns: ['id'],
      where:
          '''
        id IN (${_placeholders(selectedIds.length)})
        AND deleted_at IS NOT NULL
        AND deleted_group_category_id = ?
      ''',
      whereArgs: [...selectedIds, categoryId],
    );
    if (rows.length != selectedIds.length) {
      throw StateError(
        'Every selected task must belong to deleted category $categoryId.',
      );
    }
  }

  String _placeholders(int count) => List.filled(count, '?').join(', ');

  Future<void> _ensureNameAvailable(
    DatabaseExecutor database,
    String name, {
    int? excludingId,
  }) async {
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      columns: ['id'],
      where: excludingId == null
          ? 'name = ? COLLATE NOCASE'
          : 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: excludingId == null ? [name] : [name, excludingId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError('A category named "$name" already exists.');
    }
  }

  String _normalizeName(String name) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Category name cannot be empty.');
    }
    return normalizedName;
  }

  void _validateColorValue(int colorValue) {
    if (colorValue < 0 || colorValue > 0xFFFFFFFF) {
      throw RangeError.range(colorValue, 0, 0xFFFFFFFF, 'colorValue');
    }
  }

  void _ensureCustomCategory(TaskCategory category) {
    if (category.isSystem) {
      throw StateError('System categories cannot be changed or deleted.');
    }
  }

  void _ensureActiveCustomCategory(TaskCategory category) {
    _ensureCustomCategory(category);
    if (category.deletedAt != null) {
      throw StateError('Deleted categories cannot be changed or deleted.');
    }
  }
}

class CategoryDeletionResult {
  const CategoryDeletionResult({
    required this.categoryId,
    required this.movedTaskCount,
    required this.deletedTaskCount,
    required this.detachedTaskCount,
    required this.deletedAt,
  });

  final int categoryId;
  final int movedTaskCount;
  final int deletedTaskCount;
  final int detachedTaskCount;
  final DateTime deletedAt;
}

class CategorySelectionResult {
  const CategorySelectionResult({
    required this.categoryId,
    required this.selectedTaskCount,
    required this.detachedTaskCount,
  });

  final int categoryId;
  final int selectedTaskCount;
  final int detachedTaskCount;
}
