import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../services/gemini.dart';
import '../services/updater.dart';
import 'model_picker.dart';
import 'setup_pages.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppState s = context.read<AppState>();
  late final _key = TextEditingController(text: s.settings.geminiKey);
  late final _model = TextEditingController(text: s.settings.geminiModel);
  bool _showKey = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    Updater().currentVersion().then((v) => mounted ? setState(() => _version = v) : null);
  }

  Future<void> _newCategory() async {
    await newCategoryDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: cs.onSurfaceVariant)),
        );
    Widget card(List<Widget> children) => Container(
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
          child: Column(children: children),
        );

    return ListView(padding: withBottomInset(context, const EdgeInsets.all(16)), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Text('Nastavení',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
      head('Úložiště'),
      card([
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('Google účet'),
          subtitle: Text(st.userEmail ?? '–'),
          trailing: TextButton(onPressed: st.signOut, child: const Text('Odhlásit')),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Složka se skeny'),
          subtitle: Text(st.settings.folderName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const FolderPickerPage(asDialog: true))),
        ),
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Tabulka s daty'),
          subtitle: const Text('Faktury – data'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(
              Uri.parse('https://docs.google.com/spreadsheets/d/${st.settings.sheetId}/edit'),
              mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Synchronizovat'),
          subtitle: Text(st.lastSync == null
              ? 'zatím neproběhlo'
              : 'naposledy ${dateCz(st.lastSync)} ${TimeOfDay.fromDateTime(st.lastSync!).format(context)}'),
          onTap: st.refresh,
        ),
      ]),
      head('Čtení dokladů (Gemini)'),
      card([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _key,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: 'Gemini API klíč',
              helperText: 'Uloží se jen v tomto zařízení.',
              suffixIcon: IconButton(
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (v) => st.settings.geminiKey = v,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model',
              helperText: 'Používá se: ${st.settings.geminiModel}'
                  '${st.settings.geminiModel == GeminiService.defaultModel ? ' (výchozí)' : ''}. '
                  'Když Google model ukončí, napište sem nový.',
              helperMaxLines: 3,
            ),
            onChanged: (v) => setState(() => st.settings.geminiModel = v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.list_alt_outlined),
          title: const Text('Vybrat model ze seznamu'),
          subtitle: const Text('Načte dostupné modely a umožní je vyzkoušet'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            if (!st.hasGemini) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nejdřív vložte Gemini API klíč.')));
              return;
            }
            final m = await pickGeminiModel(context);
            if (m != null && mounted) setState(() => _model.text = m);
          },
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Získat klíč zdarma'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'),
              mode: LaunchMode.externalApplication),
        ),
      ]),
      head('Kategorie'),
      card([
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in st.categories)
              ActionChip(
                avatar: Icon(st.categoryIcon(c), size: 18),
                label: Text(c),
                tooltip: 'Změnit ikonu',
                onPressed: () async {
                  final k = await pickCategoryIcon(context,
                      current: st.categoryIconKey(c), title: 'Ikona: $c');
                  if (k != null) await st.setCategoryIcon(c, k);
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Přidat'),
              onPressed: _newCategory,
            ),
          ]),
        ),
      ]),
      head('Aplikace'),
      const UpdateBanner(showUpToDate: true),
      const SizedBox(height: 10),
      card([
        ListTile(title: const Text('Verze'), trailing: Text(_version)),
      ]),
    ]);
  }
}

/// Kontrola nové verze na GitHubu a instalace jedním tlačítkem.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, this.showUpToDate = false});
  final bool showUpToDate;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  final _u = Updater();
  UpdateInfo? _info;
  bool _checked = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final i = await _u.check();
      if (mounted) {
        setState(() {
          _info = i;
          _checked = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checked = true;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() => _progress = 0);
    try {
      await _u.install(_info!, (p) => mounted ? setState(() => _progress = p) : null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i = _info;
    if (i == null) {
      if (!widget.showUpToDate) return const SizedBox.shrink();
      return Container(
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        child: ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(!_checked
              ? 'Kontroluji aktualizace…'
              : (_error ?? 'Máte nejnovější verzi')),
          trailing: TextButton(onPressed: _check, child: const Text('Zkontrolovat')),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nová verze ${i.version}',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
        if (i.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(i.notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: cs.onPrimaryContainer)),
          ),
        const SizedBox(height: 10),
        if (_progress != null)
          LinearProgressIndicator(value: _progress == 0 ? null : _progress)
        else
          FilledButton(onPressed: _install, child: const Text('Aktualizovat')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
          ),
      ]),
    );
  }
}
