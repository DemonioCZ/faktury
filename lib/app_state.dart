import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/gemini.dart';
import 'services/google.dart';
import 'services/settings.dart';

enum WarrantyFilter { all, active, endingSoon, expired, extended }

class AppState extends ChangeNotifier {
  AppState(this.settings);

  final Settings settings;
  late final GoogleService google = GoogleService(settings.prefs);

  bool signedIn = false;
  bool loading = false;
  String? error;
  DateTime? lastSync;

  List<Receipt> receipts = [];
  List<String> categories = [...defaultCategories];

  // ---- filtry ----
  String query = '';
  int? year; // null = všechny roky
  String? category; // null = všechny kategorie
  WarrantyFilter warranty = WarrantyFilter.all;

  bool get configured => settings.folderId.isNotEmpty && settings.sheetId.isNotEmpty;
  bool get hasGemini => settings.geminiKey.isNotEmpty;
  String? get userEmail => google.email;

  DateTime get today => DateTime.now();

  Future<void> init() async {
    _loadCache();
    signedIn = await google.trySilentSignIn();
    notifyListeners();
    if (signedIn && configured) await refresh();
  }

  Future<void> signIn() async {
    error = null;
    try {
      signedIn = await google.signIn();
      notifyListeners();
      if (signedIn && configured) await refresh();
    } catch (e) {
      error = 'Přihlášení se nepovedlo: $e';
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await google.signOut();
    signedIn = false;
    receipts = [];
    settings.cache = null;
    notifyListeners();
  }

  Future<void> chooseFolder(String id, String name) async {
    await _run(() async {
      settings.folderId = id;
      settings.folderName = name;
      settings.sheetId = await google.findOrCreateSheet(id);
      await _reload();
    });
  }

  Future<void> refresh() => _run(_reload);

  Future<void> _reload() async {
    final id = settings.sheetId;
    final res = await Future.wait([
      google.readReceipts(id),
      google.readCategories(id),
    ]);
    receipts = res[0] as List<Receipt>;
    final cats = res[1] as List<String>;
    categories = cats.isEmpty ? [...defaultCategories] : cats;
    _sort();
    lastSync = DateTime.now();
    _saveCache();
  }

  Future<void> _run(Future<void> Function() job) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await job();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _sort() => receipts.sort((a, b) =>
      (b.date ?? DateTime(1900)).compareTo(a.date ?? DateTime(1900)));

  // ---- cache pro offline zobrazení ----
  void _saveCache() {
    settings.cache = jsonEncode({
      'receipts': receipts.map((r) => r.toJson()).toList(),
      'categories': categories,
      'sync': lastSync?.toIso8601String(),
    });
  }

  void _loadCache() {
    final c = settings.cache;
    if (c == null) return;
    try {
      final j = jsonDecode(c) as Map<String, dynamic>;
      receipts = [
        for (final r in j['receipts'] as List) Receipt.fromJson(r as Map<String, dynamic>)
      ];
      categories = (j['categories'] as List).cast<String>();
      lastSync = DateTime.tryParse(j['sync'] as String? ?? '');
    } catch (_) {}
  }

  // ---- filtrování ----
  List<int> get years {
    final s = <int>{for (final r in receipts) if (r.date != null) r.date!.year};
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  List<Receipt> get filtered {
    final t = today;
    return receipts.where((r) {
      if (year != null && r.date?.year != year) return false;
      if (category != null && r.category != category) return false;
      switch (warranty) {
        case WarrantyFilter.all:
          break;
        case WarrantyFilter.active:
          final s = r.stateAt(t);
          if (s != WarrantyState.active && s != WarrantyState.endingSoon) return false;
        case WarrantyFilter.endingSoon:
          if (r.stateAt(t) != WarrantyState.endingSoon) return false;
        case WarrantyFilter.expired:
          if (r.stateAt(t) != WarrantyState.expired) return false;
        case WarrantyFilter.extended:
          if (!r.hasExtendedWarranty) return false;
      }
      return r.matches(query);
    }).toList();
  }

  int countWhere(bool Function(Receipt) f) => receipts.where(f).length;

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setYear(int? y) {
    year = y;
    notifyListeners();
  }

  void setCategory(String? c) {
    category = c;
    notifyListeners();
  }

  void setWarranty(WarrantyFilter w) {
    warranty = w;
    notifyListeners();
  }

  // ---- úpravy ----
  Future<bool> save(Receipt r) async {
    var ok = false;
    await _run(() async {
      if (r.category.isNotEmpty && !categories.contains(r.category)) {
        await google.addCategory(settings.sheetId, r.category);
        categories = [...categories, r.category];
      }
      if (r.row == null) {
        r.row = await google.appendReceipt(settings.sheetId, r);
        receipts.add(r);
      } else {
        await google.updateReceipt(settings.sheetId, r);
        final i = receipts.indexWhere((x) => x.row == r.row);
        if (i >= 0) receipts[i] = r;
      }
      _sort();
      _saveCache();
      ok = true;
    });
    return ok;
  }

  Future<void> delete(Receipt r) async {
    if (r.row == null) return;
    await _run(() async {
      await google.deleteReceipt(settings.sheetId, r.row!);
      await _reload();
    });
  }

  Future<void> addCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty || categories.contains(n)) return;
    await _run(() async {
      await google.addCategory(settings.sheetId, n);
      categories = [...categories, n];
      _saveCache();
    });
  }

  // ---- nové doklady ----

  /// Skeny ve složce, které ještě nejsou v tabulce.
  Future<List<DriveFile>> findNewScans() async {
    final known = {for (final r in receipts) r.fileId};
    final all = await google.listScans(settings.folderId);
    return all.where((f) => !known.contains(f.id)).toList();
  }

  GeminiService _gemini() {
    if (!hasGemini) {
      throw Exception('Chybí Gemini API klíč. Doplňte ho v Nastavení.');
    }
    return GeminiService(settings.geminiKey, model: settings.geminiModel);
  }

  Future<Receipt> extractDriveFile(DriveFile f) async {
    final bytes = await google.download(f.id);
    final r = await _gemini().extract(
      bytes: bytes,
      mimeType: f.mimeType,
      categories: categories,
      fileName: f.name,
    );
    r.fileId = f.id;
    r.folder = f.folderName;
    r.scanUrl = 'https://drive.google.com/file/d/${f.id}/view';
    return r;
  }

  /// Nahraje vyfocený/vybraný doklad na Disk a vytěží z něj údaje.
  Future<Receipt> uploadAndExtract(Uint8List bytes, String fileName) async {
    final mime = mimeFromName(fileName);
    final r = await _gemini().extract(
      bytes: bytes,
      mimeType: mime,
      categories: categories,
      fileName: '',
    );
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final y = (r.date ?? today).year;
    final safe = r.product.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    final name = '$y - ${safe.isEmpty ? 'doklad' : safe}.$ext';
    final id = await google.upload(
        folderId: settings.folderId, name: name, bytes: bytes, mimeType: mime);
    r.fileId = id;
    r.folder = settings.folderName;
    r.scanUrl = 'https://drive.google.com/file/d/$id/view';
    return r;
  }
}
