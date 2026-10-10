part of '../asset_detail_screen.dart';

/// Kendi göstergeni yaz — varlık grafiğindeki katman (2026-10-10).
///
/// Dil ve yorumlayıcı `services/gosterge_betigi/`, çizim
/// `widgets/gosterge_cizimi.dart`, liste/düzenleyici
/// `screens/ozel_gosterge_screen.dart`. Burada yalnız grafiğe bağlama.
///
/// ## Kim görür
/// EMA/Mum ile AYNI kapı (`_katmanlarGorunur`, `_katmanlarKilitli`): tek
/// anahtar `paywall_enabled`, yeni bayrak yok. Görünmüyorsa çip yok, liste
/// okunmaz, grafik birebir eskisi (canlıdaki kullanıcı etkilenmez).
///
/// ## Hangi çubuklar
/// Betik grafiğin ÇİZDİĞİ noktalarda çalışır — EMA ile aynı seri ve aynı
/// ısınma (`_emaOnSeriniIste`, dönem öncesi ~200 çubuk). Böylece gösterge
/// seçili dönemin/zaman aralığının çubuklarıdır (TradingView'deki gibi) ve
/// ölçeği çizgiyle birebir (fiyat kaynağı sözleşmesi madde 2). Bugün seri
/// yalnız kapanış taşır; açılış/yüksek/düşük/hacim `na` kalır ve düzenleyici
/// bunu söyler. Gerçek OHLC katmanı geldiğinde tek değişecek yer
/// [_betikVerisi].
///
/// Karşılaştırma açıkken çizilmez (EMA ile aynı gerekçe: çizgi % ölçeğinde).

/// Kod → derlenmiş betik ya da hatası. Her zoom/fiyat turunda yeniden
/// ayrıştırmamak için; kod metni anahtar olduğu için düzenleme kendiliğinden
/// yeni kayıt açar. Sınırlı: 20 gösterge × birkaç sürüm.
final Map<String, Object> _betikOnbellegi = {};

/// Kod + veri parmak izi → sonuç (bkz. `_ozelGostergeleriCalistir`).
final Map<String, BetikSonucu> _sonucOnbellegi = {};

DerlenmisBetik? _derlenmisBetik(String kod) {
  final v = _betikOnbellegi[kod] ??= () {
    if (_betikOnbellegi.length > 64) _betikOnbellegi.clear();
    try {
      return GostergeBetigi.derle(kod);
    } on BetikHatasi catch (e) {
      return e;
    }
  }();
  return v is DerlenmisBetik ? v : null;
}

typedef _OzelSonuc = ({OzelGosterge g, BetikSonucu s, BetikVerisi v});

extension _OzelGostergeler on _AssetDetailScreenState {
  /// Grafikte açık, derlenebilen göstergeler. Kapı kapalıysa ya da
  /// kilitliyse boş — sağlayıcı hiç izlenmez.
  List<OzelGosterge> get _acikOzelGostergeler {
    if (!_katmanlarGorunur || _katmanlarKilitli) return const [];
    final liste = ref.watch(ozelGostergelerProvider).valueOrNull ?? const [];
    return [
      for (final g in liste)
        if (g.grafikte && _derlenmisBetik(g.kod) != null) g
    ];
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

  /// Açık göstergeleri çalıştırır. Çalışma hatası (bütçe aşımı) o
  /// göstergeyi atlar; düzenleyici aynı hatayı satırıyla gösterir.
  /// Sonuç kod + veri parmak izine göre saklanır: Pine betiği çubuk çubuk
  /// çalışır ve her build'de (crosshair, zoom) yeniden koşmasın.
  List<_OzelSonuc> _ozelGostergeleriCalistir(
      List<OzelGosterge> acik, BetikVerisi veri) {
    if (acik.isEmpty || veri.uzunluk == 0) return const [];
    final iz = Object.hash(veri.uzunluk, veri.x.first, veri.x.last,
        veri.kapanis.last, veri.kapanis[veri.uzunluk ~/ 2]);
    final out = <_OzelSonuc>[];
    for (final g in acik) {
      final d = _derlenmisBetik(g.kod);
      if (d == null) continue;
      final anahtar = '${g.kod.hashCode}|$iz';
      final hazir = _sonucOnbellegi[anahtar];
      if (hazir != null) {
        out.add((g: g, s: hazir, v: veri));
        continue;
      }
      try {
        final s = d.calistir(veri);
        if (_sonucOnbellegi.length > 32) _sonucOnbellegi.clear();
        _sonucOnbellegi[anahtar] = s;
        out.add((g: g, s: s, v: veri));
      } on BetikHatasi {
        continue;
      }
    }
    return out;
  }

  /// Fiyatın üstündeki göstergelerin çubukları ve dolguları (grafiğin Y
  /// uzayında; LOG açıkken [toY] ile taşınır — EMA ile aynı kural).
  /// [ofset]: bu çubuklardan önce ana grafikte kaç çubuk var (dolgu
  /// dizinleri ona göre kayar).
  ({List<LineChartBarData> bars, List<BetweenBarsData> dolgular})
      _ozelCubuklar(List<_OzelSonuc> sonuclar, double Function(double) toY,
          {required int ofset}) {
    final bars = <LineChartBarData>[];
    final dolgular = <BetweenBarsData>[];
    for (final r in sonuclar) {
      if (!r.s.fiyatUstunde) continue;
      final kayma = r.v.uzunluk - r.s.x.length;
      final fiyatY = [
        for (var i = kayma; i < r.v.uzunluk; i++) toY(r.v.kapanis[i])
      ];
      final c = betikCizimleri(context, r.s,
          toY: toY, fiyatY: fiyatY, ofset: ofset + bars.length);
      bars.addAll(c.bars);
      dolgular.addAll(c.dolgular);
    }
    return (bars: bars, dolgular: dolgular);
  }

  /// Y bandına girecek noktalar (fiyatın üstündeki görünür çizgiler) — EMA
  /// gibi: banda girmeyen çizgi kartın dışında kalır ve "çalışmıyor" diye
  /// okunur.
  List<FlSpot> _ozelBantNoktalari(
          List<_OzelSonuc> sonuclar, double Function(double) toY) =>
      [
        for (final r in sonuclar)
          if (r.s.fiyatUstunde)
            for (final c in r.s.cizgiler)
              if (!c.gizli)
                for (var i = 0; i < r.s.x.length; i++)
                  if (c.degerler[i].isFinite)
                    FlSpot(r.s.x[i], toY(c.degerler[i])),
      ];

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

  /// Grafiğin altındaki bölüm: fiyatın üstündeki göstergelerin adları
  /// (lejant) ve ayrı panel göstergeleri.
  List<Widget> _ozelAltBolum(List<_OzelSonuc> sonuclar) {
    if (sonuclar.isEmpty) return const [];
    final ust = [
      for (final r in sonuclar)
        if (r.s.fiyatUstunde) r
    ];
    final panel = [
      for (final r in sonuclar)
        if (!r.s.fiyatUstunde) r
    ];
    return [
      if (ust.isNotEmpty) ...[
        const SizedBox(height: SandikSpace.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in ust)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xxs),
                  child: BetikLejandi(baslik: r.g.ad, sonuc: r.s),
                ),
            ],
          ),
        ),
      ],
      for (final r in panel) ...[
        const SizedBox(height: SandikSpace.sm),
        ValueListenableBuilder<({double min, double max})?>(
          valueListenable: _ozelGorunum,
          builder: (_, g, __) => BetikPaneli(
            baslik: r.g.ad,
            sonuc: r.s,
            minX: g?.min ?? r.s.x.first,
            maxX: g?.max ?? r.s.x.last,
          ),
        ),
      ],
    ];
  }

  /// Araç çubuğundaki `ƒx` çipi. Kilitliyse paywall; değilse göstergeler
  /// sayfası (grafiğin o anki çubuklarıyla — düzenleyici önizlemesi için).
  Widget _ozelGostergeCipi(int acikSayi) {
    final kilitli = _katmanlarKilitli;
    return Semantics(
      label: context.l10n.ozgCipSemantik,
      child: _OverlayChip(
        label: acikSayi > 0 ? 'ƒx $acikSayi' : 'ƒx',
        active: acikSayi > 0,
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
      ),
    );
  }
}
