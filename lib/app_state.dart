import 'dart:convert';
import 'dart:typed_data';

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
      if (category != null && !r.hasCategory(category!)) return false;
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
      for (final c in r.categoryList) {
        if (!categories.contains(c)) {
          await google.addCategory(settings.sheetId, c);
          categories = [...categories, c];
        }
      }
      if (r.row == null) {
        r.row = await google.appendReceipt(settings.sheetId, r);
        receipts.add(r);
        await _renameScan(r);
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

  /// Sjednotí název skenu na "rok-název" (rok mohl uživatel při kontrole opravit).
  /// Nepovedené přejmenování nesmí zmařit uložení dokladu.
  Future<void> _renameScan(Receipt r) async {
    if (r.fileId.isEmpty || r.fileName.isEmpty) return;
    final target = r.targetFileName(today);
    if (target == r.fileName) return;
    try {
      await google.rename(r.fileId, target);
      r.fileName = target;
    } catch (e) {
      debugPrint('Sken se nepodařilo přejmenovat: $e');
    }
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

  // ---- skeny (krátkodobá cache v paměti) ----
  final Map<String, Future<Uint8List>> _scans = {};

  Future<Uint8List> scanBytes(String fileId) {
    final cached = _scans.remove(fileId);
    if (cached != null) {
      _scans[fileId] = cached; // posunout na konec (nejnověji použitý)
      return cached;
    }
    final f = google.download(fileId);
    _scans[fileId] = f;
    f.catchError((_) {
      _scans.remove(fileId);
      return Uint8List(0);
    });
    while (_scans.length > 15) {
      _scans.remove(_scans.keys.first);
    }
    return f;
  }

  // ---- nové doklady ----

  /// Skeny ve složce, které ještě nejsou v tabulce.
  Future<List<DriveFile>> findNewScans() async {
    final known = {for (final r in receipts) r.fileId};
    final all = await google.listScans(settings.folderId);
    return all.where((f) => !known.contains(f.id)).toList();
  }

  GeminiService gemini() {
    if (!hasGemini) {
      throw Exception('Chybí Gemini API klíč. Doplňte ho v Nastavení.');
    }
    return GeminiService(settings.geminiKey, model: settings.geminiModel);
  }

  void setGeminiModel(String m) {
    settings.geminiModel = m;
    notifyListeners();
  }

  Future<Receipt> extractDriveFile(DriveFile f,
      {void Function(TaskProgress)? onProgress, CancelToken? cancel}) async {
    onProgress?.call(const TaskProgress(1, 2, 'Stahuji sken z Disku'));
    final bytes = await google.download(f.id);
    cancel?.check();
    final model = settings.geminiModel;
    onProgress?.call(TaskProgress(2, 2, 'Čtu údaje pomocí Gemini ($model)'));
    final r = await gemini().extract(
      bytes: bytes,
      mimeType: f.mimeType,
      categories: categories,
      fileName: f.name,
      cancel: cancel,
      onStatus: (s) => onProgress?.call(TaskProgress(2, 2, 'Čtu údaje pomocí Gemini ($model)', detail: s)),
    );
    r.fileId = f.id;
    r.fileName = f.name;
    r.folder = f.folderName;
    r.scanUrl = 'https://drive.google.com/file/d/${f.id}/view';
    return r;
  }

  /// Vytěží údaje z vyfoceného/vybraného dokladu a pak ho nahraje na Disk.
  /// Na Disk se nahrává až po úspěšném přečtení, takže chyba Gemini nezpůsobí duplicitu.
  Future<Receipt> uploadAndExtract(Uint8List bytes, String fileName,
      {void Function(TaskProgress)? onProgress, CancelToken? cancel}) async {
    final mime = mimeFromName(fileName);
    final model = settings.geminiModel;
    onProgress?.call(TaskProgress(1, 2, 'Čtu údaje pomocí Gemini ($model)'));
    final r = await gemini().extract(
      bytes: bytes,
      mimeType: mime,
      categories: categories,
      fileName: '',
      cancel: cancel,
      onStatus: (s) => onProgress?.call(TaskProgress(1, 2, 'Čtu údaje pomocí Gemini ($model)', detail: s)),
    );
    cancel?.check();
    final ext = fileExtension(fileName);
    r.fileName = 'sken.${ext.isEmpty ? 'jpg' : ext}';
    final name = r.targetFileName(today);
    r.fileName = name;
    final kb = (bytes.length / 1024).round();
    onProgress?.call(TaskProgress(2, 2, 'Nahrávám sken na Disk', detail: '$kb kB', value: 0));
    final id = await google.upload(
      folderId: settings.folderId,
      name: name,
      bytes: bytes,
      mimeType: mime,
      onProgress: (p) => onProgress?.call(TaskProgress(2, 2, 'Nahrávám sken na Disk',
          detail: '${(p * kb).round()} z $kb kB', value: p)),
    );
    r.fileId = id;
    r.folder = settings.folderName;
    r.scanUrl = 'https://drive.google.com/file/d/$id/view';
    return r;
  }
}
