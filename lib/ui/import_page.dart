import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/google.dart';
import '../services/gemini.dart';
import 'edit_page.dart';
import 'model_picker.dart';

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
  Object? _error;
  TaskProgress? _progress;
  CancelToken? _cancel;
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final cancel = CancelToken();
    setState(() {
      _error = null;
      _progress = null;
      _cancel = cancel;
      _runId++;
    });
    try {
      final r = await context.read<AppState>().uploadAndExtract(widget.bytes, widget.name,
          cancel: cancel, onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      if (mounted) setState(() => _draft = r);
    } on CancelledException {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickModel() async {
    final m = await pickGeminiModel(context);
    if (m != null && mounted) _run();
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d != null) {
      return EditPage(receipt: d, title: 'Zkontrolujte údaje', saveLabel: 'Uložit doklad');
    }
    final p = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Nový doklad')),
      body: _Busy(
        key: ValueKey(_runId),
        error: _error,
        progress: p,
        onRetry: _run,
        onPickModel: _pickModel,
        // Během nahrávání na Disk už nerušit, soubor by tam zůstal bez záznamu.
        onCancel: p == null || p.step == 1 ? () => _cancel?.cancel() : null,
        text: 'Připravuji…',
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
  Object? _error;
  TaskProgress? _progress;
  CancelToken? _cancel;
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() => _error = null);
    try {
      final f = await context.read<AppState>().findNewScans();
      if (!mounted) return;
      setState(() => _files = f);
      if (f.isNotEmpty) _process();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _process() async {
    final cancel = CancelToken();
    setState(() {
      _draft = null;
      _error = null;
      _progress = null;
      _cancel = cancel;
      _runId++;
    });
    try {
      final r = await context.read<AppState>().extractDriveFile(_files![_index],
          cancel: cancel, onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      if (mounted) setState(() => _draft = r);
    } on CancelledException {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickModel() async {
    final m = await pickGeminiModel(context);
    if (m != null && mounted) _process();
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
        key: ValueKey(_runId),
        error: _error,
        progress: _progress,
        onRetry: _process,
        onSkip: _next,
        onPickModel: _pickModel,
        onCancel: () => _cancel?.cancel(),
        text: '„${f.name}“',
      ),
    );
  }
}

/// Průběh zpracování: krok, co se právě děje, uplynulý čas a možnost zrušit.
class _Busy extends StatefulWidget {
  const _Busy({
    super.key,
    required this.text,
    this.progress,
    this.error,
    this.onRetry,
    this.onSkip,
    this.onCancel,
    this.onPickModel,
  });
  final String text;
  final TaskProgress? progress;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;
  final VoidCallback? onCancel;
  final VoidCallback? onPickModel;

  @override
  State<_Busy> createState() => _BusyState();
}

class _BusyState extends State<_Busy> {
  final _sw = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.error == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final s = _sw.elapsed.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.progress;
    final err = widget.error;
    final muted = TextStyle(color: cs.onSurfaceVariant);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (err == null) ...[
              if (p == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(widget.text, textAlign: TextAlign.center),
              ] else ...[
                Text('Krok ${p.step} ze ${p.steps}', style: muted),
                const SizedBox(height: 6),
                Text(p.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: p.value, minHeight: 6),
                ),
                const SizedBox(height: 10),
                if (p.value != null) Text('${(p.value! * 100).round()} %', style: muted),
                if (p.detail != null) ...[
                  const SizedBox(height: 6),
                  Text(p.detail!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 6),
                Text('Uplynulo $_elapsed', style: muted),
                if (p.value == null && _sw.elapsed.inSeconds >= 20) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Čtení dokladu obvykle trvá do 20 s. U Gemini nejde změřit procenta, '
                    'aplikace jen čeká na odpověď.',
                    textAlign: TextAlign.center,
                    style: muted.copyWith(fontSize: 12.5),
                  ),
                ],
              ],
              if (widget.onCancel != null) ...[
                const SizedBox(height: 20),
                OutlinedButton(onPressed: widget.onCancel, child: const Text('Zrušit')),
              ],
            ] else ...[
              Icon(Icons.error_outline, color: cs.error, size: 40),
              const SizedBox(height: 12),
              Text(err.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                if (widget.onSkip != null)
                  OutlinedButton(onPressed: widget.onSkip, child: const Text('Přeskočit')),
                if (err is GeminiOverloadedException && widget.onPickModel != null)
                  OutlinedButton(
                      onPressed: widget.onPickModel, child: const Text('Vybrat jiný model')),
                if (widget.onRetry != null)
                  FilledButton(onPressed: widget.onRetry, child: const Text('Zkusit znovu')),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
