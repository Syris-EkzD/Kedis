import 'package:kedis/settings/home_layout_controller.dart';
import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('missing layout preference defaults to List', () async {
    SharedPreferences.setMockInitialValues({});

    final store = HomeLayoutPreferenceStore();
    final initial = await store.load();
    final controller = HomeLayoutController(store);

    expect(initial, HomeLayoutMode.list);
    expect(controller.layoutMode, HomeLayoutMode.list);
  });

  test('loads an explicit Grid preference', () async {
    SharedPreferences.setMockInitialValues({'home_layout': 'grid'});

    expect(await HomeLayoutPreferenceStore().load(), HomeLayoutMode.grid);
  });

  test('loads an explicit List preference', () async {
    SharedPreferences.setMockInitialValues({'home_layout': 'list'});

    expect(await HomeLayoutPreferenceStore().load(), HomeLayoutMode.list);
  });

  test('unknown layout preference falls back to List', () async {
    SharedPreferences.setMockInitialValues({'home_layout': 'unexpected'});

    expect(await HomeLayoutPreferenceStore().load(), HomeLayoutMode.list);
  });

  test('persists a changed layout preference', () async {
    SharedPreferences.setMockInitialValues({});

    final store = HomeLayoutPreferenceStore();
    final controller = HomeLayoutController(store);
    await controller.setLayoutMode(HomeLayoutMode.grid);

    expect(controller.layoutMode, HomeLayoutMode.grid);
    expect(await HomeLayoutPreferenceStore().load(), HomeLayoutMode.grid);
  });
}
