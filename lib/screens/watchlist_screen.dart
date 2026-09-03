import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Material,
        Colors,
        Dismissible,
        DismissDirection,
        ScaffoldMessenger,
        SnackBar,
        SnackBarAction,
        SnackBarBehavior;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../models/watchlist_item.dart';
import '../providers/auth_provider.dart' show activePartnersProvider;
import '../providers/watchlist_provider.dart';
import '../services/history_service.dart' show NormalizedSeries;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/watchlist_chart.dart';
import 'add_asset_screen.dart';
import 'add_watchlist_screen.dart';
import 'watchlist_detail_screen.dart';

/// Takip listesi — sahip OLMADIĞIN, yalnızca izlediğin varlıklar.
///
/// ## Neden kendi sayfası (Ana ekranda segment değil)
/// Ana ekranda zaten beş katman var: hero özet · ortak seçici · tür çipleri ·
/// varlık listesi · hareketler. Oraya bir segment daha koymak ÜÇÜNCÜ yatay
/// seçici olurdu. Dahası mantık çakışırdı: ortak seçici aynı verinin
/// filtresidir, takip listesi ise FARKLI bir veri kümesi — ikisini üst üste
/// koymak "hangi seçici neyi filtreliyor" sorusunu doğurur.
///
/// Bunun yerine üst barda bir ikon (çan deseninin aynısı) ve tam sayfa.
/// Ana ekran hiç değişmez.
///
/// ## Değişmez
/// Buradaki hiçbir değer portföy toplamına, kâr/zarara, tür dökümüne veya
/// grafik serisine girmez. `watchlist` tablosu `assets`'ten ayrıdır.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchlistProvider);

    return DefaultTextStyle(
      style: GoogleFonts.dmSans(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        // Material: SnackBar ve InkWell'in çalışabilmesi için (Cupertino
        // scaffold tek başına ScaffoldMessenger sağlamaz).
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                _header(context),
                const _PeriodToggle(),
                const SizedBox(height: SandikSpace.sm),
                Expanded(
                  child: async.when(
                    loading: () => const CustomLoadingView(),
                    error: (e, _) => SandikErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(watchlistProvider),
                    ),
                    data: (items) => items.isEmpty
                        ? const _EmptyState()
                        : _List(items: items),
                  ),
                ),
                const _FooterNote(),
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
              // Ölçek içi (`SandikSpace`); dokunma hedefi `height: 44`.
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
              child: Text(
                'Takip Listesi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: context.c.text90),
              ),
            ),
            SandikTappable(
              semanticLabel: 'Takibe varlık ekle',
              onTap: () => pushGuarded(
                context,
                adaptiveRoute(
                  builder: (_) => const AddWatchlistScreen(),
                  fullscreenDialog: true,
                ),
              ),
              // 44pt dokunma hedefi.
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.add_rounded,
                    size: 24, color: context.c.amberText),
              ),
            ),
          ],
        ),
      );
}

/// Dönem seçici — `portfolio_performance_screen.dart`'taki `_buildPeriodToggle`
/// ile AYNI dil: 44pt yükseklik, `surface1` zemin, seçili olan `surface2`.
///
/// Kullanıcı iki ekranda aynı bileşeni görmeli; farklı bir seçici çizmek
/// "bunlar farklı şeyler mi?" sorusunu doğururdu.
class _PeriodToggle extends ConsumerWidget {
  const _PeriodToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(watchlistPeriodProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
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
                  ref.read(watchlistPeriodProvider.notifier).state = i;
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
      ),
    );
  }
}

class _List extends ConsumerWidget {
  final List<WatchlistItem> items;
  const _List({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodLabel =
        watchlistPeriods[ref.watch(watchlistPeriodProvider)].label;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      // +2: grafik kartı ve sayı başlığı.
      itemCount: items.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: SandikSpace.sm),
      itemBuilder: (context, i) {
        // Grafik listeyle BİRLİKTE kayar (üstte sabit değil): dar ekranda
        // sabit bir grafik, listeye ayrılan alanın yarısını yerdi.
        if (i == 0) return const _ChartCard();
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              '${items.length} VARLIK · $periodLabel',
              style: context.t.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: context.c.text36),
            ),
          );
        }
        return _Row(item: items[i - 2]);
      },
    );
  }
}

/// Karşılaştırma grafiği kartı.
///
/// Serilerin tamamı dönem başı `%0` olacak şekilde normalize edilir
/// (`comparison_screen` ile aynı motor). Kullanıcının portföyü de bir seri
/// olarak çizilir — kıyas noktası odur.
class _ChartCard extends ConsumerWidget {
  const _ChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchlistChartProvider);
    final periodLabel =
        watchlistPeriods[ref.watch(watchlistPeriodProvider)].label;
    final partners = ref.watch(activePartnersProvider);
    final view = ref.watch(watchlistCompareViewProvider);
    final portfolioLabel = _portfolioLabel(view, partners);
    final focused = ref.watch(watchlistFocusProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kıyas seçici — ortak YOKSA hiç çizilmez: tek seçenekli bir
          // seçici karar verecek bir şey sunmaz, yalnızca yer kaplar.
          if (partners.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 10),
              child: ModernTabSelector(
                partners: partners,
                selectedId: view,
                onChanged: (v) =>
                    ref.read(watchlistCompareViewProvider.notifier).state = v,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              // Hangi portföyle kıyaslandığı BAŞLIKTA yazar — kullanıcı
              // grafiğe bakarken seçiciye geri dönmek zorunda kalmasın.
              'DÖNEM BAŞINA GÖRE · $periodLabel · ${portfolioLabel.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: context.c.text36),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          async.when(
            loading: () =>
                const SizedBox(height: 210, child: CustomLoadingView()),
            // Grafik çizilemezse liste KULLANILABİLİR kalmalı — hata ekranı
            // basıp satırları gizlemek orantısız olurdu.
            error: (_, __) => SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Grafik yüklenemedi.',
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ),
            ),
            data: (series) {
              if (series.isEmpty) {
                return SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'Grafik için yeterli fiyat geçmişi yok.',
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text36),
                    ),
                  ),
                );
              }
              // Odaktaki seri artık YOKSA odağı yok say: varlık takipten
              // çıkarılmış ya da yeni dönemde fiyat geçmişi gelmemiş olabilir.
              // Bayat bir anahtar tutulursa TÜM seriler soluk kalır ve grafik
              // sebepsiz sönük görünür.
              final gecerliOdak =
                  (focused != null && series.containsKey(focused))
                      ? focused
                      : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WatchlistChart(
                    series: series,
                    portfolioLabel: portfolioLabel,
                    focused: gecerliOdak,
                    onFocusChanged: (k) =>
                        ref.read(watchlistFocusProvider.notifier).state = k,
                  ),
                  const SizedBox(height: SandikSpace.sm),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: WatchlistChartLegend(
                      series: series,
                      colors: _legendColors(context, series),
                      portfolioLabel: portfolioLabel,
                      focused: gecerliOdak,
                      onFocusChanged: (k) =>
                          ref.read(watchlistFocusProvider.notifier).state = k,
                    ),
                  ),
                  // Portföy çizgisi bir SENARYO; bunu söylememek yanıltıcı
                  // olurdu. Kullanıcı "%12 kazanmışım" diye okumamalı.
                  if (series.containsKey(WatchlistChart.portfolioSeriesKey))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 12, color: context.c.text36),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$portfolioLabel çizgisi, bugünkü varlıklarını '
                              'dönem başından beri tutsaydın senaryosudur — '
                              'gerçekleşmiş getirin değildir.',
                              style: context.t.bodySmall?.copyWith(
                                  color: context.c.text36,
                                  fontSize: 10,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Kıyas çizgisinin adı. `ModernTabSelector` ile AYNI sözleşme:
  /// `null` → Birlikte, `''` → Ben, uuid → o ortak.
  ///
  /// Ortağın adı seçicideki gibi yalnızca İLK ADI — tam ad grafiğin
  /// açıklamasını taşırırdı.
  String _portfolioLabel(String? view, List<AppUser> partners) {
    if (view == null) return 'Birlikte';
    if (view == '') return 'Portföyüm';
    for (final p in partners) {
      if (p.id == view) return p.displayName.split(' ').first;
    }
    // Ortak listeden düşmüş (ortaklık pasifleşti) — seri zaten boş gelir.
    return 'Portföy';
  }

  /// Açıklama renkleri grafikle AYNI kuralı izlemeli — yoksa çizgi mavi,
  /// açıklaması yeşil olurdu.
  Map<String, Color> _legendColors(
      BuildContext context, Map<String, NormalizedSeries> series) {
    final p = context.c;
    final palette = [p.info, p.gain, p.loss, p.text58, p.gold];
    final watchKeys = series.keys
        .where((k) => k != WatchlistChart.portfolioSeriesKey)
        .toList()
      ..sort();
    return {
      for (var i = 0; i < watchKeys.length; i++)
        watchKeys[i]: palette[i % palette.length],
      WatchlistChart.portfolioSeriesKey: p.amberText,
    };
  }
}

class _Row extends ConsumerWidget {
  final WatchlistItem item;
  const _Row({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = item.periodChangePct;
    // Yuvarlanmış yüzde sıfırsa nötr renk — yeşil "kazanç var" yanılgısı
    // yaratır. Ekranın geri kalanıyla aynı kural.
    final isFlat = pct == null || pct.abs() < 0.005;
    final color = isFlat
        ? context.c.text36
        : (pct >= 0 ? context.c.gain : context.c.loss);

    final fmt = NumberFormat.currency(
        locale: 'tr_TR',
        symbol: currencySymbolFor(item.ticker, item.currency) ?? '₺',
        decimalDigits: 2);

    // Ekran okuyucu için tek parça cümle — parçalı okunursa yön bilgisi
    // yalnızca renkte kalırdı.
    final semantic = [
      item.name,
      if (item.currentPrice != null) fmt.format(item.currentPrice),
      if (!isFlat) '${pct >= 0 ? 'artış' : 'düşüş'} ${fmtPct(pct.abs())}',
      'takip ediliyor',
    ].join(', ');

    return Semantics(
      container: true,
      label: semantic,
      child: ExcludeSemantics(
        child: Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              color: context.c.loss,
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
            child: Icon(Icons.delete_outline_rounded,
                color: context.c.onStatus, size: 20),
          ),
          onDismissed: (_) => _remove(context, ref),
          child: SandikTappable(
            semanticLabel: '${item.name} detayını aç',
            onTap: () => pushGuarded(
              context,
              adaptiveRoute(builder: (_) => WatchlistDetailScreen(item: item)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                // KESİKLİ kenarlık yerine düşük opaklıklı amber: Flutter'ın
                // `Border`'ı kesikli çizgi desteklemiyor ve bunun için
                // `CustomPainter` yazmak bu satır için aşırıya kaçardı.
                // Ayrım yine net: portföy satırları dolu `surface1` zeminli,
                // takip satırları saydam + amber kenarlıklı.
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: context.c.amberFill.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: item.type.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text90),
                        ),
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text36, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.currentPrice != null
                                ? fmt.format(item.currentPrice)
                                : '—',
                            maxLines: 1,
                            style: context.t.numSmall.copyWith(
                                color: context.c.text90,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            isFlat
                                ? '—'
                                : '${pct >= 0 ? '+' : '−'}${fmtPct(pct.abs())}',
                            maxLines: 1,
                            style: context.t.numSmall
                                .copyWith(color: color, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // "Portföyüme ekle" — Karşılaştır ekranındaki `_actionRow`
                  // ile aynı eylem, aynı ön doldurma.
                  //
                  // Takip listesinin varlık sebebi "almayı düşündüğüm şey";
                  // almaya karar verince kullanıcıyı arama ekranına geri
                  // gönderip aynı varlığı ikinci kez aratmak gereksizdi.
                  // Al/Sat burada YOK: takip edilen varlık tanımı gereği
                  // portföyde değildir (iki küme yapısal olarak ayrık).
                  SandikTappable(
                    semanticLabel: '${item.displayLabel} portföyüme ekle',
                    onTap: () => Navigator.push(
                      context,
                      adaptiveRoute(
                        builder: (_) => AddAssetScreen(
                          prefillTicker: item.ticker,
                          prefillName: item.name,
                          prefillType: item.type,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 44,
                      child: Icon(Icons.add_circle_outline_rounded,
                          size: 20, color: context.c.amberText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Siler ve GERİ ALMA sunar.
  ///
  /// HIG: yıkıcı kaydırma eylemi geri alma sunmalı. Kullanıcı yanlışlıkla
  /// kaydırdığında kaydı yeniden aramak zorunda kalmamalı.
  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(watchlistProvider.notifier);
    try {
      await notifier.remove(item.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.displayLabel} takipten çıkarıldı'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => notifier.add(item),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      // Provider state'i zaten geri aldı; burada SEBEBİ söylüyoruz — satırın
      // sessizce geri gelmesi kullanıcıya hata gibi görünürdü.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Takipten çıkarılamadı. Bağlantını kontrol et.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.c.loss,
        ),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      child: Column(
        children: [
          Icon(Icons.visibility_outlined, size: 40, color: context.c.text36),
          const SizedBox(height: SandikSpace.md),
          Text(
            'Henüz izlediğin varlık yok',
            textAlign: TextAlign.center,
            style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: context.c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            'Almadan önce takibe al. Fiyatını portföyüne dokunmadan izle.',
            textAlign: TextAlign.center,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          SandikTappable(
            semanticLabel: 'Takibe varlık ekle',
            onTap: () => pushGuarded(
              context,
              adaptiveRoute(
                builder: (_) => const AddWatchlistScreen(),
                fullscreenDialog: true,
              ),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.c.amberFill,
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: Text('Varlık Ekle',
                  style: context.t.titleSmall?.copyWith(
                      color: context.c.onStatus, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: SandikSpace.lg),
          // Değer önerisini AÇIKÇA söyler — kullanıcı özelliği keşfetmek
          // zorunda kalmasın.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: context.c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEDEN TAKİP LİSTESİ?',
                  style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36),
                ),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  'Bir varlığı satın almadan fiyatını izleyebilirsin. '
                  'Takip listesi portföyüne girmez; toplam değerini ve '
                  'kâr/zararını etkilemez.',
                  style: context.t.bodySmall
                      ?.copyWith(color: context.c.text58, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En kritik ayrımı sürekli görünür tutar.
class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Text(
          'Bu varlıklar portföyüne dahil değildir.',
          textAlign: TextAlign.center,
          style: context.t.bodySmall
              ?.copyWith(color: context.c.text36, fontSize: 11),
        ),
      );
}

/// Ekranda gösterilecek kısa etiket: ticker varsa o, yoksa alt kategori.
extension on WatchlistItem {
  String get displayLabel {
    final t = ticker.trim();
    if (t.isNotEmpty) {
      // `TEFAS:AFO` → `AFO`, `AGHOL.IS` → `AGHOL` — kaynak önekleri
      // kullanıcıya hiçbir şey ifade etmez (bkz. `shortLabel`, edge function).
      final sade =
          t.contains(':') ? t.split(':').last : t.replaceAll('.IS', '');
      if (sade.length >= 2) return sade;
    }
    final sub = subCategory?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    return name;
  }
}
