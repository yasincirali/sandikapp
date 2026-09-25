import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Tooltip,
        TooltipTriggerMode,
        Colors,
        Dismissible,
        DismissDirection,
        RefreshIndicator;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../models/watchlist_item.dart';
import '../providers/auth_provider.dart' show activePartnersProvider;
import '../providers/preferences_provider.dart' show watchlistLimitProvider;
import '../providers/watchlist_provider.dart';
import '../services/history_service.dart' show NormalizedSeries;
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/watchlist_chart.dart';
import 'add_asset_screen.dart';
import 'add_watchlist_screen.dart';
import 'watchlist_detail_screen.dart';
import '../l10n/l10n.dart';

/// Takip listesinin GÖVDESİ — dönem seçici · grafik · liste · dipnot.
///
/// ## Neden bir "Screen" değil
/// Giriş noktası Portföy ekranının üstündeki `Varlıklarım | Takip Listesi`
/// segmentidir (bkz. `portfolio_screen.dart`); tam sayfa bir `WatchlistScreen`
/// vardı ama segmentten sonra ona giden hiçbir yol kalmadı ve kaldırıldı.
/// Ulaşılamayan bir route bakım yükünden başka bir şey değildir — bu ekranın
/// kendi geçmişinde de yaşandı (bkz. `leaderboard_screen`'in solo paneli).
///
/// Dosya adı `watchlist_screen.dart` olarak kaldı: takip yüzeyinin tamamı
/// (gövde, satır, grafik kartı, boş durum) burada yaşıyor ve dosyayı
/// adlandıran şey ekran sınıfı değil, o yüzey.
///
/// Dikey alanı sınırlı bir ebeveyn ister (`Expanded` içine konur): içindeki
/// liste kendi kaydırmasını yönetir. Sarmalayan ağaçta bir `Material` ve
/// `ScaffoldMessenger` bulunmalı — satırlar `Dismissible` ve `SnackBar`
/// kullanıyor. Portföy ekranı ikisini de sağlıyor.
///
/// ## Değişmez
/// Buradaki hiçbir değer portföy toplamına, kâr/zarara, tür dökümüne veya
/// grafik serisine girmez. `watchlist` tablosu `assets`'ten ayrıdır.
class WatchlistBody extends ConsumerWidget {
  const WatchlistBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchlistProvider);

    return Column(
      children: [
        const _AddHeader(),
        const SizedBox(height: SandikSpace.sm),
        const _PeriodToggle(),
        const SizedBox(height: SandikSpace.sm),
        Expanded(
          child: async.when(
            loading: () => const CustomLoadingView(),
            error: (e, _) => SandikErrorView(
              error: e,
              onRetry: () => ref.invalidate(watchlistProvider),
            ),
            data: (items) =>
                items.isEmpty ? const _EmptyState() : _List(items: items),
          ),
        ),
        const _FooterNote(),
      ],
    );
  }
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
      padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
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
                minimumSize: SandikTouch.minSize,
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

    return RefreshIndicator(
      color: context.c.amberText,
      onRefresh: () async {
        ref.invalidate(watchlistChartProvider);
        ref.invalidate(watchlistProvider);
        await ref.read(watchlistProvider.future);
      },
      child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 4, SandikSpace.screenH(context), 12),
      // +2: grafik kartı ve sayı başlığı. Ekleme satırı artık listede
      // DEĞİL, gövdenin üstünde (`_AddHeader`).
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
              context.l10n.nAssetsPeriod(items.length, periodLabel),
              style: context.t.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: context.c.text36),
            ),
          );
        }
        return _Row(item: items[i - 2]);
      },
    ),
    );
  }
}

/// Portföy çizgisinin NE olduğunu söyleyen minik bilgi ipucu.
///
/// Çizgi dönemden dönem farklı bir şey gösteriyor (`watchlistChartProvider`):
/// GÜNLÜK'te Performans ekranının günlük grafiğiyle aynı gün içi motor —
/// gerçek değer; 1H ve üstünde `simulate: true` — bugünkü varlıklar dönem
/// başından beri tutulmuş gibi. Kullanıcı bildirimi 2026-09-25: "günlükte
/// gerçek grafiğin aynısı, haftalık/aylıkta simülasyona geçiyor; akıllarda
/// soru işareti kalabilir."
///
/// Eskiden grafiğin altında HER dönemde sabit bir not vardı ("senaryodur,
/// gerçekleşmiş getirin değildir"). İki sorunu vardı: günlükte YANLIŞTI
/// (orada çizgi gerçek) ve her bakışta yer kaplıyordu. Not dönemi bilen bir
/// ipucuna taşındı; simülasyon uyarısı kaybolmadı, dokununca okunuyor.
///
/// Dokunarak açılır (`TooltipTriggerMode.tap`): mobilde uzun basış
/// keşfedilmiyor. Görsel ikon 15pt, dokunma hedefi 44pt (HIG #37).
class _PortfoyCizgisiBilgisi extends StatelessWidget {
  final String portfolioLabel;
  final bool gunIci;
  const _PortfoyCizgisiBilgisi(
      {required this.portfolioLabel, required this.gunIci});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: gunIci
          ? context.l10n.portfolioLineInfoDaily(portfolioLabel)
          : context.l10n.portfolioLineInfoSim(portfolioLabel),
      triggerMode: TooltipTriggerMode.tap,
      // Okuma süresi: iki cümlelik metin varsayılan 1.5 sn'de okunmuyor.
      showDuration: const Duration(seconds: 8),
      preferBelow: true,
      margin: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
      padding: const EdgeInsets.all(SandikSpace.md),
      decoration: BoxDecoration(
        color: context.c.surface2,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      textStyle:
          context.t.bodySmall?.copyWith(color: context.c.text90, height: 1.45),
      child: SizedBox.square(
        dimension: SandikTouch.min,
        child: Align(
          alignment: Alignment.centerRight,
          child: Icon(Icons.info_outline_rounded,
              size: 15, color: context.c.text36),
        ),
      ),
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
            child: Row(
              children: [
                Expanded(
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
                _PortfoyCizgisiBilgisi(
                  portfolioLabel: portfolioLabel,
                  gunIci:
                      watchlistPeriods[ref.watch(watchlistPeriodProvider)].days <=
                          1,
                ),
              ],
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
                  context.l10n.chartLoadFailed,
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
                      context.l10n.notEnoughPriceHistory,
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
                    periodDays:
                        watchlistPeriods[ref.watch(watchlistPeriodProvider)]
                            .days,
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
        : context.signColor(pct);

    final fmt = tryFormatter(
        digits: 2,
        symbol: currencySymbolFor(item.ticker, item.currency) ?? '₺');

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
            semanticLabel: context.l10n.openDetailSemantics(item.name),
            onTap: () => pushGuarded(
              context,
              adaptiveRoute<void>(builder: (_) => WatchlistDetailScreen(item: item)),
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
                    semanticLabel: context.l10n.addToPortfolioSemantics(item.displayLabel),
                    onTap: () => pushGuarded(
                      context,
                      adaptiveRoute<void>(
                        builder: (_) => AddAssetScreen(
                          prefillTicker: item.ticker,
                          prefillName: item.name,
                          prefillType: item.type,
                        ),
                      ),
                    ),
                    // 44×44 HIG dokunma hedefi; ikon küçük kalır, dolgu
                    // şeffaftır (bkz. `touch_target_size_test`).
                    child: SizedBox(
                      width: 44,
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

  /// Takipten çıkarır.
  ///
  /// ## Neden "Geri al" toast'ı YOK (kullanıcı kararı, 2026-09-16)
  ///
  /// Önceden "… takipten çıkarıldı" + "Geri al" toast'ı çıkıyordu; kullanıcı
  /// bunu gereksiz buldu. Takibe geri alma ucuz: satır listede kayboluyor,
  /// yanlışlıkla çıkarılan sembol arama ekranından tek dokunuşla geri
  /// eklenebiliyor (silme gibi geçmiş kaybı yok — takip listesi yalnızca bir
  /// sembol kümesi). BAŞARISIZLIK yolu toast'ını KORUR: orada satır sessizce
  /// geri gelir ve bu hata gibi görünür.
  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(watchlistProvider.notifier);
    try {
      await notifier.remove(item.id);
    } catch (_) {
      if (!context.mounted) return;
      // Provider state'i zaten geri aldı; burada SEBEBİ söylüyoruz — satırın
      // sessizce geri gelmesi kullanıcıya hata gibi görünürdü.
      sandikSnack(context, 'Takipten çıkarılamadı. Bağlantını kontrol et.',
          kind: SandikSnackKind.error);
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
            context.l10n.noWatchlistYet,
            textAlign: TextAlign.center,
            style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: context.c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            context.l10n.noWatchlistBody,
            textAlign: TextAlign.center,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          SandikTappable(
            semanticLabel: context.l10n.addToWatchlist,
            onTap: () => pushGuarded(
              context,
              adaptiveRoute<void>(
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
                  context.l10n.whyWatchlistUpper,
                  style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36),
                ),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  context.l10n.whyWatchlistBody,
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

/// Gövdenin ÜSTÜNDEKİ kapasite kartı: "Takipte 5/7", 7 bölmeli şerit ve Ekle.
///
/// Ekleme satırı önce listenin dibindeydi ("sekmede üst bar yok, yol
/// listenin kendisinde olmalı"). Kullanıcı bulgusu (2026-09-25): liste
/// uzadıkça satır kaydırmanın sonunda kalıyor. Gövde bir `Column`; en üst
/// satır kaydırmadan bağımsız, her zaman görünür. Yerleşim geçmişi
/// `watchlist_placement_test`'te.
///
/// Neden şerit (kullanıcı kararı, 2026-09-25 — üç seçenek arasından "C"):
/// iki eşit hap denemesinde sayaç hapı sekme gibi okunuyor ama
/// dokunulmuyordu; Ekle ile seçili sekme aynı amber dolguyu paylaşıyordu.
/// Kart içinde sayaç + bölmeli şerit BİLGİ, dolu Ekle EYLEM: farklı biçim
/// dili, dokunulabilirlik yalan söylemez; şerit limiti okumadan anlatır.
/// Dolunca son bölme `loss` rengine döner ve düğme "Dolu" olur — ama
/// dokunuş sessiz kalmaz, çıkış yolunu söyler ("birini çıkar"). İleride
/// paywall açılınca "limiti artır" düğmesinin doğal yeri burasıdır.
/// Premium'da limit pratik sonsuz: şerit çizilmez, yalnız sayı + Ekle.
class _AddHeader extends ConsumerWidget {
  const _AddHeader();

  void _ekle(BuildContext context) => pushGuarded(
        context,
        adaptiveRoute<void>(
          builder: (_) => const AddWatchlistScreen(),
          fullscreenDialog: true,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final n = ref.watch(watchlistProvider).valueOrNull?.length ?? 0;
    final limit = ref.watch(watchlistLimitProvider);
    final sinirli = limit < (1 << 30);
    final dolu = sinirli && n >= limit;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
      // Ölçüler `ModernTabSelector` ile birebir (kullanıcı, 2026-09-25:
      // "font ve büyüklük uygulama genelindeki kurallara uygun olmalı"):
      // kart 48 pt, iç boşluk 4 pt, düğme 40 pt, metin `bodyMedium`.
      // Üstteki sekme seçici ve alttaki dönem seçiciyle aynı ritim.
      child: Container(
        height: 48,
        // Dikey iç boşluk YOK: düğmenin dokunma alanı kartın tam
        // yüksekliği (48 pt ≥ HIG 44), görsel 40 pt kutu kendi içinde
        // 4 pt pay bırakır. Sol 16 pt = segment seçicinin metin girintisi.
        padding: const EdgeInsets.only(left: SandikSpace.md, right: SandikSpace.xs),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: sinirli
                    ? context.l10n.watchlistCountOfLimit(n, limit)
                    : '${context.l10n.watchlistInListLabel} $n',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(context.l10n.watchlistInListLabel,
                            style: context.t.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: c.text58)),
                        const Spacer(),
                        Text.rich(
                          TextSpan(
                            text: '$n',
                            style: context.t.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dolu ? c.loss : c.text90),
                            children: [
                              if (sinirli)
                                TextSpan(
                                    text: '/$limit',
                                    style: TextStyle(color: c.text36)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (sinirli) ...[
                      const SizedBox(height: SandikSpace.xs),
                      _KapasiteSeridi(dolu: n, toplam: limit),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.smd),
            SandikTappable(
              semanticLabel: dolu
                  ? context.l10n.watchlistLimitReached(limit)
                  : context.l10n.addToWatchlist,
              onTap: dolu
                  ? () => sandikSnack(
                        context,
                        context.l10n.watchlistLimitReached(limit),
                        kind: SandikSnackKind.warning,
                      )
                  : () => _ekle(context),
              // Dokunma hedefi 48 pt (kartın tamamı); görsel kutu 40 pt,
              // segment düğmesiyle aynı ölçü ve köşe.
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.md),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dolu ? Colors.transparent : c.amberFill,
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      border: dolu ? Border.all(color: c.hairline) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!dolu) ...[
                          Icon(Icons.add_rounded,
                              size: 18, color: c.onStatus),
                          const SizedBox(width: SandikSpace.xs),
                        ],
                        Text(
                          dolu
                              ? context.l10n.watchlistFullShort
                              : context.l10n.watchlistAddShort,
                          style: context.t.bodyMedium?.copyWith(
                              color: dolu ? c.text58 : c.onStatus,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bölmeli kapasite şeridi: [toplam] bölme, ilk [dolu] tanesi amber.
///
/// Her varlık bir bölme — yüzde çubuğu değil: "7'de 5" sayılabilir olmalı.
/// Liste dolunca son bölme `loss` rengine döner; sınır aşımı yok ama
/// "yer kalmadı" rengiyle söylenir. Yalnızca çizim; anlamı üstteki
/// `Semantics` etiketi taşır (`excludeSemantics`), ekran okuyucu 7 kutu
/// saymaz.
class _KapasiteSeridi extends StatelessWidget {
  const _KapasiteSeridi({required this.dolu, required this.toplam});

  final int dolu;
  final int toplam;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tamamen = dolu >= toplam;
    return SizedBox(
      height: SandikSpace.xs2,
      child: Row(
        children: [
          for (var i = 0; i < toplam; i++) ...[
            if (i > 0) const SizedBox(width: SandikSpace.xxs),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Boş bölme `surface2` idi: `surface1` kart üstünde
                  // kayboluyordu (ekran görüntüsü). Zeminden ayrışan ama
                  // amberle yarışmayan ton.
                  color: i < dolu
                      ? (tamamen && i == toplam - 1 ? c.loss : c.amberFill)
                      : c.text36.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(SandikSpace.xxs),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 4, SandikSpace.screenH(context), 12),
        child: Text(
          context.l10n.notInPortfolioNote,
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
