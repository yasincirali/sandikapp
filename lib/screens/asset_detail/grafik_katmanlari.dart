part of '../asset_detail_screen.dart';

/// Fiyat grafiğinin Premium katmanları: EMA50 / EMA200 ve logaritmik mum
/// (yasin, 2026-10-10). `asset_detail_screen.dart`'ın part'ı; hesaplar
/// `utils/hareketli_ortalama.dart`'ta.
///
/// ## Kim görür (yeni bayrak YOK)
/// Tek anahtar `paywall_enabled` (`premiumOzellikleriGorunurProvider`):
/// kapalıyken yalnız admin hesabı görür — mağazadaki kullanıcının araç
/// çubuğu birebir eskisi gibi (MA20 · LOG). Açıkken herkes görür; Premium
/// olmayanda çip kilitlidir ve dokunuş paywall'u açar. Gerekçe: "yeni
/// özellikler paywall arkasında" (yasin 2026-10-10) ve "bayrak sayısı
/// artmasın" (2026-10-09). MA20 ve LOG ücretsiz kalır — canlıdaki kullanıcının
/// kullandığı şey elinden alınmaz.
///
/// ## Mumun verisi
/// Uygulama hiçbir sağlayıcıdan açılış/en yüksek/en düşük çekmiyor; seriler
/// yalnız kapanış taşır (`PriceService`, `HistoryService`). Mum, Performans'taki
/// gibi eldeki noktalardan KOVA bazında türetilir (`mumlariGrafikUzayinda`):
/// fitil örneklenmiş noktaların uçlarıdır. Bu bütün varlık türlerinde aynı
/// çalışır; tek istisna mevduat — çizgisi fiyat değil faiz birikimi, mum ve
/// EMA orada anlamsız, çipler hiç çıkmaz.
extension _GrafikKatmanlari on _AssetDetailScreenState {
  /// EMA/Mum çipleri bu kullanıcıda ve bu varlıkta çizilir mi.
  bool get _katmanlarGorunur =>
      ref.watch(premiumOzellikleriGorunurProvider) &&
      widget.asset.type != AssetType.mevduat;

  /// Çipler kilitli mi (paywall açık, Premium değil).
  bool get _katmanlarKilitli => ref.watch(premiumKilitliProvider);

  /// Seçili dönemin EMA ısınma serisini (dönem öncesi çubuklar) ister.
  ///
  /// Grafikle AYNI motor, AYNI birim varlık ve AYNI çözünürlük katmanı
  /// (`_donemSerisi` ile aynı kurallar) — yalnız başlangıç [emaGeriBakisGunu]
  /// kadar geride. Böylece ölçek ve kaynak grafikle birebir (CLAUDE.md
  /// "Fiyat kaynağı"). Gün içinde istenmez: GÜNLÜK tek seanstır.
  ///
  /// Build sırasında çağrılır ama setState'i senkron yapmaz; aynı dönem
  /// için ikinci kez istemez. Gelmezse (ağ, eski veri yok) EMA dönem içindeki
  /// noktalardan hesaplanır ve yeterli nokta yoksa çizilmez — uydurma yok.
  void _emaOnSeriniIste(int days) {
    if (days == 0 || _emaOnSeriGun == days) return;
    _emaOnSeriGun = days;
    final now = DateTime.now();
    final from = _AssetDetailScreenState._donemBaslangici(days, now);
    final katman = ResolutionTierMeta.pickForSpan(
        now.difference(from).inMinutes / (60.0 * 24.0));
    final geri = emaGeriBakisGunu(katman, kEmaUzun);
    final yukleme = HistoryService.instance
        .getPortfolioHistoryBreakdownAtResolution(
          assets: [FiyatKaynagi.birimVarlik(_canli.asset)],
          from: from.subtract(Duration(days: geri)),
          to: now,
          tier: katman,
        )
        .then<void>((b) {
      if (!mounted || _emaOnSeriGun != days) return;
      _guncelle(() => _emaOnSeri = (gun: days, seri: b.total));
    });
    CrashReporter.arkaPlan(yukleme, reason: 'AssetDetail.emaOnSeri');
  }

  /// Mumun seri kaynağı: grafik HAFTALIK çizerken (6A, 1Y, 5Y —
  /// `pickForSpan`) aynı pencerenin GÜNLÜK serisi istenir.
  ///
  /// Neden: mum ancak kovasında birden çok nokta varken bilgi taşır
  /// (`mumKovasiSec`, asgari 2 nokta). Haftalık 52 noktadan 1Y'de yalnız 12
  /// aylık mum çıkıyordu; günlük seriden 52 haftalık mum çıkar
  /// (TradingView'in 1Y haftalık görünümü). Motor, birim varlık ve ölçek
  /// grafikle aynı; yalnız çözünürlük katmanı bir alt basamak. Daha ince
  /// katmanlarda (gün içi, 1H, 1A, 3A) grafiğin kendi noktaları kullanılır.
  void _mumSerisiniIste(int days) {
    if (days == 0 || _mumSerisiGun == days) return;
    final now = DateTime.now();
    final from = _AssetDetailScreenState._donemBaslangici(days, now);
    final katman = ResolutionTierMeta.pickForSpan(
        now.difference(from).inMinutes / (60.0 * 24.0));
    if (katman != ResolutionTier.weekly) return;
    _mumSerisiGun = days;
    final yukleme = HistoryService.instance
        .getPortfolioHistoryBreakdownAtResolution(
          assets: [FiyatKaynagi.birimVarlik(_canli.asset)],
          from: from,
          to: now,
          tier: ResolutionTier.daily,
        )
        .then<void>((b) {
      if (!mounted || _mumSerisiGun != days) return;
      _guncelle(() => _mumSerisi = (gun: days, seri: b.total));
    });
    CrashReporter.arkaPlan(yukleme, reason: 'AssetDetail.mumSerisi');
  }

  /// [_mumSerisiniIste]'nin noktaları grafiğin X uzayında; yoksa null
  /// (çağıran grafiğin kendi noktalarına düşer). Son nokta canlı birim
  /// fiyata sabitlenir — çizginin ucuyla aynı kural
  /// (`_convertHistoryToSegments`), son mumun kapanışı başlıktaki fiyattır.
  List<FlSpot>? _mumNoktalari(
      int days, DateTime startDate, DateTime endDate, double canliBirim) {
    final m = _mumSerisi;
    if (m == null || m.gun != days || m.seri.length < 2) return null;
    final seg = _convertHistoryToSegments(m.seri, startDate, endDate,
        currentUnitPriceOverride: canliBirim);
    for (final s in seg) {
      if (!s.piyasaKapali && s.spots.length >= 2) return s.spots;
    }
    return null;
  }

  /// Isınma serisini grafiğin X uzayına (dönem başından kesirli gün) çevirir.
  /// Yalnız istenen dönemin serisi kullanılır: dönem değişip yenisi henüz
  /// gelmediyse eski dönemin noktaları başka bir başlangıca göre ölçülmüştü.
  List<FlSpot> _emaOnNoktalari(int days, DateTime startDate) {
    final on = _emaOnSeri;
    if (on == null || on.gun != days) return const [];
    final ts = on.seri.keys.toList()..sort();
    return [
      for (final t in ts)
        FlSpot(
          DateTime.fromMillisecondsSinceEpoch(t)
                  .difference(startDate)
                  .inMinutes /
              (60.0 * 24.0),
          on.seri[t]!,
        ),
    ];
  }

  /// EMA çizgileri (grafiğin Y uzayında). [hamSeri] grafiğin ham fiyat
  /// noktaları; EMA ham fiyattan hesaplanır, sonra [toY] ile (LOG) taşınır —
  /// log fiyatın ortalaması fiyat ortalamasının log'u değildir.
  List<({List<FlSpot> spots, Color renk})> _emaCizgileri({
    required List<FlSpot> hamSeri,
    required List<FlSpot> onSeri,
    required double Function(double) toY,
    required bool ema50,
    required bool ema200,
  }) {
    final out = <({List<FlSpot> spots, Color renk})>[];
    for (final (acik, periyot, renk) in [
      (ema50, kEmaKisa, context.c.gain),
      (ema200, kEmaUzun, context.c.loss),
    ]) {
      if (!acik) continue;
      final ham = emaNoktalari(hamSeri, periyot: periyot, onSeri: onSeri);
      if (ham.length < 2) continue;
      out.add((
        spots: [for (final s in ham) FlSpot(s.x, toY(s.y))],
        renk: renk,
      ));
    }
    return out;
  }

  LineChartBarData _emaCubugu(({List<FlSpot> spots, Color renk}) e) =>
      LineChartBarData(
        spots: e.spots,
        isCurved: false,
        color: e.renk,
        barWidth: 1.6,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );

  /// Mum çubukları — Performans'la aynı türetici ve aynı çizim
  /// (`GrafikStili.mumCubuklari`). Bu ekranın X'i her dönemde KESİRLİ GÜN
  /// (gün içi dahil, `_convertHistoryToSegments`), birim bu yüzden sabit.
  /// [hamSeri] ham fiyattır; mum ham fiyattan türetilip sonra [toY] ile
  /// log'a taşınır — fitilin uçları log'da da aynı noktalar kalır.
  List<LineChartBarData> _mumCubuklari({
    required List<FlSpot> hamSeri,
    required DateTime startDate,
    required double Function(double) toY,
    required double viewMinX,
    required double viewMaxX,
    required double genislik,
  }) {
    final mumlar = mumlariGrafikUzayinda(hamSeri,
        baslangicMs: startDate.millisecondsSinceEpoch.toDouble(),
        birimMs: 24 * 60 * 60 * 1000.0);
    return GrafikStili.mumCubuklari(
      context,
      mumlariDonustur(mumlar, toY),
      genislik: genislik,
      gorunurAralik: viewMaxX > viewMinX ? viewMaxX - viewMinX : null,
    );
  }

  /// Araç çubuğunun Premium çipleri (MUM · EMA50 · EMA200). Kilitliyse
  /// dokunuş seçimi değiştirmez, paywall'u açar.
  ({Widget mum, Widget ema50, Widget ema200}) _katmanCipleri({
    required bool mumOn,
    required bool ema50On,
    required bool ema200On,
  }) {
    final kilitli = _katmanlarKilitli;
    VoidCallback dokun(void Function() degistir, String kaynak) => () {
          if (kilitli) {
            PaywallScreen.show(context, source: kaynak);
            return;
          }
          degistir();
        };
    return (
      mum: _OverlayChip(
        label: context.l10n.chartCandleChip,
        active: mumOn,
        kilitli: kilitli,
        onTap: dokun(
            () => ref.read(chartCandleProvider.notifier).set(!mumOn),
            'grafik_mum'),
      ),
      ema50: _OverlayChip(
        label: 'EMA50',
        active: ema50On,
        kilitli: kilitli,
        renk: context.c.gain,
        onTap: dokun(
            () => ref.read(chartEma50Provider.notifier).set(!ema50On),
            'grafik_ema'),
      ),
      ema200: _OverlayChip(
        label: 'EMA200',
        active: ema200On,
        kilitli: kilitli,
        renk: context.c.loss,
        onTap: dokun(
            () => ref.read(chartEma200Provider.notifier).set(!ema200On),
            'grafik_ema'),
      ),
    );
  }
}
