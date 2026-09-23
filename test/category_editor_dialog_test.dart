import 'package:kedis/models/task_category.dart';
import 'package:kedis/widgets/category_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates a category without editor teardown exceptions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _CategoryEditorHarness()));

    await tester.tap(find.byKey(const ValueKey('open-create')));
    await tester.pumpAndSettle();

    expect(find.text('Create category'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      '',
    );

    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Enter a category name.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '  School  ');
    await tester.tap(find.byTooltip('Choose color').first);
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Create category'), findsNothing);
    expect(find.text('Result name: School'), findsOneWidget);
    expect(
      find.text('Result color: ${categoryColorPalette[1]}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits a prefilled category without teardown exceptions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _CategoryEditorHarness()));

    await tester.tap(find.byKey(const ValueKey('open-edit')));
    await tester.pumpAndSettle();

    expect(find.text('Edit category'), findsOneWidget);
    final nameField = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(nameField.initialValue, 'School');

    await tester.enterText(find.byType(TextFormField), '  Programming  ');
    await tester.tap(find.byTooltip('Choose color').first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit category'), findsNothing);
    expect(find.text('Result name: Programming'), findsOneWidget);
    expect(
      find.text('Result color: ${categoryColorPalette.first}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _CategoryEditorHarness extends StatefulWidget {
  const _CategoryEditorHarness();

  @override
  State<_CategoryEditorHarness> createState() => _CategoryEditorHarnessState();
}

class _CategoryEditorHarnessState extends State<_CategoryEditorHarness> {
  static final _existingCategory = TaskCategory(
    id: 2,
    name: 'School',
    colorValue: categoryColorPalette[1],
    isSystem: false,
    createdAt: DateTime.utc(2026, 9, 17),
    deletedAt: null,
  );

  CategoryEditorResult? _result;

  Future<void> _openCreate() async {
    final result = await showCategoryEditorDialog(context);
    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  Future<void> _openEdit() async {
    final result = await showCategoryEditorDialog(
      context,
      category: _existingCategory,
    );
    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const ValueKey('open-create'),
            onPressed: _openCreate,
            child: const Text('Open create'),
          ),
          TextButton(
            key: const ValueKey('open-edit'),
            onPressed: _openEdit,
            child: const Text('Open edit'),
          ),
          if (_result != null) ...[
            Text('Result name: ${_result!.name}'),
            Text('Result color: ${_result!.colorValue}'),
          ],
        ],
      ),
    );
  }
}
