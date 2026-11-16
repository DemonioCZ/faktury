import 'package:shared_preferences/shared_preferences.dart';

import 'gemini.dart';

/// Nastavení uložené jen v zařízení.
class Settings {
  Settings(this._p);
  final SharedPreferences _p;
  SharedPreferences get prefs => _p;

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  String get folderId => _p.getString('folderId') ?? '';
  set folderId(String v) => _p.setString('folderId', v);

  String get folderName => _p.getString('folderName') ?? '';
  set folderName(String v) => _p.setString('folderName', v);

  String get sheetId => _p.getString('sheetId') ?? '';
  set sheetId(String v) => _p.setString('sheetId', v);

  String get geminiKey => _p.getString('geminiKey') ?? '';
  set geminiKey(String v) => _p.setString('geminiKey', v.trim());

  String get geminiModel {
    final m = _p.getString('geminiModel');
    // Starý výchozí model Google ukončil, uložená hodnota se nahradí novým výchozím.
    if (m == null || m.isEmpty || m == 'gemini-2.5-flash') return GeminiService.defaultModel;
    return m;
  }
  set geminiModel(String v) =>
      _p.setString('geminiModel', v.trim().isEmpty ? GeminiService.defaultModel : v.trim());

  int get defaultWarranty => _p.getInt('defaultWarranty') ?? 24;
  set defaultWarranty(int v) => _p.setInt('defaultWarranty', v);

  String? get cache => _p.getString('cache');
  set cache(String? v) =>
      v == null ? _p.remove('cache') : _p.setString('cache', v);
}
