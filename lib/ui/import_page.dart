import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/google.dart';
import 'edit_page.dart';

/// Nabídka: vyfotit doklad / vybrat soubor / načíst nové skeny z Disku.
Future<void> openImport(BuildContext context, {bool scanFolder = false}) async {
  final s = context.read<AppState>();
  if (!s.hasGemini) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nejdřív vložte Gemini API klíč v Nastavení.')));
    return;
  }
  if (scanFolder) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const FolderImportPage()));
    return;
  }
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Vyfotit doklad'),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: Text(Platform.isAndroid ? 'Vybrat fotku nebo PDF' : 'Vybrat soubor (foto, PDF)'),
          onTap: () => Navigator.pop(c, 'file'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('Načíst nové skeny ze složky na Disku'),
          onTap: () => Navigator.pop(c, 'drive'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'drive') {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const FolderImportPage()));
    return;
  }

  Uint8List? bytes;
  String name = 'doklad.jpg';
  if (choice == 'camera') {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
    if (x == null) return;
    bytes = await x.readAsBytes();
    name = 'doklad.jpg';
  } else {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
    );
    final f = res.firstOrNull;
    if (f == null) return;
    bytes = await f.readAsBytes();
    name = f.name;
  }
  if (bytes == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => _SingleImportPage(bytes: bytes!, name: name)),
  );
}

class _SingleImportPage extends StatefulWidget {
  const _SingleImportPage({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;

  @override
  State<_SingleImportPage> createState() => _SingleImportPageState();
}

class _SingleImportPageState extends State<_SingleImportPage> {
  Receipt? _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      final r = await context.read<AppState>().uploadAndExtract(widget.bytes, widget.name);
      if (mounted) setState(() => _draft = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d != null) {
      return EditPage(receipt: d, title: 'Zkontrolujte údaje', saveLabel: 'Uložit doklad');
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Nový doklad')),
      body: _Busy(
        error: _error,
        onRetry: _run,
        text: 'Nahrávám sken na Disk a čtu údaje…',
      ),
    );
  }
}

/// Projde složku na Disku, najde skeny, které nejsou v tabulce, a postupně je zpracuje.
class FolderImportPage extends StatefulWidget {
  const FolderImportPage({super.key});

  @override
  State<FolderImportPage> createState() => _FolderImportPageState();
}

class _FolderImportPageState extends State<FolderImportPage> {
  List<DriveFile>? _files;
  int _index = 0;
  int _saved = 0;
  Receipt? _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    setState(() => _error = null);
    try {
      final f = await context.read<AppState>().findNewScans();
      if (!mounted) return;
      setState(() => _files = f);
      if (f.isNotEmpty) _process();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _process() async {
    setState(() {
      _draft = null;
      _error = null;
    });
    try {
      final r = await context.read<AppState>().extractDriveFile(_files![_index]);
      if (mounted) setState(() => _draft = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _next({bool saved = false}) {
    if (saved) _saved++;
    if (_index + 1 >= _files!.length) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hotovo, uloženo $_saved z ${_files!.length} dokladů.')));
      return;
    }
    setState(() => _index++);
    _process();
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    if (files == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nové skeny')),
        body: _Busy(error: _error, onRetry: _find, text: 'Hledám nové skeny ve složce…'),
      );
    }
    if (files.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nové skeny')),
        body: const Center(child: Text('Všechny skeny ve složce už jsou v přehledu.')),
      );
    }
    final f = files[_index];
    final d = _draft;
    final title = '${_index + 1} z ${files.length}';
    if (d != null) {
      return EditPage(
        key: ValueKey(f.id),
        receipt: d,
        title: 'Kontrola $title',
        saveLabel: _index + 1 < files.length ? 'Uložit a další' : 'Uložit a dokončit',
        onSkip: _next,
        onSaved: () => _next(saved: true),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Nové skeny · $title')),
      body: _Busy(
        error: _error,
        onRetry: _process,
        onSkip: _next,
        text: 'Čtu údaje z „${f.name}“…',
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text, this.error, this.onRetry, this.onSkip});
  final String text;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (error == null) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(text, textAlign: TextAlign.center),
          ] else ...[
            Icon(Icons.error_outline, color: cs.error, size: 40),
            const SizedBox(height: 12),
            Text(error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              if (onSkip != null) OutlinedButton(onPressed: onSkip, child: const Text('Přeskočit')),
              if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Zkusit znovu')),
            ]),
          ],
        ]),
      ),
    );
  }
}
