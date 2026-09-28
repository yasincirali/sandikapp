import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart';
import '../services/varlik_istatistik.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/fiyat_grafigi.dart';
import '../widgets/sandik_skeleton.dart';
import 'asset_detail_screen.dart' show TechnicalSignalPanel;
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
/// Performans ekranı ve takip listesiyle AYNI etiketler; 5Y yalnızca burada
/// — "bu varlık uzun vadede ne yaptı" sorusu almadan önce sorulur, sahip
/// olunan varlıkta sorulmaz. Servis `5y` aralığını zaten destekliyor
/// (`HistoryService.rangeForPeriod`).
const varlikSayfasiDonemleri = <int>[1, 7, 30, 180, 365, 1825];

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
  static const _grafikYuksekligi = 220.0;

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

  @override
  void initState() {
    super.initState();
    CrashReporter.arkaPlan(_ilkYukleme(), reason: 'VarlikSayfasi.ilkYukleme');
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
    await Future.wait([
      _yukle(_gun),
      for (final g in varlikSayfasiDonemleri)
        if (g != _gun) _yukle(g),
    ]);
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

  String _donemEtiketi(int gun) {
    final l = context.l10n;
    return switch (gun) {
      1 => l.periodDaily,
      7 => l.period1W,
      30 => l.period1M,
      180 => l.period6M,
      365 => l.period1Y,
      _ => l.period5Y,
    };
  }

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
                _tutamac(),
                _baslik(),
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
    final bicim = tryFormatter(
        digits: 2, symbol: currencySymbolFor(k.ticker, k.currency) ?? '₺');
    final bayat = cizilen != null && cizilen != _gun;

    return [
      _fiyatBlogu(ist, bicim, cizilen),
      const SizedBox(height: SandikSpace.smd),
      _grafik(ist, bicim, cizilen, bayat),
      const SizedBox(height: SandikSpace.sm),
      _donemCipleri(),
      const SizedBox(height: SandikSpace.md),
      if (ist != null) ...[
        _istatistikIzgarasi(ist, cizilen!),
        const SizedBox(height: SandikSpace.sm),
        _aralikCubugu(ist, bicim),
        const SizedBox(height: SandikSpace.lg),
      ],
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
                  : '${ist.degisimPct >= 0 ? '+' : '−'}'
                      '${fmtPct(ist.degisimPct.abs())} · '
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
    final renk = ist.isFlat
        ? context.c.text36
        : context.signColor(ist.degisimPct);
    return AnimatedOpacity(
      opacity: bayat ? 0.35 : 1.0,
      duration: SandikMotion.of(context, SandikMotion.state),
      curve: SandikMotion.enter,
      child: FiyatGrafigi(
        seri: seri,
        periodDays: cizilen!,
        bicim: bicim,
        renk: renk,
        height: _grafikYuksekligi,
        semanticLabel: context.l10n
            .vsChartSemantics(widget.kimlik.name, _donemEtiketi(cizilen)),
      ),
    );
  }

  /// Dönem çipleri — her çipin altında o dönemin getirisi. Çipler böylece
  /// aynı zamanda bir getiri şeridi olur: "son bir yılda ne yaptı" sorusu
  /// dokunmadan cevaplanır.
  Widget _donemCipleri() {
    return Row(
      children: [
        for (final g in varlikSayfasiDonemleri)
          Expanded(child: _cip(g)),
      ],
    );
  }

  Widget _cip(int gun) {
    final secili = gun == _gun;
    final ist = _istatistik[gun];
    final etiket = _donemEtiketi(gun);
    return SandikTappable(
      onTap: secili ? null : () => _donemSec(gun),
      semanticLabel: ist == null
          ? etiket
          : '$etiket, ${fmtPct(ist.degisimPct, showSign: true)}',
      child: Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        margin: const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
        decoration: context.chip(selected: secili),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              etiket,
              maxLines: 1,
              style: context.t.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: secili ? context.c.amberText : context.c.text58,
              ),
            ),
            Text(
              ist == null ? ' ' : fmtPct(ist.degisimPct, digits: 1, showSign: true),
              maxLines: 1,
              style: context.t.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: ist == null || ist.isFlat
                    ? context.c.text36
                    : context.signColor(ist.degisimPct),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _istatistikIzgarasi(DonemIstatistigi ist, int gun) {
    final bugun = _istatistik[1];
    final l = context.l10n;
    Color yon(double v, {bool duz = false}) =>
        duz ? context.c.text58 : context.signColor(v);

    final hucreler = <(String, String, Color)>[
      (
        l.vsPeriodReturnUpper,
        fmtPct(ist.degisimPct, showSign: true),
        yon(ist.degisimPct, duz: ist.isFlat),
      ),
      (
        l.vsTodayUpper,
        bugun == null ? '—' : fmtPct(bugun.degisimPct, showSign: true),
        bugun == null
            ? context.c.text58
            : yon(bugun.degisimPct, duz: bugun.isFlat),
      ),
      (
        l.vsMaxDrawdownUpper,
        fmtPct(ist.enBuyukDususPct, showSign: true),
        ist.enBuyukDususPct.abs() < 0.005 ? context.c.text58 : context.c.loss,
      ),
      (
        l.vsVolatilityUpper,
        ist.oynaklikPct == null ? '—' : fmtPct(ist.oynaklikPct!),
        context.c.text90,
      ),
    ];

    Widget hucre((String, String, Color) h) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(SandikSpace.smd),
            decoration: context.surfaceCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: SandikSpace.xs),
                Text(h.$2,
                    maxLines: 1,
                    style: context.t.numSmall.copyWith(color: h.$3)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          hucre(hucreler[0]),
          const SizedBox(width: SandikSpace.sm),
          hucre(hucreler[1]),
        ]),
        const SizedBox(height: SandikSpace.sm),
        Row(children: [
          hucre(hucreler[2]),
          const SizedBox(width: SandikSpace.sm),
          hucre(hucreler[3]),
        ]),
        if (ist.oynaklikPct == null &&
            gun < DonemIstatistigi.oynaklikIcinAsgariDonemGun) ...[
          const SizedBox(height: SandikSpace.xs2),
          Text(l.vsVolatilityShortNote,
              style: context.t.bodySmall?.copyWith(color: context.c.text36)),
        ],
      ],
    );
  }

  /// Dönem aralığı: dip ve zirve arasında bugünkü fiyatın yeri.
  Widget _aralikCubugu(DonemIstatistigi ist, NumberFormat bicim) {
    final l = context.l10n;
    final konumYuzde = (ist.konum * 100).round();
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: context.surfaceCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.vsPeriodLow,
                  style: context.t.labelSmall
                      ?.copyWith(color: context.c.text36)),
              Text(l.vsPeriodHigh,
                  style: context.t.labelSmall
                      ?.copyWith(color: context.c.text36)),
            ],
          ),
          const SizedBox(height: SandikSpace.xs2),
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: SandikSpace.smd,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: SandikSpace.xs2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                      gradient: LinearGradient(colors: [
                        context.c.loss.withValues(alpha: 0.7),
                        context.c.amberFill.withValues(alpha: 0.7),
                        context.c.gain.withValues(alpha: 0.7),
                      ]),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * ist.konum - SandikSpace.xs2)
                        .clamp(0.0, c.maxWidth - SandikSpace.smd),
                    child: Container(
                      width: SandikSpace.smd,
                      height: SandikSpace.smd,
                      decoration: BoxDecoration(
                        color: context.c.text90,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(bicim.format(ist.dusuk),
                  style: context.t.numSmall.copyWith(color: context.c.text90)),
              Text(bicim.format(ist.yuksek),
                  style: context.t.numSmall.copyWith(color: context.c.text90)),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(l.vsRangePosition('$konumYuzde'),
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
        ],
      ),
    );
  }

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

  /// Takibe al / takipten çıkar.
  ///
  /// Başarı mesajı YOK (kullanıcı kararı, 2026-09-16): düğmenin durumu
  /// değişir, onay orada. Takipten çıkarma geri alınabilir ("Geri al"),
  /// limit ve ağ hataları mesaj verir — orada geri bildirim tek kanal.
  Future<void> _takipDegistir(bool takipte) async {
    final k = widget.kimlik;
    final notifier = ref.read(watchlistProvider.notifier);
    setState(() => _takipIslemi = true);
    try {
      if (takipte) {
        final kayit = (ref.read(watchlistProvider).valueOrNull ?? const [])
            .where((w) => w.key == k.key)
            .firstOrNull;
        if (kayit == null) return;
        await notifier.remove(kayit.id);
        if (!mounted) return;
        sandikSnack(
          context,
          context.l10n.vsRemovedFromWatchlist(k.kisaEtiket),
          onUndo: () => CrashReporter.arkaPlan(_takibeAl(notifier),
              reason: 'VarlikSayfasi.geriAl'),
        );
      } else {
        await _takibeAl(notifier);
      }
    } catch (e) {
      if (!mounted) return;
      sandikSnackError(context, e,
          prefix: takipte ? context.l10n.removeFromWatchlistFailed : null);
    } finally {
      if (mounted) setState(() => _takipIslemi = false);
    }
  }

  Future<void> _takibeAl(WatchlistNotifier notifier) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    try {
      await notifier.add(widget.kimlik.toWatchlistItem(userId: user.id));
    } on WatchlistLimitException catch (e) {
      if (!mounted) return;
      sandikSnack(context, context.l10n.watchlistLimitReached(e.limit),
          kind: SandikSnackKind.warning);
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
