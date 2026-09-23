import 'package:shared_preferences/shared_preferences.dart';

enum HomeLayoutMode { grid, list }

class HomeLayoutPreferenceStore {
  static const _preferenceKey = 'home_layout';

  Future<HomeLayoutMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_preferenceKey));
  }

  Future<void> save(HomeLayoutMode layoutMode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, layoutMode.name);
  }

  HomeLayoutMode _decode(String? value) {
    return switch (value) {
      'grid' => HomeLayoutMode.grid,
      'list' => HomeLayoutMode.list,
      _ => HomeLayoutMode.list,
    };
  }
}
