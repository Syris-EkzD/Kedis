import 'package:kedis/repositories/task_repository.dart';
import 'package:kedis/screens/trash_screen.dart';
import 'package:kedis/settings/home_layout_controller.dart';
import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:kedis/settings/theme_controller.dart';
import 'package:kedis/theme/kedis_design.dart';
import 'package:flutter/material.dart';

const _itemVerticalPadding = 14.0;
const _itemIconSize = 40.0;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.themeController,
    required this.homeLayoutController,
    required this.taskRepository,
    required this.widgetRefresh,
    super.key,
  });

  final ThemeController themeController;
  final HomeLayoutController homeLayoutController;
  final TaskRepository taskRepository;
  final Future<void> Function() widgetRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KedisSpacing.medium,
            KedisSpacing.small,
            KedisSpacing.medium,
            KedisSpacing.large,
          ),
          children: [
            SettingsSection(
              title: 'Appearance',
              children: [
                ListenableBuilder(
                  listenable: themeController,
                  builder: (context, _) => SettingsItem(
                    icon: Icons.palette_outlined,
                    title: 'Theme',
                    description: 'Choose how Kedis looks',
                    value: _themeModeLabel(themeController.themeMode),
                    onTap: () => _showThemeDialog(context),
                  ),
                ),
                ListenableBuilder(
                  listenable: homeLayoutController,
                  builder: (context, _) => SettingsItem(
                    icon: Icons.grid_view_outlined,
                    title: 'Home layout',
                    description: 'Choose how category cards are arranged',
                    value: _homeLayoutLabel(homeLayoutController.layoutMode),
                    onTap: () => _showHomeLayoutDialog(context),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'Tasks',
              children: [
                SettingsItem(
                  icon: Icons.delete_outline,
                  title: 'Trash',
                  description: 'Restore or permanently delete tasks',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => TrashScreen(
                        taskRepository: taskRepository,
                        widgetRefresh: widgetRefresh,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThemeDialog(BuildContext context) async {
    final selectedMode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose theme'),
        content: RadioGroup<ThemeMode>(
          groupValue: themeController.themeMode,
          onChanged: (mode) => Navigator.pop(context, mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ThemeMode.values
                .map(
                  (mode) => RadioListTile<ThemeMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_themeModeLabel(mode)),
                    subtitle: Text(_themeModeDescription(mode)),
                    value: mode,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    if (selectedMode != null) {
      await themeController.setThemeMode(selectedMode);
    }
  }

  Future<void> _showHomeLayoutDialog(BuildContext context) async {
    final selectedMode = await showDialog<HomeLayoutMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose home layout'),
        content: RadioGroup<HomeLayoutMode>(
          groupValue: homeLayoutController.layoutMode,
          onChanged: (mode) => Navigator.pop(context, mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: HomeLayoutMode.values
                .map(
                  (mode) => RadioListTile<HomeLayoutMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_homeLayoutLabel(mode)),
                    subtitle: Text(_homeLayoutDescription(mode)),
                    value: mode,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    if (selectedMode != null) {
      await homeLayoutController.setLayoutMode(selectedMode);
    }
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KedisSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: KedisSpacing.xSmall,
              right: KedisSpacing.xSmall,
              bottom: KedisSpacing.small,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class SettingsItem extends StatelessWidget {
  const SettingsItem({
    required this.icon,
    required this.title,
    this.description,
    this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KedisSpacing.medium,
        vertical: _itemVerticalPadding,
      ),
      leading: Container(
        width: _itemIconSize,
        height: _itemIconSize,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(KedisRadii.small),
        ),
        child: Icon(icon, color: colorScheme.onSecondaryContainer),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: description == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: KedisSpacing.xSmall),
              child: Text(
                description!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            Text(
              value!,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.primary),
            ),
            const SizedBox(width: KedisSpacing.xSmall),
          ],
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

String _themeModeDescription(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'Match your device appearance',
    ThemeMode.light => 'Always use light appearance',
    ThemeMode.dark => 'Always use dark appearance',
  };
}

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

String _homeLayoutDescription(HomeLayoutMode mode) {
  return switch (mode) {
    HomeLayoutMode.grid => 'Two compact category cards per row',
    HomeLayoutMode.list => 'Full-width category cards',
  };
}

String _homeLayoutLabel(HomeLayoutMode mode) {
  return switch (mode) {
    HomeLayoutMode.grid => 'Grid',
    HomeLayoutMode.list => 'List',
  };
}
