import 'package:kedis/settings/home_layout_preference_store.dart';
import 'package:flutter/foundation.dart';

class HomeLayoutController extends ChangeNotifier {
  HomeLayoutController(
    this._preferenceStore, {
    HomeLayoutMode initialLayoutMode = HomeLayoutMode.list,
  }) : _layoutMode = initialLayoutMode;

  final HomeLayoutPreferenceStore _preferenceStore;
  HomeLayoutMode _layoutMode;

  HomeLayoutMode get layoutMode => _layoutMode;

  Future<void> setLayoutMode(HomeLayoutMode layoutMode) async {
    if (_layoutMode == layoutMode) return;

    _layoutMode = layoutMode;
    notifyListeners();
    await _preferenceStore.save(layoutMode);
  }
}
