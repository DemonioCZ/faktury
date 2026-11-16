import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/google.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long, size: 64, color: cs.primary),
              const SizedBox(height: 20),
              Text('Účtenky a faktury',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                'Doklady máte na Google Disku. Přihlaste se Google účtem, '
                'aplikace si z nich udělá přehled a pohlídá záruky.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: s.loading ? null : s.signIn,
                icon: const Icon(Icons.login),
                label: const Text('Přihlásit se přes Google'),
              ),
              if (s.error != null) ...[
                const SizedBox(height: 16),
                Text(s.error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Výběr složky se skeny na Google Disku.
class FolderPickerPage extends StatefulWidget {
  const FolderPickerPage({super.key, this.asDialog = false});
  final bool asDialog;

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  final _search = TextEditingController();
  final _stack = <DriveFile>[];
  List<DriveFile>? _folders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _folders = null);
    try {
      final g = context.read<AppState>().google;
      final list = await g.listFolders(
        search: _search.text.trim(),
        parent: _stack.isEmpty ? null : _stack.last.id,
      );
      if (mounted) setState(() => _folders = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _choose(DriveFile f) async {
    final s = context.read<AppState>();
    await s.chooseFolder(f.id, f.name);
    if (mounted && widget.asDialog && s.error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vyberte složku s doklady'),
        leading: _stack.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _stack.removeLast();
                  _load();
                })
            : null,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Hledat složku, např. Faktury'),
            onSubmitted: (_) => _load(),
          ),
        ),
        if (_stack.isNotEmpty)
          ListTile(
            leading: Icon(Icons.check_circle, color: cs.primary),
            title: Text('Použít složku „${_stack.last.name}“'),
            onTap: s.loading ? null : () => _choose(_stack.last),
          ),
        if (s.loading) const LinearProgressIndicator(),
        if (s.error != null || _error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s.error ?? _error!, style: TextStyle(color: cs.error)),
          ),
        Expanded(
          child: _folders == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  for (final f in _folders!)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(f.name),
                      trailing: TextButton(
                          onPressed: s.loading ? null : () => _choose(f),
                          child: const Text('Vybrat')),
                      onTap: () {
                        _stack.add(f);
                        _search.clear();
                        _load();
                      },
                    ),
                ]),
        ),
      ]),
    );
  }
}
