import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import 'edit_page.dart';
import 'scan_view.dart';
import 'widgets.dart';

class ReceiptDetail extends StatelessWidget {
  const ReceiptDetail(
      {super.key, required this.receipt, this.wide = false, this.onDeleted, this.onSideBySide});
  final Receipt receipt;
  final bool wide;
  final VoidCallback? onDeleted;
  final VoidCallback? onSideBySide;

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Smazat doklad?'),
        content: const Text(
            'Řádek se odstraní z tabulky. Sken na Google Disku zůstane.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Smazat')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AppState>().delete(receipt);
    onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final r = context
            .watch<AppState>()
            .receipts
            .where((x) => x.row != null && x.row == receipt.row)
            .firstOrNull ??
        receipt;
    final cs = Theme.of(context).colorScheme;
    final t = DateTime.now();
    final state = r.stateAt(t);
    final colors = StatusColors.of(context, state);

    final scanCard = ScanPreview(
      key: ValueKey('scan-${r.fileId}'),
      receipt: r,
      height: wide ? 420 : 220,
      onSideBySide: onSideBySide,
    );

    final warrantyCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(
            switch (state) {
              WarrantyState.active => 'V záruce',
              WarrantyState.endingSoon => 'Záruka brzy končí',
              WarrantyState.expired => 'Bez záruky',
              WarrantyState.unknown => 'Chybí datum nákupu',
            },
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colors.fg),
          ),
          const Spacer(),
          if (state == WarrantyState.active || state == WarrantyState.endingSoon)
            Text(_left(r.daysLeft(t)), style: TextStyle(fontSize: 13, color: colors.fg)),
        ]),
        if (r.date != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: r.warrantyProgress(t),
              minHeight: 8,
              color: colors.fg,
              backgroundColor: colors.fg.withValues(alpha: .18),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(dateCz(r.date), style: TextStyle(fontSize: 13, color: colors.fg)),
            const Spacer(),
            Text(dateCz(r.warrantyEnd), style: TextStyle(fontSize: 13, color: colors.fg)),
          ]),
        ],
        if (r.hasExtendedWarranty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.verified_outlined, size: 16, color: colors.fg),
            const SizedBox(width: 6),
            Text('Prodloužená záruka ${r.warrantyMonths} měsíců',
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.fg)),
          ]),
        ],
      ]),
    );

    Widget field(String l, String v, {bool ai = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(l, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(
              child: Text(v.isEmpty ? '–' : v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    final fields = Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        for (final (i, w) in [
          field('Datum nákupu', dateCz(r.date)),
          field('Prodejce', r.seller),
          field('Cena', money(r.price)),
          field('Kategorie', r.category),
          field('Číslo dokladu', r.docNumber),
          field('Délka záruky', '${r.warrantyMonths} měsíců'),
          field('Poznámka', r.note),
          field('Vyplnil', r.filledBy),
        ].indexed) ...[
          if (i > 0) Divider(height: 1, color: cs.outlineVariant),
          w,
        ],
      ]),
    );

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.product,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
      if (r.folder.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('složka ${r.folder}', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
    ]);

    final actions = Wrap(spacing: 8, children: [
      FilledButton.tonalIcon(
        onPressed: () => openEditor(context, r),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Upravit'),
      ),
      TextButton.icon(
        onPressed: () => _delete(context),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Smazat'),
      ),
    ]);

    if (wide) {
      return ListView(padding: withBottomInset(context, const EdgeInsets.all(28)), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: header),
          actions,
        ]),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Column(children: [warrantyCard, const SizedBox(height: 14), fields]),
          ),
          const SizedBox(width: 24),
          Expanded(flex: 2, child: scanCard),
        ]),
      ]);
    }
    return ListView(
        padding: withBottomInset(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
        children: [
      scanCard,
      const SizedBox(height: 16),
      header,
      const SizedBox(height: 14),
      warrantyCard,
      const SizedBox(height: 12),
      fields,
      const SizedBox(height: 12),
      actions,
    ]);
  }

  String _left(int days) {
    if (days > 60) return 'zbývá ${(days / 30.4).floor()} měsíců';
    return 'zbývá $days ${days == 1 ? 'den' : (days < 5 ? 'dny' : 'dní')}';
  }
}
