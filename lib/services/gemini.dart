import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Stav dlouhé operace pro zobrazení v UI.
class TaskProgress {
  const TaskProgress(this.step, this.steps, this.title, {this.detail, this.value});
  final int step;
  final int steps;
  final String title;
  final String? detail;

  /// 0..1, nebo null, když průběh nejde změřit (čekání na odpověď Gemini).
  final double? value;
}

/// Umožní uživateli zrušit probíhající zpracování.
class CancelToken {
  final _c = Completer<void>();
  bool get isCancelled => _c.isCompleted;
  Future<void> get whenCancelled => _c.future;
  void cancel() {
    if (!_c.isCompleted) _c.complete();
  }

  void check() {
    if (isCancelled) throw const CancelledException();
  }
}

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'Zpracování bylo zrušeno.';
}

/// Gemini je přetížený i po všech pokusech, UI nabídne jiný model.
class GeminiOverloadedException implements Exception {
  GeminiOverloadedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiModel {
  const GeminiModel(this.name, this.displayName);
  final String name;
  final String displayName;
}

/// Vytěžení údajů z fotky nebo PDF dokladu pomocí Gemini API.
class GeminiService {
  GeminiService(this.apiKey, {this.model = defaultModel});

  static const defaultModel = 'gemini-3.8-flash';

  /// Nejstarší verze modelu, která se nabízí ve výběru.
  static const minModelVersion = 3.0;
  final String apiKey;
  final String model;

  /// Čekání před dalšími pokusy, když je Gemini přetížený nebo spadne spojení.
  static const retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 12),
  ];

  /// Opraví běžné překlepy v ručně zadaném názvu modelu
  /// (mezery, velká písmena, prefix "models/", zdvojené nebo přebytečné tečky),
  /// např. "gemini-3.8.-flash" -> "gemini-3.8-flash".
  static String normalizeModel(String raw) {
    var m = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    if (m.startsWith('models/')) m = m.substring(7);
    return m
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll('.-', '-')
        .replaceAll('-.', '-')
        .replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), '');
  }

  /// Vypadá název jako platný model Gemini?
  static bool isValidModel(String m) =>
      RegExp(r'^gemini-[a-z0-9]+(\.[a-z0-9]+)*(-[a-z0-9]+(\.[a-z0-9]+)*)*$')
          .hasMatch(m);

  static bool _retryable(int code) =>
      code == 429 || code == 500 || code == 502 || code == 503 || code == 504;

  Future<Receipt> extract({
    required Uint8List bytes,
    required String mimeType,
    required List<String> categories,
    String fileName = '',
    void Function(String status)? onStatus,
    CancelToken? cancel,
  }) async {
    final prompt = '''
Jsi asistent pro evidenci nákupních dokladů (faktur, účtenek, dodacích listů) v češtině.
Z přiloženého dokladu vyčti údaje a vrať je jako JSON podle schématu.
- product: stručný a výstižný název koupené věci česky (značka + model), u více položek hlavní položku a „+ …“.
- seller: obchod nebo prodejce (krátce, např. "Alza.cz", "Datart").
- date: datum nákupu / uskutečnění zdanitelného plnění ve formátu YYYY-MM-DD.
- price: celková částka k úhradě v Kč jako číslo.
- category: vyber nejvhodnější z: ${categories.join(', ')}. Pokud doklad jasně patří do víc kategorií, uveď je oddělené čárkou. Pokud žádná nesedí, navrhni novou krátkou kategorii.
- warranty_months: délka záruky v měsících, pokud je na dokladu uvedena (např. prodloužená 36). Jinak 24.
- doc_number: číslo faktury / dokladu.
- note: krátká poznámka, jen pokud je něco důležitého (sériové číslo, prodloužená záruka, splátky). Jinak prázdné.
${fileName.isNotEmpty ? 'Název souboru (může napovědět): $fileName' : ''}
''';
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': mimeType, 'data': base64Encode(bytes)}
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'product': {'type': 'STRING'},
            'seller': {'type': 'STRING'},
            'date': {'type': 'STRING'},
            'price': {'type': 'NUMBER'},
            'category': {'type': 'STRING'},
            'warranty_months': {'type': 'INTEGER'},
            'doc_number': {'type': 'STRING'},
            'note': {'type': 'STRING'},
          },
          'required': ['product', 'seller', 'date', 'price', 'category'],
        },
      },
    };
    var useModel = normalizeModel(model);
    if (!isValidModel(useModel)) useModel = defaultModel;
    final payload = jsonEncode(body);
    final attempts = retryDelays.length + 1;

    http.Response? res;
    Object? lastError;
    String problem = '';
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        // Odpočet do dalšího pokusu, po sekundách, aby šlo zrušit a bylo vidět, co se děje.
        for (var s = retryDelays[i - 1].inSeconds; s > 0; s--) {
          cancel?.check();
          onStatus?.call('$problem Další pokus za $s s (pokus ${i + 1} ze $attempts).');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      cancel?.check();
      onStatus?.call('Čekám na odpověď modelu $useModel'
          '${i > 0 ? ' (pokus ${i + 1} ze $attempts)' : ''}…');
      try {
        res = await _send('models/$useModel:generateContent', payload, cancel);
        // Neznámý model (ukončený nebo překlep): zkusit výchozí.
        if (res.statusCode == 404 && useModel != defaultModel) {
          useModel = defaultModel;
          onStatus?.call('Model nenalezen, zkouším výchozí $useModel…');
          res = await _send('models/$useModel:generateContent', payload, cancel);
        }
        if (!_retryable(res.statusCode)) break;
        problem = res.statusCode == 429
            ? 'Vyčerpán limit dotazů (429).'
            : 'Gemini je přetížený (${res.statusCode}).';
      } on http.ClientException catch (e) {
        cancel?.check();
        lastError = e;
        res = null;
        problem = 'Spojení se přerušilo.';
      } on SocketException catch (e) {
        cancel?.check();
        lastError = e;
        res = null;
        problem = 'Spojení se přerušilo.';
      } on TimeoutException catch (e) {
        lastError = e;
        res = null;
        problem = 'Gemini neodpověděl do 90 s.';
      }
    }
    if (res == null) {
      throw Exception('Nepodařilo se spojit s Gemini ani na $attempts pokusů. '
          'Zkontrolujte připojení k internetu a zkuste to znovu. ($lastError)');
    }
    if (res.statusCode != 200) {
      final msg = _errorMessage(res);
      if (_retryable(res.statusCode)) {
        throw GeminiOverloadedException('Model $useModel je teď přetížený (${res.statusCode}), '
            'nepomohlo ani $attempts pokusů. Zkuste to za pár minut znovu, '
            'nebo vyberte jiný model. ($msg)');
      }
      throw Exception('Gemini (${res.statusCode}, model $useModel): $msg');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null) throw Exception('Gemini nevrátil žádná data.');
    final j = jsonDecode(text) as Map<String, dynamic>;
    return Receipt(
      product: (j['product'] as String? ?? '').trim(),
      seller: (j['seller'] as String? ?? '').trim(),
      date: parseSheetDate(j['date']),
      price: j['price'] as num?,
      category: (j['category'] as String? ?? '').trim(),
      warrantyMonths: (j['warranty_months'] as num?)?.toInt() ?? defaultWarrantyMonths,
      docNumber: (j['doc_number'] as String? ?? '').trim(),
      note: (j['note'] as String? ?? '').trim(),
      filledBy: 'AI',
    );
  }

  /// Modely dostupné pro tento klíč, které umí generateContent
  /// (bez specializovaných modelů na řeč, obrázky, embeddingy apod.).
  Future<List<GeminiModel>> listModels() async {
    final res = await _send('models?pageSize=1000', null, null,
        timeout: const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Seznam modelů se nepodařilo načíst (${res.statusCode}): ${_errorMessage(res)}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    const skip = ['embedding', 'tts', 'image', 'live', 'audio', 'aqa', 'robotics', 'computer-use'];
    double ver(String n) =>
        double.tryParse(RegExp(r'gemini-(\d+(\.\d+)?)').firstMatch(n)?.group(1) ?? '') ?? 0;
    final out = <GeminiModel>[];
    for (final m in (data['models'] as List? ?? [])) {
      final name = (m['name'] as String? ?? '').replaceFirst('models/', '');
      final methods = (m['supportedGenerationMethods'] as List?)?.cast<String>() ?? const [];
      if (!name.startsWith('gemini-') || !methods.contains('generateContent')) continue;
      if (skip.any(name.contains)) continue;
      // Jen modely verze 3 a novější (starší Google postupně ukončuje).
      if (ver(name) < minModelVersion) continue;
      out.add(GeminiModel(name, (m['displayName'] as String?) ?? name));
    }
    // Novější verze nahoru, flash modely před pro.
    out.sort((a, b) {
      final v = ver(b.name).compareTo(ver(a.name));
      if (v != 0) return v;
      final fa = a.name.contains('flash') ? 0 : 1, fb = b.name.contains('flash') ? 0 : 1;
      if (fa != fb) return fa - fb;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// Krátký zkušební dotaz. Vrátí dobu odpovědi, nebo vyhodí výjimku s důvodem.
  Future<Duration> testModel(String name) async {
    final sw = Stopwatch()..start();
    final res = await _send(
      'models/$name:generateContent',
      jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Odpověz jen slovem OK.'}
            ]
          }
        ]
      }),
      null,
      timeout: const Duration(seconds: 30),
    );
    if (res.statusCode != 200) throw Exception('${res.statusCode}: ${_errorMessage(res)}');
    return sw.elapsed;
  }

  static String _errorMessage(http.Response res) {
    try {
      return (jsonDecode(res.body)['error']?['message'] as String?) ?? res.body;
    } catch (_) {
      return res.body;
    }
  }

  Future<http.Response> _send(String path, String? payload, CancelToken? cancel,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final req = http.AbortableRequest(
      payload == null ? 'GET' : 'POST',
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/$path'),
      abortTrigger: cancel?.whenCancelled,
    );
    req.headers['x-goog-api-key'] = apiKey;
    if (payload != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = payload;
    }
    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } finally {
      client.close();
    }
  }
}

String mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
