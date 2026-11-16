import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub repozitář, do kterého se vydávají nové verze (Releases).
const githubRepo = 'DemonioCZ/faktury';

class UpdateInfo {
  UpdateInfo(this.version, this.notes, this.assetUrl, this.assetName, this.pageUrl);
  final String version;
  final String notes;
  final String? assetUrl;
  final String? assetName;
  final String pageUrl;
}

class Updater {
  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Vrátí novější verzi z GitHub Releases, nebo null když je aplikace aktuální.
  Future<UpdateInfo?> check() async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode != 200) {
      throw Exception('Nepodařilo se zjistit novou verzi (${res.statusCode}).');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
    final current = await currentVersion();
    if (!_isNewer(tag, current)) return null;
    final wanted = Platform.isAndroid ? '.apk' : '.dmg';
    String? url, name;
    for (final a in (j['assets'] as List? ?? [])) {
      final n = a['name'] as String? ?? '';
      if (n.toLowerCase().endsWith(wanted)) {
        url = a['browser_download_url'] as String?;
        name = n;
        break;
      }
    }
    return UpdateInfo(tag, j['body'] as String? ?? '', url, name,
        j['html_url'] as String? ?? 'https://github.com/$githubRepo/releases');
  }

  /// Stáhne instalační balíček a otevře ho (Android instalátor / DMG na Macu).
  Future<void> install(UpdateInfo info, void Function(double) onProgress) async {
    final url = info.assetUrl;
    if (url == null) throw Exception('K této verzi chybí instalační soubor.');
    final dir = Platform.isMacOS
        ? (await getDownloadsDirectory() ?? await getTemporaryDirectory())
        : await getTemporaryDirectory();
    final file = File('${dir.path}/${info.assetName}');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      final total = resp.contentLength ?? 0;
      var done = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) onProgress(done / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else {
      final r = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        throw Exception('Instalaci se nepodařilo spustit: ${r.message}');
      }
    }
  }

  /// Smaže instalační balíčky stažené dřívějšími aktualizacemi (Android).
  /// Volá se při startu, kdy už je nová verze nainstalovaná.
  Future<void> cleanup() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = await getTemporaryDirectory();
      await for (final f in dir.list()) {
        if (f is File && f.path.toLowerCase().endsWith('.apk')) await f.delete();
      }
    } catch (_) {}
  }

  bool _isNewer(String a, String b) {
    List<int> p(String v) =>
        v.split(RegExp(r'[.+]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }
}
