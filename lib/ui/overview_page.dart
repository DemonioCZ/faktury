import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'home.dart';
import 'widgets.dart';

/// Přehled podle roků a kategorií + doklady, kterým končí záruka.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final t = DateTime.now();

    final byYear = <int, num>{};
    final countYear = <int, int>{};
    for (final r in s.receipts) {
      final y = r.date?.year;
      if (y == null) continue;
      byYear[y] = (byYear[y] ?? 0) + (r.price ?? 0);
      countYear[y] = (countYear[y] ?? 0) + 1;
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    final maxYear = byYear.values.fold<num>(1, (a, b) => b > a ? b : a);

    final yearFilter = s.year;
    final scoped = s.receipts.where((r) => yearFilter == null || r.date?.year == yearFilter);
    final byCat = <String, num>{};
    for (final r in scoped) {
      final c = r.category.isEmpty ? 'Bez kategorie' : r.category;
      byCat[c] = (byCat[c] ?? 0) + (r.price ?? 0);
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxCat = cats.fold<num>(1, (a, e) => e.value > a ? e.value : a);

    final ending = s.receipts
        .where((r) => r.stateAt(t) == WarrantyState.active || r.stateAt(t) == WarrantyState.endingSoon)
        .toList()
      ..sort((a, b) => a.warrantyEnd!.compareTo(b.warrantyEnd!));

    Widget section(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ]),
        );

    Widget bar(String label, num value, num max, String trailing, {VoidCallback? onTap, bool on = false}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
                width: 130,
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : value / max,
                  minHeight: 10,
                  color: on ? cs.primary : cs.primary.withValues(alpha: .7),
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Text(trailing,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text('Přehled',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
      Row(children: [
        StatCard('Dokladů', '${s.receipts.length}'),
        const SizedBox(width: 10),
        StatCard('Utraceno celkem',
            money(s.receipts.fold<num>(0, (a, r) => a + (r.price ?? 0)))),
      ]),
      const SizedBox(height: 14),
      section('Podle roku', [
        for (final y in years)
          bar('$y  (${countYear[y]})', byYear[y]!, maxYear, money(byYear[y]),
              on: s.year == y, onTap: () => s.setYear(s.year == y ? null : y)),
      ]),
      section(yearFilter == null ? 'Podle kategorie' : 'Podle kategorie v roce $yearFilter', [
        for (final e in cats)
          bar(e.key, e.value, maxCat, money(e.value),
              on: s.category == e.key,
              onTap: () => s.setCategory(s.category == e.key ? null : e.key)),
      ]),
      section('Záruka končí nejdřív', [
        if (ending.isEmpty)
          Text('Žádný doklad není v záruce.', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final r in ending.take(8)) ...[
          ReceiptTile(r, dense: true, onTap: () => openDetail(context, r)),
          const SizedBox(height: 8),
        ],
      ]),
    ]);
  }
}
