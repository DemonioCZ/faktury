import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/gemini.dart';

/// Otevře výběr modelu Gemini. Vybraný model rovnou uloží do Nastavení a vrátí jeho název.
Future<String?> pickGeminiModel(BuildContext context) => Navigator.push<String>(
    context, MaterialPageRoute(builder: (_) => const ModelPickerPage()));

class ModelPickerPage extends StatefulWidget {
  const ModelPickerPage({super.key});

  @override
  State<ModelPickerPage> createState() => _ModelPickerPageState();
}

class _ModelTest {
  _ModelTest.running() : ok = null, text = 'zkouším…';
  _ModelTest.ok(Duration d) : ok = true, text = 'funguje, ${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  _ModelTest.fail(String e) : ok = false, text = e;
  final bool? ok;
  final String text;
}

class _ModelPickerPageState extends State<ModelPickerPage> {
  List<GeminiModel>? _models;
  String? _error;
  final _tests = <String, _ModelTest>{};
  bool _testingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await context.read<AppState>().gemini().listModels();
      if (mounted) setState(() => _models = m);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _test(String name) async {
    setState(() => _tests[name] = _ModelTest.running());
    try {
      final d = await context.read<AppState>().gemini().testModel(name);
      if (mounted) setState(() => _tests[name] = _ModelTest.ok(d));
    } catch (e) {
      var msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.length > 120) msg = '${msg.substring(0, 120)}…';
      if (mounted) setState(() => _tests[name] = _ModelTest.fail(msg));
    }
  }

  Future<void> _testAll() async {
    setState(() => _testingAll = true);
    for (final m in _models ?? const <GeminiModel>[]) {
      if (!mounted || !_testingAll) break;
      await _test(m.name);
    }
    if (mounted) setState(() => _testingAll = false);
  }

  void _select(String name) {
    context.read<AppState>().setGeminiModel(name);
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = context.watch<AppState>().settings.geminiModel;
    final models = _models;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Gemini'),
        actions: [
          if (models != null && models.isNotEmpty)
            TextButton.icon(
              onPressed: _testingAll ? () => setState(() => _testingAll = false) : _testAll,
              icon: Icon(_testingAll ? Icons.stop : Icons.play_arrow),
              label: Text(_testingAll ? 'Zastavit' : 'Vyzkoušet všechny'),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, color: cs.error, size: 40),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Zkusit znovu')),
                ]),
              ),
            )
          : models == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Modely dostupné pro váš klíč. Klepnutím na ▶ model vyzkoušíte krátkým dotazem, '
                      'klepnutím na řádek ho vyberete. Pro čtení dokladů stačí model „flash“.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                  for (final m in models) _tile(m, current, cs),
                ]),
    );
  }

  Widget _tile(GeminiModel m, String current, ColorScheme cs) {
    final t = _tests[m.name];
    final selected = m.name == current;
    return ListTile(
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? cs.primary : null),
      title: Text(m.name),
      subtitle: Text(
        t == null ? m.displayName : '${m.displayName} · ${t.text}',
        style: TextStyle(
            color: t?.ok == true
                ? Colors.green
                : t?.ok == false
                    ? cs.error
                    : null),
      ),
      trailing: t?.ok == null && t != null
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              tooltip: 'Vyzkoušet',
              icon: Icon(t?.ok == true
                  ? Icons.check_circle
                  : t?.ok == false
                      ? Icons.cancel
                      : Icons.play_circle_outline),
              color: t?.ok == true
                  ? Colors.green
                  : t?.ok == false
                      ? cs.error
                      : null,
              onPressed: () => _test(m.name),
            ),
      onTap: () => _select(m.name),
    );
  }
}
