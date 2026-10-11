part of '../asset_detail_screen.dart';

/// Fiyat grafiğinin katmanları: EMA50 / EMA200 ve logaritmik mum
/// (yasin, 2026-10-10). `asset_detail_screen.dart`'ın part'ı; hesaplar
/// `utils/hareketli_ortalama.dart`'ta.
///
/// ## Kim görür: herkes, bayraksız (yasin, 2026-10-11)
/// İlk sürümlerde tek anahtar `paywall_enabled`'a bağlıydı
/// (`premiumOzellikleriGorunurProvider`): kapalıyken yalnız admin görürdü.
/// Paywall kapıları incelemesi bunun ücretsiz özelliği ödeme anahtarına
/// bağladığını gösterdi (paywall kapatılırsa ücretsiz kullanıcıdan da
/// gider). yasin: *"mum grafik ve ema herkeste gösterilebilsin flag
/// arkasında olmasın"*. Mum, aralık seçicisi, EMA50/EMA200 artık herkese
/// açık; yalnız `ƒx` (kendi göstergen) eski kapıda kalır
/// ([_ozelGostergeGorunur]).
///
/// ## Ücretsiz (yasin, 2026-10-10 20:38)
/// İlk sürümde (#150) Mum ve EMA çipleri Premium'du. yasin aynı akşam:
/// *"mum görünümü ve preset göstergeler ücretli olmamalı, custom pine kodu
/// girmek isteyen traderlar için ücretli olmalı"*, *"ema50 ema200 ücretsiz
/// olmalı"*. Mum, aralık seçicisi, EMA50, EMA200 (MA20 ve LOG zaten) artık
/// ücretsiz; kilit yalnız `ƒx` çipinde — kendi göstergeni yaz
/// (`ozel_gostergeler.dart`, [_ozelGostergeKilitli]).
///
/// ## Mumun verisi
/// 2026-10-10'a kadar uygulama hiçbir sağlayıcıdan açılış/en yüksek/en düşük
/// çekmiyordu; mum eldeki kapanış noktalarından KOVA bazında türetiliyordu
/// (`mumlariGrafikUzayinda`). yasin aynı gün: *"mum grafik TradingView'deki
/// gibi çalışmalı: 1 dk, 1 saat, 4 saat, günlük, haftalık, aylık grafik
/// verisi çekilebilmeli."* Artık Mum açıkken aralık seçicisi çıkar ve
/// mumlar sağlayıcının GERÇEK OHLC'sidir (`services/mum_verisi.dart`;
/// kaynak kararı `FiyatKaynagi.mumKaynagi`). Seçici yalnız o dönemde
/// 3–1.500 mum veren aralıkları sunar (`gecerliAraliklar`); varsayılan ~80
/// muma en yakın olandır. Fon, BES ve eurobond günde tek fiyat yayımlar:
/// onlarda yalnız gün/hafta/ay, mumlar kapanışlardan (altyazı söyler).
///
/// Türetilmiş mum YEDEK olarak kalır: gerçek mum gelene kadar (ilk açılış,
/// ağ hatası, eski sunucu) ya da o dönemde geçerli aralık yokken (fonun
/// GÜNLÜK'ü) eski çizim görünür — ekran boş kalmaz. Mevduatta çipler hiç
/// çıkmaz (çizgisi fiyat değil faiz birikimi).
///
/// Aralık seçicisinin kendi bayrağı yok: Mum'la aynı görünürlük kararı.
extension _GrafikKatmanlari on _AssetDetailScreenState {
  /// EMA/Mum çipleri bu varlıkta çizilir mi (herkese; mevduatta yok).
  bool get _katmanlarGorunur => widget.asset.type != AssetType.mevduat;

  /// `ƒx` (kendi göstergen) bu kullanıcıda görünür mü: YENİ Premium
  /// özelliği, paywall kapalıyken yalnız admin (`premiumOzellikleriGorunur`).
  bool get _ozelGostergeGorunur =>
      _katmanlarGorunur && ref.watch(premiumOzellikleriGorunurProvider);

  /// Kendi göstergeni yaz (`ƒx`) kilitli mi (paywall açık, Premium değil).
  /// Mum/EMA kilitlenmez — yalnız özel gösterge Premium.
  bool get _ozelGostergeKilitli => ref.watch(premiumKilitliProvider);

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

  // ── Gerçek mumlar (aralık seçicisi, 2026-10-10) ─────────────────────────

  /// Mumun penceresi dakika cinsinden: GÜNLÜK tam bir takvim günüdür.
  double _mumPenceresi(bool gunIci, DateTime bas, DateTime son) =>
      gunIci ? 1440.0 : son.difference(bas).inMinutes.toDouble();

  /// Bu pencerede çizilecek aralık ve seçicinin sunacağı aralıklar.
  ({MumAraligi? aralik, List<MumAraligi> gecerli, double span}) _mumAraligi(
      bool gunIci, DateTime bas, DateTime son) {
    final span = _mumPenceresi(gunIci, bas, son);
    final secim = secilenMumAraligi(ref, span);
    final a = _canli.asset;
    return (
      aralik: etkinAralik(a, span, secim),
      gecerli: gecerliAraliklar(a, span),
      span: span,
    );
  }

  /// [aralik] çubuklarını ([kEmaUzun] kadar ısınmayla) ister ve eldekini
  /// döndürür; henüz yoksa null. Isınma, ortalamaların dönemin ilk
  /// çubuğundan çizilmesi için (`cubukOrtalamasi`); mumu çizerken
  /// [donemCubuklari] ile ayıklanır. Ortak yükleyici: varlık sayfası ve
  /// Karşılaştır aynı kuralla ister (yasin 2026-10-11, dört yüzey tutarlı).
  List<OhlcBar>? _ohlcBarlari(MumAraligi aralik, bool gunIci, DateTime bas,
          DateTime son, double canliBirim) =>
      _ohlcYukleyici.mumlar(
        a: _canli.asset,
        aralik: aralik,
        bas: bas,
        son: son,
        canliBirim: canliBirim,
        gunIci: gunIci,
        isinma: kEmaUzun,
      );

  /// Çubuklar yolda mı (yoldayken ortalama çizilmez, gelince belirir).
  bool get _ohlcYolda => _ohlcYukleyici.bekliyor;

  /// Ortalama çizgisi gerçek çubuklardan (grafiğin X'inde, kesirli gün),
  /// [toY] ile taşınmış. Gerekçe `cubukOrtalamasi`.
  List<FlSpot> _cubukOrtalamasi(List<OhlcBar> barlar, MumAraligi aralik,
      DateTime startDate, double Function(double) toY,
      {required int periyot, required OrtalamaTuru tur}) {
    final basMs = startDate.millisecondsSinceEpoch;
    return [
      for (final p in cubukOrtalamasi(barlar,
          aralik: aralik,
          periyot: periyot,
          tur: tur,
          gorunurBasMs: basMs,
          baslangicMs: basMs.toDouble(),
          birimMs: 24 * 60 * 60 * 1000.0))
        FlSpot(p.x, toY(p.y)),
    ];
  }

  /// Gerçek mumlar grafiğin X uzayında (kesirli gün), HAM fiyatla. Isınma
  /// çubukları (dönem başından önce biten) çizilmez.
  List<Mum> _ohlcMumlari(
          List<OhlcBar> barlar, MumAraligi aralik, DateTime startDate) =>
      grafikMumlari(
        donemCubuklari(
            barlar, aralik, startDate.millisecondsSinceEpoch),
        aralik: aralik,
        baslangicMs: startDate.millisecondsSinceEpoch.toDouble(),
        birimMs: 24 * 60 * 60 * 1000.0,
      );

  /// Gerçek mum çubukları — toplu çizim (mum sayısı 1.500'e kadar).
  List<LineChartBarData> _ohlcCubuklari({
    required List<Mum> mumlar,
    required double Function(double) toY,
    required double viewMinX,
    required double viewMaxX,
    required double genislik,
  }) =>
      GrafikStili.mumCubuklariToplu(
        context,
        mumlariDonustur(mumlar, toY),
        genislik: genislik,
        gorunurAralik: viewMaxX > viewMinX ? viewMaxX - viewMinX : null,
      );

  /// Fitil uçları Y bandına girsin: bant çizginin (kapanışların) noktalarından
  /// kuruluyordu; gerçek mumun en yüksek/en düşük'ü kapanışların dışına
  /// taşar ve fitil kartın kenarında kesilirdi.
  List<FlSpot> _ohlcUclari(List<Mum> mumlar, double Function(double) toY) => [
        for (final m in mumlar) ...[
          FlSpot(m.merkezX, toY(m.enYuksek)),
          FlSpot(m.merkezX, toY(m.enDusuk)),
        ],
      ];

  /// Crosshair'ın altındaki mum: [x]'i kovasında taşıyan, yoksa merkezi en
  /// yakın olan. Mumlar X'e göre sıralı.
  Mum? _imlectekiMum(List<Mum> mumlar, double x) {
    if (mumlar.isEmpty) return null;
    Mum? en;
    var fark = double.infinity;
    for (final m in mumlar) {
      if (x >= m.x && x < m.x + m.kovaMs) return m;
      final f = (m.merkezX - x).abs();
      if (f < fark) {
        fark = f;
        en = m;
      }
    }
    return en;
  }

  /// İmleç altyazısı: mumun AÇILIŞ anı (gün içinde saat, diğerlerinde
  /// tarih; günlük ve üstü mum gece yarısına oturur, saat yazılmaz).
  String _mumZamani(Mum m, DateTime startDate, bool gunIci) {
    final an = startDate.add(Duration(minutes: (m.x * 1440).round()));
    return gunIci
        ? DateFormat('d MMM · HH:mm', 'tr_TR').format(an)
        : fmtTarihSaat(an);
  }

  /// Crosshair satırı: "A … · Y … · D … · K …" (başlıktaki hane sayısıyla).
  (String, Color) _ohlcSatiri(Mum m, double canliBirim) {
    final f = _birimBicimi(canliBirim);
    return (
      context.l10n.chartOhlcLine(f.format(m.acilis), f.format(m.enYuksek),
          f.format(m.enDusuk), f.format(m.kapanis)),
      m.yukselen ? context.c.gain : context.c.loss,
    );
  }

  // Araç çubuğu (çipler + aralık seçicisi) ortak widget'ta:
  // `widgets/grafik_arac_cubugu.dart` (üç ekran tutarlılığı, 2026-10-10).
}
