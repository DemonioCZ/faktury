/// Datový model dokladu = jeden řádek listu "Doklady".
///
/// Sloupce A–N: Produkt, Prodejce, Datum nákupu, Cena (Kč), Kategorie,
/// Záruka (měs.), Konec záruky*, Stav záruky*, Číslo dokladu, Poznámka,
/// Sken, Složka, ID souboru, Vyplnil.  (* počítá tabulka, aplikace je nezapisuje)
library;

const int defaultWarrantyMonths = 24;
const int warrantySoonDays = 30;

enum WarrantyState { active, endingSoon, expired, unknown }

/// Název skenu na Disku: "rok-název", např. "2026-vrtačka.pdf".
String scanFileName(int year, String label, String ext) {
  var n = label
      .toLowerCase()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (n.length > 60) n = n.substring(0, 60);
  n = n.replaceAll(RegExp(r'^[.\- ]+|[.\- ]+$'), '');
  if (n.isEmpty) n = 'doklad';
  return ext.isEmpty ? '$year-$n' : '$year-$n.$ext';
}

/// Přípona souboru malými písmeny, bez tečky. Když žádná není, vrátí ''.
String fileExtension(String name) {
  final i = name.lastIndexOf('.');
  return i > 0 && i < name.length - 1 ? name.substring(i + 1).toLowerCase() : '';
}

class Receipt {
  Receipt({
    this.row,
    required this.product,
    this.seller = '',
    this.date,
    this.price,
    this.category = '',
    this.warrantyMonths = defaultWarrantyMonths,
    this.docNumber = '',
    this.note = '',
    this.scanUrl = '',
    this.folder = '',
    this.fileId = '',
    this.filledBy = '',
    this.fileLabel = '',
    this.fileName = '',
  });

  /// Číslo řádku v tabulce (1 = hlavička). Null = ještě neuložený doklad.
  int? row;
  String product;
  String seller;
  DateTime? date;
  num? price;
  String category;
  int warrantyMonths;
  String docNumber;
  String note;
  String scanUrl;
  String folder;
  String fileId;
  String filledBy;

  /// Obecný název věci pro název souboru („vrtačka“). Jen při importu, v tabulce není.
  String fileLabel;

  /// Aktuální název skenu na Disku. Jen při importu, v tabulce není.
  String fileName;

  /// Název, který má mít sken podle roku nákupu a názvu věci.
  String targetFileName(DateTime today) => scanFileName((date ?? today).year,
      fileLabel.isEmpty ? product : fileLabel, fileExtension(fileName));

  /// Kategorie dokladu – v tabulce jsou oddělené čárkou („Elektronika, Děti“).
  List<String> get categoryList => [
        for (final c in category.split(',')) if (c.trim().isNotEmpty) c.trim(),
      ];
  set categoryList(List<String> v) => category = v.join(', ');
  bool hasCategory(String c) => categoryList.contains(c);

  DateTime? get warrantyEnd {
    final d = date;
    if (d == null) return null;
    return DateTime(d.year, d.month + warrantyMonths, d.day);
  }

  bool get hasExtendedWarranty => warrantyMonths > defaultWarrantyMonths;

  WarrantyState stateAt(DateTime today) {
    final end = warrantyEnd;
    if (end == null) return WarrantyState.unknown;
    final left = _days(today, end);
    if (left < 0) return WarrantyState.expired;
    if (left <= warrantySoonDays) return WarrantyState.endingSoon;
    return WarrantyState.active;
  }

  int daysLeft(DateTime today) {
    final end = warrantyEnd;
    return end == null ? 0 : _days(today, end);
  }

  /// 0..1 – jak velká část záruky už uplynula.
  double warrantyProgress(DateTime today) {
    final d = date, end = warrantyEnd;
    if (d == null || end == null) return 0;
    final total = _days(d, end);
    if (total <= 0) return 1;
    return (_days(d, today) / total).clamp(0.0, 1.0);
  }

  /// Počet kalendářních dní mezi daty (bez vlivu letního času).
  static int _days(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  String get scanLink => scanUrl.isNotEmpty
      ? scanUrl
      : (fileId.isNotEmpty ? 'https://drive.google.com/file/d/$fileId/view' : '');

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = _fold(query);
    return _fold('$product $seller $category $docNumber $note').contains(q);
  }

  Receipt copy() => Receipt(
        row: row,
        product: product,
        seller: seller,
        date: date,
        price: price,
        category: category,
        warrantyMonths: warrantyMonths,
        docNumber: docNumber,
        note: note,
        scanUrl: scanUrl,
        folder: folder,
        fileId: fileId,
        filledBy: filledBy,
        fileLabel: fileLabel,
        fileName: fileName,
      );

  // ---- serializace pro Google Sheets ----

  static Receipt fromRow(int row, List<Object?> c) {
    Object? at(int i) => i < c.length ? c[i] : null;
    String s(int i) => (at(i) ?? '').toString().trim();
    return Receipt(
      row: row,
      product: s(0),
      seller: s(1),
      date: parseSheetDate(at(2)),
      price: _num(at(3)),
      category: s(4),
      warrantyMonths: _num(at(5))?.toInt() ?? defaultWarrantyMonths,
      docNumber: s(8),
      note: s(9),
      scanUrl: s(10),
      folder: s(11),
      fileId: s(12),
      filledBy: s(13),
    );
  }

  /// Hodnoty pro A–F (sloupce G a H vypočítává tabulka).
  List<Object?> toRowAF() => [
        product,
        seller,
        date == null ? '' : isoDate(date!),
        price ?? '',
        category,
        warrantyMonths,
      ];

  /// Hodnoty pro I–N.
  List<Object?> toRowIN() => [
        docNumber.isEmpty ? '' : "'$docNumber",
        note,
        scanLink,
        folder,
        fileId.isEmpty ? '' : "'$fileId",
        filledBy,
      ];

  /// Celý řádek A–N pro připojení na konec (G, H zůstanou prázdné).
  List<Object?> toFullRow() => [...toRowAF(), null, null, ...toRowIN()];

  // ---- JSON pro offline cache ----
  Map<String, Object?> toJson() => {
        'row': row,
        'product': product,
        'seller': seller,
        'date': date?.toIso8601String(),
        'price': price,
        'category': category,
        'warrantyMonths': warrantyMonths,
        'docNumber': docNumber,
        'note': note,
        'scanUrl': scanUrl,
        'folder': folder,
        'fileId': fileId,
        'filledBy': filledBy,
      };

  static Receipt fromJson(Map<String, dynamic> j) => Receipt(
        row: j['row'] as int?,
        product: j['product'] as String? ?? '',
        seller: j['seller'] as String? ?? '',
        date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
        price: j['price'] as num?,
        category: j['category'] as String? ?? '',
        warrantyMonths: j['warrantyMonths'] as int? ?? defaultWarrantyMonths,
        docNumber: j['docNumber'] as String? ?? '',
        note: j['note'] as String? ?? '',
        scanUrl: j['scanUrl'] as String? ?? '',
        folder: j['folder'] as String? ?? '',
        fileId: j['fileId'] as String? ?? '',
        filledBy: j['filledBy'] as String? ?? '',
      );
}

num? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  final t = v.toString().replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
  return t.isEmpty ? null : num.tryParse(t);
}

/// Tabulka vrací data jako sériové číslo (dny od 30. 12. 1899) nebo text.
DateTime? parseSheetDate(Object? v) {
  if (v == null) return null;
  if (v is num) {
    final u = DateTime.utc(1899, 12, 30).add(Duration(days: v.floor()));
    return DateTime(u.year, u.month, u.day);
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final m = RegExp(r'^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
  return null;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fold(String s) {
  const from = 'áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽäöü';
  const to = 'acdeeinorstuuyzACDEEINORSTUUYZaou';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i].toLowerCase() : ch);
  }
  return b.toString();
}

const defaultCategories = [
  'Elektronika',
  'Domácnost',
  'Dům a zahrada',
  'Auto',
  'Sport a volný čas',
  'Děti',
  'Oblečení',
  'Ostatní',
];
