package dev.ekzd.kedis

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

data class WidgetTask(
    val id: Long,
    val title: String,
    val isCompleted: Boolean,
)

object KedisTaskDatabase {
    fun readTasks(context: Context): List<WidgetTask> =
        Helper(context).use { helper ->
            helper.readableDatabase.query(
                TASKS_TABLE,
                arrayOf("id", "title", "is_completed"),
                "deleted_at IS NULL",
                null,
                null,
                null,
                """
                is_completed ASC,
                CASE WHEN completed_at IS NULL THEN 1 ELSE 0 END ASC,
                completed_at DESC,
                created_at ASC,
                id ASC
                """.trimIndent(),
            ).use { cursor ->
                buildList {
                    val idIndex = cursor.getColumnIndexOrThrow("id")
                    val titleIndex = cursor.getColumnIndexOrThrow("title")
                    val completedIndex = cursor.getColumnIndexOrThrow("is_completed")
                    while (cursor.moveToNext()) {
                        add(
                            WidgetTask(
                                id = cursor.getLong(idIndex),
                                title = cursor.getString(titleIndex),
                                isCompleted = cursor.getInt(completedIndex) == 1,
                            ),
                        )
                    }
                }
            }
        }

    fun toggleTask(context: Context, taskId: Long) {
        Helper(context).use { helper ->
            helper.writableDatabase.execSQL(
                """
                UPDATE $TASKS_TABLE
                SET completed_at = CASE is_completed WHEN 0 THEN ? ELSE NULL END,
                    is_completed = CASE is_completed WHEN 0 THEN 1 ELSE 0 END
                WHERE id = ? AND deleted_at IS NULL
                """.trimIndent(),
                arrayOf(System.currentTimeMillis(), taskId),
            )
        }
    }

    private class Helper(context: Context) :
        SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {
        override fun onConfigure(database: SQLiteDatabase) {
            super.onConfigure(database)
            database.setForeignKeyConstraintsEnabled(true)
        }

        override fun onCreate(database: SQLiteDatabase) {
            createCategoriesTable(database)
            insertInbox(database)
            createTasksTable(database)
        }

        override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) {
                database.execSQL("ALTER TABLE $TASKS_TABLE ADD COLUMN completed_at INTEGER")
            }
            if (oldVersion < 3) {
                migrateToCategories(database)
            }
            if (oldVersion >= 3 && oldVersion < 4) {
                database.execSQL("ALTER TABLE $TASKS_TABLE ADD COLUMN deleted_at INTEGER")
            }
        }
    }

    private fun createCategoriesTable(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE $CATEGORIES_TABLE (
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
            """.trimIndent(),
        )
        database.execSQL(
            """
            CREATE UNIQUE INDEX categories_name_nocase_unique
            ON $CATEGORIES_TABLE(name COLLATE NOCASE)
            """.trimIndent(),
        )
    }

    private fun insertInbox(database: SQLiteDatabase): Long {
        val values = ContentValues().apply {
            put("name", INBOX_NAME)
            put("color_value", INBOX_COLOR_VALUE)
            put("is_system", 1)
            put("system_key", INBOX_SYSTEM_KEY)
            put("created_at", 0L)
        }
        return database.insertOrThrow(CATEGORIES_TABLE, null, values)
    }

    private fun createTasksTable(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE $TASKS_TABLE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                is_completed INTEGER NOT NULL DEFAULT 0
                    CHECK(is_completed IN (0, 1)),
                created_at INTEGER NOT NULL,
                completed_at INTEGER,
                category_id INTEGER NOT NULL
                    REFERENCES $CATEGORIES_TABLE(id) ON DELETE RESTRICT,
                deleted_at INTEGER
            )
            """.trimIndent(),
        )
        database.execSQL(
            """
            CREATE INDEX tasks_category_id_idx
            ON $TASKS_TABLE(category_id)
            """.trimIndent(),
        )
    }

    private fun migrateToCategories(database: SQLiteDatabase) {
        createCategoriesTable(database)
        val inboxId = insertInbox(database)
        database.execSQL("ALTER TABLE $TASKS_TABLE RENAME TO tasks_v2")
        createTasksTable(database)
        database.execSQL(
            """
            INSERT INTO $TASKS_TABLE (
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
            """.trimIndent(),
            arrayOf(inboxId),
        )
        database.execSQL("DROP TABLE tasks_v2")
    }

    // Public product identity changed, but the authoritative database filename did not.
    private const val DATABASE_NAME = "dewwit.db"
    private const val DATABASE_VERSION = 4
    private const val TASKS_TABLE = "tasks"
    private const val CATEGORIES_TABLE = "categories"
    private const val INBOX_SYSTEM_KEY = "inbox"
    private const val INBOX_NAME = "Inbox"
    private const val INBOX_COLOR_VALUE = 0xFF426A5AL
}
