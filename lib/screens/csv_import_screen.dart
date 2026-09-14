import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bulk_cart_provider.dart';
import '../services/csv_import_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_app_bar.dart';

/// CSV/TSV yapıştır → önizle → sepete ekle.
///
/// Sepete ekler, KAYDETMEZ: kullanıcı toplu ekleme ekranında satırları
/// düzeltip tek seferde kaydeder (fiyatı boş satırların kapanışı orada
/// çekilir). `true` ile döner — çağıran sepeti tazeler.
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  final _ctrl = TextEditingController();
  CsvImportResult? _result;

  static const _ornek = 'Sembol;Adet;Fiyat;Tarih\n'
      'THYAO;100;312,40;05.03.2026\n'
      'TCD;250;;10.01.2026\n'
      'USD;500;32,10;';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _parse() {
    setState(() => _result = CsvImportService.parse(_ctrl.text));
  }

  void _addToCart() {
    final r = _result;
    if (r == null || r.isEmpty) return;
    final cart = ref.read(bulkCartProvider.notifier);
    for (final row in r.rows) {
      cart.add(row);
    }
    sandikSnack(context, '${r.rows.length} satır sepete eklendi',
        kind: SandikSnackKind.success);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _result;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const SandikAppBar(title: 'CSV ile içe aktar'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Aracı kurum ekstresini ya da Excel tablosunu kopyalayıp '
              'yapıştır. Başlık satırı olsun; sütun sırası önemli değil.',
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.sm),
            Container(
              padding: const EdgeInsets.all(SandikSpace.sm),
              decoration: context.surfaceCard(),
              child: Text(
                _ornek,
                style: context.t.bodySmall?.copyWith(
                  color: c.text58,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            TextField(
              controller: _ctrl,
              minLines: 6,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: context.t.bodyMedium?.copyWith(
                color: c.text90,
                fontFamily: 'monospace',
              ),
              decoration: context.inputDecoration('Buraya yapıştır'),
              onChanged: (_) {
                if (_result != null) setState(() => _result = null);
              },
            ),
            const SizedBox(height: SandikSpace.md),
            FilledButton.icon(
              onPressed: _ctrl.text.trim().isEmpty ? null : _parse,
              icon: const Icon(Icons.preview_rounded),
              label: const Text('Önizle'),
            ),
            if (r != null) ...[
              const SizedBox(height: SandikSpace.lg),
              Text(
                '${r.rows.length} satır okundu'
                '${r.errors.isEmpty ? '' : ', ${r.errors.length} satır atlandı'}',
                style: context.t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.text90,
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              for (final row in r.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xs),
                  child: Row(
                    children: [
                      Icon(row.type.icon, size: 16, color: row.type.color),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          '${row.ticker} · ${fmtNumFlex(row.quantity)} '
                          '${row.unitType == 'piece' ? 'adet' : row.unitType}'
                          ' · ${row.price > 0 ? '${fmtNumFlex(row.price)} ${row.currency}' : 'kapanış çekilecek'}',
                          style: context.t.bodySmall?.copyWith(color: c.text90),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final e in r.errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xs),
                  child: Text(e,
                      style: context.t.bodySmall?.copyWith(color: c.loss)),
                ),
              const SizedBox(height: SandikSpace.md),
              FilledButton.icon(
                onPressed: r.isEmpty ? null : _addToCart,
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text('Sepete ekle (${r.rows.length})'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
