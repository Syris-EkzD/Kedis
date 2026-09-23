import 'package:sqflite/sqflite.dart';

class KedisDatabase {
  KedisDatabase({DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory,
      _databasePath = null;

  KedisDatabase.atPath(this._databasePath, {DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;

  // Retained for compatibility with the existing authoritative task store.
  static const databaseName = 'dewwit.db';
  static const databaseVersion = 4;
  static const tasksTable = 'tasks';
  static const categoriesTable = 'categories';
  static const inboxSystemKey = 'inbox';
  static const inboxName = 'Inbox';
  static const inboxColorValue = 0xFF426A5A;

  final DatabaseFactory _factory;
  final String? _databasePath;
  Future<Database>? _database;

  Future<Database> get database => _database ??= _openDatabase();

  Future<void> close() async {
    final pendingDatabase = _database;
    if (pendingDatabase != null) {
      await (await pendingDatabase).close();
    }
    _database = null;
  }

  static Future<int> getInboxId(DatabaseExecutor database) async {
    final rows = await database.query(
      categoriesTable,
      columns: ['id'],
      where: 'system_key = ?',
      whereArgs: [inboxSystemKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Kedis Inbox is missing from the database.');
    }
    return rows.single['id']! as int;
  }

  Future<Database> _openDatabase() async {
    final path =
        _databasePath ?? '${await _factory.getDatabasesPath()}/$databaseName';
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createCategoriesTable(database);
          await _insertInbox(database);
          await _createTasksTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE $tasksTable ADD COLUMN completed_at INTEGER',
            );
          }
          if (oldVersion < 3) {
            await _migrateToCategories(database);
          }
          if (oldVersion >= 3 && oldVersion < 4) {
            await database.execute(
              'ALTER TABLE $tasksTable ADD COLUMN deleted_at INTEGER',
            );
          }
        },
      ),
    );
  }

  static Future<void> _createCategoriesTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $categoriesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        color_value INTEGER NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0 CHECK(is_system IN (0, 1)),
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
      ON $categoriesTable(name COLLATE NOCASE)
    ''');
  }

  static Future<int> _insertInbox(DatabaseExecutor database) {
    return database.insert(categoriesTable, {
      'name': inboxName,
      'color_value': inboxColorValue,
      'is_system': 1,
      'system_key': inboxSystemKey,
      'created_at': 0,
    });
  }

  static Future<void> _createTasksTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $tasksTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        is_completed INTEGER NOT NULL DEFAULT 0
          CHECK(is_completed IN (0, 1)),
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        category_id INTEGER NOT NULL
          REFERENCES $categoriesTable(id) ON DELETE RESTRICT,
        deleted_at INTEGER
      )
    ''');
    await database.execute('''
      CREATE INDEX tasks_category_id_idx
      ON $tasksTable(category_id)
    ''');
  }

  static Future<void> _migrateToCategories(DatabaseExecutor database) async {
    await _createCategoriesTable(database);
    final inboxId = await _insertInbox(database);

    await database.execute('ALTER TABLE $tasksTable RENAME TO tasks_v2');
    await _createTasksTable(database);
    await database.rawInsert(
      '''
      INSERT INTO $tasksTable (
        id,
        title,
        is_completed,
        created_at,
        completed_at,
        category_id
      )
      SELECT
        id,
        title,
        is_completed,
        created_at,
        completed_at,
        ?
      FROM tasks_v2
      ''',
      [inboxId],
    );
    await database.execute('DROP TABLE tasks_v2');
  }
}
