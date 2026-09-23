import 'dart:async';

import 'package:kedis/models/task.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:kedis/theme/kedis_design.dart';
import 'package:kedis/widgets/editable_task_item.dart';
import 'package:kedis/widgets/editing_task_item.dart';
import 'package:kedis/widgets/empty_task_state.dart';
import 'package:kedis/widgets/kedis_task_item.dart';
import 'package:flutter/material.dart';

class CategoryTaskScreen extends StatefulWidget {
  const CategoryTaskScreen({
    required this.category,
    required this.categoryRepository,
    required this.taskRepository,
    required this.widgetRefresh,
    super.key,
  });

  final TaskCategory category;
  final CategoryRepository categoryRepository;
  final TaskRepository taskRepository;
  final Future<void> Function() widgetRefresh;

  @override
  State<CategoryTaskScreen> createState() => _CategoryTaskScreenState();
}

class _CategoryTaskScreenState extends State<CategoryTaskScreen>
    with WidgetsBindingObserver {
  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _hasLoadError = false;
  bool _isCreatingTask = false;
  bool _isFinishingDraft = false;
  int? _editingTaskId;
  bool _isSavingEdit = false;
  final _draftController = TextEditingController();
  final _draftFocusNode = FocusNode();
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftFocusNode.addListener(_handleDraftFocusChange);
    _loadTasks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftFocusNode.removeListener(_handleDraftFocusChange);
    _draftController.dispose();
    _draftFocusNode.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await widget.taskRepository.getTasks(
        categoryId: widget.category.id,
      );
      if (!mounted) return;

      setState(() {
        _tasks = tasks;
        _isLoading = false;
        _hasLoadError = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasLoadError = true;
      });
    }
  }

  void _startCreatingTask() {
    if (_isCreatingTask) {
      _draftFocusNode.requestFocus();
      return;
    }

    setState(() => _isCreatingTask = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isCreatingTask) {
        _draftFocusNode.requestFocus();
      }
    });
  }

  void _startEditingTask(Task task) {
    if (_editingTaskId == task.id) {
      _editFocusNode.requestFocus();
      return;
    }

    if (_isCreatingTask) {
      _isCreatingTask = false;
      _draftController.clear();
    }
    _editController.text = task.title;
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: task.title.length,
    );
    setState(() => _editingTaskId = task.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingTaskId == task.id) {
        _editFocusNode.requestFocus();
      }
    });
  }

  void _cancelEditingTask() {
    if (_editingTaskId == null || _isSavingEdit) return;
    _editFocusNode.unfocus();
    _editController.clear();
    setState(() => _editingTaskId = null);
  }

  Future<void> _saveEditedTask() async {
    final taskId = _editingTaskId;
    if (taskId == null || _isSavingEdit) return;

    final title = _editController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task title cannot be empty.')),
      );
      _editFocusNode.requestFocus();
      return;
    }

    _isSavingEdit = true;
    final succeeded = await _runMutation(() async {
      final updated = await widget.taskRepository.updateTaskTitle(
        taskId,
        title,
      );
      if (updated == null) {
        throw StateError('Task $taskId no longer exists.');
      }
    });
    _isSavingEdit = false;
    if (!succeeded || !mounted) return;

    _editFocusNode.unfocus();
    _editController.clear();
    setState(() => _editingTaskId = null);
  }

  void _handleDraftFocusChange() {
    if (!_draftFocusNode.hasFocus && _isCreatingTask) {
      _finishDraft();
    }
  }

  Future<void> _finishDraft() async {
    if (!_isCreatingTask || _isFinishingDraft) return;

    final title = _draftController.text.trim();
    _isFinishingDraft = true;
    setState(() => _isCreatingTask = false);
    _draftController.clear();

    if (title.isNotEmpty) {
      await _runMutation(() async {
        await widget.taskRepository.createTask(
          title,
          categoryId: widget.category.id,
        );
      });
    }

    _isFinishingDraft = false;
  }

  Future<void> _toggleTask(Task task) async {
    final willComplete = !task.isCompleted;
    final succeeded = await _runMutation(() async {
      await widget.taskRepository.setTaskCompletion(
        task.id,
        isCompleted: willComplete,
        completedAt: willComplete ? DateTime.now().toUtc() : null,
      );
    });
    if (!succeeded || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text(
          willComplete ? 'Task completed' : 'Task marked incomplete',
        ),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => unawaited(_restoreTaskCompletion(task)),
        ),
      ),
    );
  }

  Future<void> _restoreTaskCompletion(Task previousTask) async {
    await _runMutation(() async {
      await widget.taskRepository.setTaskCompletion(
        previousTask.id,
        isCompleted: previousTask.isCompleted,
        completedAt: previousTask.completedAt,
      );
    });
  }

  Future<void> _deleteTask(Task task) async {
    final succeeded = await _runMutation(() async {
      final deleted = await widget.taskRepository.deleteTask(task.id);
      if (!deleted) {
        throw StateError('Task ${task.id} no longer exists.');
      }
    });
    if (!succeeded || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: const Text('Task moved to Trash'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => unawaited(_restoreDeletedTask(task)),
        ),
      ),
    );
  }

  Future<void> _restoreDeletedTask(Task task) async {
    await _runMutation(() async {
      final restored = await widget.taskRepository.restoreTask(task.id);
      if (restored == null) {
        throw StateError('Task ${task.id} is no longer in Trash.');
      }
    });
  }

  Future<void> _moveTask(Task task) async {
    List<TaskCategory> categories;
    try {
      categories = await widget.categoryRepository.getCategories();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load categories.')),
        );
      }
      return;
    }
    if (!mounted) return;

    final destinations = categories
        .where((category) => category.id != task.categoryId)
        .toList(growable: false);
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No other categories yet.')));
      return;
    }

    final targetCategoryId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move task to'),
        children: [
          for (final category in destinations)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(category.id),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(category.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: KedisSpacing.small),
                  Expanded(child: Text(category.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (targetCategoryId == null || !mounted) return;

    await _runMutation(() async {
      final moved = await widget.taskRepository.moveTaskToCategory(
        task.id,
        targetCategoryId,
      );
      if (moved == null) {
        throw StateError('Task ${task.id} no longer exists.');
      }
    });
  }

  Future<bool> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      await widget.widgetRefresh();
      await _loadTasks();
      return true;
    } on Object {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update tasks.')));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(widget.category.colorValue);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: KedisSpacing.small),
            Flexible(child: Text(widget.category.name)),
          ],
        ),
      ),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _isCreatingTask || _editingTaskId != null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 30),
              child: TextFieldTapRegion(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: FloatingActionButton(
                    onPressed: _startCreatingTask,
                    tooltip: 'Add task',
                    child: const Icon(Icons.add, size: 26),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasLoadError) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: _loadTasks,
          icon: const Icon(Icons.refresh),
          label: const Text('Could not load tasks. Try again'),
        ),
      );
    }

    if (_tasks.isEmpty && !_isCreatingTask) {
      return const EmptyTaskState();
    }

    final activeTasks = _tasks.where((task) => !task.isCompleted).toList();
    final completedTasks = _tasks.where((task) => task.isCompleted).toList();
    final items = <Widget>[
      ...activeTasks.map(_buildTaskItem),
      if (_isCreatingTask)
        EditableTaskItem(
          key: const ValueKey('task-draft-row'),
          controller: _draftController,
          focusNode: _draftFocusNode,
          onFinish: _finishDraft,
        ),
      if (completedTasks.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(
            top: KedisSpacing.small,
            left: KedisSpacing.xSmall,
          ),
          child: Text(
            'Completed',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...completedTasks.map(_buildTaskItem),
      ],
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KedisSpacing.medium,
        KedisSpacing.xSmall,
        KedisSpacing.medium,
        104,
      ),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => items[index],
    );
  }

  Widget _buildTaskItem(Task task) {
    if (_editingTaskId == task.id) {
      return EditingTaskItem(
        key: ValueKey('editing-${task.id}'),
        task: task,
        controller: _editController,
        focusNode: _editFocusNode,
        onSave: _saveEditedTask,
        onCancel: _cancelEditingTask,
      );
    }

    return KedisTaskItem(
      key: ValueKey(task.id),
      task: task,
      onToggle: () => _toggleTask(task),
      onDelete: () => _deleteTask(task),
      onEdit: () => _startEditingTask(task),
      onMove: () => _moveTask(task),
    );
  }
}
