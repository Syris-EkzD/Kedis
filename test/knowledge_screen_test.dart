import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kedis/companion/knowledge_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kedis/knowledge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final archive = <String, Object>{
    'uuid': 'test-archive',
    'title': 'Test archive',
    'date': '2026-06',
    'bytes': 1048576,
  };

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('missing archive keeps import available', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No archive installed'), findsOneWidget);
    expect(find.text('Import ZIM'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('search and read preserve article identity', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return archive;
        case 'search':
          expect(call.arguments, {'query': 'Venus'});
          return [
            {'title': 'Venus', 'path': 'Venus', 'uuid': 'test-archive'},
          ];
        case 'read':
          expect(call.arguments, {'path': 'Venus', 'uuid': 'test-archive'});
          return {
            'title': 'Venus',
            'resolvedPath': 'Venus',
            'archive': archive,
            'text': 'Plain text excerpt',
          };
        default:
          fail('Unexpected method: ${call.method}');
      }
    });
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Venus');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Venus'));
    await tester.pumpAndSettle();
    expect(find.text('Plain text excerpt'), findsOneWidget);
    expect(find.text('Article path: Venus'), findsOneWidget);
  });

  testWidgets('cancelled import preserves archive', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return archive;
      expect(call.method, 'importArchive');
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import ZIM'));
    await tester.pumpAndSettle();
    expect(find.text('Test archive'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('failed replacement preserves archive', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return archive;
      expect(call.method, 'importArchive');
      throw PlatformException(code: 'invalid', message: 'Invalid replacement');
    });
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import ZIM'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid replacement'), findsOneWidget);
    expect(find.text('Test archive'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('removal requires confirmation', (tester) async {
    var removals = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return archive;
      expect(call.method, 'remove');
      removals++;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removals, 0);
    expect(find.text('Test archive'), findsOneWidget);

    await tester.tap(find.text('Remove archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removals, 1);
    expect(find.textContaining('No archive installed'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('invalid archive reports error and permits retry', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'knowledge_error',
        message: 'Invalid archive',
      );
    });
    await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Invalid archive'), findsOneWidget);
    expect(find.textContaining('No readable archive'), findsOneWidget);
    expect(find.text('Import ZIM'), findsOneWidget);
    expect(find.text('Remove archive'), findsOneWidget);
  });
}
