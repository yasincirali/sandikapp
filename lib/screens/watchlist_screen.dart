import 'package:flutter/cupertino.dart';
import '../demo/demo_modu.dart';
import '../widgets/varlik_rozeti.dart';
import '../widgets/sandik_skeleton.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Tooltip,
        TooltipTriggerMode,
        Colors,
        Dismissible,
        DismissDirection,
        Material,
        MaterialType,
        RefreshIndicator;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../models/varlik_kimligi.dart';
import '../models/watchlist_item.dart';
import '../providers/auth_provider.dart'
    show activePartnersProvider, authProvider;
import '../providers/preferences_provider.dart'
    show takipSiralamaProvider, watchlistLimitProvider;
import '../models/yuzde_alarmi.dart';
import '../providers/price_alert_provider.dart' show symbolAlertsProvider;
import '../providers/yuzde_alarmi_provider.dart' show yuzdeAlarmlariProvider;
import '../providers/secili_donem_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/history_service.dart' show NormalizedSeries;
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../services/fiyat_kaynagi.dart';
import '../services/ozellik_olcumu.dart';
import '../services/takip_sirasi.dart';
import '../widgets/alarm_kur_sheet.dart' show alarmSembolu, yuzdeAlarmEtiketi;
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_siralama_dugmesi.dart';
import '../widgets/sinir_uyarisi.dart';
import '../widgets/sandik_bos_durum.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/donem_secici.dart';
import '../widgets/ortak_secici.dart';
import '../widgets/sandik_cam.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/watchlist_chart.dart';
import 'add_asset_screen.dart';
import 'add_watchlist_screen.dart';
import 'price_alerts_screen.dart';
import 'varlik_sayfasi.dart';
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
    final eskiyiGoster = _eskiVeriyiGoster(ref, async);

    // Cam başlık açıkken (Portföy, `goz_alici`) sabit üst kısım başlığın
    // altında başlar; kapalıyken pay 0, yerleşim birebir.
    return Padding(
      padding: EdgeInsets.only(top: SandikKaydirmaBasligi.ustPay(context)),
      child: Column(
      children: [
        const _AddHeader(),
        const SizedBox(height: SandikSpace.sm),
        const _PeriodToggle(),
        const SizedBox(height: SandikSpace.sm),
        Expanded(
          child: SandikIcerikGecisi(
            // Yükleme → içerik çapraz solar (2026-10-14).
            tamEkran: true,
            anahtar: async.isLoading && !(eskiyiGoster && async.hasValue)
              ? 'yukleniyor'
              : SandikIcerikGecisi.hal([async]),
            child: async.when(
            // Dönem değişiminde eski liste SOLUK kalır, iskelete düşmez
            // (animasyon denetimi 2026-10-01): her dönem dokunuşunda liste
            // ve grafik iskelete dönüp geri geliyor, yerleşim iki kez
            // zıplıyordu. Performans ekranının "eski veri soluk" deseni.
            skipLoadingOnReload: eskiyiGoster,
            // İlk yüklemede iskelet: satırların geleceği yer belli,
            // yerleşim zıplamaz (UX denetimi 2026-09-29).
            loading: () => const SandikSkeletonList(rows: 4),
            error: (e, _) => SandikErrorView(
              error: e,
              onRetry: () => ref.invalidate(watchlistProvider),
            ),
            data: (items) => _SolukBekleme(
              bekliyor: eskiyiGoster,
              child: items.isEmpty ? const _EmptyState() : _List(items: items),
            ),
          ),
          ),
        ),
        const _FooterNote(),
      ],
      ),
    );
  }
}

/// Yeniden yüklenirken önceki veri gösterilebilir mi: yükleme sürüyor,
/// önceki değer var VE o değer hâlâ oturumdaki kullanıcıya ait. Sahip
/// denetimi kullanıcı değişiminde başkasının listesinin bir kare bile
/// görünmemesi içindir (bkz. [WatchlistNotifier.eskiVeriGosterilebilir]).
bool _eskiVeriyiGoster(WidgetRef ref, AsyncValue<Object?> async) {
  if (!async.isLoading || !async.hasValue) return false;
  final uid = ref.watch(authProvider).valueOrNull?.id;
  return ref.read(watchlistProvider.notifier).eskiVeriGosterilebilir(uid);
}

/// Eski veri beklerken soluk — "bu sayılar tazeleniyor" işareti.
///
/// Soluklaşma yalnız bekleme başında/sonunda 180 ms oynar; arada opaklık
/// sabit kaldığı için kare başına maliyet yok.
class _SolukBekleme extends StatelessWidget {
  const _SolukBekleme({required this.bekliyor, required this.child});

  final bool bekliyor;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: bekliyor ? 0.5 : 1,
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        child: IgnorePointer(ignoring: bekliyor, child: child),
      );
}

/// Dönem seçici — ortak [DonemSecici] (tek dönem kümesi ve tek görünüş,
/// 2026-09-28). Eskiden Performans'ın 44pt eşit paylı bir kopyasıydı ve
/// etiketi çevirmeden basıyordu; kopya ilk düzeltmede ayrışmıştı.
class _PeriodToggle extends ConsumerWidget {
  const _PeriodToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
      child: DonemSecici(
        donemler: SummaryPeriod.values,
        secili: ref.watch(watchlistPeriodProvider),
        // Ortak dönem yazılır; `watchlistPeriodProvider` ondan türediği
        // için kendiliğinden izler.
        onSec: (i) => ref.read(seciliDonemProvider.notifier).state =
            SummaryPeriod.values[i],
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
    // Ekrandaki sıra kullanıcının seçimiyle (2026-10-24, `takip_sirasi.dart`):
    // "Benim sıram" varsayılan, fiyat tazelenince satır yer değiştirmez.
    final mod = takipSiralamaOf(ref.watch(takipSiralamaProvider));
    final gorunen =
        ref.watch(siraliTakipListesiProvider).valueOrNull ?? items;
    final benim = mod == TakipSiralama.benim;
    final h = SandikSpace.screenH(context);

    // Satır + alt boşluk. Sürüklenebilir listede ayırıcı yok; boşluk satırın
    // kendi payı ki sürüklenen öğeyle birlikte taşınsın.
    Widget satir(int i) {
      final w = gorunen[i];
      final govde = Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        child: _Row(
          item: w,
          sira: benim ? i : null,
          toplam: gorunen.length,
          tasi: benim
              ? (hedef) => takipSirasiniTasi(ref, gorunen, i, hedef)
              : null,
        ),
      );
      return KeyedSubtree(
        key: ValueKey('takip-sira-${w.id}'),
        // Uzun basıp sürükle: satırın her yeri (tutamaç ayrıca anında).
        child: benim
            ? ReorderableDelayedDragStartListener(index: i, child: govde)
            : govde,
      );
    }

    return RefreshIndicator.adaptive(
      color: context.c.amberText,
      onRefresh: () async {
        ref.invalidate(watchlistChartProvider);
        ref.invalidate(watchlistProvider);
        await ref.read(watchlistProvider.future);
      },
      child: CustomScrollView(
        // Segment geçişinde konum korunur (bkz. Portföy `PageStorageKey`).
        key: const PageStorageKey('portfoy-takip-listesi'),
        // Aynı ekranın Varlıklarım listesiyle AYNI fizik: Android'de biri
        // yaylanıp öteki esniyordu (animasyon denetimi 2026-10-01).
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Grafik listeyle BİRLİKTE kayar (üstte sabit değil): dar ekranda
          // sabit bir grafik, listeye ayrılan alanın yarısını yerdi. Ekleme
          // satırı listede DEĞİL, gövdenin üstünde (`_AddHeader`).
          SliverPadding(
            padding:
                EdgeInsets.fromLTRB(h, SandikSpace.xs, h, SandikSpace.sm),
            sliver: const SliverToBoxAdapter(child: _ChartCard()),
          ),
          // Sayı başlığı + sıralama seçimi (2026-10-24).
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 0, h, SandikSpace.xs),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.nAssetsPeriod(items.length, periodLabel),
                      style: context.t.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: context.c.text36),
                    ),
                  ),
                  _SiralamaDugmesi(secili: mod),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 0, h, SandikSpace.xs),
            sliver: benim
                ? SliverReorderableList(
                    itemCount: gorunen.length,
                    itemBuilder: (_, i) => satir(i),
                    onReorderStart: (_) => SandikHaptic.selection.perform(),
                    // `onReorderItem` hedefi öğe çıkarıldıktan SONRAKİ konum
                    // olarak verir; [siraTasi] da onu ister (eski
                    // `onReorder`'ın −1 düzeltmesi gerekmez).
                    onReorderItem: (eski, yeni) =>
                        takipSirasiniTasi(ref, gorunen, eski, yeni),
                    proxyDecorator: (child, _, anim) =>
                        _SurukleGolgesi(animasyon: anim, child: child),
                  )
                : SliverList.builder(
                    itemCount: gorunen.length,
                    itemBuilder: (_, i) => satir(i),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Sürüklenen satırın görünüşü: zemin + hafif gölge, başka süs yok. Hareketi
/// azalt açıkken gölge animasyonsuz, baştan tam.
class _SurukleGolgesi extends StatelessWidget {
  const _SurukleGolgesi({required this.animasyon, required this.child});

  final Animation<double> animasyon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final azalt = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: animasyon,
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            color: context.c.surface1,
            boxShadow: [
              BoxShadow(
                color: context.c.overlay,
                blurRadius: SandikSpace.md * (azalt ? 1 : animasyon.value),
              ),
            ],
          ),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Takip listesi sıralama seçimi: başlık satırının sağında seçili sıranın
/// adı; dokununca üç seçenekli alt sayfa. Düğme ve sayfa ortak bileşenden
/// (`SandikSiralamaDugmesi.etiketli`, 2026-10-25 — eskiden Portföy'ün
/// `_SortButton`/`_SortSheet` kalıbının kopyasıydı). Kayan segment DEĞİL
/// (kabul raporu 13:15 #2): üç seçenek liste başında yer kaplamasın; seçim
/// ekranın ne gösterdiğini değiştirmez, yalnız sırasını.
class _SiralamaDugmesi extends ConsumerWidget {
  const _SiralamaDugmesi({required this.secili});

  final TakipSiralama secili;

  static String etiket(AppLocalizations l, TakipSiralama m) => switch (m) {
        TakipSiralama.benim => l.watchlistSortMine,
        TakipSiralama.yukselen => l.watchlistSortGainers,
        TakipSiralama.dusen => l.watchlistSortLosers,
      };

  static IconData ikon(TakipSiralama m) => switch (m) {
        TakipSiralama.benim => Icons.drag_indicator_rounded,
        TakipSiralama.yukselen => Icons.trending_up_rounded,
        TakipSiralama.dusen => Icons.trending_down_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SandikSiralamaDugmesi<TakipSiralama>.etiketli(
      secenekler: [
        for (final m in TakipSiralama.values)
          SandikSiralamaSecenegi(
            deger: m,
            baslik: etiket(l, m),
            altBaslik: m == TakipSiralama.benim
                ? l.watchlistSortMineHint
                : l.watchlistSortChangeHint,
            ikon: ikon(m),
          ),
      ],
      secili: secili,
      semantikEtiket: l.watchlistSortSemantics(etiket(l, secili)),
      onSec: (m) {
        ref.read(takipSiralamaProvider.notifier).set(m.index);
        OzellikOlcumu.say(Ozellik.takipSirasi);
      },
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
    final eskiyiGoster = _eskiVeriyiGoster(ref, async);
    final periodLabel =
        watchlistPeriods[ref.watch(watchlistPeriodProvider)].label;
    final partners = ref.watch(activePartnersProvider);
    final view = ref.watch(watchlistCompareViewProvider);
    final portfolioLabel = _portfolioLabel(view, partners);
    final focused = ref.watch(watchlistFocusProvider);

    return SandikCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kıyas seçici — ortak YOKSA hiç çizilmez: tek seçenekli bir
          // seçici karar verecek bir şey sunmaz, yalnızca yer kaplar.
          if (partners.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 10),
              child: OrtakSecici(
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
          SandikIcerikGecisi(
            // Yükleme → içerik çapraz solar (2026-10-14).
            anahtar: async.isLoading && !(eskiyiGoster && async.hasValue)
                ? 'yukleniyor'
                : SandikIcerikGecisi.hal([async]),
            child: async.when(
            // Dönem değişiminde eski grafik soluk kalır ve yenisine MORF
            // eder; iskelete düşüp sıfırdan çizilmez (bkz. `WatchlistBody`).
            skipLoadingOnReload: eskiyiGoster,
            loading: () =>
                const SandikSkeletonChart(height: 210),
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

              // Liste de yeniden yükleniyorsa grafik zaten onun soluk
              // katmanının içinde — ikinci kez soluklaştırmak 0,25'e iner.
              final listeBekliyor = ref.watch(watchlistProvider).isLoading;
              return _SolukBekleme(
                bekliyor: eskiyiGoster && !listeBekliyor,
                child: Column(
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
              ),
              );
            },
          ),
          ),
        ],
      ),
    );
  }

  /// Kıyas çizgisinin adı. `OrtakSecici` ile AYNI sözleşme:
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

  /// "Benim sıram"da satırın konumu; null = sürükleme kapalı (yükselen/düşen).
  final int? sira;
  final int toplam;

  /// Satırı verilen konuma taşı (erişilebilirlik eylemleri); null = kapalı.
  final ValueChanged<int>? tasi;

  const _Row({required this.item, this.sira, this.toplam = 0, this.tasi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = item.periodChangePct;
    // Yuvarlanmış yüzde sıfırsa nötr renk — yeşil "kazanç var" yanılgısı
    // yaratır. Ekranın geri kalanıyla aynı kural.
    final isFlat = pct == null || pct.abs() < 0.005;
    final color = isFlat
        ? context.c.text36
        : context.signColor(pct);

    final fiyatMetni = takipFiyatMetni(item);
    final l10n = context.l10n;

    // Etkin fiyat alarmı (2026-10-26): kurulu ve bekleyen alarm satırda çan
    // + fiyata en yakın hedef olarak görünür; alarm ekranına gitmeden "bu
    // varlığa alarm kurmuş muydum, hangi fiyata" sorusu cevaplanır. Sembol
    // alarm kurarkenki kuralla (`alarmSembolu`) eşlenir; veri zaten
    // yüklenmiş `priceAlertsProvider`'dan — yeni sunucu çağrısı yok.
    // Günlük yüzde alarmı da çanda (2026-10-29, `takipCaniOzeti`): fiyat
    // alarmı yoksa "±%2", varsa "+N" sayısına girer.
    final alarmKodu = alarmSembolu(item.ticker, item.subCategory);
    final alarm = alarmKodu == null
        ? null
        : takipCaniOzeti(
            ref.watch(symbolAlertsProvider(alarmKodu)),
            ref.watch(yuzdeAlarmlariProvider).valueOrNull ??
                const <YuzdeAlarmi>[],
            sembol: alarmKodu,
            guncelFiyat: item.currentPrice);
    final yuzdeAlarm = alarm?.yuzde;
    final yuzdeCaldi = yuzdeAlarm?.bugunCaldi(DateTime.now()) ?? false;
    final hedefMetni = alarm == null
        ? null
        : alarm.fiyat != null
            ? takipFiyatBicimi(item, alarm.fiyat!.targetPrice)
            : yuzdeKisaMetni(yuzdeAlarm!);

    // Ekran okuyucu için tek parça cümle — parçalı okunursa yön bilgisi
    // yalnızca renkte kalırdı.
    final semantic = [
      item.name,
      if (item.currentPrice != null) fiyatMetni,
      if (!isFlat)
        pct >= 0
            ? l10n.watchlistRowUp(fmtPct(pct.abs()))
            : l10n.watchlistRowDown(fmtPct(pct.abs())),
      if (alarm != null)
        [
          if (alarm.fiyat != null)
            l10n.watchlistAlertSet(hedefMetni!)
          else
            l10n.watchlistYuzdeAlarmSet(
                yuzdeAlarmEtiketi(l10n, yuzdeAlarm!.esikPct, yuzdeAlarm.yon)),
          if (yuzdeCaldi) l10n.watchlistYuzdeAlarmCaldi,
          if (alarm.digerSayisi > 0) l10n.watchlistAlertMore(alarm.digerSayisi),
        ].join(' '),
      l10n.watchlistRowFollowing,
    ].join(', ');

    // ## Erişilebilirlik ağacı (emülatör testi #17, 2026-09-29)
    // Önceden bütün satır `Semantics(label) + ExcludeSemantics` ile
    // sarılıydı. `ExcludeSemantics` altındaki HER şeyi siliyordu — metinlerle
    // birlikte satırın dokunma eylemini ve + düğmesini de: TalkBack satırı
    // okuyor ama "clickable=false" görüyor, "Portföyüme ekle"ye hiç
    // ulaşamıyordu.
    //
    // Şimdi: satır TEK bir düğme düğümü (`container` + `button` + cümle
    // etiketi); dokunma eylemi dıştaki `SandikTappable`'ın jestinden bu
    // düğüme katılır (Semantics'e ayrıca `onTap` VERİLMEZ — iki tap eylemi
    // aynı düğümde çakışır ve jest etiketsiz ayrı bir düğüme düşer). Yalnızca
    // görsel metinler `ExcludeSemantics` altında (cümle zaten onları
    // söylüyor); + düğmesi kendi `container` düğümünde, kendi etiketiyle.
    // Kaydırarak silme TalkBack'te çalışmadığı için aynı iş özel eylem
    // olarak da sunulur.
    return Semantics(
      container: true,
      button: true,
      label: semantic,
      // Sürükleme ekran okuyucuda yapılamaz; aynı iş "yukarı/aşağı taşı"
      // eylemleriyle (yalnız "Benim sıram"da, uçta olmayan yönde).
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.removeFromWatchlist): () =>
            _remove(context, ref),
        if (sira != null && tasi != null && sira! > 0)
          CustomSemanticsAction(label: l10n.watchlistMoveUp): () =>
              tasi!(sira! - 1),
        if (sira != null && tasi != null && sira! < toplam - 1)
          CustomSemanticsAction(label: l10n.watchlistMoveDown): () =>
              tasi!(sira! + 1),
      },
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
            // Zemin NE olacağını söyler: "Takipten çıkar". Aynı ekranın
            // Varlıklarım sekmesinde aynı jest bir SİL panelini açıyor (lot
            // silmek geri alınamaz, onay ister); burada iş geri alınabilir
            // (yeniden eklenir) ve onaysızdır. Yalnız çöp kutusu ikonu iki
            // farklı sonucu aynı gösteriyordu (animasyon denetimi 2026-10-01).
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    context.l10n.removeFromWatchlist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelLarge
                        ?.copyWith(color: context.c.onStatus),
                  ),
                ),
                const SizedBox(width: SandikSpace.xs2),
                Icon(Icons.visibility_off_outlined,
                    color: context.c.onStatus, size: 20),
              ],
            ),
          ),
          // Demo modunda yazma engellidir: sağlayıcı satırı listeden
          // DÜŞÜRMEDEN hata fırlatıyordu, kaydırılıp kapatılan satır ağaçta
          // kalıyor ve Flutter "dismissed Dismissible is still part of the
          // tree" hatası veriyordu (animasyon denetimi 2026-10-01). Onay
          // aşamasında durdurulur: satır yerine yaylanır, demo mesajı
          // `yazmaEngeli` dinleyicisinden gelir.
          confirmDismiss: (_) async {
            if (DemoModu.aktif) {
              await _remove(context, ref);
              return false;
            }
            SandikHaptic.medium.perform();
            return true;
          },
          onDismissed: (_) => _remove(context, ref),
          child: SandikTappable(
            // Etiket YOK: satırın adı dıştaki `Semantics` cümlesi; buradaki
            // jest yalnızca dokunma eylemini o düğüme katar.
            // Varlık sayfası TAM hâlde açılır (kullanıcı bu varlığa bakmaya
            // geldi) ve listedeki dönemle başlar. Eski ayrı detay ekranının
            // yerini aldı — iki detay yüzeyi zamanla ayrışırdı.
            onTap: () => showVarlikSayfasi(
              context,
              VarlikKimligi.fromWatchlistItem(item),
              tamAcilis: true,
              baslangicDonemGun:
                  watchlistPeriods[ref.read(watchlistPeriodProvider)].days,
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
                  // Bayrak `goz_alici` açıkken sembol rozeti, kapalıyken
                  // birebir eski tür noktası.
                  VarlikRozeti(type: item.type, ticker: item.ticker),
                  const SizedBox(width: 10),
                  Expanded(
                    child: alarm == null
                        ? ExcludeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _adMetni(context),
                                // Kısa ad zaten görünen adsa (endeks, altın,
                                // emtia) ikinci satır aynı metni tekrar ederdi.
                                if (item.displayLabel != item.name)
                                  _uzunAdMetni(context),
                              ],
                            ),
                          )
                        // Alarmlı satır: çan kendi düğümü olduğundan
                        // `ExcludeSemantics` yalnız metinleri sarar. `Wrap`:
                        // çan ada sığarsa yanında, sığmazsa (dar ekran, büyük
                        // yazı 3.1×) alt satıra iner — ad çan için kısalmaz.
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: SandikSpace.xs,
                                children: [
                                  ExcludeSemantics(child: _adMetni(context)),
                                  _TakipAlarmCani(
                                    sembol: alarmKodu!,
                                    hedefMetni: hedefMetni!,
                                    digerSayisi: alarm.digerSayisi,
                                    bugunCaldi: yuzdeCaldi,
                                  ),
                                ],
                              ),
                              if (item.displayLabel != item.name)
                                ExcludeSemantics(child: _uzunAdMetni(context)),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                  // Expanded (sıkı), Flexible (gevşek) DEĞİL: gevşek hâlde
                  // sütun fiyat metni kadar daralıyor, artan boşluk satırın
                  // SONUNA düşüyordu — + düğmesi fiyatın hemen ardına yapışıp
                  // her satırda başka x'te duruyordu. Sıkı sütun + sağa yaslı
                  // FittedBox ile + her satırda kartın sağ kenarında hizalı.
                  Expanded(
                    child: ExcludeSemantics(
                      child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fiyatMetni,
                            maxLines: 1,
                            style: context.t.numSmall.copyWith(
                                color: context.c.text90,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            isFlat ? '—' : fmtPctIsaretli(pct),
                            maxLines: 1,
                            style: context.t.numSmall
                                .copyWith(color: color, fontSize: 11),
                          ),
                        ],
                      ),
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
                  // Kendi düğümü (`container`): etiketi ve dokunma eylemi
                  // satırın cümlesine karışmaz, TalkBack'te ayrı odaklanır.
                  Semantics(
                    container: true,
                    child: SandikTappable(
                    semanticLabel: context.l10n.addToPortfolioSemantics(item.displayLabel),
                    onTap: () => pushGuarded(
                      context,
                      adaptiveRoute<void>(
                        settings: const RouteSettings(name: 'add_asset'),
                        builder: (_) => AddAssetScreen(
                          prefillTicker: item.ticker,
                          prefillName: item.name,
                          prefillType: item.type,
                          ekleYolu: 'takip',
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
                  ),
                  // Sürükleme tutamacı (yalnız "Benim sıram"): 44 pt, anında
                  // sürükler; satırın kendisi uzun basışla sürüklenir.
                  // Ekran okuyucuda gizli: aynı iş satırın "yukarı/aşağı
                  // taşı" eylemlerinde.
                  if (sira != null)
                    ReorderableDragStartListener(
                      index: sira!,
                      child: ExcludeSemantics(
                        child: SizedBox.square(
                          dimension: SandikTouch.min,
                          child: Icon(Icons.drag_handle_rounded,
                              color: context.c.text36),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _adMetni(BuildContext context) => Text(
        item.displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.bodyMedium?.copyWith(color: context.c.text90),
      );

  Widget _uzunAdMetni(BuildContext context) => Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.bodySmall
            ?.copyWith(color: context.c.text36, fontSize: 11),
      );

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
    } on DemoYazmaEngeli {
      // Demo mesajı `DemoModu.yazmaEngeli` dinleyicisinden gösterildi;
      // "bağlantını kontrol et" burada yanlış olurdu.
      return;
    } catch (_) {
      if (!context.mounted) return;
      // Provider state'i zaten geri aldı; burada SEBEBİ söylüyoruz — satırın
      // sessizce geri gelmesi kullanıcıya hata gibi görünürdü.
      sandikSnack(context, 'Takipten çıkarılamadı. Bağlantını kontrol et.',
          kind: SandikSnackKind.error);
    }
  }
}

/// Takip satırındaki alarm çanı: zil + fiyata en yakın hedef (+N).
///
/// Ayrı dokunma hedefi (≥44 pt, kendi semantik düğümü): satırın dokunuşu
/// varlık sayfasını açar, çanınki o varlığın alarmlarını. Anlam renkte
/// değil: zil ikonu + hedef metni; renk yalnız token (`amberText`, Portföy
/// kartındaki alarm rozetiyle aynı dil).
class _TakipAlarmCani extends StatelessWidget {
  final String sembol;
  final String hedefMetni;
  final int digerSayisi;

  /// Öndeki yüzde alarmı bugün çaldı: zil boş çizgili ve sönük. Anlam
  /// yalnız renkte değil, ikon biçiminde ve satırın cümlesinde de.
  final bool bugunCaldi;

  const _TakipAlarmCani({
    required this.sembol,
    required this.hedefMetni,
    required this.digerSayisi,
    this.bugunCaldi = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final renk = bugunCaldi ? context.c.text36 : context.c.amberText;
    final metin = digerSayisi > 0
        ? '$hedefMetni ${l10n.watchlistAlertExtra(digerSayisi)}'
        : hedefMetni;
    return Semantics(
      container: true,
      child: SandikTappable(
        semanticLabel: l10n.watchlistOpenAlerts,
        onTap: () {
          OzellikOlcumu.say(Ozellik.takipAlarmCani);
          pushGuarded(
            context,
            adaptiveRoute<void>(
              settings: const RouteSettings(name: 'price_alerts'),
              builder: (_) => PriceAlertsScreen(sembol: sembol),
            ),
          );
        },
        // Görsel küçük, dokunma alanı 44×44 (şeffaf dolgu;
        // `touch_target_size_test`).
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    bugunCaldi
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                    size: 14,
                    color: renk),
                const SizedBox(width: SandikSpace.xxs),
                Flexible(
                  child: Text(
                    metin,
                    style: context.t.numSmall.copyWith(color: renk),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Boş takip listesi: başlık, tek cümle açıklama, öneri çipleri, Varlık Ekle.
///
/// "NEDEN TAKİP LİSTESİ?" kutusu kaldırıldı (2026-10-25): `noWatchlistBody`
/// aynı şeyi tek cümlede söylüyordu; boş ekranda iki açıklama okutmak yerine
/// ilk takibi tek dokunuşa indiren üç öneri çipi kondu.
class _EmptyState extends ConsumerStatefulWidget {
  const _EmptyState();

  @override
  ConsumerState<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends ConsumerState<_EmptyState> {
  /// Bu oturumda çipten eklenenler. Liste dolunca boş durum zaten gider;
  /// bu küme sunucu yanıtı ile listenin tazelenmesi arasındaki anda (ya da
  /// tazeleme başarısız olursa) çipin ikinci kez dokunulmasını önler.
  final Set<String> _eklenen = {};

  /// Öneri çipinden takibe alma — `AddWatchlistScreen._add` ile AYNI yol:
  /// aynı kimlik (`VarlikKimligi`), aynı `watchlistProvider.add` (limit
  /// kapısı orada), aynı hata ayrımı. Başarı toast'ı yok (2026-09-16 kararı):
  /// onay çipin kaybolması ve satırın listeye gelmesi.
  Future<void> _ekle(VarlikKimligi k) async {
    // Demo (F1): takibe almak bir yazma; Varlık Ekle düğmesiyle aynı kapı.
    if (DemoModu.yazmaKapisi('takip')) return;
    OzellikOlcumu.say(Ozellik.takipOnerisi);
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(watchlistProvider.notifier)
          .add(k.toWatchlistItem(userId: user.id));
      if (mounted) setState(() => _eklenen.add(k.key));
    } on WatchlistLimitException catch (e) {
      if (!mounted) return;
      takipSiniriUyarisi(context, ref, e.limit);
    } on DemoYazmaEngeli {
      return; // Mesajı `DemoModu.yazmaEngeli` dinleyicisi gösterdi.
    } catch (_) {
      if (!mounted) return;
      sandikSnack(context, context.l10n.watchlistSuggestFailed,
          kind: SandikSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final takipte = {
      for (final w in ref.watch(watchlistProvider).valueOrNull ?? const [])
        w.key,
    };
    final l = context.l10n;
    // Etiketler sembole göre: kimlik listesi sırayı ve varlığı belirler,
    // ekran yalnız adını koyar.
    final etiketler = <String, (String, String)>{
      FiyatKaynagi.gramAltin24: (
        l.watchlistSuggestGold,
        l.watchlistSuggestGoldSemantics,
      ),
      FiyatKaynagi.usdTry: (
        l.watchlistSuggestUsd,
        l.watchlistSuggestUsdSemantics,
      ),
      FiyatKaynagi.bist100: (
        l.watchlistSuggestBist,
        l.watchlistSuggestBistSemantics,
      ),
    };
    final oneriler = [
      for (final k in VarlikKimligi.takipOnerileri)
        if (etiketler[k.ticker] != null &&
            !takipte.contains(k.key) &&
            !_eklenen.contains(k.key))
          k,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      child: Column(
        children: [
          // Bayrak `goz_alici`: kapalı sandık; kapalıyken eski ikon.
          const SandikBosIkonu(ikon: Icons.visibility_outlined, boyut: 40),
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
          if (oneriler.isNotEmpty) ...[
            const SizedBox(height: SandikSpace.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: SandikSpace.sm,
              runSpacing: SandikSpace.sm,
              children: [
                for (final k in oneriler)
                  _OneriCipi(
                    key: ValueKey('takip_onerisi_${k.ticker}'),
                    ad: etiketler[k.ticker]!.$1,
                    semanticLabel: etiketler[k.ticker]!.$2,
                    onTap: () => _ekle(k),
                  ),
              ],
            ),
          ],
          const SizedBox(height: SandikSpace.md),
          SandikTappable(
            semanticLabel: context.l10n.addToWatchlist,
            // Demo (F1): takibe almak bir yazma.
            onTap: () => DemoModu.yazmaKapisi('takip')
                ? null
                : pushGuarded(
                    context,
                    adaptiveRoute<void>(
                      settings: const RouteSettings(name: 'add_watchlist'),
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
        ],
      ),
    );
  }
}

/// Öneri çipi — `SandikFiltreCipi`'nin seçili olmayan hâliyle aynı hap
/// (tam yuvarlak, 44 pt, `surface2` + `hairline`), başta "+" ikonu.
///
/// Neden `SandikFiltreCipi` değil: o çip SÜZER ve "seçili" taşır; bu çip
/// istek atar. İstek atan hedef `SandikAsyncTap` (TASARIM_DILI "bir iş = bir
/// bileşen"): çift dokunma yutulur, iş sürerken etiketin yerinde gösterge
/// döner, hap yerinde kalır (`zemin:`) — boy değişmez. "+" ikonu eylemi
/// renksiz de anlatır; seçili hâli yok, dokununca kaybolur.
class _OneriCipi extends StatelessWidget {
  const _OneriCipi({
    super.key,
    required this.ad,
    required this.semanticLabel,
    required this.onTap,
  });

  final String ad;
  final String semanticLabel;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SandikAsyncTap(
      onTap: onTap,
      semanticLabel: semanticLabel,
      zemin: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SandikTouch.min / 2),
        border: Border.all(color: c.hairline),
      ),
      // Etiket [semanticLabel]; çipin metni ikinci kez okunmasın.
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: c.text58),
              const SizedBox(width: SandikSpace.xs2),
              Flexible(
                child: Text(
                  ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600, color: c.text90),
                ),
              ),
            ],
          ),
        ),
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

  void _ekle(BuildContext context) {
    if (DemoModu.yazmaKapisi('takip')) return; // Demo: takip bir yazma (F1).
    pushGuarded(
      context,
      adaptiveRoute<void>(
        settings: const RouteSettings(name: 'add_watchlist'),
        builder: (_) => const AddWatchlistScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final n = ref.watch(watchlistProvider).valueOrNull?.length ?? 0;
    final limit = ref.watch(watchlistLimitProvider);
    final sinirli = limit < (1 << 30);
    final dolu = sinirli && n >= limit;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
      // Ölçüler kanvastaki C taslağıyla birebir (kullanıcı, 2026-09-25:
      // "C seçeneği buradaki"): kart 56 pt, sol 14 / sağ 6 pt iç boşluk,
      // düğme 44 pt, etiketler `bodySmall`, şerit 4 pt. Bir ara segment
      // seçicinin 48/40 ölçüsüne indirilmişti; kullanıcı taslağı istedi —
      // kart bir seçici değil, bilgi + eylem kartı; kendi ölçüsü olabilir.
      // Kabuk kenarsız `SandikCard` (2. tur, 2026-10-08) — piksel aynı.
      child: SizedBox(
        height: 56,
        child: SandikCard(
          bordered: false,
          padding: const EdgeInsets.only(
              left: SandikSpace.md2, right: SandikSpace.xs2),
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
                              style: context.t.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: c.text58)),
                          const Spacer(),
                          Text.rich(
                            TextSpan(
                              text: '$n',
                              style: context.t.bodySmall?.copyWith(
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
                        const SizedBox(height: SandikSpace.xs2 + 1),
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
                // Dokunma hedefi 56 pt (kartın tamamı); görsel kutu 44 pt
                // (taslak), 6 pt dikey pay.
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.md2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: dolu ? Colors.transparent : c.amberFill,
                        borderRadius: BorderRadius.circular(SandikSpace.sm2),
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
                            style: context.t.titleSmall?.copyWith(
                                color: dolu ? c.text58 : c.onStatus,
                                fontWeight: FontWeight.w700),
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
      height: SandikSpace.xs,
      child: Row(
        // `stretch` ŞART: `DecoratedBox` çocuksuzdur ve Row'un dikey kısıtı
        // gevşek olduğundan yüksekliği 0'a düşer — şerit yerleşimde var
        // (227×4) ama çizilmezdi (golden ile ölçüldü, 2026-09-25).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < toplam; i++) ...[
            if (i > 0) const SizedBox(width: SandikSpace.xxs + 1),
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

/// Ekranda gösterilecek kısa etiket — grafikle AYNI kural
/// (`WatchlistItem.kisaEtiket`; `TEFAS:AFO` → `AFO`, `ALTIN_GRAM` → ad).
extension on WatchlistItem {
  String get displayLabel => kisaEtiket;
}

/// Satırdaki fiyat metni. Endeks puandır: para simgesi ve kuruş yok
/// (arama satırı ve piyasa bandıyla aynı kural, `endeksMi`).
///
/// Diğerleri ₺ ile ([sembolSerisiSimgesi], seri denetimi 2026-10-08):
/// `currentPrice` sembol serisinin son noktasıdır ve seri her sembolde TL'dir
/// (`WatchlistNotifier._withPrices`). Eskiden simge kotasyonun para
/// biriminden seçiliyordu (`kotasyonSembolu`) ve USD kote satır TL sayıyı
/// "$" ile yazıyordu. Döviz paritesi zaten ₺ idi (2026-09-29 emülatör
/// testi #13); o kural bu genellemenin özel hâli.
@visibleForTesting
String takipFiyatMetni(WatchlistItem item) {
  final f = item.currentPrice;
  if (f == null) return '—';
  return takipFiyatBicimi(item, f);
}

/// [item]'ın fiyat biçimiyle herhangi bir fiyat (alarm hedefi dahil): satırdaki
/// güncel fiyat ile çanın hedefi aynı biçimde okunsun — biri "₺4.300,00",
/// öbürü "4.300" olsaydı iki sayı kıyaslanamazdı.
String takipFiyatBicimi(WatchlistItem item, double f) {
  if (endeksMi(item.ticker)) return fmtNum(f, digits: 0);
  // Sabit 2 hane SHIB'i "₺0,00" yazıyordu — ondalık [fiyatBicimi]'nden.
  return fmtFiyat(f,
      azami: item.type.fiyatHassasiyeti, symbol: sembolSerisiSimgesi);
}
