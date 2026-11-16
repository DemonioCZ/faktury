import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';

bool isPdfBytes(Uint8List b) =>
    b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46; // %PDF

/// Náhled skenu v detailu dokladu (první strana PDF nebo fotka).
class ScanPreview extends StatelessWidget {
  const ScanPreview({super.key, required this.receipt, required this.height, this.onSideBySide});
  final Receipt receipt;
  final double height;

  /// Když je zadané, zobrazí se tlačítko „Na výšku okna“ (sken vedle údajů).
  final VoidCallback? onSideBySide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.read<AppState>();
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: height,
            width: double.infinity,
            color: cs.surfaceContainerHighest,
            child: child,
          ),
        );

    if (receipt.fileId.isEmpty) {
      return frame(Center(
        child: Text('K dokladu není připojený sken.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ));
    }

    return FutureBuilder<Uint8List>(
      future: s.scanBytes(receipt.fileId),
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sken se nepodařilo načíst.\n${snap.error}',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            ),
          );
        } else if (!snap.hasData) {
          body = const Center(child: CircularProgressIndicator());
        } else {
          final bytes = snap.data!;
          body = isPdfBytes(bytes)
              ? PdfDocumentViewBuilder(
                  documentRef:
                      PdfDocumentRefData(bytes, sourceName: 'nahled-${receipt.fileId}'),
                  builder: (context, doc) => doc == null
                      ? const Center(child: CircularProgressIndicator())
                      : PdfPageView(document: doc, pageNumber: 1, alignment: Alignment.topCenter),
                )
              : Image.memory(bytes, fit: BoxFit.cover, alignment: Alignment.topCenter);
        }
        return InkWell(
          onTap: () => openScanViewer(context, receipt),
          child: Stack(children: [
            frame(body),
            Positioned(
              right: 12,
              bottom: 12,
              child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                if (onSideBySide != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: cs.inverseSurface, foregroundColor: cs.onInverseSurface),
                    onPressed: onSideBySide,
                    icon: const Icon(Icons.vertical_split_outlined),
                    label: const Text('Na výšku okna'),
                  ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: cs.inverseSurface, foregroundColor: cs.onInverseSurface),
                  onPressed: () => openScanViewer(context, receipt),
                  icon: const Icon(Icons.zoom_out_map),
                  label: const Text('Zobrazit sken'),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Sken na celou výšku okna s ovládáním zoomu (pro režim vedle údajů na Macu).
class ScanPanel extends StatefulWidget {
  const ScanPanel({super.key, required this.receipt, this.onClose});
  final Receipt receipt;
  final VoidCallback? onClose;

  @override
  State<ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends State<ScanPanel> {
  final _pdf = PdfViewerController();
  final _img = TransformationController();
  bool? _isPdf;

  void _zoom(double factor) {
    if (_isPdf == true) {
      factor > 1 ? _pdf.zoomUp() : _pdf.zoomDown();
    } else {
      final m = _img.value.clone();
      final cur = m.getMaxScaleOnAxis();
      final next = (cur * factor).clamp(0.5, 8.0);
      final size = context.size ?? const Size(800, 800);
      final c = Offset(size.width / 2, size.height / 2);
      final s = next / cur;
      m
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..scaleByDouble(s, s, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
      _img.value = m;
    }
  }

  void _reset() {
    if (_isPdf == true) {
      _pdf.setZoom(Offset.zero, 1);
    } else {
      _img.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final r = widget.receipt;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(children: [
        Material(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              const SizedBox(width: 8),
              Text('Sken', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(tooltip: 'Zmenšit', onPressed: () => _zoom(1 / 1.25), icon: const Icon(Icons.remove)),
              IconButton(tooltip: 'Přizpůsobit', onPressed: _reset, icon: const Icon(Icons.fit_screen_outlined)),
              IconButton(tooltip: 'Zvětšit', onPressed: () => _zoom(1.25), icon: const Icon(Icons.add)),
              IconButton(
                tooltip: 'Otevřít na Google Disku',
                onPressed: () =>
                    launchUrl(Uri.parse(r.scanLink), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
              ),
              if (widget.onClose != null)
                IconButton(tooltip: 'Zavřít', onPressed: widget.onClose, icon: const Icon(Icons.close)),
            ]),
          ),
        ),
        Expanded(
          child: r.fileId.isEmpty
              ? Center(child: Text('K dokladu není připojený sken.',
                  style: TextStyle(color: cs.onSurfaceVariant)))
              : FutureBuilder<Uint8List>(
                  future: s.scanBytes(r.fileId),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Sken se nepodařilo načíst: ${snap.error}'));
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final bytes = snap.data!;
                    _isPdf = isPdfBytes(bytes);
                    if (_isPdf!) {
                      return PdfViewer.data(bytes,
                          sourceName: 'panel-${r.fileId}', controller: _pdf);
                    }
                    return InteractiveViewer(
                      transformationController: _img,
                      minScale: 0.5,
                      maxScale: 8,
                      child: SizedBox.expand(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

void openScanViewer(BuildContext context, Receipt r) {
  if (r.fileId.isEmpty) {
    if (r.scanLink.isNotEmpty) {
      launchUrl(Uri.parse(r.scanLink), mode: LaunchMode.externalApplication);
    }
    return;
  }
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => ScanViewerPage(receipt: r)));
}

/// Celoobrazovkový prohlížeč skenu se zoomem.
class ScanViewerPage extends StatelessWidget {
  const ScanViewerPage({super.key, required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.product, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Otevřít na Google Disku',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.parse(receipt.scanLink),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: s.scanBytes(receipt.fileId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Sken se nepodařilo načíst: ${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final bytes = snap.data!;
          if (isPdfBytes(bytes)) {
            return PdfViewer.data(bytes, sourceName: 'sken-${receipt.fileId}');
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.memory(bytes)),
          );
        },
      ),
    );
  }
}
