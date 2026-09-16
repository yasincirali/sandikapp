import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bulk_cart_provider.dart';
import '../services/csv_import_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_app_bar.dart';
import '../l10n/l10n.dart';

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
    // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): ekran kapanıp toplu
    // ekleme sepetine dönülüyor, satırlar orada listeleniyor. Sayıyı ayrıca
    // söylemek aynı bilgiyi iki kez veriyordu.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _result;
    return Scaffold(
      backgroundColor: c.background,
      appBar: SandikAppBar(title: context.l10n.csvImportTitle),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 32),
          children: [
            Text(
              context.l10n.csvImportBody,
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
              decoration: context.inputDecoration(context.l10n.pasteHere),
              // HER değişimde setState — koşulsuz.
              //
              // **Ölçülen arıza (kullanıcı bildirimi, 2026-09-16):** metin
              // yapıştırıldığı hâlde "Önizle" pasif kalıyordu. Koşul
              // `_result != null` idi; ilk yazışta `_result` zaten null
              // olduğu için setState HİÇ çağrılmıyor, ekran yeniden
              // çizilmiyor ve buton `_ctrl.text` BOŞKEN hesaplanmış
              // `onPressed: null` hâliyle kalıyordu. Kullanıcı ancak başka
              // bir şey rebuild tetiklerse (kaydırma, odak değişimi)
              // butonu açabiliyordu.
              //
              // Buton `_ctrl.text`'i doğrudan okuyor, yani metnin her
              // değişimi bir rebuild gerektiriyor. Eski önizlemeyi temizleme
              // işi koşullu kalabilir ama setState kalamaz.
              onChanged: (_) {
                setState(() {
                  // Metin değişti: önceki önizleme artık o metne ait değil.
                  if (_result != null) _result = null;
                });
              },
            ),
            const SizedBox(height: SandikSpace.md),
            FilledButton.icon(
              onPressed: _ctrl.text.trim().isEmpty ? null : _parse,
              icon: const Icon(Icons.preview_rounded),
              label: Text(context.l10n.preview),
            ),
            if (r != null) ...[
              const SizedBox(height: SandikSpace.lg),
              Text(
                '${context.l10n.csvRowsRead(r.rows.length)}'
                '${r.errors.isEmpty ? '' : context.l10n.csvRowsSkipped(r.errors.length)}',
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
                      Icon(row.type.icon,
                          size: 16, color: row.type.onSurface(context)),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          '${row.ticker} · ${fmtNumFlex(row.quantity)} '
                          '${row.unitType == 'piece' ? context.l10n.unitPiece : row.unitType}'
                          ' · ${row.price > 0 ? '${fmtNumFlex(row.price)} ${row.currency}' : context.l10n.closePriceWillBeFetched}',
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
