import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as gauth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';

const sheetTitle = 'Faktury – data';
const receiptsTab = 'Doklady';
const categoriesTab = 'Kategorie';
const _folderMime = 'application/vnd.google-apps.folder';
const _sheetMime = 'application/vnd.google-apps.spreadsheet';

class DriveFile {
  DriveFile(this.id, this.name, this.mimeType, this.folderName);
  final String id;
  final String name;
  final String mimeType;
  final String folderName;
  bool get isScan =>
      mimeType == 'application/pdf' || mimeType.startsWith('image/');
}

const _scopes = [
  drive.DriveApi.driveScope,
  sheets.SheetsApi.spreadsheetsScope,
];

/// OAuth klient typu „Desktop“ pro macOS (doplní se při sestavení přes --dart-define).
const _desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
const _desktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

/// Přihlášení ke Google účtu + práce s Diskem a Tabulkami.
///
/// Android používá nativní Google Sign-In. Na macOS (nepodepsaná aplikace bez
/// přístupu ke klíčence) se přihlašuje přes prohlížeč a token se uloží lokálně.
class GoogleService {
  GoogleService(this._prefs);
  final SharedPreferences _prefs;

  final GoogleSignIn _signIn = GoogleSignIn(scopes: _scopes);
  gauth.AuthClient? _client;
  String? _email;

  String? get email => _email;
  bool get _desktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<bool> trySilentSignIn() async {
    try {
      if (_desktop) {
        final saved = _prefs.getString('gcreds');
        if (saved == null) return false;
        final creds = gauth.AccessCredentials.fromJson(
            jsonDecode(saved) as Map<String, dynamic>);
        _client = _autoRefresh(creds);
      } else {
        final acc = await _signIn.signInSilently();
        if (acc == null) return false;
        _client = await _signIn.authenticatedClient();
        _email = acc.email;
      }
      if (_client == null) return false;
      await _loadEmail();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> signIn() async {
    if (_desktop) {
      if (_desktopClientId.isEmpty) {
        throw Exception('Chybí OAuth klient pro Mac (GOOGLE_DESKTOP_CLIENT_ID).');
      }
      final base = http.Client();
      final creds = await gauth_io.obtainAccessCredentialsViaUserConsent(
        gauth.ClientId(_desktopClientId, _desktopClientSecret),
        _scopes,
        base,
        (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
      base.close();
      await _prefs.setString('gcreds', jsonEncode(creds.toJson()));
      _client = _autoRefresh(creds);
    } else {
      final acc = await _signIn.signIn();
      if (acc == null) return false;
      _client = await _signIn.authenticatedClient();
      _email = acc.email;
    }
    if (_client == null) return false;
    await _loadEmail();
    return true;
  }

  gauth.AutoRefreshingAuthClient _autoRefresh(gauth.AccessCredentials creds) {
    final c = gauth.autoRefreshingClient(
      gauth.ClientId(_desktopClientId, _desktopClientSecret),
      creds,
      http.Client(),
    );
    c.credentialUpdates.listen(
        (n) => _prefs.setString('gcreds', jsonEncode(n.toJson())));
    return c;
  }

  Future<void> _loadEmail() async {
    if (_email != null) return;
    try {
      final about = await _drive.about.get($fields: 'user(emailAddress)');
      _email = about.user?.emailAddress;
    } catch (_) {}
  }

  Future<void> signOut() async {
    if (_desktop) {
      await _prefs.remove('gcreds');
    } else {
      await _signIn.signOut();
    }
    _client?.close();
    _client = null;
    _email = null;
  }

  gauth.AuthClient get _c {
    final c = _client;
    if (c == null) throw StateError('Nejste přihlášeni ke Google účtu.');
    return c;
  }

  drive.DriveApi get _drive => drive.DriveApi(_c);
  sheets.SheetsApi get _sheets => sheets.SheetsApi(_c);

  // ---------------- Disk ----------------

  /// Složky pro výběr (v kořeni Disku nebo podle hledaného textu).
  Future<List<DriveFile>> listFolders({String? search, String? parent}) async {
    final q = StringBuffer("mimeType='$_folderMime' and trashed=false");
    if (search != null && search.isNotEmpty) {
      q.write(" and name contains '${search.replaceAll("'", "\\'")}'");
    } else {
      q.write(" and '${parent ?? 'root'}' in parents");
    }
    final res = await _drive.files.list(
      q: q.toString(),
      $fields: 'files(id,name,mimeType)',
      orderBy: 'name',
      pageSize: 200,
    );
    return [
      for (final f in res.files ?? <drive.File>[])
        DriveFile(f.id!, f.name ?? '', f.mimeType ?? '', ''),
    ];
  }

  Future<String> folderName(String id) async {
    final f = await _drive.files.get(id, $fields: 'name') as drive.File;
    return f.name ?? '';
  }

  /// Všechny skeny ve složce a jejích podsložkách.
  Future<List<DriveFile>> listScans(String folderId) async {
    final out = <DriveFile>[];
    Future<void> walk(String id, String name, int depth) async {
      String? token;
      do {
        final res = await _drive.files.list(
          q: "'$id' in parents and trashed=false",
          $fields: 'nextPageToken, files(id,name,mimeType)',
          pageSize: 1000,
          pageToken: token,
        );
        for (final f in res.files ?? <drive.File>[]) {
          final mt = f.mimeType ?? '';
          if (mt == _folderMime) {
            if (depth < 3) await walk(f.id!, f.name ?? '', depth + 1);
          } else {
            final df = DriveFile(f.id!, f.name ?? '', mt, name);
            if (df.isScan) out.add(df);
          }
        }
        token = res.nextPageToken;
      } while (token != null);
    }

    await walk(folderId, await folderName(folderId), 0);
    return out;
  }

  Future<Uint8List> download(String fileId) async {
    final media = await _drive.files.get(fileId,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final b = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  Future<String> upload({
    required String folderId,
    required String name,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    // Data po kouscích, aby šlo ukazovat průběh nahrávání.
    Stream<List<int>> chunks() async* {
      const size = 64 * 1024;
      for (var i = 0; i < bytes.length; i += size) {
        final end = i + size < bytes.length ? i + size : bytes.length;
        yield bytes.sublist(i, end);
        onProgress?.call(end / bytes.length);
      }
    }

    final f = await _drive.files.create(
      drive.File(name: name, parents: [folderId]),
      uploadMedia: drive.Media(chunks(), bytes.length, contentType: mimeType),
      $fields: 'id',
    );
    return f.id!;
  }

  Future<void> rename(String fileId, String newName) async {
    await _drive.files.update(drive.File(name: newName), fileId);
  }

  // ---------------- Tabulka ----------------

  /// Najde tabulku "Faktury – data" ve složce, případně ji založí.
  Future<String> findOrCreateSheet(String folderId) async {
    final res = await _drive.files.list(
      q: "'$folderId' in parents and mimeType='$_sheetMime' and name='$sheetTitle' and trashed=false",
      $fields: 'files(id)',
    );
    final found = res.files ?? [];
    if (found.isNotEmpty) return found.first.id!;
    return _createSheet(folderId);
  }

  Future<String> _createSheet(String folderId) async {
    final f = await _drive.files.create(
      drive.File(name: sheetTitle, mimeType: _sheetMime, parents: [folderId]),
      $fields: 'id',
    );
    final id = f.id!;
    final meta = await _sheets.spreadsheets.get(id);
    final firstId = meta.sheets!.first.properties!.sheetId!;
    await _sheets.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: [
        sheets.Request(
          updateSheetProperties: sheets.UpdateSheetPropertiesRequest(
            properties: sheets.SheetProperties(
              sheetId: firstId,
              title: receiptsTab,
              gridProperties: sheets.GridProperties(frozenRowCount: 1),
            ),
            fields: 'title,gridProperties.frozenRowCount',
          ),
        ),
        sheets.Request(
          addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: categoriesTab)),
        ),
      ]),
      id,
    );
    // Locale tabulky určuje oddělovač argumentů ve vzorcích.
    final locale = (await _sheets.spreadsheets.get(id, $fields: 'properties.locale'))
            .properties
            ?.locale ??
        'en_US';
    final sep = _usesSemicolon(locale) ? ';' : ',';
    await _sheets.spreadsheets.values.update(
      sheets.ValueRange(values: [
        [
          'Produkt', 'Prodejce', 'Datum nákupu', 'Cena (Kč)', 'Kategorie',
          'Záruka (měs.)',
          '={"Konec záruky";ARRAYFORMULA(IF(C2:C=""$sep$sep DATE(YEAR(C2:C)${sep}MONTH(C2:C)+F2:F${sep}DAY(C2:C))))}',
          '={"Stav záruky";ARRAYFORMULA(IF(G2:G=""$sep$sep IF(G2:G<TODAY()$sep"Bez záruky"${sep}IF(G2:G-TODAY()<=30$sep"Končí brzy"$sep"V záruce"))))}',
          'Číslo dokladu', 'Poznámka', 'Sken', 'Složka', 'ID souboru', 'Vyplnil',
        ]
      ]),
      id,
      '$receiptsTab!A1:N1',
      valueInputOption: 'USER_ENTERED',
    );
    await _sheets.spreadsheets.values.update(
      sheets.ValueRange(values: [
        ['Kategorie'],
        for (final c in defaultCategories) [c],
      ]),
      id,
      '$categoriesTab!A1',
      valueInputOption: 'USER_ENTERED',
    );
    return id;
  }

  bool _usesSemicolon(String locale) {
    const commaDecimal = ['cs', 'sk', 'de', 'fr', 'pl', 'it', 'es', 'nl', 'pt', 'ru', 'hu'];
    return commaDecimal.contains(locale.split('_').first);
  }

  Future<List<Receipt>> readReceipts(String sheetId) async {
    final res = await _sheets.spreadsheets.values.get(
      sheetId,
      '$receiptsTab!A2:N',
      valueRenderOption: 'UNFORMATTED_VALUE',
      dateTimeRenderOption: 'SERIAL_NUMBER',
    );
    final rows = res.values ?? [];
    final out = <Receipt>[];
    for (var i = 0; i < rows.length; i++) {
      final r = Receipt.fromRow(i + 2, rows[i]);
      if (r.product.isEmpty && r.fileId.isEmpty) continue;
      out.add(r);
    }
    return out;
  }

  /// Kategorie a jejich ikony (list Kategorie: A = název, B = klíč ikony, může chybět).
  Future<List<(String, String)>> readCategories(String sheetId) async {
    try {
      final res = await _sheets.spreadsheets.values
          .get(sheetId, '$categoriesTab!A2:B');
      return [
        for (final r in res.values ?? <List<Object?>>[])
          if (r.isNotEmpty && r.first.toString().trim().isNotEmpty)
            (r.first.toString().trim(), r.length > 1 ? r[1].toString().trim() : ''),
      ];
    } catch (_) {
      return [for (final c in defaultCategories) (c, '')];
    }
  }

  Future<void> addCategory(String sheetId, String name, {String icon = ''}) async {
    await _sheets.spreadsheets.values.append(
      sheets.ValueRange(values: [
        [name, icon]
      ]),
      sheetId,
      '$categoriesTab!A:B',
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  /// Uloží ikonu kategorie do sloupce B na jejím řádku.
  Future<void> setCategoryIcon(String sheetId, String name, String icon) async {
    final res = await _sheets.spreadsheets.values.get(sheetId, '$categoriesTab!A:A');
    final rows = res.values ?? <List<Object?>>[];
    final i = rows.indexWhere((r) => r.isNotEmpty && r.first.toString().trim() == name);
    if (i < 0) {
      await addCategory(sheetId, name, icon: icon);
      return;
    }
    await _sheets.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: [
        sheets.ValueRange(range: '$categoriesTab!B1', values: [
          ['Ikona']
        ]),
        sheets.ValueRange(range: '$categoriesTab!B${i + 1}', values: [
          [icon]
        ]),
      ]),
      sheetId,
    );
  }

  Future<void> updateReceipt(String sheetId, Receipt r) async {
    final row = r.row!;
    await _sheets.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: [
          sheets.ValueRange(range: '$receiptsTab!A$row:F$row', values: [r.toRowAF()]),
          sheets.ValueRange(range: '$receiptsTab!I$row:N$row', values: [r.toRowIN()]),
        ],
      ),
      sheetId,
    );
  }

  /// Připojí doklad na konec tabulky a vrátí číslo řádku.
  Future<int?> appendReceipt(String sheetId, Receipt r) async {
    final res = await _sheets.spreadsheets.values.append(
      sheets.ValueRange(values: [r.toFullRow()]),
      sheetId,
      '$receiptsTab!A:N',
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
    final range = res.updates?.updatedRange ?? '';
    final m = RegExp(r'![A-Z]+(\d+)').firstMatch(range);
    return m == null ? null : int.parse(m[1]!);
  }

  Future<void> deleteReceipt(String sheetId, int row) async {
    final meta = await _sheets.spreadsheets.get(sheetId, $fields: 'sheets.properties');
    final tab = meta.sheets!
        .firstWhere((s) => s.properties?.title == receiptsTab)
        .properties!
        .sheetId!;
    await _sheets.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: [
        sheets.Request(
          deleteDimension: sheets.DeleteDimensionRequest(
            range: sheets.DimensionRange(
                sheetId: tab, dimension: 'ROWS', startIndex: row - 1, endIndex: row),
          ),
        ),
      ]),
      sheetId,
    );
  }
}
