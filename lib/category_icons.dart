import 'package:flutter/material.dart';

/// Sada ikon, ze které se vybírá ikona kategorie. Klíč se ukládá do tabulky
/// (list Kategorie, sloupec B), proto se klíče nesmí měnit.
const categoryIconSet = <String, IconData>{
  'elektronika': Icons.devices_other_outlined,
  'pocitac': Icons.computer_outlined,
  'telefon': Icons.smartphone_outlined,
  'tv': Icons.tv_outlined,
  'foto': Icons.photo_camera_outlined,
  'hudba': Icons.headphones_outlined,
  'hry': Icons.sports_esports_outlined,
  'domacnost': Icons.home_outlined,
  'kuchyne': Icons.kitchen_outlined,
  'pracka': Icons.local_laundry_service_outlined,
  'nabytek': Icons.chair_outlined,
  'svetlo': Icons.lightbulb_outline,
  'uklid': Icons.cleaning_services_outlined,
  'zahrada': Icons.yard_outlined,
  'kytka': Icons.local_florist_outlined,
  'naradi': Icons.handyman_outlined,
  'stavba': Icons.construction_outlined,
  'energie': Icons.bolt_outlined,
  'voda': Icons.water_drop_outlined,
  'topeni': Icons.local_fire_department_outlined,
  'auto': Icons.directions_car_outlined,
  'motorka': Icons.two_wheeler_outlined,
  'kolo': Icons.pedal_bike_outlined,
  'palivo': Icons.local_gas_station_outlined,
  'servis': Icons.car_repair_outlined,
  'sport': Icons.sports_soccer_outlined,
  'fitness': Icons.fitness_center_outlined,
  'turistika': Icons.hiking_outlined,
  'cestovani': Icons.flight_outlined,
  'kemp': Icons.cabin_outlined,
  'deti': Icons.child_care_outlined,
  'hracky': Icons.toys_outlined,
  'skola': Icons.school_outlined,
  'obleceni': Icons.checkroom_outlined,
  'zdravi': Icons.medical_services_outlined,
  'leky': Icons.medication_outlined,
  'krasa': Icons.spa_outlined,
  'zvire': Icons.pets_outlined,
  'jidlo': Icons.restaurant_outlined,
  'nakup': Icons.shopping_cart_outlined,
  'darek': Icons.card_giftcard_outlined,
  'knihy': Icons.menu_book_outlined,
  'kancelar': Icons.work_outline,
  'pojisteni': Icons.verified_user_outlined,
  'sluzby': Icons.support_agent_outlined,
  'penize': Icons.payments_outlined,
  'ostatni': Icons.category_outlined,
};

const defaultCategoryIcon = Icons.category_outlined;

/// Bez diakritiky a malými písmeny, pro odhad ikony podle názvu kategorie.
String _fold(String s) {
  const from = 'áčďéěíňóřšťúůýž';
  const to = 'acdeeinorstuuyz';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Odhad ikony podle názvu kategorie, když uživatel žádnou nevybral.
String guessCategoryIcon(String category) {
  final n = _fold(category);
  const rules = <String, List<String>>{
    'elektronika': ['elektro'],
    'pocitac': ['pocitac', 'notebook'],
    'telefon': ['telefon', 'mobil'],
    'zahrada': ['zahrad'],
    'domacnost': ['domacnost', 'dum', 'byt'],
    'naradi': ['naradi', 'dilna'],
    'servis': ['servis', 'oprav'],
    'auto': ['auto', 'vuz', 'pneu'],
    'motorka': ['motork'],
    'kolo': ['kolo', 'cyklo'],
    'sport': ['sport', 'volny cas'],
    'deti': ['deti', 'dite', 'detsk'],
    'hracky': ['hrack'],
    'obleceni': ['obleceni', 'odev'],
    'zdravi': ['zdravi', 'lekar'],
    'zvire': ['zvir', 'pes', 'kocka', 'mazl'],
    'jidlo': ['jidlo', 'potravin'],
    'cestovani': ['cestov', 'dovolen'],
    'knihy': ['knih'],
    'kancelar': ['kancel', 'prace', 'firma'],
    'energie': ['energ', 'elektrin'],
    'ostatni': ['ostatni', 'jine'],
  };
  for (final e in rules.entries) {
    for (final w in e.value) {
      if (RegExp('(^|[^a-z])$w').hasMatch(n)) return e.key;
    }
  }
  return 'ostatni';
}

IconData categoryIconData(String key) => categoryIconSet[key] ?? defaultCategoryIcon;
