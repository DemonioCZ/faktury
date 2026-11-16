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
  const ScanPreview({super.key, required this.receipt, required this.height});
  final Receipt receipt;
  final double height;

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
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: cs.inverseSurface, foregroundColor: cs.onInverseSurface),
                onPressed: () => openScanViewer(context, receipt),
                icon: const Icon(Icons.zoom_out_map),
                label: const Text('Zobrazit sken'),
              ),
            ),
          ]),
        );
      },
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
