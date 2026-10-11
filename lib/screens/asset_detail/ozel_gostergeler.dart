part of '../asset_detail_screen.dart';

/// Kendi göstergeni yaz — varlık grafiğindeki katman (2026-10-10).
///
/// Dil ve yorumlayıcı `services/gosterge_betigi/`, çizim
/// `widgets/gosterge_cizimi.dart`, liste/düzenleyici
/// `screens/ozel_gosterge_screen.dart`. Burada yalnız grafiğe bağlama.
///
/// ## Kim görür
/// Görünürlük EMA/Mum ile AYNI (`_katmanlarGorunur`): tek anahtar
/// `paywall_enabled`, yeni bayrak yok. Görünmüyorsa çip yok, liste okunmaz,
/// grafik birebir eskisi (canlıdaki kullanıcı etkilenmez).
///
/// Kilit yalnız burada (`_ozelGostergeKilitli`): yasin 2026-10-10 — *"pine
/// kodu girip kendi göstergesini çalıştırmak ücretli olmalı"*; Mum ve EMA
/// ücretsiz. Sunucu eşi 0141 (`premium_icerik_gorebilir()` yazma kapısı).
///
/// ## Hangi çubuklar
/// Varlığın gerçek mumu varsa (hisse, döviz, altın, emtia Yahoo; kripto
/// Binance — `MumKaynagi.gercekOhlc`) betik o mumlarda çalışır: aralık mum
/// grafiğinin aralığıdır (seçici, yoksa otomatik), açılış/yüksek/düşük/hacim
/// gerçek. ATR, Supertrend, Stokastik, VWAP gibi göstergeler ancak böyle
/// veri bulur (yasin 2026-10-10: "TradingView'deki gibi, zaman aralığıyla
/// kombine"). Isınma için pencerenin öncesinden de mum istenir
/// (`_betikIsinmaCubugu`), EMA200 dönemin başında da çizilir. Mum katmanı
/// kapalıyken de istenir: gösterge mumu değil veriyi ister.
///
/// Gerçek mum yoksa (fon, BES, eurobond) ya da mumlar henüz gelmediyse
/// betik grafiğin ÇİZDİĞİ noktalarda çalışır — EMA ile aynı seri ve ısınma
/// (`_emaOnSeriniIste`). O zaman açılış/yüksek/düşük/hacim `na` kalır ve
/// düzenleyici bunu söyler (uydurma yok). İki yolda da ölçek ekrandaki
/// fiyatla aynı (fiyat kaynağı sözleşmesi madde 2; mumlar `canliyaHizala`).
///
/// Karşılaştırma açıkken çizilmez (EMA ile aynı gerekçe: çizgi % ölçeğinde).

// Derleyici ve sonuç önbelleği, çalıştırıcı: `services/ozel_gosterge_calistirici.dart`
// (varlık sayfasıyla ortak, 2026-10-10 gece).
const int _betikIsinmaCubugu = betikIsinmaCubugu;

typedef _OzelSonuc = OzelSonuc;

extension _OzelGostergeler on _AssetDetailScreenState {
  /// Grafikte açık, derlenebilen göstergeler. Kapı kapalıysa ya da
  /// kilitliyse boş — sağlayıcı hiç izlenmez.
  List<OzelGosterge> get _acikOzelGostergeler {
    if (!_katmanlarGorunur || _ozelGostergeKilitli) return const [];
    final liste = ref.watch(ozelGostergelerProvider).valueOrNull ?? const [];
    return grafiktekiGostergeler(liste);
  }

  /// Grafiğin çubukları → betik girdisi. [onSeri] dönem öncesi ısınma
  /// noktaları (yalnız `hamSeri.first.x`'ten öncekiler). Grafiğin X'i
  /// [baslangic]'tan beri GÜN; Pine'ın `time`'ı epoch ms ister, ayrıca
  /// çevrilir. Aralık (`timeframe.period`) çubuk sıklığından okunur.
  BetikVerisi _betikVerisi(
      List<FlSpot> hamSeri, List<FlSpot> onSeri, DateTime baslangic) {
    final ilkX = hamSeri.isEmpty ? double.infinity : hamSeri.first.x;
    final noktalar = <FlSpot>[
      for (final s in onSeri)
        if (s.x < ilkX && s.y.isFinite && s.y > 0) s,
      for (final s in hamSeri)
        if (s.y.isFinite) s,
    ];
    final bas = baslangic.millisecondsSinceEpoch.toDouble();
    final zaman = [
      for (final s in noktalar) bas + s.x * Duration.millisecondsPerDay,
    ];
    return BetikVerisi.yalnizKapanis(
      [for (final s in noktalar) s.x],
      [for (final s in noktalar) s.y],
      zaman: zaman,
      zamanDilimi: BetikVerisi.aralikTahmini(zaman),
      sembol: _kimlik.kisaEtiket,
    );
  }

  /// Gerçek mumdan betik girdisi (ortak `betikVerisiMumdan`); X mumun
  /// grafikteki ortası.
  BetikVerisi _betikVerisiMumdan(
      List<OhlcBar> barlar, MumAraligi aralik, DateTime baslangic) {
    final mumlar = _ohlcMumlari(barlar, aralik, baslangic);
    return betikVerisiMumdan(barlar, aralik,
        x: [for (final m in mumlar) m.merkezX], sembol: _kimlik.kisaEtiket);
  }

  /// Betiğin mumları: [aralik] ile, pencereden [_betikIsinmaCubugu] mum
  /// önceden başlayarak. Mum katmanının isteğinden AYRI tutulur (başlangıcı
  /// farklı; aynı alana yazsalar birbirini sürekli yeniden isterdi).
  /// `_ohlcBarlari` ile aynı desen: build sırasında ister, eldekini döndürür,
  /// gelmediyse null (çağıran kapanış çizgisine düşer).
  List<OhlcBar>? _betikMumlari(MumAraligi aralik, bool gunIci, DateTime bas,
      DateTime son, double canliBirim) {
    // Seansı olan piyasada gün içi mum gece/hafta sonu yoktur: duvar
    // saatinde daha geriye gidilir ki ısınma yine ~200 mum olsun.
    final carpan = aralik.gunIci ? 4 : 1.5;
    final isinmaBas = bas.subtract(Duration(
        minutes: (aralik.dakika * _betikIsinmaCubugu * carpan).round()));
    final basMs = isinmaBas.millisecondsSinceEpoch;
    final adim = aralik.gunIci ? 60000 : 600000;
    final anahtar = '${aralik.name}|${bas.millisecondsSinceEpoch}|'
        '${DateTime.now().millisecondsSinceEpoch ~/ adim}';
    if (_betikOhlcIstenen != anahtar) {
      _betikOhlcIstenen = anahtar;
      final pencereSonu = gunIci ? bas.add(const Duration(days: 1)) : son;
      final simdi = DateTime.now();
      final yukleme = MumVerisi.instance
          .mumlar(
            a: _canli.asset,
            aralik: aralik,
            bas: isinmaBas,
            son: pencereSonu.isAfter(simdi) ? simdi : pencereSonu,
            canliBirim: canliBirim,
          )
          .then<void>((barlar) {
        if (!mounted || _betikOhlcIstenen != anahtar) return;
        if (barlar.isEmpty &&
            _betikOhlc?.aralik == aralik &&
            _betikOhlc?.basMs == basMs) {
          return;
        }
        _guncelle(() =>
            _betikOhlc = (aralik: aralik, basMs: basMs, barlar: barlar));
      });
      CrashReporter.arkaPlan(yukleme, reason: 'AssetDetail.betikOhlc');
    }
    final o = _betikOhlc;
    if (o == null || o.aralik != aralik || o.basMs != basMs) return null;
    // Yorumlayıcı son kBetikAzamiCubuk çubuğu alır; fazlası ısınmadan düşer.
    return o.barlar.length >= 2 ? o.barlar : null;
  }

  List<_OzelSonuc> _ozelGostergeleriCalistir(
          List<OzelGosterge> acik, BetikVerisi veri) =>
      ozelGostergeleriCalistir(acik, veri);

  /// Fiyatın üstündeki çizimler ortak
  /// (`widgets/gosterge_cizimi.dart`, varlık sayfasıyla aynı).
  ({List<LineChartBarData> bars, List<BetweenBarsData> dolgular})
      _ozelCubuklar(List<_OzelSonuc> sonuclar, double Function(double) toY,
              {required int ofset}) =>
          fiyatUstuCizimleri(context, sonuclar, toY, ofset: ofset);

  /// Fiyat üstü göstergelerin bant noktaları — bandı yalnız dışına
  /// taşarlarsa genişletirler (`gostergeyiKapsayanBant`).
  List<FlSpot> _ozelBantNoktalari(
          List<_OzelSonuc> sonuclar, double Function(double) toY) =>
      fiyatUstuBantNoktalari(sonuclar, toY);

  /// Ana grafiğin odak penceresi değişti (dönem, veri). Build içinden
  /// çağrılır; bildirim kare sonrasına ertelenir (build sırasında dinleyici
  /// setState'i yasak — `ChartViewport.updateFullRangeSessiz` gerekçesi).
  void _ozelOdagiBildir(double minX, double maxX) {
    if (_ozelOdak?.min == minX && _ozelOdak?.max == maxX) return;
    _ozelOdak = (min: minX, max: maxX);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ozelGorunum.value = (min: minX, max: maxX);
    });
  }

  /// Kullanıcı yakınlaştırdı/kaydırdı: alt paneller aynı pencereye oturur.
  void _ozelGorunumuYaz(double minX, double maxX) =>
      _ozelGorunum.value = (min: minX, max: maxX);

  /// Grafiğin altındaki bölüm (lejant + paneller) — ortak widget.
  List<Widget> _ozelAltBolum(List<_OzelSonuc> sonuclar) => sonuclar.isEmpty
      ? const []
      : [OzelGostergeAltBolumu(sonuclar: sonuclar, gorunum: _ozelGorunum)];

  /// Araç çubuğundaki `ƒx` çipi. Kilitliyse paywall; değilse göstergeler
  /// sayfası (grafiğin o anki çubuklarıyla — düzenleyici önizlemesi için).
  GrafikOzelCipi _ozelGostergeCipi(int acikSayi) {
    final kilitli = _ozelGostergeKilitli;
    return GrafikOzelCipi(
      acikSayi: acikSayi,
      kilitli: kilitli,
      onTap: () {
        if (kilitli) {
          PaywallScreen.show(context, source: 'grafik_ozel_gosterge');
          return;
        }
        showOzelGostergeSayfasi(
          context,
          onizleme: _ozelVeri,
          varlikAdi: _kimlik.kisaEtiket,
        );
      },
    );
  }
}
