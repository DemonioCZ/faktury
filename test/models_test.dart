import 'package:faktury/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 16);

  test('záruka 24 měsíců', () {
    final r = Receipt(product: 'X', date: DateTime(2025, 7, 22));
    expect(r.warrantyEnd, DateTime(2027, 7, 22));
    expect(r.stateAt(today), WarrantyState.active);
  });

  test('končí brzy a bez záruky', () {
    expect(Receipt(product: 'a', date: DateTime(2024, 12, 4)).stateAt(today),
        WarrantyState.endingSoon);
    expect(Receipt(product: 'b', date: DateTime(2024, 9, 5)).stateAt(today),
        WarrantyState.expired);
  });

  test('prodloužená záruka', () {
    final r = Receipt(product: 'c', date: DateTime(2024, 1, 16), warrantyMonths: 36);
    expect(r.hasExtendedWarranty, isTrue);
    expect(r.stateAt(today), WarrantyState.active);
  });

  test('čtení řádku z tabulky (sériové datum)', () {
    final r = Receipt.fromRow(5, [
      'Mac Mini', 'iStyle', 45860, 21190, 'Elektronika', 24, 46591, 'V záruce',
      571095213, 'SN', 'https://x', 'Faktury', 'abc', 'Claude'
    ]);
    expect(r.date, DateTime(2025, 7, 22));
    expect(r.docNumber, '571095213');
    expect(r.row, 5);
  });

  test('více kategorií', () {
    final r = Receipt(product: 'x', category: 'Elektronika, Děti');
    expect(r.categoryList, ['Elektronika', 'Děti']);
    expect(r.hasCategory('Děti'), isTrue);
    r.categoryList = [...r.categoryList, 'Auto'];
    expect(r.category, 'Elektronika, Děti, Auto');
  });

  test('hledání bez diakritiky', () {
    final r = Receipt(product: 'Sendvičovač Tefal', seller: 'Datart');
    expect(r.matches('sendvicovac'), isTrue);
    expect(r.matches('alza'), isFalse);
  });
}
