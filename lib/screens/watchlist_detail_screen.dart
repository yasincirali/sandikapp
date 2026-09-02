import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Icons, Material, Colors, ScaffoldMessenger, SnackBar, SnackBarBehavior;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../models/watchlist_item.dart';
import '../providers/watchlist_provider.dart';
import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/asset_sparkline.dart';
import '../widgets/custom_loading_indicator.dart';
import 'performance_screen.dart' show TechnicalSignalPanel;

/// Takip edilen bir varlığın detay ekranı — fiyat + teknik göstergeler.
///
/// ## Neden `PerformanceScreen` kullanılmıyor
/// `PerformanceScreen` yapısal olarak bir SAHİPLİK ekranıdır; gösterdiği her
/// sayı miktara ya da maliyete bağlıdır:
///   · grafiğin Y ekseni `pozisyon değeri / quantity` (birim fiyata BÖLEREK),
///   · maliyet çizgisi `purchasePrice × purchaseFxRate`,
///   · seri `addedDate`'te başlar,
///   · "TOPLAM MİKTAR" şeridi, kâr/zarar özeti, ortak sekmeleri, silme menüsü.
///
/// Oraya bir `watchOnly` bayrağı eklemek, ekranı beslemek için sahte bir
/// `Asset` üretmeyi gerektirirdi (`quantity: 1, purchasePrice: dönem başı`).
/// O nesne GERÇEK bir `Asset` olurdu — `aggregatePositions`'a geçebilir,
/// bir toplama sızabilirdi. `watchlist_isolation_test.dart` tam olarak bunu
/// engellemek için var: koruma derleme zamanında, çalışma zamanında değil.
///
/// Bu yüzden ayrı ekran. Sahipliğe bağlı OLMAYAN parçalar paylaşılıyor:
/// fiyat serisi (`getSymbolHistory`), teknik gösterge paneli
/// ([TechnicalSignalPanel]) ve sparkline çizimi ([SparklineChart]).
///
/// ## Değişmez
/// Buradaki hiçbir değer portföy toplamına girmez.
class WatchlistDetailScreen extends ConsumerStatefulWidget {
  final WatchlistItem item;
  const WatchlistDetailScreen({super.key, required this.item});

  @override
  ConsumerState<WatchlistDetailScreen> createState() =>
      _WatchlistDetailScreenState();
}

class _WatchlistDetailScreenState extends ConsumerState<WatchlistDetailScreen> {
  /// Seçili dönem — listedeki seçimle AYNI provider'dan başlar, sonra bu
  /// ekranda bağımsız değişir. Listeye dönünce oradaki seçim korunur.
  late int _periodIdx = ref.read(watchlistPeriodProvider);

  Future<Map<int, double>>? _future;
  int? _loadedFor;

  /// Fiyat serisi — liste satırıyla AYNI kaynak (`getSymbolHistory`).
  /// İki ayrı kaynak kullanmak bu projede tekrar eden hata sınıfı: üst kart
  /// ile dökümün ayrışması buradan çıkmıştı.
  Future<Map<int, double>> _load() {
    if (_loadedFor == _periodIdx && _future != null) return _future!;
    _loadedFor = _periodIdx;
    _future = HistoryService.instance.getSymbolHistory(
      widget.item.ticker,
      periodDays: watchlistPeriods[_periodIdx].days,
    );
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return DefaultTextStyle(
      style: GoogleFonts.dmSans(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      _PeriodToggle(
                        selected: _periodIdx,
                        onChanged: (i) => setState(() => _periodIdx = i),
                      ),
                      const SizedBox(height: SandikSpace.md),
                      FutureBuilder<Map<int, double>>(
                        future: _load(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                                height: 220, child: CustomLoadingView());
                          }
                          final map = snap.data ?? const <int, double>{};
                          if (map.length < 2) return const _NoData();
                          return _PriceCard(
                            item: item,
                            series: map,
                            periodLabel: watchlistPeriods[_periodIdx].label,
                          );
                        },
                      ),
                      const SizedBox(height: SandikSpace.lg),
                      // Takip listesinin ASIL değeri burada: sahip olmadığın
                      // varlık için de teknik göstergeler hesaplanır. Panel bir
                      // `Asset` istemiyor (bkz. `TechnicalSignalPanel`).
                      if (item.type != AssetType.mevduat)
                        TechnicalSignalPanel(
                          ticker: item.ticker,
                          type: item.type,
                          subCategory: item.subCategory,
                        ),
                      const SizedBox(height: SandikSpace.lg),
                      const _FooterNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 44,
              child: CupertinoButton(
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: context.c.text90),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  Text(
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text36, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RemoveButton(item: widget.item),
          ],
        ),
      );
}

/// Takipten çıkarma — yıkıcı eylem, onay ister.
///
/// HIG "forgiveness": yıkıcı eylem ya geri alınabilir olmalı ya da onay
/// istemeli. Liste tarafında kaydırma + geri alma var; burada tek dokunuş
/// olduğu için onay soruluyor.
class _RemoveButton extends ConsumerWidget {
  final WatchlistItem item;
  const _RemoveButton({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SandikTappable(
      semanticLabel: 'Takipten çıkar',
      onTap: () async {
        final onay = await showCupertinoDialog<bool>(
          context: context,
          builder: (dlg) => CupertinoAlertDialog(
            title: const Text('Takipten çıkar'),
            content:
                Text('${item.displayLabel} takip listenden kaldırılsın mı?'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dlg, false),
                child: const Text('Vazgeç'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(dlg, true),
                child: const Text('Çıkar'),
              ),
            ],
          ),
        );
        if (onay != true || !context.mounted) return;

        try {
          await ref.read(watchlistProvider.notifier).remove(item.id);
          if (context.mounted) Navigator.pop(context);
        } catch (_) {
          if (!context.mounted) return;
          // Provider state'i geri aldı; sebebi söylemek gerekiyor — satırın
          // sessizce kalması kullanıcıya "çalışmadı" hissi verirdi.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('Takipten çıkarılamadı. Bağlantını kontrol et.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: context.c.loss,
            ),
          );
        }
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.visibility_off_outlined,
            size: 20, color: context.c.text58),
      ),
    );
  }
}

/// Dönem seçici — `watchlist_screen.dart` ve `portfolio_performance_screen`
/// ile aynı dil. Durumu bu ekran taşıyor (liste seçimini değiştirmesin).
class _PeriodToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _PeriodToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(watchlistPeriods.length, (i) {
          final isSelected = selected == i;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () {
                if (isSelected) return;
                SandikHaptic.selection.perform();
                onChanged(i);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    watchlistPeriods[i].label,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSelected ? context.c.amberText : context.c.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Fiyat + dönem değişimi + eğri.
///
/// Formül ekranın geri kalanıyla AYNI: yüzde `(son − ilk) / ilk`, tutar
/// `son − ilk`. Burada "tutar" birim fiyat farkıdır — miktar bilinmediği için
/// toplam kazanç HESAPLANMAZ ve gösterilmez.
class _PriceCard extends StatelessWidget {
  final WatchlistItem item;
  final Map<int, double> series;
  final String periodLabel;

  const _PriceCard({
    required this.item,
    required this.series,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ts = series.keys.toList()..sort();
    final first = series[ts.first]!;
    final last = series[ts.last]!;
    final diff = last - first;
    final pct = first > 0 ? (diff / first) * 100 : 0.0;

    // Yuvarlanmış yüzde sıfırsa nötr renk — yeşil "kazanç var" yanılgısı
    // yaratır. Ekranın geri kalanıyla aynı kural.
    final isFlat = pct.abs() < 0.005;
    final color = isFlat
        ? context.c.text36
        : (pct >= 0 ? context.c.gain : context.c.loss);

    final fmt = NumberFormat.currency(
        locale: 'tr_TR',
        symbol: currencySymbolFor(item.ticker, item.currency) ?? '₺',
        decimalDigits: 2);

    // 0..1 normalize — çizim katmanı ham fiyatla uğraşmasın.
    final vals = [for (final t in ts) series[t]!];
    var mn = vals.first, mx = vals.first;
    for (final v in vals) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final span = mx - mn;
    final norm = [
      for (final v in vals) span.abs() < 1e-9 ? 0.5 : (v - mn) / span
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GÜNCEL FİYAT',
            style: context.t.labelSmall?.copyWith(
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: context.c.text36),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmt.format(last),
              maxLines: 1,
              style: context.t.numLarge.copyWith(
                  color: context.c.text90,
                  fontSize: 28,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Row(
            children: [
              Icon(
                isFlat
                    ? Icons.remove_rounded
                    : (pct >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded),
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isFlat
                        ? '$periodLabel · değişim yok'
                        : '${pct >= 0 ? '+' : '−'}${fmtPct(pct.abs())} · '
                            '${diff >= 0 ? '+' : '−'}${fmt.format(diff.abs())} · '
                            '$periodLabel',
                    maxLines: 1,
                    style:
                        context.t.numSmall.copyWith(color: color, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
          // Eğri sayının yönünü GÖRSEL olarak tekrarlar; rengi aynı kaynaktan
          // gelir, yani yazı kırmızıyken eğri yeşil olamaz.
          LayoutBuilder(
            builder: (context, c) => SparklineChart(
              series: norm,
              color: isFlat ? context.c.text36 : color,
              width: c.maxWidth,
              height: 64,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // Birim fiyat farkı olduğu bilgisi AÇIKÇA yazılır — kullanıcı
            // bunu "kazancım" sanmasın; miktarı yok.
            'Değişim birim fiyat farkıdır — bu varlığa sahip değilsin.',
            style: context.t.bodySmall
                ?.copyWith(color: context.c.text36, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: context.c.text36),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bu varlık için yeterli fiyat geçmişi yok.',
                style: context.t.bodySmall?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) => Text(
        'Bu varlık portföyüne dahil değildir.',
        textAlign: TextAlign.center,
        style: context.t.bodySmall
            ?.copyWith(color: context.c.text36, fontSize: 11),
      );
}

/// Ekranda gösterilecek kısa etiket — `watchlist_screen.dart`'takiyle aynı
/// kural (kaynak önekleri kullanıcıya bir şey ifade etmez).
extension on WatchlistItem {
  String get displayLabel {
    final t = ticker.trim();
    if (t.isNotEmpty) {
      final sade =
          t.contains(':') ? t.split(':').last : t.replaceAll('.IS', '');
      if (sade.length >= 2) return sade;
    }
    final sub = subCategory?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    return name;
  }
}
