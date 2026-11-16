import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import 'scan_view.dart';
import 'widgets.dart';

Future<bool?> openEditor(BuildContext context, Receipt r, {String title = 'Upravit doklad'}) {
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => EditPage(receipt: r.copy(), title: title)),
  );
}

/// Formulář pro úpravu nebo kontrolu vytěženého dokladu.
class EditPage extends StatefulWidget {
  const EditPage({
    super.key,
    required this.receipt,
    required this.title,
    this.saveLabel = 'Uložit',
    this.onSkip,
    this.onSaved,
  });
  final Receipt receipt;
  final String title;
  final String saveLabel;
  final VoidCallback? onSkip;

  /// Když je zadané, po uložení se zavolá místo zavření stránky.
  final VoidCallback? onSaved;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final Receipt r = widget.receipt;
  late final _product = TextEditingController(text: r.product);
  late final _seller = TextEditingController(text: r.seller);
  late final _price = TextEditingController(text: r.price?.toString() ?? '');
  late final _doc = TextEditingController(text: r.docNumber);
  late final _note = TextEditingController(text: r.note);
  late final _warranty = TextEditingController(text: '${r.warrantyMonths}');
  final _form = GlobalKey<FormState>();

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: r.date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => r.date = d);
  }

  Future<void> _newCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nová kategorie'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'např. Zahrada, Nářadí'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Přidat')),
        ],
      ),
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty || !mounted) return;
    await context.read<AppState>().addCategory(n);
    setState(() => r.category = n);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    r
      ..product = _product.text.trim()
      ..seller = _seller.text.trim()
      ..price = num.tryParse(_price.text.replaceAll(' ', '').replaceAll(',', '.'))
      ..docNumber = _doc.text.trim()
      ..note = _note.text.trim()
      ..warrantyMonths = int.tryParse(_warranty.text.trim()) ?? defaultWarrantyMonths;
    if (r.filledBy.isEmpty) r.filledBy = 'ručně';
    final ok = await context.read<AppState>().save(r);
    if (!ok || !mounted) return;
    if (widget.onSaved != null) {
      widget.onSaved!();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final cats = {...s.categories, if (r.category.isNotEmpty) r.category}.toList();
    final ai = r.filledBy == 'AI';

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          suffixIcon: ai
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('AI',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                )
              : null,
        );

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (r.scanLink.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => openScanViewer(context, r),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Zobrazit sken'),
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _product,
            decoration: deco('Produkt'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Vyplňte název' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _seller, decoration: deco('Prodejce')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: deco('Datum nákupu'),
                  child: Text(dateCz(r.date)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco('Cena (Kč)'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(r.category),
                initialValue: r.category.isEmpty ? null : r.category,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: [
                  for (final c in cats) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => r.category = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Přidat novou kategorii',
              onPressed: _newCategory,
              icon: const Icon(Icons.add),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _doc, decoration: deco('Číslo dokladu'))),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: TextFormField(
                controller: _warranty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Záruka (měs.)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          if ((int.tryParse(_warranty.text) ?? 24) > defaultWarrantyMonths)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.verified_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text('Prodloužená záruka', style: TextStyle(color: cs.primary)),
              ]),
            ),
          const SizedBox(height: 12),
          TextFormField(controller: _note, maxLines: 3, minLines: 1, decoration: deco('Poznámka')),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(s.error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 20),
          Row(children: [
            if (widget.onSkip != null) ...[
              Expanded(
                child: OutlinedButton(onPressed: widget.onSkip, child: const Text('Přeskočit')),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: s.loading ? null : _save,
                child: s.loading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.saveLabel),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
