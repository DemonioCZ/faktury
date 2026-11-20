import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'detail_page.dart';
import 'edit_page.dart';
import 'scan_view.dart';
import 'import_page.dart';
import 'overview_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  Receipt? _selected;
  bool _sideBySide = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) return _wide(context);
      return _narrow(context);
    });
  }

  // ------------------------- mobil -------------------------
  Widget _narrow(BuildContext context) {
    final pages = [
      ReceiptList(onOpen: (r) => openDetail(context, r)),
      const OverviewPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => openImport(context),
              icon: const Icon(Icons.add),
              label: const Text('Přidat doklad'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Doklady'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Přehled'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Nastavení'),
        ],
      ),
    );
  }

  // ------------------------- Mac / široké okno -------------------------
  Widget _wide(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    if (_selected != null && !s.receipts.contains(_selected)) {
      _selected = s.receipts.where((r) => r.row == _selected!.row).firstOrNull;
    }
    Widget main;
    if (_tab == 1) {
      main = const OverviewPage();
    } else if (_tab == 2) {
      main = const SettingsPage();
    } else {
      main = Row(children: [
        SizedBox(
          width: 460,
          child: ReceiptList(
            dense: true,
            selected: _selected,
            onOpen: (r) => setState(() => _selected = r),
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: _selected == null
              ? Center(
                  child: Text('Vyberte doklad ze seznamu',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : _sideBySide
                  ? Row(children: [
                      SizedBox(
                        width: 460,
                        child: EditPage(
                          key: ValueKey('edit-${_selected!.row}'),
                          receipt: _selected!.copy(),
                          title: 'Kontrola údajů',
                          onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Uloženo'))),
                        ),
                      ),
                      VerticalDivider(width: 1, color: cs.outlineVariant),
                      Expanded(
                        child: ScanPanel(
                          key: ValueKey('panel-${_selected!.fileId}'),
                          receipt: _selected!,
                          onClose: () => setState(() => _sideBySide = false),
                        ),
                      ),
                    ])
                  : ReceiptDetail(
                      key: ValueKey(_selected!.row),
                      receipt: _selected!,
                      wide: true,
                      onDeleted: () => setState(() => _selected = null),
                      onSideBySide: () => setState(() => _sideBySide = true),
                    ),
        ),
      ]);
    }
    return Scaffold(
      body: Row(children: [
        SizedBox(width: 250, child: Sidebar(tab: _tab, onTab: (i) => setState(() => _tab = i))),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(child: main),
      ]),
    );
  }
}

void openDetail(BuildContext context, Receipt r) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(),
        body: ReceiptDetail(receipt: r, onDeleted: () => Navigator.pop(context)),
      ),
    ),
  );
}

/// Seznam dokladů s hledáním, filtry a součty (sdílený pro mobil i Mac).
class ReceiptList extends StatelessWidget {
  const ReceiptList({super.key, required this.onOpen, this.dense = false, this.selected});
  final void Function(Receipt) onOpen;
  final bool dense;
  final Receipt? selected;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final list = s.filtered;
    final groups = groupByMonth(list);
    final total = list.fold<num>(0, (a, r) => a + (r.price ?? 0));
    final t = DateTime.now();
    final inWarranty = list
        .where((r) =>
            r.stateAt(t) == WarrantyState.active || r.stateAt(t) == WarrantyState.endingSoon)
        .length;
    final soon = list.where((r) => r.stateAt(t) == WarrantyState.endingSoon).length;

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: CustomScrollView(slivers: [
        if (!dense)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(children: [
                Text('Doklady',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'Načíst nové skeny z Disku',
                  onPressed: () => openImport(context, scanFolder: true),
                  icon: const Icon(Icons.cloud_sync_outlined),
                ),
              ]),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, dense ? 14 : 6, 16, 8),
            child: Row(children: [
              Expanded(
                child: SearchBar(
                  hintText: 'Hledat produkt, prodejce, číslo…',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: s.setQuery,
                ),
              ),
              if (dense) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => openImport(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat'),
                ),
              ],
            ]),
          ),
        ),
        if (!dense) SliverToBoxAdapter(child: FilterChips(state: s)),
        if (s.loading) const SliverToBoxAdapter(child: LinearProgressIndicator()),
        if (s.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.error!, style: TextStyle(color: cs.error)),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(children: [
              StatCard(s.year == null ? 'Utraceno celkem' : 'Utraceno ${s.year}', money(total)),
              const SizedBox(width: 10),
              StatCard('V záruce', '$inWarranty / ${list.length}'),
              if (dense) ...[
                const SizedBox(width: 10),
                StatCard('Končí do 30 dní', '$soon',
                    valueColor: soon > 0
                        ? StatusColors.of(context, WarrantyState.endingSoon).fg
                        : null),
              ],
            ]),
          ),
        ),
        if (list.isEmpty && !s.loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  s.receipts.isEmpty
                      ? 'Zatím tu nejsou žádné doklady.'
                      : 'Filtru neodpovídá žádný doklad.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        for (final g in groups) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: MonthHeader(g.key, g.value)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: g.value.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => ReceiptTile(
                g.value[i],
                dense: dense,
                selected: identical(g.value[i], selected),
                onTap: () => onOpen(g.value[i]),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ]),
    );
  }
}

class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _menuChip<int?>(
            context,
            label: s.year == null ? 'Všechny roky' : '${s.year}',
            active: s.year != null,
            items: [null, ...s.years],
            text: (y) => y == null ? 'Všechny roky' : '$y',
            onSelected: s.setYear,
          ),
          const SizedBox(width: 8),
          _menuChip<String?>(
            context,
            label: s.category ?? 'Všechny kategorie',
            active: s.category != null,
            items: [null, ...s.categories],
            text: (c) => c ?? 'Všechny kategorie',
            onSelected: s.setCategory,
          ),
          const SizedBox(width: 8),
          for (final w in [
            (WarrantyFilter.active, 'V záruce'),
            (WarrantyFilter.endingSoon, 'Končí brzy'),
            (WarrantyFilter.expired, 'Bez záruky'),
            (WarrantyFilter.extended, 'Delší záruka'),
          ]) ...[
            FilterChip(
              label: Text(w.$2),
              selected: s.warranty == w.$1,
              onSelected: (on) => s.setWarranty(on ? w.$1 : WarrantyFilter.all),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _menuChip<T>(
    BuildContext context, {
    required String label,
    required bool active,
    required List<T> items,
    required String Function(T) text,
    required void Function(T) onSelected,
  }) {
    return MenuAnchor(
      menuChildren: [
        for (final i in items)
          MenuItemButton(onPressed: () => onSelected(i), child: Text(text(i))),
      ],
      builder: (context, ctrl, _) => FilterChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
        selected: active,
        onSelected: (_) => ctrl.isOpen ? ctrl.close() : ctrl.open(),
      ),
    );
  }
}

/// Levý panel na Macu: navigace + rychlé filtry.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.tab, required this.onTab});
  final int tab;
  final void Function(int) onTab;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final t = DateTime.now();
    Widget item(String label,
        {int? count, bool on = false, VoidCallback? onTap, Color? dot, IconData? icon}) {
      return Material(
        color: on ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: dot ?? cs.onSurfaceVariant),
                const SizedBox(width: 8),
              ] else if (dot != null) ...[
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (count != null)
                Text('$count', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      );
    }

    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: cs.onSurfaceVariant)),
        );

    const dots = [
      Color(0xFF3D6FB4), Color(0xFFB4541E), Color(0xFF1F8F6C), Color(0xFF8A5BA8),
      Color(0xFFC0912B), Color(0xFFC0506A), Color(0xFF4F9AA8), Color(0xFF7D7A73),
    ];

    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: .5),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 18, 12, 12), children: [
        item('Doklady', on: tab == 0, onTap: () => onTab(0), count: s.receipts.length),
        item('Přehled', on: tab == 1, onTap: () => onTab(1)),
        item('Nastavení', on: tab == 2, onTap: () => onTab(2)),
        if (tab == 0) ...[
          head('Záruka'),
          item('Všechny', on: s.warranty == WarrantyFilter.all,
              onTap: () => s.setWarranty(WarrantyFilter.all)),
          item('V záruce',
              on: s.warranty == WarrantyFilter.active,
              count: s.countWhere((r) =>
                  r.stateAt(t) == WarrantyState.active ||
                  r.stateAt(t) == WarrantyState.endingSoon),
              onTap: () => s.setWarranty(WarrantyFilter.active)),
          item('Záruka brzy končí',
              on: s.warranty == WarrantyFilter.endingSoon,
              count: s.countWhere((r) => r.stateAt(t) == WarrantyState.endingSoon),
              onTap: () => s.setWarranty(WarrantyFilter.endingSoon)),
          item('Bez záruky',
              on: s.warranty == WarrantyFilter.expired,
              count: s.countWhere((r) => r.stateAt(t) == WarrantyState.expired),
              onTap: () => s.setWarranty(WarrantyFilter.expired)),
          item('Delší záruka',
              on: s.warranty == WarrantyFilter.extended,
              count: s.countWhere((r) => r.hasExtendedWarranty),
              onTap: () => s.setWarranty(WarrantyFilter.extended)),
          head('Rok'),
          item('Všechny roky', on: s.year == null, onTap: () => s.setYear(null)),
          for (final y in s.years)
            item('$y',
                on: s.year == y,
                count: s.countWhere((r) => r.date?.year == y),
                onTap: () => s.setYear(y)),
          head('Kategorie'),
          item('Všechny kategorie', on: s.category == null, onTap: () => s.setCategory(null)),
          for (final (i, c) in s.categories.indexed)
            item(c,
                on: s.category == c,
                dot: dots[i % dots.length],
                icon: s.categoryIcon(c),
                count: s.countWhere((r) => r.hasCategory(c)),
                onTap: () => s.setCategory(c)),
        ],
        const SizedBox(height: 16),
        const UpdateBanner(),
      ]),
    );
  }
}
