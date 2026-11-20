import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../category_icons.dart';
import '../models.dart';

/// Odsazení obsahu, aby nezajížděl pod systémovou lištu Androidu (tlačítka / gesta).
EdgeInsets withBottomInset(BuildContext context, EdgeInsets p) =>
    p.copyWith(bottom: p.bottom + MediaQuery.viewPaddingOf(context).bottom);

/// Čtvereček s ikonou kategorie dokladu (v seznamu Doklady).
class CategoryIconBox extends StatelessWidget {
  const CategoryIconBox({super.key, required this.icon, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.52, color: cs.onSecondaryContainer),
    );
  }
}

/// Mřížka ikon ze sady. Vrátí klíč vybrané ikony.
Future<String?> pickCategoryIcon(BuildContext context, {String? current, String? title}) =>
    showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title ?? 'Ikona kategorie'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(width: 360, child: _IconGrid(current: current, onPick: (k) => Navigator.pop(c, k))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit'))],
      ),
    );

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.current, required this.onPick});
  final String? current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in categoryIconSet.entries)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPick(e.key),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: e.key == current ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: e.key == current ? Border.all(color: cs.primary, width: 2) : null,
              ),
              child: Icon(e.value,
                  color: e.key == current ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}

/// Dialog pro novou kategorii: název a ikona. Kategorii rovnou přidá a vrátí její název.
Future<String?> newCategoryDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  String icon = '';
  final name = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final key = icon.isNotEmpty ? icon : guessCategoryIcon(ctrl.text);
        return AlertDialog(
          title: const Text('Nová kategorie'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'např. Zahrada, Nářadí',
                  prefixIcon: Icon(categoryIconData(key)),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => Navigator.pop(c, v),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Ikona', style: Theme.of(c).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              Flexible(child: _IconGrid(current: key, onPick: (k) => setState(() => icon = k))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Přidat')),
          ],
        );
      },
    ),
  );
  final n = name?.trim() ?? '';
  if (n.isEmpty || !context.mounted) return null;
  await context
      .read<AppState>()
      .addCategory(n, icon: icon.isNotEmpty ? icon : guessCategoryIcon(n));
  return n;
}

final _money = NumberFormat.decimalPattern('cs');
String money(num? v) => v == null ? '–' : '${_money.format(v.round())} Kč';
String dateCz(DateTime? d) => d == null ? '–' : DateFormat('d. M. yyyy').format(d);
String monthCz(DateTime d) {
  final s = DateFormat('LLLL yyyy', 'cs').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

class StatusColors {
  StatusColors(this.bg, this.fg);
  final Color bg;
  final Color fg;

  static StatusColors of(BuildContext context, WarrantyState s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (s) {
      case WarrantyState.active:
        return dark
            ? StatusColors(const Color(0xFF173B32), const Color(0xFF8FD9C0))
            : StatusColors(const Color(0xFFDCEDE7), const Color(0xFF0F4A3C));
      case WarrantyState.endingSoon:
        return dark
            ? StatusColors(const Color(0xFF4A2A16), const Color(0xFFFFB98A))
            : StatusColors(const Color(0xFFF8E4D6), const Color(0xFF97431A));
      case WarrantyState.expired:
      case WarrantyState.unknown:
        return dark
            ? StatusColors(const Color(0xFF2E2C29), const Color(0xFFB8B3AA))
            : StatusColors(const Color(0xFFE9E6E0), const Color(0xFF5F5B53));
    }
  }
}

String warrantyLabel(Receipt r, DateTime today, {bool short = false}) {
  switch (r.stateAt(today)) {
    case WarrantyState.active:
      return short ? 'V záruce' : 'Záruka do ${dateCz(r.warrantyEnd)}';
    case WarrantyState.endingSoon:
      final d = r.daysLeft(today);
      return 'Končí za $d ${d == 1 ? 'den' : (d < 5 ? 'dny' : 'dní')}';
    case WarrantyState.expired:
      return 'Bez záruky';
    case WarrantyState.unknown:
      return 'Bez data';
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.text, this.colors, {super.key, this.icon});
  final String text;
  final StatusColors colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: colors.fg),
          const SizedBox(width: 4),
        ] else ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colors.fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.fg)),
      ]),
    );
  }
}

class WarrantyBadge extends StatelessWidget {
  const WarrantyBadge(this.r, {super.key, this.short = false});
  final Receipt r;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    final s = r.stateAt(t);
    return Wrap(spacing: 6, runSpacing: 4, children: [
      Badge2(warrantyLabel(r, t, short: short), StatusColors.of(context, s)),
      if (r.hasExtendedWarranty && s != WarrantyState.expired)
        Badge2('${r.warrantyMonths} měs.',
            StatusColors.of(context, WarrantyState.active),
            icon: Icons.verified_outlined),
    ]);
  }
}

class ScanThumb extends StatelessWidget {
  const ScanThumb({super.key, this.size = 46, required this.isPdf});
  final double size;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined,
          size: size * 0.45, color: cs.onSurfaceVariant),
    );
  }
}

bool isPdfReceipt(Receipt r) =>
    r.scanUrl.toLowerCase().contains('.pdf') || r.note.contains('PDF');

class ReceiptTile extends StatelessWidget {
  const ReceiptTile(this.r, {super.key, this.onTap, this.selected = false, this.dense = false});
  final Receipt r;
  final VoidCallback? onTap;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = [
      if (r.seller.isNotEmpty) r.seller,
      if (r.category.isNotEmpty) r.category,
      if (dense && r.date != null) DateFormat('d. M.').format(r.date!),
    ].join(' · ');
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(dense ? 12 : 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(dense ? 12 : 18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 10 : 14),
          child: Row(children: [
            CategoryIconBox(
                icon: context.watch<AppState>().receiptIcon(r), size: dense ? 34 : 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.product.isEmpty ? '(bez názvu)' : r.product,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: dense ? 14 : 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                if (!dense) ...[const SizedBox(height: 6), WarrantyBadge(r)],
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(r.price),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()])),
              if (dense) ...[const SizedBox(height: 4), WarrantyBadge(r, short: true)],
            ]),
          ]),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Seskupí doklady podle měsíce (nejnovější první).
List<MapEntry<DateTime?, List<Receipt>>> groupByMonth(List<Receipt> list) {
  final map = <String, MapEntry<DateTime?, List<Receipt>>>{};
  for (final r in list) {
    final d = r.date;
    final key = d == null ? 'none' : '${d.year}-${d.month}';
    map.putIfAbsent(key, () => MapEntry(d == null ? null : DateTime(d.year, d.month), []));
    map[key]!.value.add(r);
  }
  return map.values.toList();
}

class MonthHeader extends StatelessWidget {
  const MonthHeader(this.month, this.items, {super.key});
  final DateTime? month;
  final List<Receipt> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sum = items.fold<num>(0, (a, r) => a + (r.price ?? 0));
    final style = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
      child: Row(children: [
        Text((month == null ? 'Bez data' : monthCz(month!)).toUpperCase(), style: style),
        const Spacer(),
        Text(money(sum), style: style),
      ]),
    );
  }
}
