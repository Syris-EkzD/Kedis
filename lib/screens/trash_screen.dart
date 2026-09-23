import 'package:flutter/material.dart';
import 'package:kedis/models/task.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:kedis/theme/kedis_design.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    required this.categoryRepository,
    required this.taskRepository,
    required this.widgetRefresh,
    super.key,
  });
  final CategoryRepository categoryRepository;
  final TaskRepository taskRepository;
  final Future<void> Function() widgetRefresh;
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<TaskCategory> _deletedCategories = const [];
  List<TaskCategory> _activeCategories = const [];
  List<Task> _standaloneTasks = const [];
  Map<int, List<Task>> _groups = const {};
  final _expanded = <int>{};
  final _standaloneSelection = <int>{};
  final _groupSelections = <int, Set<int>>{};
  bool _loading = true;
  bool _loadFailed = false;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final deleted = await widget.categoryRepository.getDeletedCategories();
      final active = await widget.categoryRepository.getCategories();
      final standalone = await widget.taskRepository
          .getStandaloneDeletedTasks();
      final groups = <int, List<Task>>{};
      for (final category in deleted) {
        groups[category.id] = await widget.taskRepository
            .getDeletedTasksForCategoryGroup(category.id);
      }
      if (!mounted) return;
      setState(() {
        _deletedCategories = deleted;
        _activeCategories = active;
        _standaloneTasks = standalone;
        _groups = groups;
        _standaloneSelection.removeWhere(
          (id) => !standalone.any((task) => task.id == id),
        );
        for (final entry in _groupSelections.entries) {
          final ids =
              groups[entry.key]?.map((task) => task.id).toSet() ??
              const <int>{};
          entry.value.removeWhere((id) => !ids.contains(id));
        }
        _loading = false;
        _loadFailed = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await action();
      await widget.widgetRefresh();
      await _load();
    } on Object {
      if (mounted) _message('Could not update Trash.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  bool _retainsActiveCategory(Task task) =>
      task.categoryId != null &&
      _activeCategories.any((category) => category.id == task.categoryId);

  Future<int?> _destination() async {
    if (_activeCategories.isEmpty) return null;
    final inbox = _activeCategories.firstWhere(
      (category) => category.isSystem,
      orElse: () => _activeCategories.first,
    );
    var selected = inbox.id;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Restore task to'),
          content: DropdownButtonFormField<int>(
            key: const ValueKey('trash-restore-destination'),
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final category in _activeCategories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-trash-destination'),
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreTask(Task task) async {
    int? destination;
    if (task.deletedGroupCategoryId != null || !_retainsActiveCategory(task)) {
      destination = await _destination();
      if (destination == null || !mounted) return;
    }
    await _mutate(() async {
      final restored = await widget.taskRepository.restoreTask(
        task.id,
        destinationCategoryId: destination,
      );
      if (restored == null) throw StateError('Task is no longer in Trash.');
    });
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete task?'),
        content: Text(
          '"${task.title}" will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() async {
      if (!await widget.taskRepository.permanentlyDeleteTask(task.id)) {
        throw StateError('Missing task');
      }
    });
  }

  Future<void> _restoreStandaloneBatch() async {
    final selected = _standaloneTasks
        .where((task) => _standaloneSelection.contains(task.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    int? destination;
    if (selected.any((task) => !_retainsActiveCategory(task))) {
      destination = await _destination();
      if (destination == null || !mounted) return;
    }
    final ids = selected.map((task) => task.id).toList(growable: false);
    await _mutate(() async {
      await widget.taskRepository.restoreStandaloneTasks(
        ids,
        destinationCategoryId: destination,
      );
    });
  }

  Future<void> _deleteStandaloneBatch() async {
    final ids = _standaloneSelection.toList(growable: false);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Permanently delete ${ids.length} task${ids.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'Only selected tasks will be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-batch-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() async {
      await widget.taskRepository.permanentlyDeleteStandaloneTasks(ids);
    });
  }

  Future<void> _categoryAction(
    TaskCategory category, {
    required bool delete,
  }) async {
    final tasks = _groups[category.id] ?? const [];
    final selected = <int>{};
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final count = selected.length;
          return AlertDialog(
            title: Text(
              delete
                  ? 'Permanently delete ${category.name}?'
                  : 'Restore ${category.name}?',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delete
                          ? 'The category will be permanently removed. Only selected tasks will be deleted; unselected tasks stay recoverable in Deleted Tasks.'
                          : 'Only selected tasks will be restored with the category. Unselected tasks stay deleted in Deleted Tasks.',
                    ),
                    const SizedBox(height: KedisSpacing.small),
                    Text('$count selected'),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setDialogState(
                            () => selected.addAll(tasks.map((task) => task.id)),
                          ),
                          child: const Text('Select All'),
                        ),
                        TextButton(
                          onPressed: () => setDialogState(selected.clear),
                          child: const Text('Deselect All'),
                        ),
                      ],
                    ),
                    for (final task in tasks)
                      CheckboxListTile(
                        key: ValueKey('category-dialog-task-${task.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(task.title),
                        value: selected.contains(task.id),
                        onChanged: (value) => setDialogState(() {
                          value == true
                              ? selected.add(task.id)
                              : selected.remove(task.id);
                        }),
                      ),
                    if (delete)
                      const Text('Permanent deletion cannot be undone.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: ValueKey(
                  delete
                      ? 'confirm-category-permanent-delete'
                      : 'confirm-category-restore',
                ),
                onPressed: () =>
                    Navigator.pop(dialogContext, Set<int>.of(selected)),
                child: Text(
                  delete
                      ? count == 0
                            ? 'Delete category only'
                            : 'Delete category + $count'
                      : count == 0
                      ? 'Restore category only'
                      : 'Restore category + $count',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    await _mutate(() async {
      if (delete) {
        await widget.categoryRepository.permanentlyDeleteCategory(
          category.id,
          result,
        );
      } else {
        await widget.categoryRepository.restoreDeletedCategory(
          category.id,
          result,
        );
      }
    });
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trash')),
    body: SafeArea(child: _body()),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Could not load Trash. Try again'),
        ),
      );
    }
    if (_deletedCategories.isEmpty && _standaloneTasks.isEmpty) {
      return const Center(child: Text('Trash is empty'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KedisSpacing.medium,
        KedisSpacing.small,
        KedisSpacing.medium,
        KedisSpacing.large,
      ),
      children: [
        Text(
          'Deleted Categories',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: KedisSpacing.small),
        if (_deletedCategories.isEmpty)
          const Text('No deleted categories')
        else
          for (final category in _deletedCategories) _categoryGroup(category),
        const SizedBox(height: KedisSpacing.large),
        Text('Deleted Tasks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: KedisSpacing.small),
        if (_standaloneTasks.isEmpty)
          const Text('No standalone deleted tasks')
        else ...[
          Row(
            children: [
              TextButton(
                onPressed: _mutating
                    ? null
                    : () => setState(
                        () => _standaloneSelection.addAll(
                          _standaloneTasks.map((task) => task.id),
                        ),
                      ),
                child: const Text('Select All'),
              ),
              TextButton(
                onPressed: _mutating
                    ? null
                    : () => setState(_standaloneSelection.clear),
                child: const Text('Deselect All'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Restore selected tasks',
                onPressed: _mutating || _standaloneSelection.isEmpty
                    ? null
                    : _restoreStandaloneBatch,
                icon: const Icon(Icons.restore),
              ),
              IconButton(
                tooltip: 'Permanently delete selected tasks',
                onPressed: _mutating || _standaloneSelection.isEmpty
                    ? null
                    : _deleteStandaloneBatch,
                icon: const Icon(Icons.delete_forever_outlined),
              ),
            ],
          ),
          for (final task in _standaloneTasks)
            _taskTile(task, _standaloneSelection),
        ],
      ],
    );
  }

  Widget _categoryGroup(TaskCategory category) {
    final tasks = _groups[category.id] ?? const [];
    final selection = _groupSelections.putIfAbsent(category.id, () => {});
    final expanded = _expanded.contains(category.id);
    return Card(
      margin: const EdgeInsets.only(bottom: KedisSpacing.small),
      child: Column(
        children: [
          ListTile(
            key: ValueKey('deleted-category-${category.id}'),
            leading: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            title: Text(category.name),
            subtitle: Text(
              '${tasks.length} grouped task${tasks.length == 1 ? '' : 's'}',
            ),
            onTap: () => setState(
              () => expanded
                  ? _expanded.remove(category.id)
                  : _expanded.add(category.id),
            ),
            trailing: PopupMenuButton<_CategoryAction>(
              tooltip: 'Deleted category actions',
              onSelected: (action) => _categoryAction(
                category,
                delete: action == _CategoryAction.delete,
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _CategoryAction.restore,
                  child: Text('Restore category'),
                ),
                PopupMenuItem(
                  value: _CategoryAction.delete,
                  child: Text('Delete category permanently'),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => selection.addAll(tasks.map((task) => task.id)),
                  ),
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: () => setState(selection.clear),
                  child: const Text('Deselect All'),
                ),
              ],
            ),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(KedisSpacing.medium),
                child: Text('No grouped tasks'),
              )
            else
              for (final task in tasks) _taskTile(task, selection),
          ],
        ],
      ),
    );
  }

  Widget _taskTile(Task task, Set<int> selection) => ListTile(
    key: ValueKey('deleted-task-${task.id}'),
    leading: Checkbox(
      value: selection.contains(task.id),
      onChanged: _mutating
          ? null
          : (value) => setState(() {
              value == true
                  ? selection.add(task.id)
                  : selection.remove(task.id);
            }),
    ),
    title: Text(task.title),
    subtitle: Text(task.isCompleted ? 'Completed' : 'Active'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Restore ${task.title}',
          onPressed: _mutating ? null : () => _restoreTask(task),
          icon: const Icon(Icons.restore),
        ),
        IconButton(
          tooltip: 'Permanently delete ${task.title}',
          onPressed: _mutating ? null : () => _deleteTask(task),
          icon: const Icon(Icons.delete_forever_outlined),
        ),
      ],
    ),
  );
}

enum _CategoryAction { restore, delete }
