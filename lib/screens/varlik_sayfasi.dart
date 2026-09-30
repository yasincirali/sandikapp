import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../services/son_bakilanlar.dart';
import '../services/varlik_istatistik.dart';
import '../theme/sandik.dart';
import '../utils/acilis_kapisi.dart';
import '../utils/tr_format.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/donem_istatistik.dart';
import '../widgets/donem_secici.dart';
import '../widgets/fiyat_grafigi.dart';
import '../widgets/fon_karnesi_karti.dart';
import '../widgets/grafik_stili.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/takip_yildizi.dart';
import '../widgets/varlik_iskeleti.dart';
import 'asset_detail_screen.dart'
    show TechnicalSignalPanel, kSinyalPenceresiGun;
import 'pozisyona_git.dart';

/// Varlık sayfası — bir varlığı portföye EKLEMEDEN incelemek.
///
/// ## Karar (kullanıcı, 2026-09-28)
/// "Herhangi bir varlığın bireysel istatistik ve zaman aralığına göre
/// grafiklerini portföyüme eklemeden izlemek isterim, oradan direkt
/// portföyüme ya da takip listesine eklenebilir." Üç tasarım seçeneğinden
/// **C (büyüyen sayfa)** seçildi: alttan yarım açılır, yukarı çekince tam
/// sayfa olur; alt çubuk iki hâlde de aynı yerde durur. Ardından: "karşılaştır
/// menüsü, takibe alınanlar ve varlık ekle kısımlarında da varlıklar var; o
/// adımlarda da varlığın detayını izlemek isteyecekler." Dört giriş noktası:
///   · Takip listesi satırı (tam hâlde açılır; eski `WatchlistDetailScreen`'in
///     yerini aldı — ikinci bir detay ekranı ayrışırdı),
///   · Takibe al araması (satıra dokunmak önizler, "+" hemen ekler),
///   · Karşılaştır seçim satırı,
///   · Varlık ekleme seçicileri (hisse, fon, altın, kripto) — orada birincil
///     eylem "Bunu seç" olur, akış bozulmaz.
///
/// ## Sahiplik yok
/// Bu dosya `Asset` tipini bilmez, sahte bir `Asset` üretmez ve sahiplik
/// ekranını açmaz; portföyde olan bir varlık için geçiş `pozisyona_git.dart`
/// üzerinden yapılır (`varlik_sayfasi_test` kilitler). Buradaki hiçbir değer
/// portföy toplamına girmez.
///
/// ## Tek kaynak
/// Fiyat serisi `HistoryService.getSymbolHistory` — takip listesi satırıyla
/// AYNI kaynak; başlıktaki fiyat serinin son noktası, ayrı bir canlı fiyat
/// çağrısı yapılmaz (iki kaynak = ayrışan iki sayı). İstatistikler
/// [DonemIstatistigi]'nde, `build()` dışında, seri gelince bir kez hesaplanır.
///
/// ## Performans
///   · Sayfa grafik beklemeden açılır; grafik yeri aynı yükseklikte iskeletle
///     ayrılır, yerleşim zıplamaz.
///   · Altı dönemin serisi AYNI ANDA istenir; seçili dönem kendi yanıtı
///     gelince ötekileri beklemeden çizilir. Dönem değiştirmek çoğu zaman
///     bekleme göstermez; bekletirse eski çizgi soluk kalır, dönen tekerlek
///     gösterilmez.
///   · Çip altındaki getiriler o dönemin KENDİ serisinden gelir — başka bir
///     seriden türetilseydi çip ile başlık aynı dönem için iki sayı yazardı.
Future<void> showVarlikSayfasi(
  BuildContext context,
  VarlikKimligi kimlik, {
  bool tamAcilis = false,
  int? baslangicDonemGun,
  VoidCallback? onSec,
}) async {
  // Satıra hızlı iki dokunuş iki sayfa açmasın (`pushGuarded`'ın gerekçesi).
  if (_acik) return;
  _acik = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Zemin `background` — varlık detayıyla AYNI katman sırası.
      // `colorScheme.surface` (= surface2) iken sayfa, kartlarından ve
      // dönem seçicinin kabuğundan (surface1) daha AÇIKTI: kabuk zeminde
      // kayboluyor, seçili segment (surface2) zeminle aynı tona düşüyor,
      // istatistik kartları çukur gibi duruyordu. Aynı düzeni paylaşan iki
      // ekran iki farklı yükseklik hiyerarşisi çiziyordu (kullanıcı
      // bildirimi 2026-09-28). Sayfa tam yükseklikte açıldığı için sheet
      // yükselti ipucu kaybolmaz: köşe yuvarlağı ve karartma yeter.
      backgroundColor: context.c.background,
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (_) => VarlikSayfasi(
        kimlik: kimlik,
        anaBaglam: context,
        tamAcilis: tamAcilis,
        baslangicDonemGun: baslangicDonemGun,
        onSec: onSec,
      ),
    );
  } finally {
    _acik = false;
  }
}

bool _acik = false;

/// Sayfanın dönemleri (gün). `1` = GÜNLÜK (takvim günü, 5 dakikalık seri).
///
/// Uygulamanın tek dönem kümesinden ([SummaryPeriod]) türetilir
/// (2026-09-28): önceden burada 3A yoktu, Performans'ta 5Y yoktu; seçiciler
/// artık her ekranda birebir aynı. Servis `3mo`/`5y` aralıklarını zaten
/// destekliyor (`HistoryService.rangeForPeriod`).
final varlikSayfasiDonemleri = <int>[
  for (final p in SummaryPeriod.values) p.sembolGunu,
];

/// Seri yükleyici — testte ağ yerine sahte seri verilir.
typedef SeriYukleyici = Future<Map<int, double>> Function(
    String ticker, int periodDays);

class VarlikSayfasi extends ConsumerStatefulWidget {
  const VarlikSayfasi({
    super.key,
    required this.kimlik,
    this.anaBaglam,
    this.tamAcilis = false,
    this.baslangicDonemGun,
    this.onSec,
    this.seriYukleyici,
  });

  final VarlikKimligi kimlik;

  /// Sayfanın ALTINDAKİ ekranın bağlamı. Sayfa kapandıktan sonra "Portföye
  /// ekle" / "Pozisyonuma git" rotası buradan itilir; sayfanın kendi bağlamı
  /// kapanınca geçersizleşir.
  final BuildContext? anaBaglam;

  /// Takip listesinden açılınca tam hâlde başlar: kullanıcı zaten o varlığa
  /// "bakmaya" gelmiştir. Aramadan açılınca yarım hâlde başlar; liste arkada
  /// görünür kalır.
  final bool tamAcilis;

  final int? baslangicDonemGun;

  /// Verilirse (varlık ekleme seçicisi) birincil eylem "Bunu seç" olur.
  final VoidCallback? onSec;

  final SeriYukleyici? seriYukleyici;

  @override
  ConsumerState<VarlikSayfasi> createState() => _VarlikSayfasiState();
}

class _VarlikSayfasiState extends ConsumerState<VarlikSayfasi> {
  static const _yarim = 0.7;
  static const _tam = 0.94;
  /// Grafik kartının dış yüksekliği — ortak grafik stilinden (Performans
  /// stili, 2026-09-28); yükleme/hata kutuları da aynı yükseklikte.
  static const _grafikYuksekligi = GrafikStili.kartYuksekligi;

  final _sayfa = DraggableScrollableController();

  late int _gun = varlikSayfasiDonemleri.contains(widget.baslangicDonemGun)
      ? widget.baslangicDonemGun!
      : 365;

  /// Grafikte ŞU AN çizilen dönem. Yeni dönem yüklenirken eski çizgi soluk
  /// kalır — boş kutu ya da dönen tekerlek yerine bağlam.
  int? _cizilen;

  final Map<int, Map<int, double>> _seriler = {};
  final Map<int, DonemIstatistigi?> _istatistik = {};
  final Set<int> _yukleniyor = {};
  final Set<int> _hatali = {};

  bool _takipIslemi = false;

  /// Açılış kapısı açıldı mı (bkz. `utils/acilis_kapisi.dart`): altı dönem
  /// ve sinyal serisi geldi ya da süre doldu. Bir kez `true` olur.
  bool _acildi = false;

  @override
  void initState() {
    super.initState();
    CrashReporter.arkaPlan(_ilkYukleme(), reason: 'VarlikSayfasi.ilkYukleme');
    // Arama ekranının "Son baktıkların" şeridi — hangi girişten açıldıysa
    // (arama, takip, karşılaştır, ekleme seçicisi) bakılan varlık odur.
    final uid = ref.read(authProvider).valueOrNull?.id;
    // Demo (F1): "son bakılanlar" diske yazılır ve gerçek hesapta görünürdü.
    if (uid != null && !DemoModu.aktif) {
      CrashReporter.arkaPlan(
          SonBakilanlar.instance.kaydet(uid, widget.kimlik),
          reason: 'VarlikSayfasi.sonBakilan');
    }
  }

  @override
  void dispose() {
    _sayfa.dispose();
    super.dispose();
  }

  Future<void> _ilkYukleme() async {
    // Altı dönem AYNI ANDA istenir (kullanıcı kararı 2026-09-28: "tüm
    // varlıklar için paralel çağrı"). İlk sürüm seçili dönemi tek başına,
    // kalanları ikişer ikişer çekiyordu — dört dalga ardı ardına bekliyordu
    // ve son çip getirisi ancak dördüncü yanıttan sonra doluyordu.
    //
    // Seçili dönem yine ÖNCE başlatılır ve kendi yanıtı gelir gelmez
    // çizilir (`_yukle` her dönemi bağımsız `setState` eder); ötekileri
    // beklemez. Aşırı yük kaygısı yok: `HistoryService` aynı anahtardaki
    // uçuşan isteği tekilleştirir, önbellekte olan dönem ağa hiç çıkmaz.
    //
    // Açılış kapısı (kullanıcı kararı 2026-09-28): dönemler ve sinyal
    // panelinin serisi aynı anda istenir, sayfa hepsi gelince BİRLİKTE
    // dolar — çipler birer birer, panel en son dolmaz. Panel aynı seriyi
    // `HistoryService` önbelleğinden alır. Testte yükleyici verilmişse
    // (ağsız) sinyal serisi burada istenmez.
    await acilisKapisi([
      _yukle(_gun),
      for (final g in varlikSayfasiDonemleri)
        if (g != _gun) _yukle(g),
      if (widget.seriYukleyici == null && widget.kimlik.ticker.isNotEmpty)
        HistoryService.instance.getSymbolHistory(widget.kimlik.ticker,
            periodDays: kSinyalPenceresiGun),
    ]);
    if (!mounted) return;
    await rotaGecisiniBekle(context);
    if (mounted) setState(() => _acildi = true);
  }

  Future<void> _yukle(int gun) async {
    if (_seriler.containsKey(gun) || _yukleniyor.contains(gun)) return;
    setState(() {
      _yukleniyor.add(gun);
      _hatali.remove(gun);
    });
    try {
      final yukleyici = widget.seriYukleyici ??
          (t, d) => HistoryService.instance.getSymbolHistory(t, periodDays: d);
      final seri = await yukleyici(widget.kimlik.ticker, gun);
      if (!mounted) return;
      setState(() {
        _yukleniyor.remove(gun);
        _seriler[gun] = seri;
        _istatistik[gun] = DonemIstatistigi.hesapla(seri, periodDays: gun);
        if (gun == _gun) _cizilen = gun;
      });
    } catch (e, st) {
      // Ağ hatası kullanıcıya dönem kutusunda söylenir; sessiz kalmasın diye
      // Crashlytics'e de non-fatal gider (CLAUDE.md "Hata gösterimi").
      CrashReporter.report(e, st, reason: 'VarlikSayfasi._yukle');
      if (!mounted) return;
      setState(() {
        _yukleniyor.remove(gun);
        _hatali.add(gun);
      });
    }
  }

  void _donemSec(int gun) {
    setState(() {
      _gun = gun;
      if (_seriler.containsKey(gun)) _cizilen = gun;
    });
    // Hatalı dönem yeniden seçilince yeniden dener — çıkış yolu açık.
    CrashReporter.arkaPlan(_yukle(gun), reason: 'VarlikSayfasi.donemSec');
  }

  void _boyutuDegistir() {
    if (!_sayfa.isAttached) return;
    final hedef = _sayfa.size < (_yarim + _tam) / 2 ? _tam : _yarim;
    final sure = SandikMotion.of(context, SandikMotion.surface);
    if (sure == Duration.zero) {
      _sayfa.jumpTo(hedef);
    } else {
      _sayfa.animateTo(hedef, duration: sure, curve: SandikMotion.enter);
    }
  }

  /// Tutamaçtan sürükleme: parmağın dikey hareketi sayfa oranına çevrilir.
  /// Yarım boyutun altına inen çekiş kapatmaya sayılır (modalın kendi
  /// jestiyle aynı his).
  double _asagiTasma = 0;

  void _surukle(DragUpdateDetails d) {
    if (!_sayfa.isAttached) return;
    final h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return;
    final yeni = _sayfa.size - d.delta.dy / h;
    if (yeni < _yarim) {
      _asagiTasma += d.delta.dy;
      _sayfa.jumpTo(_yarim);
      return;
    }
    _asagiTasma = 0;
    _sayfa.jumpTo(yeni.clamp(_yarim, _tam));
  }

  void _birak(DragEndDetails d) {
    if (!_sayfa.isAttached) return;
    final hiz = d.primaryVelocity ?? 0; // + aşağı
    final tasma = _asagiTasma;
    _asagiTasma = 0;
    final yarimda = _sayfa.size <= _yarim + 0.01;
    if (yarimda && (tasma > SandikTouch.min * 2 || hiz > 700)) {
      Navigator.of(context).maybePop();
      return;
    }
    final hedef = hiz < -300
        ? _tam
        : hiz > 300
            ? _yarim
            : (_sayfa.size < (_yarim + _tam) / 2 ? _yarim : _tam);
    final sure = SandikMotion.of(context, SandikMotion.surface);
    if (sure == Duration.zero) {
      _sayfa.jumpTo(hedef);
    } else {
      _sayfa.animateTo(hedef, duration: sure, curve: SandikMotion.enter);
    }
  }

  String _donemEtiketi(int gun) => donemEtiketi(
      context.l10n,
      SummaryPeriod.values[varlikSayfasiDonemleri.indexOf(gun).clamp(
              0, SummaryPeriod.values.length - 1)]
          .label);

  @override
  Widget build(BuildContext context) {
    final k = widget.kimlik;
    return Semantics(
      label: context.l10n.vsSheetSemantics(k.name),
      container: true,
      child: DraggableScrollableSheet(
        controller: _sayfa,
        expand: false,
        initialChildSize: widget.tamAcilis ? _tam : _yarim,
        minChildSize: 0.5,
        maxChildSize: _tam,
        snap: true,
        snapSizes: const [_yarim],
        builder: (ctx, sc) => Stack(
          children: [
            Column(
              children: [
                // Tutamaç + başlık sayfayı İKİ YÖNE de sürükler (kullanıcı
                // bildirimi 2026-09-28): `DraggableScrollableSheet` yalnızca
                // kendi kaydırma denetleyicisine bağlı listeden büyür;
                // liste dışındaki tutamaçta aşağı çekmek modalın kapatma
                // jestine düşüyor, yukarı çekmek hiçbir şey yapmıyordu.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _surukle,
                  onVerticalDragEnd: _birak,
                  child: Column(children: [_tutamac(), _baslik()]),
                ),
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: EdgeInsets.fromLTRB(
                      SandikSpace.screenH(context),
                      SandikSpace.xs,
                      SandikSpace.screenH(context),
                      // Alt çubuğun altında içerik kalmasın.
                      96 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    children: _govde(),
                  ),
                ),
              ],
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _altCubuk()),
          ],
        ),
      ),
    );
  }

  // ── Üst kısım ─────────────────────────────────────────────────────────────

  /// Tutamaç — sürüklenir; dokununca yarım ↔ tam arasında geçer (sürükleme
  /// jestini bilmeyen kullanıcı için ikinci yol).
  Widget _tutamac() => SandikTappable(
        onTap: _boyutuDegistir,
        semanticLabel: context.l10n.vsSheetSemantics(widget.kimlik.name),
        child: const SizedBox(
          width: 120,
          height: SandikTouch.min,
          child: Center(child: _TutamacCizgisi()),
        ),
      );

  Widget _baslik() {
    final k = widget.kimlik;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          SandikSpace.screenH(context), 0, SandikSpace.xs, SandikSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k.kisaEtiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90),
                ),
                Text(
                  '${k.name} · ${k.type.labelOf(context.l10n)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.close,
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: context.c.text58),
            constraints: const BoxConstraints(
                minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          ),
        ],
      ),
    );
  }

  // ── Gövde ─────────────────────────────────────────────────────────────────

  List<Widget> _govde() {
    final k = widget.kimlik;
    final cizilen = _cizilen;
    final ist = cizilen == null ? null : _istatistik[cizilen];
    // Fiyatın sembolü kotasyonun para birimi: dolar kuru "₺49,00", "$" değil
    // (2026-09-29 emülatör testi #13; bkz. [kotasyonSembolu]).
    final bicim =
        tryFormatter(digits: 2, symbol: kotasyonSembolu(k.ticker, k.currency));
    final bayat = cizilen != null && cizilen != _gun;

    if (!_acildi) {
      return const [VarlikIskeleti(grafikYuksekligi: _grafikYuksekligi)];
    }
    return [
      _fiyatBlogu(ist, bicim, cizilen),
      const SizedBox(height: SandikSpace.smd),
      // Seçici grafiğin ÜSTÜNDE — Performans ve varlık detayıyla aynı sıra
      // (kullanıcı kararı 2026-09-28; gerekçe
      // `portfolio_performance/kartlar.dart` kontrol yığını notu).
      _donemCipleri(),
      const SizedBox(height: SandikSpace.sm),
      _grafik(ist, bicim, cizilen, bayat),
      const SizedBox(height: SandikSpace.md),
      if (ist != null) ...[
        _istatistikIzgarasi(ist, cizilen!),
        const SizedBox(height: SandikSpace.sm),
        _aralikCubugu(ist, bicim),
        const SizedBox(height: SandikSpace.lg),
      ],
      FonKarnesiKarti(tur: k.type, ticker: k.ticker),
      // Sahip olunmayan varlık için de teknik göstergeler hesaplanır; panel
      // bir `Asset` istemez.
      TechnicalSignalPanel(
        ticker: k.ticker,
        type: k.type,
        subCategory: k.subCategory,
      ),
      // AL/SAT sinyali gösteren her yüzey yasal ibareyi de taşır.
      const SizedBox(height: SandikSpace.sm),
      const DisclaimerWidget(),
      const SizedBox(height: SandikSpace.md),
      Text(
        portfoydeMi(ref, k)
            ? context.l10n.vsOwnedNote
            : context.l10n.unitPriceDiffNote,
        textAlign: TextAlign.center,
        style: context.t.bodySmall?.copyWith(color: context.c.text36),
      ),
    ];
  }

  Widget _fiyatBlogu(
      DonemIstatistigi? ist, NumberFormat bicim, int? cizilen) {
    final renk = ist == null || ist.isFlat
        ? context.c.text36
        : context.signColor(ist.degisimPct);
    final donem = cizilen == null ? '' : _donemEtiketi(cizilen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.currentPriceUpper,
          style: context.t.labelSmall?.copyWith(
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: context.c.text36),
        ),
        const SizedBox(height: SandikSpace.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            ist == null ? '—' : bicim.format(ist.son),
            maxLines: 1,
            style: context.t.numLarge.copyWith(color: context.c.text90),
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          ist == null
              ? ' '
              : ist.isFlat
                  ? context.l10n.periodNoChange(donem)
                  : '${fmtPctIsaretli(ist.degisimPct)} · '
                      '${ist.fark >= 0 ? '+' : '−'}'
                      '${bicim.format(ist.fark.abs())} · $donem',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.numSmall.copyWith(color: renk),
        ),
      ],
    );
  }

  Widget _grafik(
      DonemIstatistigi? ist, NumberFormat bicim, int? cizilen, bool bayat) {
    final seri = cizilen == null ? null : _seriler[cizilen];
    if (seri == null || ist == null) {
      // Seçili dönem hatalıysa ve çizilecek başka seri yoksa: neden ve çıkış
      // yolu. Aksi halde aynı yükseklikte iskelet (yerleşim zıplamaz).
      if (_hatali.contains(_gun)) {
        return SizedBox(
          height: _grafikYuksekligi,
          child: Center(
            child: Text(
              context.l10n.vsLoadFailed,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        );
      }
      if (!_yukleniyor.contains(_gun) && seri != null) {
        return SizedBox(
          height: _grafikYuksekligi,
          child: Center(
            child: Text(
              context.l10n.notEnoughHistoryForAsset,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        );
      }
      return const SandikSkeletonChart(height: _grafikYuksekligi);
    }
    return AnimatedOpacity(
      opacity: bayat ? 0.35 : 1.0,
      duration: SandikMotion.of(context, SandikMotion.state),
      curve: SandikMotion.enter,
      child: FiyatGrafigi(
        seri: seri,
        periodDays: cizilen!,
        bicim: bicim,
        semanticLabel: context.l10n
            .vsChartSemantics(widget.kimlik.name, _donemEtiketi(cizilen)),
      ),
    );
  }

  /// Dönem seçici — ortak [DonemSecici]; her segmentin altında o dönemin
  /// getirisi. Seçici böylece aynı zamanda bir getiri şeridi olur: "son bir
  /// yılda ne yaptı" sorusu dokunmadan cevaplanır (eski çiplerin işi,
  /// tek görünüş kararıyla kabuğa taşındı, 2026-09-28).
  Widget _donemCipleri() {
    return DonemSecici(
      donemler: SummaryPeriod.values,
      secili: varlikSayfasiDonemleri.indexOf(_gun),
      getiriler: [
        for (final g in varlikSayfasiDonemleri) _istatistik[g]?.degisimPct,
      ],
      onSec: (i) => _donemSec(varlikSayfasiDonemleri[i]),
    );
  }

  Widget _istatistikIzgarasi(DonemIstatistigi ist, int gun) =>
      DonemIstatistikIzgarasi(
        ist: ist,
        gun: gun,
        donemPct: ist.degisimPct,
        bugunPct: _istatistik[1]?.degisimPct,
      );

  /// Dönem aralığı: dip ve zirve arasında bugünkü fiyatın yeri.
  Widget _aralikCubugu(DonemIstatistigi ist, NumberFormat bicim) =>
      DonemAralikCubugu(
        dusuk: ist.dusuk,
        yuksek: ist.yuksek,
        konum: ist.konum,
        bicim: bicim,
      );

  // ── Alt çubuk ─────────────────────────────────────────────────────────────

  /// Duruma göre alt çubuk:
  ///   · seçiciden açıldıysa → [Takip et] [Bunu seç]
  ///   · portföyde           → ([Takipte]) [Pozisyonuma git]
  ///   · diğer               → [Takip et | Takipte] [Portföyüme ekle]
  /// Portföy yüklenirken birincil eylem pasif: sahip olunan varlıkta bir an
  /// "Portföyüme ekle" görünmesi ikinci bir kayıt açtırabilirdi.
  Widget _altCubuk() {
    final k = widget.kimlik;
    final takipte = (ref.watch(watchlistProvider).valueOrNull ?? const [])
        .any((w) => w.key == k.key);
    final yukleniyor = portfoyYukleniyor(ref);
    final sahip = !yukleniyor && portfoydeMi(ref, k);
    final l = context.l10n;

    final Widget birincil;
    if (widget.onSec != null) {
      birincil = _birincilDugme(
        etiket: l.vsSelect,
        ikon: Icons.check_rounded,
        onPressed: () {
          Navigator.pop(context);
          widget.onSec!();
        },
      );
    } else if (sahip) {
      birincil = _birincilDugme(
        etiket: l.vsGoToPosition,
        ikon: Icons.arrow_forward_rounded,
        onPressed: () => _sayfadanGec((ctx) => pozisyonuAc(ctx, ref, k)),
      );
    } else {
      birincil = _birincilDugme(
        etiket: l.addToMyPortfolio,
        ikon: Icons.add_rounded,
        onPressed: yukleniyor
            ? null
            : () => _sayfadanGec((ctx) => portfoyeEkleAc(ctx, k)),
      );
    }

    // Portföydeki varlıkta takip düğmesi yalnızca zaten takipteyse görünür
    // (çıkarabilmek için); yeni takip önerilmez — ikisi aynı şeyi izler.
    final takipDugmesi = !sahip || takipte || widget.onSec != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.smd,
        SandikSpace.screenH(context),
        SandikSpace.smd + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.c.hairline)),
      ),
      child: Row(
        children: [
          if (takipDugmesi) ...[
            _takipDugmesi(takipte),
            const SizedBox(width: SandikSpace.sm),
          ],
          Expanded(child: birincil),
        ],
      ),
    );
  }

  /// Sayfayı kapatıp alttaki ekrandan rota iter. Sayfanın kendi bağlamı
  /// kapanınca geçersizleşir; rota ALTTAKİ ekranın bağlamından itilir.
  void _sayfadanGec(void Function(BuildContext ctx) git) {
    final alt = widget.anaBaglam;
    Navigator.pop(context);
    if (alt != null && alt.mounted) git(alt);
  }

  Widget _birincilDugme({
    required String etiket,
    required IconData ikon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(ikon, size: 18),
        label: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
          textStyle:
              context.t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md)),
        ),
      ),
    );
  }

  Widget _takipDugmesi(bool takipte) {
    final k = widget.kimlik;
    final l = context.l10n;
    // Ekran okuyucu eylemi okur ("THYAO takibe al"), yalnızca görünen
    // "Takip et" etiketini değil.
    return Semantics(
      toggled: takipte,
      label: takipte ? l.vsUnwatchSemantics(k.name) : l.vsWatchSemantics(k.name),
      child: SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _takipIslemi ? null : () => _takipDegistir(takipte),
          icon: Icon(takipte ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20, color: takipte ? context.c.gold : context.c.text90),
          label: Text(
            takipte ? l.watchlistInListLabel : l.vsWatch,
            maxLines: 1,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.c.text90,
            side: BorderSide(color: context.c.hairline),
            textStyle:
                context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md)),
          ),
        ),
      ),
    );
  }

  /// Takibe al / takipten çıkar — kural ve mesajlar `takipDegistir`'de
  /// (portföy varlık detayıyla ortak).
  Future<void> _takipDegistir(bool takipte) async {
    setState(() => _takipIslemi = true);
    try {
      await takipDegistir(context, ref, widget.kimlik, takipte: takipte);
    } finally {
      if (mounted) setState(() => _takipIslemi = false);
    }
  }
}

/// Sayfa tutamacının çizgisi — dokunma hedefi [_VarlikSayfasiState._tutamac]
/// (44pt); çizgi yalnızca görsel işaret.
class _TutamacCizgisi extends StatelessWidget {
  const _TutamacCizgisi();

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: SandikSpace.xs,
        decoration: BoxDecoration(
          color: context.c.text20,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
      );
}
