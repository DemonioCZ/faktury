import 'package:faktury/services/gemini.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oprava překlepů v názvu modelu', () {
    expect(GeminiService.normalizeModel('gemini-3.8.-flash'), 'gemini-3.8-flash');
    expect(GeminiService.normalizeModel(' Gemini-3.8-Flash '), 'gemini-3.8-flash');
    expect(GeminiService.normalizeModel('models/gemini-3.8-flash'), 'gemini-3.8-flash');
    expect(GeminiService.normalizeModel('gemini-3..8-flash.'), 'gemini-3.8-flash');
    expect(GeminiService.normalizeModel('gemini 3.8 flash'), 'gemini-3.8-flash');
  });

  test('platnost názvu modelu', () {
    expect(GeminiService.isValidModel('gemini-3.8-flash'), isTrue);
    expect(GeminiService.isValidModel('gemini-2.5-flash-lite'), isTrue);
    expect(GeminiService.isValidModel('gemini-3.8.-flash'), isFalse);
    expect(GeminiService.isValidModel('gpt-4'), isFalse);
    expect(GeminiService.isValidModel(''), isFalse);
  });
}
