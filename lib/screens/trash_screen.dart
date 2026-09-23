import 'package:kedis/models/task.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:kedis/theme/kedis_design.dart';
import 'package:flutter/material.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    required this.taskRepository,
    required this.widgetRefresh,
    super.key,
  });

  final TaskRepository taskRepository;
  final Future<void> Function() widgetRefresh;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    try {
      final tasks = await widget.taskRepository.getDeletedTasks();
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

  Future<void> _restoreTask(Task task) async {
    try {
      final restored = await widget.taskRepository.restoreTask(task.id);
      if (restored == null) {
        throw StateError('Task is no longer in Trash.');
      }
      await widget.widgetRefresh();
      await _loadTrash();
    } on Object {
      if (mounted) {
        _showMessage('Could not restore task.');
      }
    }
  }

  Future<void> _permanentlyDeleteTask(Task task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete task?'),
        content: Text(
          '"${task.title}" will be deleted permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      final deleted = await widget.taskRepository.permanentlyDeleteTask(
        task.id,
      );
      if (!deleted) {
        throw StateError('Task is no longer in Trash.');
      }
      await widget.widgetRefresh();
      await _loadTrash();
    } on Object {
      if (mounted) {
        _showMessage('Could not permanently delete task.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasLoadError) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: _loadTrash,
          icon: const Icon(Icons.refresh),
          label: const Text('Could not load Trash. Try again'),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KedisSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: KedisSpacing.small),
              Text(
                'Trash is empty',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: KedisSpacing.xSmall),
              Text(
                'Deleted tasks stay here until you restore or permanently delete them.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KedisSpacing.medium,
        KedisSpacing.small,
        KedisSpacing.medium,
        KedisSpacing.large,
      ),
      itemCount: _tasks.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: KedisSpacing.small),
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(task.title),
            subtitle: Text(task.isCompleted ? 'Completed' : 'Active'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Restore ${task.title}',
                  onPressed: () => _restoreTask(task),
                  icon: const Icon(Icons.restore),
                ),
                IconButton(
                  tooltip: 'Permanently delete ${task.title}',
                  onPressed: () => _permanentlyDeleteTask(task),
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
