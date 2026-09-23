import 'package:kedis/main.dart';
import 'package:kedis/models/task_category.dart';
import 'package:kedis/settings/home_layout_controller.dart';
import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:kedis/settings/theme_controller.dart';
import 'package:kedis/settings/theme_preference_store.dart';
import 'package:kedis/widgets/category_card.dart';
import 'package:kedis/widgets/editable_task_item.dart';
import 'package:kedis/widgets/editing_task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_repositories.dart';

void main() {
  late FakeTaskRepository tasks;
  late FakeCategoryRepository categories;
  late _FakeThemePreferenceStore themePreferenceStore;
  late _FakeHomeLayoutPreferenceStore homeLayoutPreferenceStore;
  late HomeLayoutController homeLayoutController;
  late int widgetRefreshCount;

  setUp(() {
    final repositories = FakeRepositories();
    tasks = repositories.tasks;
    categories = repositories.categories;
    themePreferenceStore = _FakeThemePreferenceStore();
    homeLayoutPreferenceStore = _FakeHomeLayoutPreferenceStore();
    homeLayoutController = HomeLayoutController(homeLayoutPreferenceStore);
    widgetRefreshCount = 0;
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
    String failureMessage,
  ) async {
    await tester.pump();
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail(failureMessage);
  }

  Future<void> waitForUndo(WidgetTester tester, String failureMessage) async {
    await pumpUntil(
      tester,
      () => find.text('UNDO').hitTestable().evaluate().isNotEmpty,
      failureMessage,
    );
  }

  Future<void> pumpKedis(WidgetTester tester) async {
    await tester.pumpWidget(
      KedisApp(
        taskRepository: tasks,
        categoryRepository: categories,
        themeController: ThemeController(themePreferenceStore),
        homeLayoutController: homeLayoutController,
        widgetRefresh: () async {
          widgetRefreshCount += 1;
        },
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('Inbox').evaluate().isNotEmpty,
      'Kedis category home did not finish loading.',
    );
  }

  Future<void> expandHomeCreationMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-create-menu')));
    await pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey('home-create-task'))
              .evaluate()
              .isNotEmpty &&
          find
              .byKey(const ValueKey('home-create-category'))
              .evaluate()
              .isNotEmpty,
      'Home creation menu did not expand.',
    );
  }

  Future<void> openHomeTaskCapture(WidgetTester tester) async {
    await expandHomeCreationMenu(tester);
    await tester.tap(find.byKey(const ValueKey('home-create-task')));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('quick-capture-category'))
          .evaluate()
          .isNotEmpty,
      'Quick-capture dialog did not appear.',
    );
    expect(find.byKey(const ValueKey('home-create-task')), findsNothing);
    expect(find.byKey(const ValueKey('home-create-category')), findsNothing);
  }

  Future<void> openHomeCategoryCreation(WidgetTester tester) async {
    await expandHomeCreationMenu(tester);
    await tester.tap(find.byKey(const ValueKey('home-create-category')));
    await pumpUntil(
      tester,
      () => find.text('Create category').evaluate().isNotEmpty,
      'Create-category dialog did not appear.',
    );
    expect(find.byKey(const ValueKey('home-create-task')), findsNothing);
    expect(find.byKey(const ValueKey('home-create-category')), findsNothing);
  }

  Future<void> openCategory(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await pumpUntil(
      tester,
      () => find.byTooltip('Add task').evaluate().isNotEmpty,
      '$name task screen did not finish loading.',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home creation FAB expands and collapses create actions', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('home-create-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-create-task')), findsNothing);
    expect(find.byKey(const ValueKey('home-create-category')), findsNothing);
    expect(find.byTooltip('Add category'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await expandHomeCreationMenu(tester);

    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.byIcon(Icons.add_task), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-create-menu')));
    await tester.pump();

    expect(find.byKey(const ValueKey('home-create-task')), findsNothing);
    expect(find.byKey(const ValueKey('home-create-category')), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('List keeps three display-only checkbox previews', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    final firstPreview = await tasks.createTask('One', categoryId: school.id);
    for (final title in ['Two', 'Three', 'Four']) {
      await tasks.createTask(title, categoryId: school.id);
    }
    final completed = await tasks.createTask(
      'Completed',
      categoryId: school.id,
    );
    await tasks.setTaskCompletion(
      completed.id,
      isCompleted: true,
      completedAt: DateTime.utc(2026, 9, 16, 12),
    );
    final trashed = await tasks.createTask('Trashed', categoryId: school.id);
    await tasks.deleteTask(trashed.id);

    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('category-home-list')), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('School'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Four'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Trashed'), findsNothing);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('4 active'), findsOneWidget);
    expect(find.text('· 5 total'), findsOneWidget);

    final previewCheckbox = find.byKey(
      ValueKey('task-preview-checkbox-${firstPreview.id}'),
    );
    expect(previewCheckbox, findsOneWidget);
    expect(
      tester.widget<Icon>(previewCheckbox).icon,
      Icons.check_box_outline_blank,
    );
    expect(
      find.ancestor(of: previewCheckbox, matching: find.byType(Checkbox)),
      findsNothing,
    );

    await tester.tap(previewCheckbox);
    await tester.pumpAndSettle();

    final persisted = (await tasks.getTasks(categoryId: school.id))
        .firstWhere((task) => task.id == firstPreview.id);
    expect(persisted.isCompleted, isFalse);
    expect(persisted.completedAt, isNull);
    expect(widgetRefreshCount, 0);
  });

  testWidgets('Grid cards size naturally up to the maximum height', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.grid,
    );

    final inbox = await categories.getInbox();
    final programming = await categories.createCategory(
      'Programming',
      0xFF6750A4,
    );
    final wrapped = await categories.createCategory(
      'Research and Development',
      0xFF006C4C,
    );
    final excessive = await categories.createCategory(
      'An extremely long category title that cannot fit within two lines',
      0xFF9C4146,
    );

    for (final title in ['One', 'Two', 'Three', 'Four']) {
      await tasks.createTask(title, categoryId: programming.id);
      await tasks.createTask('Long $title', categoryId: wrapped.id);
    }

    await pumpKedis(tester);

    expect(find.byType(MasonryGridView), findsOneWidget);

    final inboxCard = find.byKey(ValueKey('category-card-${inbox.id}'));
    final programmingCard = find.byKey(
      ValueKey('category-card-${programming.id}'),
    );
    final wrappedCard = find.byKey(ValueKey('category-card-${wrapped.id}'));
    final excessiveCard = find.byKey(ValueKey('category-card-${excessive.id}'));

    for (final card in [
      inboxCard,
      programmingCard,
      wrappedCard,
      excessiveCard,
    ]) {
      expect(
        tester.getSize(card).height,
        lessThanOrEqualTo(CategoryCard.gridMaxHeight),
      );
    }
    expect(
      tester.getSize(inboxCard).height,
      lessThan(tester.getSize(programmingCard).height),
    );
    expect(
      tester.getSize(excessiveCard).height,
      lessThan(CategoryCard.gridMaxHeight),
    );

    expect(
      tester.getSize(inboxCard).width,
      tester.getSize(programmingCard).width,
    );
    expect(
      tester.getTopLeft(inboxCard).dx,
      lessThan(tester.getTopLeft(programmingCard).dx),
    );
    expect(
      tester.getTopLeft(inboxCard).dy,
      tester.getTopLeft(programmingCard).dy,
    );

    final programmingTitle = tester.widget<Text>(
      find.descendant(
        of: programmingCard,
        matching: find.text(programming.name),
      ),
    );
    final wrappedTitle = tester.widget<Text>(
      find.descendant(of: wrappedCard, matching: find.text(wrapped.name)),
    );
    final excessiveTitle = tester.widget<Text>(
      find.descendant(of: excessiveCard, matching: find.text(excessive.name)),
    );

    expect(programmingTitle.maxLines, CategoryCard.gridTitleMaxLines);
    expect(wrappedTitle.maxLines, CategoryCard.gridTitleMaxLines);
    expect(excessiveTitle.maxLines, CategoryCard.gridTitleMaxLines);
    expect(excessiveTitle.overflow, TextOverflow.ellipsis);

    expect(
      find.descendant(of: programmingCard, matching: find.text('One')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: programmingCard, matching: find.text('Two')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: programmingCard, matching: find.text('Three')),
      findsNothing,
    );
    expect(
      find.descendant(of: programmingCard, matching: find.text('Four')),
      findsNothing,
    );
    expect(
      find.descendant(of: programmingCard, matching: find.text('+2 more')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inboxCard, matching: find.text('No active tasks')),
      findsOneWidget,
    );

    final previewCheckboxes = find.descendant(
      of: programmingCard,
      matching: find.byIcon(Icons.check_box_outline_blank),
    );
    expect(previewCheckboxes, findsNWidgets(2));

    final actionButton = find.descendant(
      of: programmingCard,
      matching: find.byTooltip('Category actions'),
    );
    expect(actionButton, findsOneWidget);
    final titleCenter = tester.getCenter(
      find.descendant(
        of: programmingCard,
        matching: find.text(programming.name),
      ),
    );
    final actionCenter = tester.getCenter(actionButton);
    expect((titleCenter.dy - actionCenter.dy).abs(), lessThan(12));

    await tester.tap(actionButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit category'), findsOneWidget);
    expect(find.text('Delete category'), findsOneWidget);
    expect(find.text('E'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Grid packs shorter cards below the shorter masonry column', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.grid,
    );

    final inbox = await categories.getInbox();
    final tall = await categories.createCategory('Tall', 0xFF6750A4);
    final nextShort = await categories.createCategory('Next short', 0xFF006C4C);
    final finalShort = await categories.createCategory(
      'Final short',
      0xFF9C4146,
    );

    for (final title in ['One', 'Two', 'Three']) {
      await tasks.createTask(title, categoryId: tall.id);
    }

    await pumpKedis(tester);

    final inboxCard = find.byKey(ValueKey('category-card-${inbox.id}'));
    final tallCard = find.byKey(ValueKey('category-card-${tall.id}'));
    final nextShortCard = find.byKey(ValueKey('category-card-${nextShort.id}'));
    final finalShortCard = find.byKey(
      ValueKey('category-card-${finalShort.id}'),
    );

    final inboxBottom = tester.getBottomLeft(inboxCard).dy;
    final tallBottom = tester.getBottomLeft(tallCard).dy;
    final nextShortTop = tester.getTopLeft(nextShortCard).dy;
    final finalShortTop = tester.getTopLeft(finalShortCard).dy;

    expect(
      tester.getTopLeft(inboxCard).dx,
      lessThan(tester.getTopLeft(tallCard).dx),
    );
    expect(
      tester.getTopLeft(nextShortCard).dx,
      tester.getTopLeft(inboxCard).dx,
    );
    expect(nextShortTop, greaterThan(inboxBottom));
    expect(nextShortTop, lessThan(tallBottom));
    expect(finalShortTop, greaterThan(tallBottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Grid falls back to one column on a narrow surface', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(340, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.grid,
    );

    final inbox = await categories.getInbox();
    final school = await categories.createCategory('School', 0xFF6750A4);

    await pumpKedis(tester);

    expect(find.byType(MasonryGridView), findsOneWidget);

    final inboxCard = find.byKey(ValueKey('category-card-${inbox.id}'));
    final schoolCard = find.byKey(ValueKey('category-card-${school.id}'));

    expect(tester.getTopLeft(inboxCard).dx, tester.getTopLeft(schoolCard).dx);
    expect(
      tester.getTopLeft(schoolCard).dy,
      greaterThan(tester.getTopLeft(inboxCard).dy),
    );
    expect(
      tester.getSize(inboxCard).height,
      lessThanOrEqualTo(CategoryCard.gridMaxHeight),
    );
    expect(
      tester.getSize(schoolCard).height,
      lessThanOrEqualTo(CategoryCard.gridMaxHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Grid leaves bottom clearance above the Home FAB', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.grid,
    );

    TaskCategory lastCategory = await categories.getInbox();
    for (var index = 1; index <= 12; index += 1) {
      lastCategory = await categories.createCategory(
        'Category $index',
        0xFF6750A4,
      );
    }

    await pumpKedis(tester);

    final grid = find.byKey(const ValueKey('category-home-grid'));
    final lastCard = find.byKey(ValueKey('category-card-${lastCategory.id}'));
    final fab = find.byKey(const ValueKey('home-create-menu'));

    final scrollable = tester.widget<Scrollable>(
      find.descendant(of: grid, matching: find.byType(Scrollable)),
    );
    scrollable.controller!.jumpTo(
      scrollable.controller!.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();

    expect(lastCard, findsOneWidget);
    expect(
      tester.getBottomLeft(lastCard).dy,
      lessThan(tester.getTopLeft(fab).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed-only category still reports its total', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    final completed = await tasks.createTask('Finished', categoryId: school.id);
    await tasks.setTaskCompletion(
      completed.id,
      isCompleted: true,
      completedAt: DateTime.utc(2026, 9, 18, 12),
    );

    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('category-home-list')), findsOneWidget);
    expect(find.text('0 active'), findsWidgets);
    expect(find.text('· 1 total'), findsOneWidget);
    expect(find.text('No active tasks'), findsWidgets);
    expect(find.text('Finished'), findsNothing);
  });

  testWidgets('default Home layout is List', (WidgetTester tester) async {
    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('category-home-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-home-grid')), findsNothing);
  });

  testWidgets('explicit Grid initial layout opens Grid', (
    WidgetTester tester,
  ) async {
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.grid,
    );

    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('category-home-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-home-list')), findsNothing);
  });

  testWidgets('explicit List initial layout opens List', (
    WidgetTester tester,
  ) async {
    homeLayoutController = HomeLayoutController(
      homeLayoutPreferenceStore,
      initialLayoutMode: HomeLayoutMode.list,
    );

    await pumpKedis(tester);

    expect(find.byKey(const ValueKey('category-home-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-home-grid')), findsNothing);
  });

  testWidgets('switches the home layout to Grid from Settings', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);
    expect(find.byKey(const ValueKey('category-home-list')), findsOneWidget);
    expect(find.byTooltip('Add category'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(
      tester,
      () => find.text('Home layout').evaluate().isNotEmpty,
      'Settings screen did not appear.',
    );
    await tester.tap(find.text('Home layout'));
    await pumpUntil(
      tester,
      () => find.text('Choose home layout').evaluate().isNotEmpty,
      'Home-layout picker did not appear.',
    );
    await tester.tap(find.text('Grid'));
    await pumpUntil(
      tester,
      () => homeLayoutController.layoutMode == HomeLayoutMode.grid,
      'Home-layout preference did not update.',
    );
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('category-home-grid'))
          .evaluate()
          .isNotEmpty,
      'Home did not render the selected Grid layout.',
    );

    expect(homeLayoutPreferenceStore.savedLayoutMode, HomeLayoutMode.grid);
    expect(find.byKey(const ValueKey('category-home-grid')), findsOneWidget);
  });

  testWidgets('opens the grouped Trash screen through Settings', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Archived', 0xFF6750A4);
    await categories.softDeleteEmptyCategory(category.id);
    await pumpKedis(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted Categories'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Deleted Tasks'), findsOneWidget);
  });

  testWidgets('home quick capture creates a task in Inbox', (
    WidgetTester tester,
  ) async {
    final inbox = await categories.getInbox();
    await pumpKedis(tester);

    await openHomeTaskCapture(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('quick-capture-selected-category')),
          )
          .data,
      inbox.name,
    );
    final selectedColor = tester.widget<Container>(
      find.byKey(const ValueKey('quick-capture-selected-category-color')),
    );
    expect(
      (selectedColor.decoration! as BoxDecoration).color,
      Color(inbox.colorValue),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).controller, isNull);
    await tester.enterText(find.byType(TextField), '  Quick capture  ');
    await tester.tap(find.text('Add'));
    await pumpUntil(
      tester,
      () => find.text('Quick capture').evaluate().isNotEmpty,
      'Quick-capture task did not appear on the category home.',
    );
    await tester.pumpAndSettle();

    final created = (await tasks.getTasks()).single;
    expect(created.title, 'Quick capture');
    expect(created.categoryId, inbox.id);
    expect(widgetRefreshCount, 1);
    expect(find.text('Quick capture'), findsOneWidget);
    expect(find.text('Add task'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home quick capture keeps a stable responsive width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpKedis(tester);
    await openHomeTaskCapture(tester);

    const layoutTolerance = 1.0;
    final dialogContent = find.byKey(const ValueKey('quick-capture-content'));
    final titleField = find.byKey(const ValueKey('quick-capture-title'));
    final categorySelector = find.byKey(
      const ValueKey('quick-capture-category'),
    );
    final cancelAction = find.text('Cancel');
    final addAction = find.text('Add');

    final initialContentWidth = tester.getSize(dialogContent).width;
    final initialFieldWidth = tester.getSize(titleField).width;
    final initialFieldHeight = tester.getSize(titleField).height;
    final field = tester.widget<TextField>(titleField);

    expect(field.minLines, 1);
    expect(field.maxLines, isNull);
    expect(field.autofocus, isTrue);
    expect(field.textCapitalization, TextCapitalization.sentences);
    expect(field.controller, isNull);
    expect(initialContentWidth, lessThan(360));
    expect(categorySelector, findsOneWidget);
    expect(cancelAction, findsOneWidget);
    expect(addAction, findsOneWidget);

    await tester.enterText(titleField, 'Short title');
    await tester.pump();

    expect(
      tester.getSize(dialogContent).width,
      closeTo(initialContentWidth, layoutTolerance),
    );
    expect(
      tester.getSize(titleField).width,
      closeTo(initialFieldWidth, layoutTolerance),
    );

    const longTitle =
        'This is a deliberately long task title that should wrap naturally '
        'inside the available Add Task dialog width without making the dialog '
        'itself any wider, even as more words continue onto additional lines.';
    await tester.enterText(titleField, longTitle);
    await tester.pump();

    expect(
      tester.getSize(dialogContent).width,
      closeTo(initialContentWidth, layoutTolerance),
    );
    expect(
      tester.getSize(titleField).width,
      closeTo(initialFieldWidth, layoutTolerance),
    );
    expect(tester.getSize(titleField).height, greaterThan(initialFieldHeight));

    final editableText = tester.widget<EditableText>(
      find.descendant(of: titleField, matching: find.byType(EditableText)),
    );
    expect(editableText.controller.text, longTitle);
    expect(editableText.maxLines, isNull);
    expect(categorySelector, findsOneWidget);
    expect(cancelAction, findsOneWidget);
    expect(addAction, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(cancelAction);
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home quick capture remains usable with the keyboard open', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpKedis(tester);
    await openHomeTaskCapture(tester);

    const keyboardHeight = 340.0;
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final titleField = find.byKey(const ValueKey('quick-capture-title'));
    final categorySelector = find.byKey(
      const ValueKey('quick-capture-category'),
    );
    final cancelAction = find.text('Cancel');
    final addAction = find.text('Add');

    await tester.enterText(titleField, 'First line\nSecond line\nThird line');
    await tester.pumpAndSettle();

    expect(titleField.hitTestable(), findsOneWidget);
    expect(categorySelector.hitTestable(), findsOneWidget);
    expect(cancelAction.hitTestable(), findsOneWidget);
    expect(addAction.hitTestable(), findsOneWidget);
    expect(
      tester.getBottomRight(categorySelector).dy,
      lessThan(800 - keyboardHeight),
    );
    expect(tester.getBottomRight(addAction).dy, lessThan(800 - keyboardHeight));
    expect(tester.takeException(), isNull);

    await tester.tap(cancelAction.hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsNothing);
    expect(await tasks.getTasks(), isEmpty);
    expect(widgetRefreshCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long task title scrolls with keyboard open and keeps controls', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final school = await categories.createCategory('School', 0xFF6750A4);
    await pumpKedis(tester);
    await openHomeTaskCapture(tester);

    const keyboardHeight = 340.0;
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final titleField = find.byKey(const ValueKey('quick-capture-title'));
    final categorySelector = find.byKey(
      const ValueKey('quick-capture-category'),
    );
    final cancelAction = find.text('Cancel');
    final addAction = find.text('Add');
    final longTitle = List.generate(
      32,
      (index) => 'Long task title line ${index + 1}',
    ).join('\n');

    await tester.enterText(titleField, longTitle);
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(
      find.descendant(of: titleField, matching: find.byType(EditableText)),
    );
    expect(editableText.controller.text, longTitle);
    expect(tester.widget<TextField>(titleField).maxLines, isNull);

    final inputScroll = find.descendant(
      of: titleField,
      matching: find.byType(Scrollable),
    );
    expect(inputScroll, findsOneWidget);
    expect(
      tester.state<ScrollableState>(inputScroll).position.maxScrollExtent,
      greaterThan(0),
    );

    expect(titleField.hitTestable(), findsOneWidget);
    expect(categorySelector.hitTestable(), findsOneWidget);
    expect(cancelAction.hitTestable(), findsOneWidget);
    expect(addAction.hitTestable(), findsOneWidget);
    expect(
      tester.getBottomRight(categorySelector).dy,
      lessThan(800 - keyboardHeight),
    );
    expect(tester.getBottomRight(addAction).dy, lessThan(800 - keyboardHeight));
    expect(tester.takeException(), isNull);

    await tester.tap(categorySelector.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(ValueKey('quick-capture-category-option-${school.id}'))
          .hitTestable(),
    );
    await pumpUntil(tester, () {
      final selectedCategory = find.byKey(
        const ValueKey('quick-capture-selected-category'),
      );
      return selectedCategory.evaluate().isNotEmpty &&
          tester.widget<Text>(selectedCategory).data == school.name &&
          find
              .byKey(ValueKey('quick-capture-category-option-${school.id}'))
              .evaluate()
              .isEmpty;
    }, 'The selected category did not update with the keyboard open.');

    expect(titleField.hitTestable(), findsOneWidget);
    expect(categorySelector.hitTestable(), findsOneWidget);
    expect(addAction.hitTestable(), findsOneWidget);
    expect(cancelAction.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(addAction.hitTestable());
    await pumpUntil(
      tester,
      () => find.text('Add task').evaluate().isEmpty,
      'Quick-capture dialog did not close after creating the task.',
    );

    final created = (await tasks.getTasks(categoryId: school.id)).single;
    expect(created.title, longTitle);
    expect(created.categoryId, school.id);
    expect(widgetRefreshCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home quick capture creates in a selected category', (
    WidgetTester tester,
  ) async {
    final inbox = await categories.getInbox();
    final school = await categories.createCategory('School', 0xFF6750A4);
    await pumpKedis(tester);

    await openHomeTaskCapture(tester);
    await tester.tap(find.byKey(const ValueKey('quick-capture-category')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('quick-capture-category-option-${inbox.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('quick-capture-category-option-${school.id}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              ValueKey('quick-capture-category-option-label-${school.id}'),
            ),
          )
          .data,
      school.name,
    );
    final optionColor = tester.widget<Container>(
      find.byKey(ValueKey('quick-capture-category-option-color-${school.id}')),
    );
    expect(
      (optionColor.decoration! as BoxDecoration).color,
      Color(school.colorValue),
    );

    await tester.tap(
      find.byKey(ValueKey('quick-capture-category-option-${school.id}')),
    );
    await pumpUntil(tester, () {
      final selectedCategory = find.byKey(
        const ValueKey('quick-capture-selected-category'),
      );
      return selectedCategory.evaluate().isNotEmpty &&
          tester.widget<Text>(selectedCategory).data == school.name &&
          find
              .byKey(ValueKey('quick-capture-category-option-${school.id}'))
              .evaluate()
              .isEmpty &&
          find.text('Add task').evaluate().isNotEmpty;
    }, 'Selected category did not update after the menu closed.');

    expect(find.text('Add task'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('quick-capture-selected-category')),
          )
          .data,
      school.name,
    );
    final selectedColor = tester.widget<Container>(
      find.byKey(const ValueKey('quick-capture-selected-category-color')),
    );
    expect(
      (selectedColor.decoration! as BoxDecoration).color,
      Color(school.colorValue),
    );

    await tester.enterText(find.byType(TextField), '  Database proposal  ');
    await tester.tap(find.text('Add'));
    await pumpUntil(
      tester,
      () => find.text('Database proposal').evaluate().isNotEmpty,
      'Quick-capture task did not appear in the selected category.',
    );
    await tester.pumpAndSettle();

    final created = (await tasks.getTasks(categoryId: school.id)).single;
    expect(created.title, 'Database proposal');
    expect(created.categoryId, school.id);
    expect(widgetRefreshCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home quick capture rejects empty titles and cancels safely', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);

    await openHomeTaskCapture(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Add task'), findsOneWidget);
    expect(await tasks.getTasks(), isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsNothing);
    expect(await tasks.getTasks(), isEmpty);
    expect(widgetRefreshCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a category opens its full task list', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    for (final title in ['One', 'Two', 'Three', 'Four']) {
      await tasks.createTask(title, categoryId: school.id);
    }

    await pumpKedis(tester);
    expect(find.text('Four'), findsNothing);
    await openCategory(tester, 'School');

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Four'), findsOneWidget);
  });

  testWidgets('category inline capture assigns the current category', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    await pumpKedis(tester);
    await openCategory(tester, 'School');

    await tester.tap(find.byTooltip('Add task'));
    await pumpUntil(
      tester,
      () =>
          find.byType(EditableTaskItem).evaluate().isNotEmpty &&
          find.byTooltip('Add task').evaluate().isEmpty,
      'Inline task draft did not replace the add-task action.',
    );
    expect(find.byType(EditableTaskItem), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Database proposal  ');
    await pumpUntil(tester, () {
      final saveAction = find.byTooltip('Save task').hitTestable();
      return saveAction.evaluate().isNotEmpty;
    }, 'Inline task save action did not become tappable.');
    await tester.tap(find.byTooltip('Save task').hitTestable());
    await pumpUntil(
      tester,
      () => find.text('Database proposal').evaluate().isNotEmpty,
      'Category task did not finish saving.',
    );

    final created = (await tasks.getTasks(categoryId: school.id)).single;
    expect(created.title, 'Database proposal');
    expect(created.categoryId, school.id);
    expect(find.text('Database proposal'), findsOneWidget);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('empty inline draft is discarded without persistence', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    await tester.tap(find.byTooltip('Add task'));
    await pumpUntil(
      tester,
      () => find.byType(EditableTaskItem).evaluate().isNotEmpty,
      'Inline task draft did not appear.',
    );
    await tester.tap(find.byTooltip('Discard draft'));
    await pumpUntil(
      tester,
      () => find.byType(EditableTaskItem).evaluate().isEmpty,
      'Inline task draft did not close.',
    );

    expect(find.byType(EditableTaskItem), findsNothing);
    expect(await tasks.getTasks(), isEmpty);
    expect(widgetRefreshCount, 0);
  });

  testWidgets('edits a task title without changing task state', (
    WidgetTester tester,
  ) async {
    final inbox = await categories.getInbox();
    final original = await tasks.createTask('Original title');
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    await tester.tap(find.text('Original title'));
    await pumpUntil(
      tester,
      () => find.byType(EditingTaskItem).evaluate().isNotEmpty,
      'Task editor did not appear.',
    );
    expect(find.byType(EditingTaskItem), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Updated title  ');
    await tester.tap(find.byTooltip('Save changes'));
    await pumpUntil(
      tester,
      () =>
          find.text('Updated title').evaluate().isNotEmpty &&
          find.byType(EditingTaskItem).evaluate().isEmpty,
      'Task title edit did not finish saving.',
    );

    final updated = (await tasks.getTasks(categoryId: inbox.id)).single;
    expect(updated.id, original.id);
    expect(updated.title, 'Updated title');
    expect(updated.isCompleted, original.isCompleted);
    expect(updated.createdAt, original.createdAt);
    expect(updated.completedAt, original.completedAt);
    expect(updated.categoryId, original.categoryId);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('rejects an empty task-title edit', (WidgetTester tester) async {
    await tasks.createTask('Keep title');
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    await tester.tap(find.text('Keep title'));
    await pumpUntil(
      tester,
      () => find.byType(EditingTaskItem).evaluate().isNotEmpty,
      'Task editor did not appear.',
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Save changes'));
    await tester.pump();

    expect(find.text('Task title cannot be empty.'), findsOneWidget);
    expect(find.byType(EditingTaskItem), findsOneWidget);
    expect((await tasks.getTasks()).single.title, 'Keep title');
    expect(widgetRefreshCount, 0);
  });

  testWidgets('completes a task and undo restores its active state', (
    WidgetTester tester,
  ) async {
    await tasks.createTask('Accidental completion');
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    await tester.tap(find.byType(Checkbox));
    await pumpUntil(
      tester,
      () =>
          find.text('Completed').evaluate().isNotEmpty &&
          find.text('UNDO').evaluate().isNotEmpty,
      'Completion did not update the task UI.',
    );
    expect((await tasks.getTasks()).single.isCompleted, isTrue);
    await waitForUndo(tester, 'Completion Undo action was not tappable.');

    await tester.tap(find.text('UNDO').hitTestable());
    await pumpUntil(
      tester,
      () => find.text('Completed').evaluate().isEmpty,
      'Completion Undo did not restore the active task UI.',
    );
    final restored = (await tasks.getTasks()).single;
    expect(restored.isCompleted, isFalse);
    expect(restored.completedAt, isNull);
    expect(widgetRefreshCount, 2);
  });

  testWidgets('deletes and restores a task with its category identity', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    final original = await tasks.createTask(
      'Restore me',
      categoryId: school.id,
    );
    await pumpKedis(tester);
    await openCategory(tester, 'School');

    await tester.tap(find.byTooltip('Delete Restore me'));
    await pumpUntil(
      tester,
      () =>
          find.text('Restore me').evaluate().isEmpty &&
          find.text('UNDO').evaluate().isNotEmpty,
      'Deleted task did not leave the category list.',
    );
    expect(await tasks.getTasks(categoryId: school.id), isEmpty);
    await waitForUndo(tester, 'Delete Undo action was not tappable.');

    await tester.tap(find.text('UNDO').hitTestable());
    await pumpUntil(
      tester,
      () => find.text('Restore me').evaluate().isNotEmpty,
      'Delete Undo did not restore the task.',
    );
    final restored = (await tasks.getTasks(categoryId: school.id)).single;
    expect(restored.id, original.id);
    expect(restored.categoryId, school.id);
    expect(restored.createdAt, original.createdAt);
    expect(widgetRefreshCount, 2);
  });

  testWidgets('moves a task to another category from the task row', (
    WidgetTester tester,
  ) async {
    final school = await categories.createCategory('School', 0xFF6750A4);
    final programming = await categories.createCategory(
      'Programming',
      0xFF006C4C,
    );
    final task = await tasks.createTask('Move me', categoryId: school.id);
    final completedAt = DateTime.utc(2026, 9, 16, 14);
    await tasks.setTaskCompletion(
      task.id,
      isCompleted: true,
      completedAt: completedAt,
    );
    await pumpKedis(tester);
    await openCategory(tester, 'School');

    await tester.tap(find.byTooltip('Move Move me'));
    await pumpUntil(
      tester,
      () => find.text('Programming').evaluate().isNotEmpty,
      'Move-category dialog did not appear.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programming'));
    await pumpUntil(
      tester,
      () => find.text('Move me').evaluate().isEmpty,
      'Moved task did not leave its original category.',
    );

    expect(await tasks.getTasks(categoryId: school.id), isEmpty);
    final moved = (await tasks.getTasks(categoryId: programming.id)).single;
    expect(moved.id, task.id);
    expect(moved.isCompleted, isTrue);
    expect(moved.completedAt, completedAt);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('creates, renames, and safely deletes a custom category', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);

    await openHomeCategoryCreation(tester);
    await tester.enterText(find.byType(TextField), 'School');
    await tester.tap(find.text('Create'));
    await pumpUntil(
      tester,
      () => find.byTooltip('Category actions').evaluate().isNotEmpty,
      'Created category did not appear on the category home.',
    );
    expect(find.text('School'), findsOneWidget);

    final school = (await categories.getCategories()).singleWhere(
      (category) => category.name == 'School',
    );
    await tasks.createTask('Keep task', categoryId: school.id);

    await tester.tap(find.byTooltip('Category actions'));
    await pumpUntil(
      tester,
      () => find.text('Edit category').evaluate().isNotEmpty,
      'Category action menu did not appear.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit category'));
    await pumpUntil(
      tester,
      () => find.byType(TextField).evaluate().isNotEmpty,
      'Edit-category dialog did not appear.',
    );
    await tester.enterText(find.byType(TextField), 'Programming');
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      () =>
          find.text('Programming').evaluate().isNotEmpty &&
          find.byTooltip('Category actions').evaluate().isNotEmpty,
      'Edited category did not appear on the category home.',
    );
    expect(find.text('Programming'), findsOneWidget);

    await tester.tap(find.byTooltip('Category actions'));
    await pumpUntil(
      tester,
      () => find.text('Delete category').evaluate().isNotEmpty,
      'Category action menu did not reopen.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await pumpUntil(
      tester,
      () => find.text('Move tasks elsewhere').evaluate().isNotEmpty,
      'Delete-category confirmation did not appear.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move tasks elsewhere'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('category-delete-destination')),
          )
          .initialValue,
      (await categories.getInbox()).id,
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-category-destination')),
    );
    await pumpUntil(
      tester,
      () => find.text('Programming').evaluate().isEmpty,
      'Deleted category remained on the category home.',
    );

    final inbox = await categories.getInbox();
    expect(
      (await tasks.getTasks(categoryId: inbox.id)).single.title,
      'Keep task',
    );
  });

  testWidgets('empty category deletion can be cancelled or moved to Trash', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Empty', 0xFF6750A4);
    await pumpKedis(tester);

    await tester.tap(find.byTooltip('Category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await tester.pumpAndSettle();
    expect(
      find.text('The category will move to Trash and can be restored later.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await categories.getCategories()).any((item) => item.id == category.id),
      isTrue,
    );

    await tester.tap(find.byTooltip('Category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-empty-category-trash')),
    );
    await tester.pumpAndSettle();

    expect((await categories.getDeletedCategories()).single.id, category.id);
    expect(widgetRefreshCount, 1);
  });

  testWidgets('nonempty category can move category and tasks to Trash', (
    WidgetTester tester,
  ) async {
    final category = await categories.createCategory('Project', 0xFF6750A4);
    final task = await tasks.createTask('Grouped', categoryId: category.id);
    await pumpKedis(tester);

    await tester.tap(find.byTooltip('Category actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-category-trash-tasks')));
    await tester.pumpAndSettle();

    expect((await categories.getDeletedCategories()).single.id, category.id);
    expect(
      (await tasks.getDeletedTasksForCategoryGroup(category.id)).single.id,
      task.id,
    );
    expect(widgetRefreshCount, 1);
  });

  testWidgets('keeps active tasks before newest-first completed tasks', (
    WidgetTester tester,
  ) async {
    final oldest = await tasks.createTask('Oldest completed');
    final newer = await tasks.createTask('Newer completed');
    await tasks.createTask('Active');
    await tasks.setTaskCompletion(
      oldest.id,
      isCompleted: true,
      completedAt: DateTime.utc(2026, 9, 16, 10),
    );
    await tasks.setTaskCompletion(
      newer.id,
      isCompleted: true,
      completedAt: DateTime.utc(2026, 9, 16, 11),
    );
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    final activeY = tester.getTopLeft(find.text('Active')).dy;
    final completedLabelY = tester.getTopLeft(find.text('Completed')).dy;
    final newerY = tester.getTopLeft(find.text('Newer completed')).dy;
    final oldestY = tester.getTopLeft(find.text('Oldest completed')).dy;
    expect(activeY, lessThan(completedLabelY));
    expect(completedLabelY, lessThan(newerY));
    expect(newerY, lessThan(oldestY));
  });

  testWidgets('reloads category tasks when the app resumes', (
    WidgetTester tester,
  ) async {
    final task = await tasks.createTask('Changed from widget');
    await pumpKedis(tester);
    await openCategory(tester, 'Inbox');

    await tasks.toggleTask(task.id);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpUntil(
      tester,
      () => tester.widget<Checkbox>(find.byType(Checkbox)).value == true,
      'Resumed task screen did not reload task state.',
    );

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('changes and persists theme from settings', (
    WidgetTester tester,
  ) async {
    await pumpKedis(tester);

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(
      tester,
      () => find.text('Theme').evaluate().isNotEmpty,
      'Settings screen did not appear.',
    );
    await tester.tap(find.text('Theme'));
    await pumpUntil(
      tester,
      () => find.text('Dark').evaluate().isNotEmpty,
      'Theme picker did not appear.',
    );
    await tester.tap(find.text('Dark'));
    await pumpUntil(
      tester,
      () =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
          ThemeMode.dark,
      'Theme mode did not update to dark.',
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(themePreferenceStore.savedThemeMode, ThemeMode.dark);
  });
}

class _FakeThemePreferenceStore extends ThemePreferenceStore {
  ThemeMode? savedThemeMode;

  @override
  Future<void> save(ThemeMode themeMode) async {
    savedThemeMode = themeMode;
  }
}

class _FakeHomeLayoutPreferenceStore extends HomeLayoutPreferenceStore {
  HomeLayoutMode? savedLayoutMode;

  @override
  Future<void> save(HomeLayoutMode layoutMode) async {
    savedLayoutMode = layoutMode;
  }
}
