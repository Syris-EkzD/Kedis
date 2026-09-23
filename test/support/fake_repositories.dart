import 'package:kedis/models/task.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/task_repository.dart';

class FakeRepositories {
  FakeRepositories() {
    categories = FakeCategoryRepository._(_store);
    tasks = FakeTaskRepository._(_store);
  }

  final _FakeRepositoryStore _store = _FakeRepositoryStore();
  late final FakeCategoryRepository categories;
  late final FakeTaskRepository tasks;
}

class FakeTaskRepository implements TaskRepository {
  FakeTaskRepository._(this._store);

  final _FakeRepositoryStore _store;

  @override
  Future<Task> createTask(String title, {int? categoryId}) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Task title cannot be empty.');
    }

    final resolvedCategoryId = categoryId ?? _store.inbox.id;
    if (!_store.categories.containsKey(resolvedCategoryId)) {
      throw StateError('Task category does not exist.');
    }

    final task = Task(
      id: _store.nextTaskId++,
      title: normalizedTitle,
      isCompleted: false,
      createdAt: _now(),
      completedAt: null,
      categoryId: resolvedCategoryId,
      deletedAt: null,
    );
    _store.tasks[task.id] = task;
    return task;
  }

  @override
  Future<List<Task>> getTasks({int? categoryId}) async {
    final result = <Task>[];
    for (final task in _store.tasks.values) {
      final inCategory = categoryId == null || task.categoryId == categoryId;
      if (task.deletedAt == null && inCategory) {
        result.add(task);
      }
    }
    result.sort(_compareTasks);
    return List.unmodifiable(result);
  }

  @override
  Future<List<Task>> getActiveTasks({int? categoryId}) async {
    final result = <Task>[];
    for (final task in _store.tasks.values) {
      final inCategory = categoryId == null || task.categoryId == categoryId;
      if (task.deletedAt == null && !task.isCompleted && inCategory) {
        result.add(task);
      }
    }
    result.sort((left, right) {
      final byCreatedAt = left.createdAt.compareTo(right.createdAt);
      if (byCreatedAt != 0) {
        return byCreatedAt;
      }
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }

  @override
  Future<List<Task>> getDeletedTasks() async {
    final result = _store.tasks.values
        .where((task) => task.deletedAt != null)
        .toList();
    result.sort((left, right) {
      final byDeletedAt = right.deletedAt!.compareTo(left.deletedAt!);
      if (byDeletedAt != 0) {
        return byDeletedAt;
      }
      return right.id.compareTo(left.id);
    });
    return List.unmodifiable(result);
  }

  @override
  Future<Task?> updateTaskTitle(int id, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Task title cannot be empty.');
    }

    final current = _store.tasks[id];
    if (current == null || current.deletedAt != null) {
      return null;
    }

    final updated = _copyTask(current, title: normalizedTitle);
    _store.tasks[id] = updated;
    return updated;
  }

  @override
  Future<Task?> moveTaskToCategory(int id, int categoryId) async {
    final current = _store.tasks[id];
    if (current == null || current.deletedAt != null) {
      return null;
    }
    if (!_store.categories.containsKey(categoryId)) {
      throw StateError('Task category does not exist.');
    }

    final updated = _copyTask(current, categoryId: categoryId);
    _store.tasks[id] = updated;
    return updated;
  }

  @override
  Future<Task?> toggleTask(int id) async {
    final current = _store.tasks[id];
    if (current == null || current.deletedAt != null) {
      return null;
    }

    final Task updated;
    if (current.isCompleted) {
      updated = _copyTask(current, isCompleted: false, clearCompletedAt: true);
    } else {
      updated = _copyTask(current, isCompleted: true, completedAt: _now());
    }
    _store.tasks[id] = updated;
    return updated;
  }

  @override
  Future<Task?> setTaskCompletion(
    int id, {
    required bool isCompleted,
    required DateTime? completedAt,
  }) async {
    if (isCompleted && completedAt == null) {
      throw ArgumentError.notNull('completedAt');
    }

    final current = _store.tasks[id];
    if (current == null || current.deletedAt != null) {
      return null;
    }

    final updated = _copyTask(
      current,
      isCompleted: isCompleted,
      completedAt: completedAt,
      clearCompletedAt: !isCompleted,
    );
    _store.tasks[id] = updated;
    return updated;
  }

  @override
  Future<bool> deleteTask(int id) async {
    final current = _store.tasks[id];
    if (current == null || current.deletedAt != null) {
      return false;
    }
    _store.tasks[id] = _copyTask(current, deletedAt: _now());
    return true;
  }

  @override
  Future<Task?> restoreTask(int id) async {
    final current = _store.tasks[id];
    if (current == null || current.deletedAt == null) {
      return null;
    }
    final restored = _copyTask(current, clearDeletedAt: true);
    _store.tasks[id] = restored;
    return restored;
  }

  @override
  Future<bool> permanentlyDeleteTask(int id) async {
    final current = _store.tasks[id];
    if (current == null || current.deletedAt == null) {
      return false;
    }
    _store.tasks.remove(id);
    return true;
  }

  @override
  Future<void> close() async {}

  int _compareTasks(Task left, Task right) {
    if (left.isCompleted != right.isCompleted) {
      return left.isCompleted ? 1 : -1;
    }

    if (left.isCompleted) {
      final leftCompletedAt = left.completedAt;
      final rightCompletedAt = right.completedAt;
      if (leftCompletedAt != null && rightCompletedAt != null) {
        final byCompletion = rightCompletedAt.compareTo(leftCompletedAt);
        if (byCompletion != 0) {
          return byCompletion;
        }
      } else if (leftCompletedAt != null) {
        return -1;
      } else if (rightCompletedAt != null) {
        return 1;
      }
    }

    final byCreatedAt = left.createdAt.compareTo(right.createdAt);
    if (byCreatedAt != 0) {
      return byCreatedAt;
    }
    return left.id.compareTo(right.id);
  }
}

class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository._(this._store);

  final _FakeRepositoryStore _store;

  @override
  Future<List<TaskCategory>> getCategories() async {
    final result = _store.categories.values.toList();
    result.sort((left, right) {
      if (left.isSystem != right.isSystem) {
        return left.isSystem ? -1 : 1;
      }

      final byCreatedAt = left.createdAt.compareTo(right.createdAt);
      if (byCreatedAt != 0) {
        return byCreatedAt;
      }
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }

  @override
  Future<TaskCategory> getInbox() async {
    return _store.inbox;
  }

  @override
  Future<TaskCategory> createCategory(String name, int colorValue) async {
    final normalizedName = _normalizeName(name);
    _validateColorValue(colorValue);
    _ensureNameAvailable(normalizedName);

    final category = TaskCategory(
      id: _store.nextCategoryId++,
      name: normalizedName,
      colorValue: colorValue,
      isSystem: false,
      createdAt: _now(),
    );
    _store.categories[category.id] = category;
    return category;
  }

  @override
  Future<TaskCategory?> renameCategory(int id, String name) async {
    final current = _store.categories[id];
    if (current == null) {
      return null;
    }
    _ensureCustomCategory(current);

    final normalizedName = _normalizeName(name);
    _ensureNameAvailable(normalizedName, excludingId: id);
    final updated = _copyCategory(current, name: normalizedName);
    _store.categories[id] = updated;
    return updated;
  }

  @override
  Future<TaskCategory?> updateCategoryColor(int id, int colorValue) async {
    _validateColorValue(colorValue);
    final current = _store.categories[id];
    if (current == null) {
      return null;
    }
    _ensureCustomCategory(current);

    final updated = _copyCategory(current, colorValue: colorValue);
    _store.categories[id] = updated;
    return updated;
  }

  @override
  Future<int?> deleteCategory(int id) async {
    final current = _store.categories[id];
    if (current == null) {
      return null;
    }
    _ensureCustomCategory(current);

    var movedTasks = 0;
    for (final entry in _store.tasks.entries.toList()) {
      final task = entry.value;
      if (task.categoryId != id) {
        continue;
      }
      _store.tasks[entry.key] = _copyTask(task, categoryId: _store.inbox.id);
      movedTasks += 1;
    }
    _store.categories.remove(id);
    return movedTasks;
  }

  @override
  Future<void> close() async {}

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

  void _ensureNameAvailable(String name, {int? excludingId}) {
    final normalizedName = name.toLowerCase();
    for (final category in _store.categories.values) {
      if (category.id == excludingId) {
        continue;
      }
      if (category.name.toLowerCase() == normalizedName) {
        throw StateError('A category named "$name" already exists.');
      }
    }
  }

  void _ensureCustomCategory(TaskCategory category) {
    if (category.isSystem) {
      throw StateError('System categories cannot be changed or deleted.');
    }
  }
}

class _FakeRepositoryStore {
  _FakeRepositoryStore()
    : inbox = TaskCategory(
        id: 1,
        name: 'Inbox',
        colorValue: 0xFF426A5A,
        isSystem: true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ) {
    categories[inbox.id] = inbox;
  }

  final TaskCategory inbox;
  final Map<int, TaskCategory> categories = {};
  final Map<int, Task> tasks = {};
  int nextCategoryId = 2;
  int nextTaskId = 1;
}

DateTime _now() {
  return DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  );
}

Task _copyTask(
  Task task, {
  String? title,
  bool? isCompleted,
  DateTime? completedAt,
  bool clearCompletedAt = false,
  int? categoryId,
  DateTime? deletedAt,
  bool clearDeletedAt = false,
}) {
  return Task(
    id: task.id,
    title: title ?? task.title,
    isCompleted: isCompleted ?? task.isCompleted,
    createdAt: task.createdAt,
    completedAt: clearCompletedAt ? null : completedAt ?? task.completedAt,
    categoryId: categoryId ?? task.categoryId,
    deletedAt: clearDeletedAt ? null : deletedAt ?? task.deletedAt,
  );
}

TaskCategory _copyCategory(
  TaskCategory category, {
  String? name,
  int? colorValue,
}) {
  return TaskCategory(
    id: category.id,
    name: name ?? category.name,
    colorValue: colorValue ?? category.colorValue,
    isSystem: category.isSystem,
    createdAt: category.createdAt,
  );
}
