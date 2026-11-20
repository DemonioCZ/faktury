import 'package:faktury/category_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('výchozí ikony stávajících kategorií', () {
    expect(guessCategoryIcon('Elektronika'), 'elektronika');
    expect(guessCategoryIcon('Domácnost'), 'domacnost');
    expect(guessCategoryIcon('Dům a zahrada'), 'zahrada');
    expect(guessCategoryIcon('Auto'), 'auto');
    expect(guessCategoryIcon('Sport a volný čas'), 'sport');
    expect(guessCategoryIcon('Děti'), 'deti');
    expect(guessCategoryIcon('Oblečení'), 'obleceni');
    expect(guessCategoryIcon('Ostatní'), 'ostatni');
    expect(guessCategoryIcon('Něco úplně jiného'), 'ostatni');
  });

  test('každý odhad je v sadě ikon', () {
    for (final c in ['Nářadí', 'Kolo', 'Mazlíčci', 'Telefony']) {
      expect(categoryIconSet.containsKey(guessCategoryIcon(c)), isTrue, reason: c);
    }
  });
}
