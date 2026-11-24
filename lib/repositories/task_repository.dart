import 'package:kedis/models/task.dart';
import 'package:kedis/repositories/kedis_database.dart';
import 'package:sqflite/sqflite.dart';

class TaskRepository {
  TaskRepository({DatabaseFactory? factory})
    : _database = KedisDatabase(factory: factory),
      _ownsDatabase = true;

  TaskRepository.atPath(String databasePath, {DatabaseFactory? factory})
    : _database = KedisDatabase.atPath(databasePath, factory: factory),
      _ownsDatabase = true;

  TaskRepository.withDatabase(this._database) : _ownsDatabase = false;

  static const _taskOrder = '''
    is_completed ASC,
    CASE WHEN completed_at IS NULL THEN 1 ELSE 0 END ASC,
    completed_at DESC,
    created_at ASC,
    id ASC
  ''';

  final KedisDatabase _database;
  final bool _ownsDatabase;

  Future<Task> createTask(String title, {int? categoryId}) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Task title cannot be empty.');
    }

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    final database = await _database.database;
    return database.transaction((transaction) async {
      final resolvedCategoryId =
          categoryId ?? await KedisDatabase.getInboxId(transaction);
      await _requireActiveCategory(transaction, resolvedCategoryId);
      final id = await transaction.insert(KedisDatabase.tasksTable, {
        'title': normalizedTitle,
        'is_completed': 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': null,
        'category_id': resolvedCategoryId,
        'deleted_at': null,
        'deleted_group_category_id': null,
      });

      return Task(
        id: id,
        title: normalizedTitle,
        isCompleted: false,
        createdAt: createdAt,
        completedAt: null,
        categoryId: resolvedCategoryId,
        deletedAt: null,
        deletedGroupCategoryId: null,
      );
    });
  }

  Future<List<Task>> getTasks({int? categoryId}) async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: categoryId == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND category_id = ?',
      whereArgs: categoryId == null ? null : [categoryId],
      orderBy: _taskOrder,
    );

    return rows.map(Task.fromMap).toList(growable: false);
  }

  Future<List<Task>> getActiveTasks({int? categoryId}) async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: categoryId == null
          ? 'deleted_at IS NULL AND is_completed = 0'
          : 'deleted_at IS NULL AND is_completed = 0 AND category_id = ?',
      whereArgs: categoryId == null ? null : [categoryId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(Task.fromMap).toList(growable: false);
  }

  Future<List<Task>> getDeletedTasks() async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC, id DESC',
    );
    return rows.map(Task.fromMap).toList(growable: false);
  }

  Future<List<Task>> getStandaloneDeletedTasks() async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: 'deleted_at IS NOT NULL AND deleted_group_category_id IS NULL',
      orderBy: 'deleted_at DESC, id DESC',
    );
    return rows.map(Task.fromMap).toList(growable: false);
  }

  Future<List<Task>> getDeletedTasksForCategoryGroup(int categoryId) async {
    final database = await _database.database;
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: 'deleted_group_category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'deleted_at DESC, id DESC',
    );
    return rows.map(Task.fromMap).toList(growable: false);
  }

  Future<Task?> updateTaskTitle(int id, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Task title cannot be empty.');
    }

    final database = await _database.database;
    final updatedRows = await database.update(
      KedisDatabase.tasksTable,
      {'title': normalizedTitle},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (updatedRows == 0) {
      return null;
    }

    return _getTask(database, id);
  }

  Future<Task?> moveTaskToCategory(int id, int categoryId) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireActiveCategory(transaction, categoryId);
      final updatedRows = await transaction.update(
        KedisDatabase.tasksTable,
        {'category_id': categoryId},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      if (updatedRows == 0) {
        return null;
      }
      return _getTask(transaction, id);
    });
  }

  Future<Task?> toggleTask(int id) async {
    final database = await _database.database;

    return database.transaction((transaction) async {
      final updatedRows = await transaction.rawUpdate(
        '''
        UPDATE ${KedisDatabase.tasksTable}
        SET completed_at = CASE is_completed WHEN 0 THEN ? ELSE NULL END,
            is_completed = CASE is_completed WHEN 0 THEN 1 ELSE 0 END
        WHERE id = ? AND deleted_at IS NULL
        ''',
        [DateTime.now().millisecondsSinceEpoch, id],
      );
      if (updatedRows == 0) {
        return null;
      }

      return _getTask(transaction, id);
    });
  }

  Future<Task?> setTaskCompletion(
    int id, {
    required bool isCompleted,
    required DateTime? completedAt,
  }) async {
    if (isCompleted && completedAt == null) {
      throw ArgumentError.notNull('completedAt');
    }

    final database = await _database.database;
    return database.transaction((transaction) async {
      final updatedRows = await transaction.update(
        KedisDatabase.tasksTable,
        {
          'is_completed': isCompleted ? 1 : 0,
          'completed_at': isCompleted
              ? completedAt!.millisecondsSinceEpoch
              : null,
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      if (updatedRows == 0) {
        return null;
      }

      return _getTask(transaction, id);
    });
  }

  Future<bool> deleteTask(int id) async {
    final database = await _database.database;
    final deletedAt = DateTime.now().millisecondsSinceEpoch;
    final updatedRows = await database.update(
      KedisDatabase.tasksTable,
      {'deleted_at': deletedAt},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return updatedRows > 0;
  }

  Future<Task?> restoreTask(int id, {int? destinationCategoryId}) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        KedisDatabase.tasksTable,
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final task = Task.fromMap(rows.single);
      int restoredCategoryId;
      if (task.deletedGroupCategoryId == null && task.categoryId != null) {
        final retainedCategoryIsActive = await _isActiveCategory(
          transaction,
          task.categoryId!,
        );
        if (retainedCategoryIsActive) {
          restoredCategoryId = task.categoryId!;
        } else {
          restoredCategoryId = await _requireExplicitDestination(
            transaction,
            destinationCategoryId,
          );
        }
      } else {
        restoredCategoryId = await _requireExplicitDestination(
          transaction,
          destinationCategoryId,
        );
      }

      await transaction.update(
        KedisDatabase.tasksTable,
        {
          'category_id': restoredCategoryId,
          'deleted_at': null,
          'deleted_group_category_id': null,
        },
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [id],
      );
      return _getTask(transaction, id);
    });
  }

  Future<bool> permanentlyDeleteTask(int id) async {
    final database = await _database.database;
    final deletedRows = await database.delete(
      KedisDatabase.tasksTable,
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [id],
    );
    return deletedRows > 0;
  }

  Future<int> restoreStandaloneTasks(
    Iterable<int> taskIds, {
    int? destinationCategoryId,
  }) async {
    final selectedIds = taskIds.toList(growable: false);
    _ensureUniqueSelection(selectedIds);
    if (selectedIds.isEmpty) return 0;

    final database = await _database.database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        KedisDatabase.tasksTable,
        where:
            '''
          id IN (${_placeholders(selectedIds.length)})
          AND deleted_at IS NOT NULL
          AND deleted_group_category_id IS NULL
        ''',
        whereArgs: selectedIds,
      );
      if (rows.length != selectedIds.length) {
        throw StateError('Every selected task must be standalone in Trash.');
      }

      final selectedTasks = rows.map(Task.fromMap).toList(growable: false);
      final destinationNeeded = <Task>[];
      for (final task in selectedTasks) {
        final categoryId = task.categoryId;
        if (categoryId == null ||
            !await _isActiveCategory(transaction, categoryId)) {
          destinationNeeded.add(task);
        }
      }
      if (destinationNeeded.isNotEmpty) {
        if (destinationCategoryId == null) {
          throw ArgumentError.notNull('destinationCategoryId');
        }
        await _requireActiveCategory(transaction, destinationCategoryId);
      }

      for (final task in selectedTasks) {
        final retainedCategoryId = task.categoryId;
        final useRetainedCategory =
            retainedCategoryId != null &&
            await _isActiveCategory(transaction, retainedCategoryId);
        await transaction.update(
          KedisDatabase.tasksTable,
          {
            'category_id': useRetainedCategory
                ? retainedCategoryId
                : destinationCategoryId,
            'deleted_at': null,
            'deleted_group_category_id': null,
          },
          where: 'id = ? AND deleted_at IS NOT NULL',
          whereArgs: [task.id],
        );
      }
      return selectedTasks.length;
    });
  }

  Future<int> permanentlyDeleteStandaloneTasks(Iterable<int> taskIds) async {
    final selectedIds = taskIds.toList(growable: false);
    _ensureUniqueSelection(selectedIds);
    if (selectedIds.isEmpty) return 0;

    final database = await _database.database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        KedisDatabase.tasksTable,
        columns: ['id'],
        where:
            '''
          id IN (${_placeholders(selectedIds.length)})
          AND deleted_at IS NOT NULL
          AND deleted_group_category_id IS NULL
        ''',
        whereArgs: selectedIds,
      );
      if (rows.length != selectedIds.length) {
        throw StateError('Every selected task must be standalone in Trash.');
      }
      return transaction.delete(
        KedisDatabase.tasksTable,
        where: 'id IN (${_placeholders(selectedIds.length)})',
        whereArgs: selectedIds,
      );
    });
  }

  Future<int> restoreGroupedTasks(
    int deletedCategoryId,
    Iterable<int> taskIds, {
    required int destinationCategoryId,
  }) async {
    final selectedIds = taskIds.toList(growable: false);
    _ensureNonEmptyUniqueSelection(selectedIds);

    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireDeletedCategory(transaction, deletedCategoryId);
      await _requireActiveCategory(transaction, destinationCategoryId);
      await _validateGroupedSelection(
        transaction,
        deletedCategoryId,
        selectedIds,
      );
      return transaction.update(
        KedisDatabase.tasksTable,
        {
          'category_id': destinationCategoryId,
          'deleted_at': null,
          'deleted_group_category_id': null,
        },
        where: 'id IN (${_placeholders(selectedIds.length)})',
        whereArgs: selectedIds,
      );
    });
  }

  Future<int> permanentlyDeleteGroupedTasks(
    int deletedCategoryId,
    Iterable<int> taskIds,
  ) async {
    final selectedIds = taskIds.toList(growable: false);
    _ensureNonEmptyUniqueSelection(selectedIds);

    final database = await _database.database;
    return database.transaction((transaction) async {
      await _requireDeletedCategory(transaction, deletedCategoryId);
      await _validateGroupedSelection(
        transaction,
        deletedCategoryId,
        selectedIds,
      );
      return transaction.delete(
        KedisDatabase.tasksTable,
        where: 'id IN (${_placeholders(selectedIds.length)})',
        whereArgs: selectedIds,
      );
    });
  }

  Future<void> close() async {
    if (_ownsDatabase) {
      await _database.close();
    }
  }

  Future<Task?> _getTask(DatabaseExecutor database, int id) async {
    final rows = await database.query(
      KedisDatabase.tasksTable,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Task.fromMap(rows.single);
  }

  Future<bool> _isActiveCategory(
    DatabaseExecutor database,
    int categoryId,
  ) async {
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [categoryId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _requireActiveCategory(
    DatabaseExecutor database,
    int categoryId,
  ) async {
    if (!await _isActiveCategory(database, categoryId)) {
      throw StateError('Active category $categoryId does not exist.');
    }
  }

  Future<void> _requireDeletedCategory(
    DatabaseExecutor database,
    int categoryId,
  ) async {
    final rows = await database.query(
      KedisDatabase.categoriesTable,
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Deleted category $categoryId does not exist.');
    }
  }

  Future<void> _validateGroupedSelection(
    DatabaseExecutor database,
    int categoryId,
    List<int> selectedIds,
  ) async {
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

  Future<int> _requireExplicitDestination(
    DatabaseExecutor database,
    int? destinationCategoryId,
  ) async {
    if (destinationCategoryId == null) {
      throw ArgumentError.notNull('destinationCategoryId');
    }
    await _requireActiveCategory(database, destinationCategoryId);
    return destinationCategoryId;
  }

  void _ensureUniqueSelection(List<int> selectedIds) {
    if (selectedIds.toSet().length != selectedIds.length) {
      throw ArgumentError('Selected task IDs must not contain duplicates.');
    }
  }

  void _ensureNonEmptyUniqueSelection(List<int> selectedIds) {
    if (selectedIds.isEmpty) {
      throw ArgumentError('At least one task must be selected.');
    }
    _ensureUniqueSelection(selectedIds);
  }

  String _placeholders(int count) => List.filled(count, '?').join(', ');
}
