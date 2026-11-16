import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Vytěžení údajů z fotky nebo PDF dokladu pomocí Gemini API.
class GeminiService {
  GeminiService(this.apiKey, {this.model = defaultModel});

  static const defaultModel = 'gemini-3.8-flash';
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
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future.delayed(retryDelays[i - 1]);
      try {
        res = await _post(useModel, payload);
        // Neznámý model (ukončený nebo překlep): zkusit výchozí.
        if (res.statusCode == 404 && useModel != defaultModel) {
          useModel = defaultModel;
          res = await _post(useModel, payload);
        }
        if (!_retryable(res.statusCode)) break;
      } on SocketException catch (e) {
        lastError = e;
        res = null;
        continue;
      } on http.ClientException catch (e) {
        lastError = e;
        res = null;
        continue;
      } on TimeoutException catch (e) {
        lastError = e;
        res = null;
      }
    }
    if (res == null) {
      throw Exception('Nepodařilo se spojit s Gemini ani na $attempts pokusů. '
          'Zkontrolujte připojení k internetu a zkuste to znovu. ($lastError)');
    }
    if (res.statusCode != 200) {
      String msg = res.body;
      try {
        msg = (jsonDecode(res.body)['error']?['message'] as String?) ?? msg;
      } catch (_) {}
      if (_retryable(res.statusCode)) {
        throw Exception('Gemini je teď přetížený (${res.statusCode}), nepomohlo ani '
            '$attempts pokusů. Zkuste to za pár minut znovu. ($msg)');
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

  Future<http.Response> _post(String useModel, String payload) => http
      .post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
            '$useModel:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: payload,
      )
      .timeout(const Duration(seconds: 90));
}

String mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
