import 'package:kedis/models/task.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/repositories/category_repository.dart';
import 'package:kedis/repositories/task_repository.dart';
import 'package:kedis/screens/category_task_screen.dart';
import 'package:kedis/settings/home_layout_controller.dart';
import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:kedis/settings/settings_screen.dart';
import 'package:kedis/settings/theme_controller.dart';
import 'package:kedis/theme/kedis_design.dart';
import 'package:kedis/widgets/category_card.dart';
import 'package:kedis/widgets/category_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class CategoryHomeScreen extends StatefulWidget {
  const CategoryHomeScreen({
    required this.categoryRepository,
    required this.taskRepository,
    required this.themeController,
    required this.homeLayoutController,
    required this.widgetRefresh,
    super.key,
  });

  final CategoryRepository categoryRepository;
  final TaskRepository taskRepository;
  final ThemeController themeController;
  final HomeLayoutController homeLayoutController;
  final Future<void> Function() widgetRefresh;

  @override
  State<CategoryHomeScreen> createState() => _CategoryHomeScreenState();
}

class _CategoryHomeScreenState extends State<CategoryHomeScreen>
    with WidgetsBindingObserver {
  static const _gridPreviewLimit = 2;
  static const _listPreviewLimit = 3;
  static const _gridSpacing = KedisSpacing.small;
  static const _minimumGridCardWidth = 156.0;
  static const _gridBottomPadding = 184.0;

  List<TaskCategory> _categories = const [];
  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _hasLoadError = false;
  bool _isCreationMenuExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOverview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadOverview();
    }
  }

  Future<void> _loadOverview() async {
    try {
      final categoriesFuture = widget.categoryRepository.getCategories();
      final tasksFuture = widget.taskRepository.getTasks();
      final categories = await categoriesFuture;
      final tasks = await tasksFuture;
      if (!mounted) return;

      setState(() {
        _categories = categories;
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

  Future<void> _openCategory(TaskCategory category) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CategoryTaskScreen(
          category: category,
          categoryRepository: widget.categoryRepository,
          taskRepository: widget.taskRepository,
          widgetRefresh: widget.widgetRefresh,
        ),
      ),
    );
    if (mounted) {
      await _loadOverview();
    }
  }

  Future<void> _quickCapture() async {
    TaskCategory inbox;
    try {
      inbox = await widget.categoryRepository.getInbox();
    } on Object {
      if (mounted) _showMessage('Could not load categories.');
      return;
    }
    if (!mounted) return;

    var draftTitle = '';
    var selectedCategoryId = inbox.id;
    final result = await showDialog<_QuickCaptureResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit(String rawTitle) {
            final normalizedTitle = rawTitle.trim();
            if (normalizedTitle.isEmpty) return;
            Navigator.of(dialogContext).pop(
              _QuickCaptureResult(
                title: normalizedTitle,
                categoryId: selectedCategoryId,
              ),
            );
          }

          return AlertDialog(
            title: const Text('Add task'),
            content: SizedBox(
              key: const ValueKey('quick-capture-content'),
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: TextField(
                      key: const ValueKey('quick-capture-title'),
                      autofocus: true,
                      minLines: 1,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Task title'),
                      onChanged: (value) => draftTitle = value,
                      onSubmitted: submit,
                    ),
                  ),
                  const SizedBox(height: KedisSpacing.medium),
                  MenuAnchor(
                    menuChildren: [
                      for (final category in _categories)
                        MenuItemButton(
                          key: ValueKey(
                            'quick-capture-category-option-${category.id}',
                          ),
                          leadingIcon: _buildCategoryColorDot(
                            category,
                            key: ValueKey(
                              'quick-capture-category-option-color-${category.id}',
                            ),
                          ),
                          onPressed: () {
                            setDialogState(
                              () => selectedCategoryId = category.id,
                            );
                          },
                          child: Text(
                            category.name,
                            key: ValueKey(
                              'quick-capture-category-option-label-${category.id}',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    builder: (context, menuController, child) {
                      final selectedCategory = _categories.firstWhere(
                        (category) => category.id == selectedCategoryId,
                        orElse: () => inbox,
                      );
                      return InkWell(
                        key: const ValueKey('quick-capture-category'),
                        borderRadius: BorderRadius.circular(KedisRadii.small),
                        onTap: () {
                          if (menuController.isOpen) {
                            menuController.close();
                          } else {
                            menuController.open();
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Row(
                            children: [
                              _buildCategoryColorDot(
                                selectedCategory,
                                key: const ValueKey(
                                  'quick-capture-selected-category-color',
                                ),
                              ),
                              const SizedBox(width: KedisSpacing.small),
                              Expanded(
                                child: Text(
                                  selectedCategory.name,
                                  key: const ValueKey(
                                    'quick-capture-selected-category',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => submit(draftTitle),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;

    try {
      await widget.taskRepository.createTask(
        result.title,
        categoryId: result.categoryId,
      );
      await widget.widgetRefresh();
      await _loadOverview();
    } on Object {
      if (!mounted) return;
      _showMessage('Could not create task.');
    }
  }

  Future<void> _createCategory() async {
    final result = await showCategoryEditorDialog(context);
    if (result == null || !mounted) return;

    try {
      await widget.categoryRepository.createCategory(
        result.name,
        result.colorValue,
      );
      await _loadOverview();
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } on Object {
      if (mounted) _showMessage('Could not create category.');
    }
  }

  Future<void> _editCategory(TaskCategory category) async {
    final result = await showCategoryEditorDialog(context, category: category);
    if (result == null || !mounted) return;

    try {
      if (result.name != category.name) {
        await widget.categoryRepository.renameCategory(
          category.id,
          result.name,
        );
      }
      if (result.colorValue != category.colorValue) {
        await widget.categoryRepository.updateCategoryColor(
          category.id,
          result.colorValue,
        );
      }
      await _loadOverview();
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } on Object {
      if (mounted) _showMessage('Could not update category.');
    }
  }

  Future<void> _deleteCategory(TaskCategory category) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        content: const Text('Its tasks will be moved to Inbox.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      await widget.categoryRepository.deleteCategory(category.id);
      await widget.widgetRefresh();
      await _loadOverview();
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } on Object {
      if (mounted) _showMessage('Could not delete category.');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsScreen(
          themeController: widget.themeController,
          homeLayoutController: widget.homeLayoutController,
          taskRepository: widget.taskRepository,
          widgetRefresh: widget.widgetRefresh,
        ),
      ),
    );
    if (mounted) {
      await _loadOverview();
    }
  }

  void _toggleCreationMenu() {
    setState(() => _isCreationMenuExpanded = !_isCreationMenuExpanded);
  }

  Future<void> _createTaskFromMenu() async {
    setState(() => _isCreationMenuExpanded = false);
    await _quickCapture();
  }

  Future<void> _createCategoryFromMenu() async {
    setState(() => _isCreationMenuExpanded = false);
    await _createCategory();
  }

  Widget _buildCategoryColorDot(TaskCategory category, {required Key key}) {
    return Container(
      key: key,
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Color(category.colorValue),
        shape: BoxShape.circle,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kedis',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            Text(
              'Your categories',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: KedisSpacing.small),
            child: IconButton(
              onPressed: _openSettings,
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isCreationMenuExpanded) ...[
              FloatingActionButton.extended(
                key: const ValueKey('home-create-category'),
                heroTag: 'home-create-category',
                onPressed: _createCategoryFromMenu,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Category'),
              ),
              const SizedBox(height: KedisSpacing.small),
              FloatingActionButton.extended(
                key: const ValueKey('home-create-task'),
                heroTag: 'home-create-task',
                onPressed: _createTaskFromMenu,
                icon: const Icon(Icons.add_task),
                label: const Text('Task'),
              ),
              const SizedBox(height: KedisSpacing.small),
            ],
            FloatingActionButton(
              key: const ValueKey('home-create-menu'),
              heroTag: 'home-create-menu',
              onPressed: _toggleCreationMenu,
              tooltip: _isCreationMenuExpanded
                  ? 'Close creation menu'
                  : 'Create',
              child: Icon(
                _isCreationMenuExpanded ? Icons.close : Icons.add,
                size: 26,
              ),
            ),
          ],
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
          onPressed: _loadOverview,
          icon: const Icon(Icons.refresh),
          label: const Text('Could not load categories. Try again'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: widget.homeLayoutController,
      builder: (context, _) {
        final tasksByCategory = <int, List<Task>>{};
        for (final task in _tasks) {
          tasksByCategory.putIfAbsent(task.categoryId, () => []).add(task);
        }

        return switch (widget.homeLayoutController.layoutMode) {
          HomeLayoutMode.grid => _buildGrid(tasksByCategory),
          HomeLayoutMode.list => _buildList(tasksByCategory),
        };
      },
    );
  }

  Widget _buildGrid(Map<int, List<Task>> tasksByCategory) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = KedisSpacing.medium * 2;
        final contentWidth = constraints.maxWidth - horizontalPadding;
        final twoColumns =
            contentWidth >= (_minimumGridCardWidth * 2) + _gridSpacing;
        return MasonryGridView.builder(
          key: const ValueKey('category-home-grid'),
          padding: const EdgeInsets.fromLTRB(
            KedisSpacing.medium,
            KedisSpacing.small,
            KedisSpacing.medium,
            _gridBottomPadding,
          ),
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: twoColumns ? 2 : 1,
          ),
          mainAxisSpacing: _gridSpacing,
          crossAxisSpacing: _gridSpacing,
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            return _buildCategoryCard(
              category,
              tasksByCategory[category.id] ?? const [],
              isGridLayout: true,
            );
          },
        );
      },
    );
  }

  Widget _buildList(Map<int, List<Task>> tasksByCategory) {
    return ListView.separated(
      key: const ValueKey('category-home-list'),
      padding: const EdgeInsets.fromLTRB(
        KedisSpacing.medium,
        KedisSpacing.small,
        KedisSpacing.medium,
        104,
      ),
      itemCount: _categories.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: KedisSpacing.medium),
      itemBuilder: (context, index) {
        final category = _categories[index];
        return _buildCategoryCard(
          category,
          tasksByCategory[category.id] ?? const [],
        );
      },
    );
  }

  Widget _buildCategoryCard(
    TaskCategory category,
    List<Task> categoryTasks, {
    bool isGridLayout = false,
  }) {
    final activeTasks = categoryTasks
        .where((task) => !task.isCompleted)
        .toList(growable: false);
    final previewLimit = isGridLayout ? _gridPreviewLimit : _listPreviewLimit;
    final previewTasks = activeTasks.take(previewLimit).toList(growable: false);

    return CategoryCard(
      key: ValueKey('category-card-${category.id}'),
      category: category,
      activeCount: activeTasks.length,
      totalCount: categoryTasks.length,
      previewTasks: previewTasks,
      isGridLayout: isGridLayout,
      onTap: () => _openCategory(category),
      onEdit: category.isSystem ? null : () => _editCategory(category),
      onDelete: category.isSystem ? null : () => _deleteCategory(category),
    );
  }
}

class _QuickCaptureResult {
  const _QuickCaptureResult({required this.title, required this.categoryId});

  final String title;
  final int categoryId;
}
