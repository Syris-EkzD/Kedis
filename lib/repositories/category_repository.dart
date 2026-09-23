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
    _ensureCustomCategory(current);
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
    _ensureCustomCategory(current);

    await database.update(
      KedisDatabase.categoriesTable,
      {'color_value': colorValue},
      where: 'id = ?',
      whereArgs: [id],
    );
    return _getCategory(database, id);
  }

  Future<int?> deleteCategory(int id) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final current = await _getCategory(transaction, id);
      if (current == null) return null;
      _ensureCustomCategory(current);

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
}
