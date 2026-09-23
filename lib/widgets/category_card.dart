import 'package:kedis/models/task.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/theme/kedis_design.dart';
import 'package:flutter/material.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    required this.category,
    required this.activeCount,
    required this.totalCount,
    required this.previewTasks,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.isGridLayout = false,
    super.key,
  });

  static const gridMaxHeight = 200.0;
  static const gridTitleMaxLines = 2;
  static const _gridActionExtent = 40.0;
  static const _gridActionIconSize = 20.0;
  static const _previewCheckboxSize = 18.0;

  final TaskCategory category;
  final int activeCount;
  final int totalCount;
  final List<Task> previewTasks;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isGridLayout;

  @override
  Widget build(BuildContext context) {
    final accent = Color(category.colorValue);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hiddenCount = activeCount - previewTasks.length;
    final titleStyle = isGridLayout
        ? textTheme.titleSmall
        : textTheme.titleMedium;

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(
            KedisSpacing.medium,
            KedisSpacing.medium,
            KedisSpacing.small,
            KedisSpacing.medium,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: isGridLayout ? gridTitleMaxLines : 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (onEdit != null && onDelete != null)
                    _buildActionMenu()
                  else
                    const SizedBox(width: KedisSpacing.small),
                ],
              ),
              const SizedBox(height: KedisSpacing.xSmall),
              _buildCounts(textTheme, colorScheme, accent),
              if (previewTasks.isEmpty) ...[
                const SizedBox(height: KedisSpacing.small),
                Text(
                  'No active tasks',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: KedisSpacing.small),
                ...previewTasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(top: KedisSpacing.xSmall),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.check_box_outline_blank,
                            key: ValueKey('task-preview-checkbox-${task.id}'),
                            size: _previewCheckboxSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: KedisSpacing.small),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: KedisSpacing.small),
                    child: Text(
                      '+$hiddenCount more',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!isGridLayout) {
      return card;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: gridMaxHeight),
      child: card,
    );
  }

  Widget _buildActionMenu() {
    final menu = PopupMenuButton<_CategoryCardAction>(
      tooltip: 'Category actions',
      padding: isGridLayout ? EdgeInsets.zero : const EdgeInsets.all(8),
      iconSize: isGridLayout ? _gridActionIconSize : null,
      onSelected: (action) {
        switch (action) {
          case _CategoryCardAction.edit:
            onEdit?.call();
            break;
          case _CategoryCardAction.delete:
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _CategoryCardAction.edit,
          child: Text('Edit category'),
        ),
        PopupMenuItem(
          value: _CategoryCardAction.delete,
          child: Text('Delete category'),
        ),
      ],
    );

    if (!isGridLayout) {
      return menu;
    }
    return SizedBox.square(dimension: _gridActionExtent, child: menu);
  }

  Widget _buildCounts(
    TextTheme textTheme,
    ColorScheme colorScheme,
    Color accent,
  ) {
    return Wrap(
      spacing: KedisSpacing.xSmall,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$activeCount active',
          style: textTheme.bodySmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '· $totalCount total',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

enum _CategoryCardAction { edit, delete }
