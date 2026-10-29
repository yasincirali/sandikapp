import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/grafik_cizimi.dart';
import '../models/ohlc.dart';
import '../models/ozel_gosterge.dart';
import '../providers/ozel_gosterge_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../services/gosterge_betigi/betik.dart';
import '../services/ozel_gosterge_calistirici.dart';
import '../services/cizim_deposu.dart';
import '../services/share_card_service.dart';
import '../services/ozellik_olcumu.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart' show FiyatKaynagi, MumKaynakTuru;
import '../services/mum_verisi.dart';
import '../services/technical_analysis_service.dart';
import '../theme/sandik.dart';
import '../utils/hareketli_ortalama.dart' show kEmaKisa, kEmaUzun;
import '../utils/friendly_error.dart' show showAppError;
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/gosterge_cizimi.dart' show betikRengi;
import '../widgets/grafik_arac_cubugu.dart' show GrafikCipi, MumAraligiAdi;
import '../widgets/sandik_async_button.dart';
import '../widgets/tam_ekran/cizim_alarm_dugmesi.dart';
import '../widgets/tam_ekran/grafik_olcegi.dart';
import '../widgets/tam_ekran/grafik_paylasimi.dart';
import 'ozel_gosterge_screen.dart' show showOzelGostergeSayfasi;
import 'paywall_screen.dart' show PaywallScreen;

/// Yatay tam ekran grafik — telefonu yan çevirince açılır.
///
/// ## Neden (yasin, 2026-10-23)
/// *"Yan döndürünce grafiği izlenebilir hale getirebilir miyiz? … trading
/// view'i birebir örnek alabilirsin, mobil uygulamada ux ve ui olarak
/// tutarlı olması gerekiyor, çizgi çektirme özelliğini de ondan alabiliriz."*
/// Önce çalışan bir web demosu gösterildi, sonra benchmark kararı ("önerini
/// yap"): yatay grafik ve çizim araçları ÜCRETSİZ.
///
/// ## Giriş: yalnız yan çevirmek
/// Dik ekrandaki "tam ekran" çipi 2026-09-17'de kullanıcı kararıyla
/// kaldırılmıştı; düğme geri gelmez. Grafik gösteren ekran telefon yan
/// dönünce bu sayfayı iter ([YanCevirinceTamEkran]), telefon dik dönünce
/// sayfa kendini kapatır. Yön kilitlenmez: kullanıcının sistem döndürme
/// kilidi neyse o geçerli.
///
/// ## Düzen (TradingView mobil yatay)
/// Üstte sembol, aralık çipleri, mum/çizgi ve ortalamalar; solda çizim
/// araçları; ortada mumlar, hacim şeridi, sağda fiyat ekseni, altta zaman
/// ekseni. Hareketler: tek parmak kaydırır, iki parmak yakınlaştırır,
/// basılı tutmak imleç (artı) açar, çift dokunuş görünümü sıfırlar.
///
/// ## Veri
/// Mumlar varlık ekranıyla AYNI kaynaktan ([MumVerisi], kaynak kararı
/// [FiyatKaynagi.mumKaynagi]) ve aynı canlı fiyata hizalı (madde 2).
/// Ortalamalar bu mumların kapanışından; seçili hâlleri dik grafikle aynı
/// tercihlerden okunur (MA20/EMA50/EMA200 iki ekranda aynı).
///
/// ## Çizimler
/// Zaman + fiyat olarak saklanır ([GrafikCizimi]); aralık değişince yerinde
/// kalır. Cihazda tutulur ([CizimDeposu]).
///
/// ## Paylaşım (Ar-Ge 25 Eki §2, rapor 13:15 §1)
/// Üst çubuktaki "Grafiği paylaş" grafiği çizimleriyle PNG yapar
/// ([RepaintBoundary] → [ShareCardService]); görsel cihazda üretilir,
/// sunucuya bir şey gitmez. Görselde sembol, dönem, verinin alındığı
/// tarih-saat (eski görüntü yeni sanılmasın), çizimler ve altta sandık
/// marka şeridi ([TamEkranGrafikEkraniState._paylasimSeridi]) var. Görsel
/// bir PAYLAŞIM KİPİNDE üretilir
/// ([TamEkranGrafikEkraniState.paylasimKipi]): imleç, seçim tutamakları,
/// yarım çizim, bildirim ve sil düğmesi çizilmez. Kişisel katman (maliyet
/// çizgisi, lot/alış noktaları, alarm çizgileri, tutar) bu ekranda bugün
/// YOK; eklenirse `_GrafikBoyaci.paylasim` açıkken çizilmemeli —
/// `tam_ekran_grafik_paylas_test` ekranın kişisel veriye erişmediğini tarar
/// ve eklendiğinde kırılır.
///
/// ## Kendi göstergen (ƒx, yasin 2026-10-29)
/// *"Yan çevrildiğinde detaylı grafikte custom Pine kodu için fx
/// girilebilmeli (premium hesapta)."* Dik grafikle AYNI kapı ve kilit:
/// çip yalnız `premiumOzellikleriGorunurProvider`'da, kilitliyse paywall
/// (kaynak `grafik_ozel_gosterge`), değilse aynı göstergeler sayfası.
/// Açık göstergeler bu ekranın mumlarında ortak çalıştırıcıyla
/// ([ozelGostergeleriCalistir]) koşar ve fiyatın üstüne çizilir. Kendi
/// göstergen kişisel veri değil (kullanıcının yazdığı formül; tutar,
/// miktar, maliyet taşımaz) — paylaşım görselinde de çizilir.
class TamEkranGrafikEkrani extends ConsumerStatefulWidget {
  const TamEkranGrafikEkrani({
    super.key,
    required this.varlik,
    required this.ad,
    required this.canliBirim,
    this.ilkAralik,
    this.dikteKapan = true,
  });

  /// Mum kaynağının sorulduğu varlık (`FiyatKaynagi.gozlemVarligi` ya da
  /// portföy lotu). Çizimler [Asset.ticker] altında saklanır.
  final Asset varlik;

  /// Üst çubukta görünen kısa ad (THYAO, US100…).
  final String ad;

  /// Ekrandaki son fiyat; mumlar bunun ölçeğine hizalanır.
  final double canliBirim;

  /// Dik grafikte seçili aralık; yoksa günlük.
  final MumAraligi? ilkAralik;

  /// Telefon dik dönünce sayfa kendini kapatsın mı (testte kapalı).
  final bool dikteKapan;

  /// Sayfayı iter. Hızlı yön değişiminde ikinci kopya açılmaz
  /// ([pushGuarded]).
  static Future<void> ac(
    BuildContext context, {
    required Asset varlik,
    required String ad,
    required double canliBirim,
    MumAraligi? ilkAralik,
  }) =>
      pushGuarded<void>(
        context,
        adaptiveRoute<void>(
          settings: const RouteSettings(name: 'tam_ekran_grafik'),
          fullscreenDialog: true,
          builder: (_) => TamEkranGrafikEkrani(
            varlik: varlik,
            ad: ad,
            canliBirim: canliBirim,
            ilkAralik: ilkAralik,
          ),
        ),
      );

  /// Bu varlıkta tam ekran grafik çizilebilir mi? Mum kaynağı olmayan
  /// (mevduat, elle fiyatlı, "diğer") varlıkta yan çevirmek bir şey açmaz.
  static bool sunulur(Asset a) =>
      FiyatKaynagi.mumKaynagi(a).tur != MumKaynakTuru.yok;

  @override
  ConsumerState<TamEkranGrafikEkrani> createState() =>
      TamEkranGrafikEkraniState();
}

/// Ekranın durumu. Test için açık: çizim ve görünüm okunur.
@visibleForTesting
class TamEkranGrafikEkraniState extends ConsumerState<TamEkranGrafikEkrani> {
  late MumAraligi _aralik;
  List<OhlcBar> _mumlar = const [];
  bool _yukleniyor = true;
  bool _hata = false;
  int _istek = 0;
  bool _mumMu = true;

  List<double> _ma20 = const [], _ema50 = const [], _ema200 = const [];

  GrafikGorunumu? _gorunum;
  GrafikOlcegi? _olcek;
  Size _alan = Size.zero;
  double _fiyatEkseni = 56;

  List<GrafikCizimi> _cizimler = const [];
  final List<List<GrafikCizimi>> _gecmis = [];
  CizimTuru? _arac;
  bool _miknatis = false;
  int _secili = -1;
  GrafikCizimi? _bekleyen;
  bool _ikinciNoktaBekleniyor = false;
  Offset? _imlec;

  final Map<int, Offset> _isaretciler = {};
  _Jest? _jest;
  Timer? _uzunBasma;
  ({Duration t, Offset p})? _sonDokunus;
  ({Duration t, Offset p, int id})? _dokunusBasi;

  String? _bildirim;
  Timer? _bildirimZamani;
  bool _kapaniyor = false;

  /// Görsel üretilirken açık: kişisel/geçici katmanlar çizilmez, başlık ve
  /// imza görünür. Bir-iki karelik; paylaşım sayfası açılmadan kapanır.
  bool _paylasimKipi = false;
  final GlobalKey _paylasimSiniri = GlobalKey();

  /// Kendi göstergelerin girdisi: bu ekranın mumları, X = mum indeksi
  /// (boyacının ölçeğiyle aynı eksen). Mumlar değişince yeniden kurulur.
  BetikVerisi? _betikVerisi;

  /// Bu karede açık göstergelerin sonuçları (build başında bir kez; ölçek,
  /// boyacı ve lejant aynı listeyi okur). Çalıştırıcı kod + veri parmak
  /// iziyle saklar; imleç/zoom kareleri betiği yeniden koşturmaz.
  List<OzelSonuc> _ozel = const [];

  /// Mumların bu ekrana geldiği an — görseldeki "… itibarıyla". Önbellek
  /// en fazla 10 dk eskidir (`MumVerisi`), saat kadar hassas değil ama
  /// "dün akşamki görüntü" ile "bugünkü"nü ayırır.
  DateTime? _veriZamani;

  /// Testte PNG üretimi + sistem paylaşım sayfası yerine geçer (widget
  /// testinde `toImage` ve platform kanalı yok).
  @visibleForTesting
  static Future<void> Function(GlobalKey sinir, String metin, Rect? kaynak)?
      paylasimTesti;

  // ── Test okumaları ────────────────────────────────────────────────────
  List<GrafikCizimi> get cizimler => _cizimler;
  GrafikGorunumu? get gorunum => _gorunum;
  GrafikOlcegi? get olcek => _olcek;
  int get secili => _secili;
  Offset? get imlec => _imlec;
  CizimTuru? get arac => _arac;
  MumAraligi get aralik => _aralik;
  bool get paylasimKipi => _paylasimKipi;

  static const double _zamanEkseni = 22;

  List<MumAraligi> get _araliklar =>
      FiyatKaynagi.mumKaynagi(widget.varlik).araliklar;

  @override
  void initState() {
    super.initState();
    final gecerli = _araliklar;
    final ilk = widget.ilkAralik;
    _aralik = ilk != null && gecerli.contains(ilk)
        ? ilk
        : (gecerli.contains(MumAraligi.gun1)
            ? MumAraligi.gun1
            : (gecerli.isEmpty ? MumAraligi.gun1 : gecerli.first));
    // Tek giriş yan çevirmek (dik ekrandaki çip 2026-09-17'de kalktı);
    // açılış burada sayılır.
    OzellikOlcumu.say(Ozellik.yatayGrafik);
    CrashReporter.arkaPlan(_cizimleriOku(), reason: 'TamEkranGrafik.cizimOku');
    CrashReporter.arkaPlan(_yukle(), reason: 'TamEkranGrafik.mumlar');
  }

  @override
  void dispose() {
    _uzunBasma?.cancel();
    _bildirimZamani?.cancel();
    super.dispose();
  }

  // ── Veri ──────────────────────────────────────────────────────────────

  Future<void> _cizimleriOku() async {
    final c = await CizimDeposu.instance.oku(widget.varlik.ticker);
    if (!mounted) return;
    setState(() => _cizimler = c);
  }

  void _kaydet() {
    CrashReporter.arkaPlan(
        CizimDeposu.instance.yaz(widget.varlik.ticker, _cizimler),
        reason: 'TamEkranGrafik.cizimYaz');
    // Çizgi zili (0170): çizim taşındı/silindiyse sunucudaki karşılığı da
    // taşınır/silinir. Zil kurulmamış sembolde hiçbir şey yapmaz.
    CrashReporter.arkaPlan(
        cizimAlarmlariniEsitle(ref,
            varlik: widget.varlik,
            canliBirim: widget.canliBirim,
            cizimler: _cizimler,
            olcek: _olcek,
            bildir: (m) {
              if (mounted) _bildir(m);
            },
            l10n: context.l10n),
        reason: 'TamEkranGrafik.zilEsitle');
  }

  /// Seçili çizime kalıcı kimlik verir (eski kayıtlarda yoktur) ve kaydeder.
  String _seciliKimligi() {
    final c = _cizimler[_secili];
    if (c.id != null) return c.id!;
    final id = GrafikCizimi.yeniKimlik();
    setState(() => _cizimler = [..._cizimler]..[_secili] = c.copyWith(id: id));
    _kaydet();
    return id;
  }

  /// Aralığın penceresi: ~400 mum (TradingView mobilin ilk yüklemesi
  /// kadar); gün içinde seans boşlukları için duvar saatinde 3 kat geri.
  /// Yahoo'nun geriye verdiği sınır aşılmaz, aşarsa istek boş dönerdi.
  Future<void> _yukle() async {
    final ar = _aralik;
    final n = ++_istek;
    // İlk yükleme initState'ten senkron başlar; orada setState yasak.
    _yukleniyor = true;
    _hata = false;
    if (n > 1) setState(() {});
    final son = DateTime.now();
    var bas = son.subtract(Duration(
        minutes: (ar.dakika * 400 * (ar.gunIci ? 3 : 1.5)).round()));
    final sinir = ar.yahooGecmisGun;
    if (sinir != null) {
      final enEski = son.subtract(Duration(days: sinir));
      if (bas.isBefore(enEski)) bas = enEski;
    }
    final barlar = await MumVerisi.instance.mumlar(
      a: widget.varlik,
      aralik: ar,
      bas: bas,
      son: son,
      canliBirim: widget.canliBirim,
    );
    if (!mounted || n != _istek) return;
    final temiz = [
      for (final b in barlar)
        if (b.gecerli) b
    ];
    final kapanis = [for (final b in temiz) b.kapanis];
    setState(() {
      _mumlar = temiz;
      _veriZamani = DateTime.now();
      _hata = temiz.length < 2;
      _yukleniyor = false;
      _ma20 = TechnicalAnalysisService.smaSeries(kapanis, 20);
      _ema50 = TechnicalAnalysisService.emaSeries(kapanis, kEmaKisa);
      _ema200 = TechnicalAnalysisService.emaSeries(kapanis, kEmaUzun);
      // Isınma ayrıca istenmez: pencere ~400 mum ve kullanıcı sondan
      // bakar; ilk [betikIsinmaCubugu] mum ısınmayı kendiliğinden verir.
      _betikVerisi = temiz.length < 2
          ? null
          : betikVerisiMumdan(temiz, ar,
              x: [for (var i = 0; i < temiz.length; i++) i.toDouble()],
              sembol: widget.ad);
      _gorunum = null;
      _imlec = null;
      _bekleyen = null;
      _ikinciNoktaBekleniyor = false;
    });
  }

  void _aralikSec(MumAraligi ar) {
    if (ar == _aralik) return;
    _aralik = ar;
    _secili = -1;
    CrashReporter.arkaPlan(_yukle(), reason: 'TamEkranGrafik.mumlar');
  }

  // ── Ölçek ─────────────────────────────────────────────────────────────

  String _fiyatMetni(double v) =>
      fmtNum(v, digits: v.abs() >= 1 || v == 0 ? 2 : 4);

  /// Ölçek çizimden ÖNCE kurulur: işaretçi olayları aynı ölçeği kullanır.
  GrafikOlcegi? _olcekKur(Size alan, TextStyle eksenStili) {
    _alan = alan;
    final m = _mumlar;
    if (m.length < 2) return null;
    // Fiyat ekseni en uzun etiket kadar geniş: sabit genişlik beş haneli
    // endekste son fiyatı kesiyordu (web demosunda bulundu, 2026-10-23).
    var enUzun = 0.0;
    for (final b in m.length > 300 ? m.sublist(m.length - 300) : m) {
      final w = (TextPainter(
              text: TextSpan(text: _fiyatMetni(b.enYuksek), style: eksenStili),
              textDirection: TextDirection.ltr)
            ..layout())
          .width;
      if (w > enUzun) enUzun = w;
    }
    _fiyatEkseni = enUzun + SandikSpace.md;
    final pw = math.max(40.0, alan.width - _fiyatEkseni);
    final ph = math.max(40.0, alan.height - _zamanEkseni);
    final g = gorunumuSinirla(
        _gorunum ?? varsayilanGorunum(m.length, pw), m.length);
    _gorunum = g;
    final i0 = math.max(0, g.bas.floor()), i1 = math.min(m.length - 1, g.son.ceil());
    var lo = double.infinity, hi = -double.infinity;
    for (var i = i0; i <= i1; i++) {
      lo = math.min(lo, _mumMu ? m[i].enDusuk : m[i].kapanis);
      hi = math.max(hi, _mumMu ? m[i].enYuksek : m[i].kapanis);
    }
    // Fiyatın üstündeki kendi göstergen bandın dışına taşarsa bant onu da
    // kapsar (dik grafikteki kural, yasin 2026-10-11 —
    // `gostergeyiKapsayanBant`). Histogram sayılmaz: sıfırdan çıkan
    // sütunlar fiyat ölçeğini ezerdi.
    for (final r in _ozel) {
      if (!r.s.fiyatUstunde) continue;
      for (final c in r.s.cizgiler) {
        if (c.gizli || c.stil == BetikCizgiStili.histogram) continue;
        for (var k = 0; k < r.s.x.length; k++) {
          final xi = r.s.x[k];
          if (xi < i0 || xi > i1) continue;
          final v = c.degerler[k];
          if (!v.isFinite) continue;
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
      }
    }
    if (!lo.isFinite || !hi.isFinite) {
      lo = m.last.kapanis * 0.98;
      hi = m.last.kapanis * 1.02;
    }
    final pay = (hi - lo) * 0.08;
    final p = pay > 0 ? pay : hi.abs() * 0.01 + 1e-9;
    final hacimVar = m.any((b) => (b.hacim ?? 0) > 0);
    final o = GrafikOlcegi(
      zamanlar: [for (final b in m) b.t],
      aralikMs: barUzunluguMs(m.last.t, _aralik),
      gorunum: g,
      genislik: pw,
      // Hacim şeridi alttaki %18; hacimsiz (endeks, kur) grafikte fiyat
      // bütün yüksekliği kullanır.
      fiyatAlani: hacimVar ? ph * 0.82 : ph,
      dusuk: lo - p,
      yuksek: hi + p,
    );
    _olcek = o;
    return o;
  }

  Size get _cizimAlani => Size(
      math.max(40.0, _alan.width - _fiyatEkseni),
      math.max(40.0, _alan.height - _zamanEkseni));

  CizimNoktasi _noktaya(Offset ekran) {
    final o = _olcek!;
    return _miknatis ? miknatisla(_mumlar, o, ekran) : o.veride(ekran);
  }

  // ── Çizim işlemleri ───────────────────────────────────────────────────

  void _gecmiseYaz() {
    _gecmis.add(List.of(_cizimler));
    if (_gecmis.length > 50) _gecmis.removeAt(0);
  }

  void _aracSec(CizimTuru? t) {
    setState(() {
      _arac = t;
      _bekleyen = null;
      _ikinciNoktaBekleniyor = false;
      _secili = -1;
    });
    if (t != null) {
      _bildir(t.tekNokta
          ? context.l10n.tegIpucuTek
          : context.l10n.tegIpucuIki);
    }
  }

  void _geriAl() {
    if (_gecmis.isEmpty) {
      _bildir(context.l10n.tegGeriYok);
      return;
    }
    setState(() {
      _cizimler = _gecmis.removeLast();
      _secili = -1;
    });
    _kaydet();
  }

  void _hepsiniSil() {
    if (_cizimler.isEmpty) {
      _bildir(context.l10n.tegSilinecekYok);
      return;
    }
    _gecmiseYaz();
    setState(() {
      _cizimler = const [];
      _secili = -1;
    });
    _kaydet();
    _bildir(context.l10n.tegHepsiSilindi);
  }

  void _seciliyiSil() {
    if (_secili < 0 || _secili >= _cizimler.length) return;
    _gecmiseYaz();
    setState(() {
      _cizimler = [..._cizimler]..removeAt(_secili);
      _secili = -1;
    });
    _kaydet();
    _bildir(context.l10n.tegSilindi);
  }

  void _bitir(GrafikCizimi c) {
    _gecmiseYaz();
    setState(() {
      _cizimler = [..._cizimler, c];
      _secili = _cizimler.length - 1;
      _bekleyen = null;
      _ikinciNoktaBekleniyor = false;
      // TradingView varsayılanı: çizimden sonra imlece dönülür.
      _arac = null;
      _imlec = null;
    });
    _kaydet();
    OzellikOlcumu.say(Ozellik.cizim);
    HapticFeedback.selectionClick();
    _bildir(context.l10n.tegCizildi);
  }

  void _bildir(String m) {
    _bildirimZamani?.cancel();
    setState(() => _bildirim = m);
    SemanticsService.sendAnnouncement(
        View.of(context), m, Directionality.of(context));
    _bildirimZamani = Timer(SandikMotion.modal * 5, () {
      if (mounted) setState(() => _bildirim = null);
    });
  }

  // ── İşaretçi ──────────────────────────────────────────────────────────

  bool _eksende(Offset p) {
    final a = _cizimAlani;
    return p.dx > a.width || p.dy > a.height;
  }

  void _asagi(PointerDownEvent e) {
    final o = _olcek;
    if (o == null) return;
    final p = e.localPosition;
    _isaretciler[e.pointer] = p;
    final dokunmatik = e.kind != PointerDeviceKind.mouse;
    if (dokunmatik) {
      _dokunusBasi = _isaretciler.length > 1
          ? null
          : (t: e.timeStamp, p: p, id: e.pointer);
      if (_isaretciler.length > 1) _sonDokunus = null;
    }
    if (_isaretciler.length == 2) {
      _uzunBasma?.cancel();
      if (_jest?.tur == _JestTuru.ciz && !_ikinciNoktaBekleniyor) {
        _bekleyen = null;
      }
      final v = _isaretciler.values.toList();
      _jest = _Jest(_JestTuru.pinch,
          baslangic: Offset((v[0].dx + v[1].dx) / 2, 0),
          mesafe: math.max(1.0, (v[0].dx - v[1].dx).abs()),
          gorunum: _gorunum);
      return;
    }
    if (_isaretciler.length > 2) return;
    if (_eksende(p)) {
      _jest = _Jest(_JestTuru.eksen, baslangic: p, gorunum: _gorunum);
      return;
    }
    final arac = _arac;
    if (arac != null) {
      final n = _noktaya(p);
      if (_ikinciNoktaBekleniyor && _bekleyen != null) {
        setState(() => _bekleyen = _bekleyen!.copyWith(b: n));
        _jest = _Jest(_JestTuru.ciz, baslangic: p, ikinci: true);
        return;
      }
      setState(() {
        _bekleyen = GrafikCizimi(
            tur: arac,
            a: n,
            b: arac.tekNokta ? null : n,
            id: GrafikCizimi.yeniKimlik());
        _imlec = dokunmatik ? p : null;
      });
      _jest = _Jest(_JestTuru.ciz, baslangic: p);
      return;
    }
    final hit = cizimIsabeti(_cizimler, o, p, _cizimAlani);
    if (hit != null) {
      _gecmiseYaz();
      setState(() => _secili = hit.indeks);
      _jest = _Jest(_JestTuru.tasi,
          baslangic: p, tutamak: hit.tutamak, cizim: _cizimler[hit.indeks]);
      return;
    }
    if (_secili >= 0) setState(() => _secili = -1);
    _jest = _Jest(_JestTuru.kaydir, baslangic: p, gorunum: _gorunum);
    if (dokunmatik) {
      _uzunBasma?.cancel();
      _uzunBasma = Timer(kLongPressTimeout, () {
        final j = _jest;
        if (!mounted || j == null || j.tur != _JestTuru.kaydir || j.oynadi) {
          return;
        }
        _jest = _Jest(_JestTuru.imlec, baslangic: p);
        HapticFeedback.selectionClick();
        setState(() => _imlec = p);
      });
    }
  }

  void _hareket(PointerMoveEvent e) {
    final o = _olcek;
    if (o == null) return;
    final p = e.localPosition;
    if (_isaretciler.containsKey(e.pointer)) _isaretciler[e.pointer] = p;
    final j = _jest;
    if (j == null) return;
    switch (j.tur) {
      case _JestTuru.pinch:
        if (_isaretciler.length < 2) return;
        final v = _isaretciler.values.toList();
        final d = math.max(1.0, (v[0].dx - v[1].dx).abs());
        final g0 = j.gorunum ?? _gorunum!;
        final genis0 = g0.son - g0.bas;
        final oran = (j.baslangic.dx / o.genislik).clamp(0.0, 1.0);
        final merkez = g0.bas + oran * genis0;
        final genis = genis0 * j.mesafe / d;
        setState(() => _gorunum =
            (bas: merkez - genis * oran, son: merkez + genis * (1 - oran)));
      case _JestTuru.kaydir:
        final dx = p.dx - j.baslangic.dx;
        if ((p - j.baslangic).distance > 4) {
          j.oynadi = true;
          _uzunBasma?.cancel();
        }
        final g0 = j.gorunum ?? _gorunum!;
        final kayma = dx / o.birim;
        setState(() {
          _gorunum = (bas: g0.bas - kayma, son: g0.son - kayma);
          if (e.kind == PointerDeviceKind.mouse) _imlec = p;
        });
      case _JestTuru.imlec:
        setState(() => _imlec = p);
      case _JestTuru.ciz:
        final b = _bekleyen;
        if (b == null) return;
        final n = _noktaya(p);
        setState(() {
          _bekleyen = b.tur.tekNokta ? b.copyWith(a: n) : b.copyWith(b: n);
          if (e.kind != PointerDeviceKind.mouse) _imlec = p;
        });
      case _JestTuru.tasi:
        final c0 = j.cizim;
        if (c0 == null || _secili < 0 || _secili >= _cizimler.length) return;
        if ((p - j.baslangic).distance > 3) j.oynadi = true;
        final GrafikCizimi yeni;
        if (j.tutamak == 'a') {
          yeni = c0.copyWith(a: _noktaya(p));
        } else if (j.tutamak == 'b') {
          yeni = c0.copyWith(b: _noktaya(p));
        } else {
          // Gövde: iki nokta birlikte, ekranda aynı kadar.
          final d = p - j.baslangic;
          CizimNoktasi kaydir(CizimNoktasi n) => o.veride(o.ekranda(n) + d);
          yeni = GrafikCizimi(
              tur: c0.tur,
              a: kaydir(c0.a),
              b: c0.b == null ? null : kaydir(c0.b!),
              id: c0.id);
        }
        setState(() =>
            _cizimler = [..._cizimler]..[_secili] = yeni);
      case _JestTuru.eksen:
        // Zaman ekseninde sürüklemek yatay ölçekler (TradingView gibi).
        if (j.baslangic.dy <= _cizimAlani.height) return;
        final g0 = j.gorunum ?? _gorunum!;
        final k = math.exp((p.dx - j.baslangic.dx) / -200);
        final genis = (g0.son - g0.bas) * k;
        setState(() => _gorunum = (bas: g0.son - genis, son: g0.son));
    }
  }

  void _hover(PointerHoverEvent e) {
    if (_olcek == null || e.kind != PointerDeviceKind.mouse) return;
    final p = e.localPosition;
    final b = _bekleyen;
    setState(() {
      _imlec = _eksende(p) ? null : p;
      if (_ikinciNoktaBekleniyor && b != null) {
        _bekleyen = b.copyWith(b: _noktaya(p));
      }
    });
  }

  void _yukari(PointerEvent e, {bool iptal = false}) {
    _uzunBasma?.cancel();
    _isaretciler.remove(e.pointer);
    _ciftDokunus(e, iptal: iptal);
    final j = _jest;
    if (j == null) return;
    if (j.tur == _JestTuru.pinch) {
      if (_isaretciler.isEmpty) _jest = null;
      return;
    }
    if (j.tur == _JestTuru.ciz) {
      final b = _bekleyen;
      _jest = null;
      if (b == null || iptal) {
        setState(() => _bekleyen = null);
        return;
      }
      final surukledi = (e.localPosition - j.baslangic).distance > 10;
      if (b.tur.tekNokta || surukledi || j.ikinci) {
        _bitir(b);
      } else {
        // Dokun-bırak: ikinci noktayı bekle.
        setState(() {
          _ikinciNoktaBekleniyor = true;
          _imlec = null;
        });
        _bildir(context.l10n.tegIpucuIkinci);
      }
      return;
    }
    if (j.tur == _JestTuru.tasi) {
      if (!j.oynadi) {
        _gecmis.removeLast();
      } else {
        _kaydet();
      }
    }
    _jest = null;
    if (j.tur == _JestTuru.imlec ||
        (j.tur == _JestTuru.kaydir && e.kind != PointerDeviceKind.mouse)) {
      setState(() => _imlec = null);
    } else {
      setState(() {});
    }
  }

  /// Çift dokunuş = görünümü sıfırla. Yalnız TEK parmakla, kıpırdamadan
  /// yapılan iki kısa dokunuş sayılır: iki parmakla yakınlaştırmanın iki
  /// bırakışı da kısa aralıkla gelir ve web demosunda her yakınlaştırmanın
  /// sonunda görünümü sıfırlıyordu (2026-10-23 testinde bulundu).
  void _ciftDokunus(PointerEvent e, {required bool iptal}) {
    final b = _dokunusBasi;
    _dokunusBasi = null;
    if (iptal ||
        e.kind == PointerDeviceKind.mouse ||
        _arac != null ||
        b == null ||
        b.id != e.pointer) {
      return;
    }
    final kisa = e.timeStamp - b.t < kDoubleTapTimeout &&
        (e.localPosition - b.p).distance < kTouchSlop;
    if (!kisa) {
      _sonDokunus = null;
      return;
    }
    final s = _sonDokunus;
    if (s != null &&
        e.timeStamp - s.t < kDoubleTapTimeout &&
        (e.localPosition - s.p).distance < kDoubleTapSlop &&
        _secili < 0) {
      _sonDokunus = null;
      _sifirla();
      return;
    }
    _sonDokunus = (t: e.timeStamp, p: e.localPosition);
  }

  void _sifirla() {
    setState(() => _gorunum = null);
    _bildir(context.l10n.tegGorunumSifir);
  }

  void _tekerlek(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final o = _olcek, g = _gorunum;
    if (o == null || g == null) return;
    final d = e.scrollDelta;
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed || d.dx.abs() > d.dy.abs()) {
        final kay = (d.dx != 0 ? d.dx : d.dy) / o.birim;
        _gorunum = (bas: g.bas + kay, son: g.son + kay);
      } else {
        final k = math.exp(d.dy * 0.0015);
        final x = math.min(e.localPosition.dx, o.genislik);
        final merkez = o.i(x), oran = x / o.genislik;
        final genis = (g.son - g.bas) * k;
        _gorunum = (bas: merkez - genis * oran, son: merkez + genis * (1 - oran));
      }
    });
  }

  KeyEventResult _tus(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) &&
        _secili >= 0) {
      _seciliyiSil();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _aracSec(null);
      return KeyEventResult.handled;
    }
    final kisayol = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (kisayol && k == LogicalKeyboardKey.keyZ) {
      _geriAl();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Paylaşım ──────────────────────────────────────────────────────────

  /// Ekranda görünen pencerenin dönemi ("6 ay").
  String _donem() {
    final m = _mumlar;
    final g = _gorunum;
    if (m.length < 2 || g == null) return '';
    final i0 = g.bas.round().clamp(0, m.length - 1);
    final i1 = g.son.round().clamp(0, m.length - 1);
    return gorunurDonemEtiketi(context.l10n, m[i0].t, m[i1].t);
  }

  /// Görseli üretir ve paylaşım sayfasını açar. Hata Crashlytics'e ve
  /// kullanıcıya dost metinle; ölçüm yalnız sayfa hatasız açılınca.
  Future<void> _paylas(Rect? kaynak) async {
    if (_mumlar.length < 2) return;
    final metin =
        grafikPaylasimMetni(context.l10n, ad: widget.ad, donem: _donem());
    // Yeni hareket yok: kip yalnız katman çizimini değiştirir, geçiş
    // animasyonu yoktur (hareketi azalt kuralı).
    setState(() => _paylasimKipi = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final test = paylasimTesti;
      if (test != null) {
        await test(_paylasimSiniri, metin, kaynak);
        if (mounted) setState(() => _paylasimKipi = false);
      } else {
        final png = await ShareCardService.renderPng(_paylasimSiniri);
        if (mounted) setState(() => _paylasimKipi = false);
        await ShareCardService.shareImage(
          png,
          text: metin,
          subject: metin.split('\n').first,
          origin: kaynak,
        );
      }
      OzellikOlcumu.say(Ozellik.grafikPaylas);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'TamEkranGrafik.paylas');
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted && _paylasimKipi) setState(() => _paylasimKipi = false);
    }
  }

  /// Görselin altındaki marka şeridi — yalnız paylaşım kipinde.
  ///
  /// ## Neden (yasin 2026-10-29)
  /// *"Yan çevrildiğinde paylaş kısmında sandık marka vurgusu daha net
  /// olmalı."* Eski görselde sağ altta küçük bir "sandık" yazısı vardı,
  /// mağaza bağlantısı yalnız paylaşım METNİNDEydi (görsel tek başına
  /// iletilince kayboluyordu). Şerit, paylaşım kartının başlığıyla aynı dil
  /// (`ShareCard._Baslik`: amber/altın "sandık", w800) + logo; ortada sembol ·
  /// dönem · "sandık ile çizildi" ve veri zamanı, sağda okunur kısa
  /// bağlantı (UTM'siz; metindeki bağlantı kanal etiketini taşımaya devam
  /// eder).
  ///
  /// ## Neden grafiğin DIŞINDA
  /// Şerit [RepaintBoundary]'nin içinde ama çizim alanının altında: eski
  /// başlık mumların ve eksenin üstüne biniyordu. Kip açıkken grafik şerit
  /// kadar kısalır; görünüm (hangi mumlar) değişmez. Tavsiye dili yok
  /// (`tam_ekran_grafik_paylas_test`).
  Widget _paylasimSeridi() {
    final c = context.c;
    final l = context.l10n;
    final z = _veriZamani;
    final dil = Localizations.localeOf(context).toLanguageTag();
    return Container(
      key: const ValueKey('tamEkranImza'),
      constraints: const BoxConstraints(minHeight: SandikSpace.xl + SandikSpace.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.smd, vertical: SandikSpace.xs),
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          const SandikLogo(size: SandikSpace.lg, withBackground: true),
          const SizedBox(width: SandikSpace.sm),
          Text(l.appName,
              style: context.t.titleMedium?.copyWith(
                  color: c.amberText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(width: SandikSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.tegPaylasimMetni(widget.ad, _donem()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
                if (z != null)
                  Text(
                      l.tegPaylasimZamani(
                          DateFormat('d MMM y HH:mm', dil).format(z)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelSmall?.copyWith(color: c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.md),
          Text(grafikPaylasimKisaBaglanti(),
              key: const ValueKey('tamEkranBaglanti'),
              style: context.t.labelSmall?.copyWith(color: c.text58)),
        ],
      ),
    );
  }

  /// `ƒx` çipine dokunuş — dik grafikle aynı yol
  /// (`asset_detail/ozel_gostergeler.dart`, `KatmanliFiyatGrafigi`).
  void _ozelGostergeAc(bool kilitli) {
    if (kilitli) {
      PaywallScreen.show(context, source: 'grafik_ozel_gosterge');
      return;
    }
    showOzelGostergeSayfasi(context,
        onizleme: _betikVerisi, varlikAdi: widget.ad);
  }

  // ── Görünüm ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final yatay = MediaQuery.orientationOf(context) == Orientation.landscape;
    // Üstte göstergeler sayfası ya da düzenleyici varken dik dönmek o
    // sayfayı KAPATMAMALI (maybePop en üstteki rotayı kapatır; yazılan kod
    // kaybolurdu). Bu sayfa yeniden en üste gelince (ModalRoute
    // bağımlılığı build'i yeniden çağırır) hâlâ dikse o zaman kapanır.
    // 2026-10-29, ƒx yatayda açılınca.
    final enUstte = ModalRoute.of(context)?.isCurrent ?? true;
    if (!yatay && widget.dikteKapan && !_kapaniyor && enUstte) {
      // Telefon dik döndü: sayfa kendini kapatır, alttaki dik grafik kalır.
      _kapaniyor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == false) {
          _kapaniyor = false;
          return;
        }
        Navigator.of(context).maybePop();
      });
    }
    _ozel = _ozelSonuclar();
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Focus(
          autofocus: true,
          onKeyEvent: _tus,
          child: Column(
            children: [
              _ustCubuk(),
              Divider(height: 1, thickness: 1, color: c.hairline),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _aracCubugu(),
                    VerticalDivider(width: 1, thickness: 1, color: c.hairline),
                    Expanded(
                      child: RepaintBoundary(
                        key: _paylasimSiniri,
                        child: ColoredBox(
                          color: c.background,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _grafik()),
                              if (_paylasimKipi) _paylasimSeridi(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Açık kendi göstergelerin sonuçları. Kapı kapalı ya da kilitliyse
  /// boş — sağlayıcı izlenmez, betik koşmaz (dik grafikle aynı kural).
  List<OzelSonuc> _ozelSonuclar() {
    final veri = _betikVerisi;
    if (veri == null ||
        !ref.watch(premiumOzellikleriGorunurProvider) ||
        ref.watch(premiumKilitliProvider)) {
      return const [];
    }
    final acik = grafiktekiGostergeler(
        ref.watch(ozelGostergelerProvider).valueOrNull ??
            const <OzelGosterge>[]);
    return ozelGostergeleriCalistir(acik, veri);
  }

  Widget _ustCubuk() {
    final l = context.l10n;
    final c = context.c;
    final ma20 = ref.watch(chartMA20Provider);
    final ozelGorunur = ref.watch(premiumOzellikleriGorunurProvider);
    final ozelKilitli = ref.watch(premiumKilitliProvider);
    final ema50 = ref.watch(chartEma50Provider);
    final ema200 = ref.watch(chartEma200Provider);
    return SizedBox(
      height: SandikTouch.min,
      child: Row(
        children: [
          const SizedBox(width: SandikSpace.smd),
          Text(widget.ad,
              style: context.t.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final ar in _araliklar)
                  Semantics(
                    label: l.chartIntervalSemantics(ar.uzunAdi(context)),
                    selected: ar == _aralik,
                    button: true,
                    excludeSemantics: true,
                    child: GrafikCipi(
                      label: ar.etiketi(context),
                      active: ar == _aralik,
                      onTap: () => _aralikSec(ar),
                    ),
                  ),
                const SizedBox(width: SandikSpace.sm),
                GrafikCipi(
                  label: 'MA20',
                  active: ma20,
                  onTap: () => ref.read(chartMA20Provider.notifier).set(!ma20),
                ),
                GrafikCipi(
                  label: 'EMA50',
                  active: ema50,
                  renk: c.gain,
                  onTap: () =>
                      ref.read(chartEma50Provider.notifier).set(!ema50),
                ),
                GrafikCipi(
                  label: 'EMA200',
                  active: ema200,
                  renk: c.loss,
                  onTap: () =>
                      ref.read(chartEma200Provider.notifier).set(!ema200),
                ),
                // Kendi göstergen — dik araç çubuğundaki çiple aynı etiket,
                // kilit ve anlam (`GrafikAracCubugu`).
                if (ozelGorunur)
                  Semantics(
                    label: l.ozgCipSemantik,
                    child: GrafikCipi(
                      key: const ValueKey('tamEkranOzelGosterge'),
                      label: _ozel.isNotEmpty ? 'ƒx ${_ozel.length}' : 'ƒx',
                      active: _ozel.isNotEmpty,
                      kilitli: ozelKilitli,
                      onTap: () => _ozelGostergeAc(ozelKilitli),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: _mumMu ? l.tegCizgiyeGec : l.tegMumaGec,
            onPressed: () => setState(() => _mumMu = !_mumMu),
            icon: CustomPaint(
              size: const Size.square(20),
              painter: _AracIkonu(_mumMu ? _Ikon.mum : _Ikon.cizgi, c.text58),
            ),
          ),
          // İstek atan düğme kalıbı (SandikAsyncTap): görsel üretilirken
          // kilitli, ikinci dokunuş yutulur. Hedef IconButton'larla aynı
          // 48 pt; simge platformun paylaş simgesi (HIG sistem kalıbı).
          // container: yoksa etiket üst çubuğun ve grafiğin özetiyle tek
          // düğüme karışıyordu (ekran okuyucu hepsini tek parça okuyordu).
          Builder(builder: (bctx) {
            final hazir = _mumlar.length >= 2;
            return Semantics(
              container: true,
              child: Tooltip(
                message: l.tegPaylas,
                // Etiket SandikAsyncTap'ten; ipucu ikinci kez okunmasın.
                excludeFromSemantics: true,
                child: SandikAsyncTap(
                  key: const ValueKey('tamEkranPaylas'),
                  semanticLabel: l.tegPaylas,
                  onTap: hazir
                      ? () => _paylas(ShareCardService.originOf(bctx))
                      : null,
                  child: SizedBox.square(
                    dimension: kMinInteractiveDimension,
                    child: Center(
                      child: Icon(Icons.adaptive.share,
                          color: hazir ? c.text58 : c.text36),
                    ),
                  ),
                ),
              ),
            );
          }),
          IconButton(
            tooltip: l.tegKapat,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: c.text58),
          ),
          const SizedBox(width: SandikSpace.xs),
        ],
      ),
    );
  }

  Widget _aracCubugu() {
    final l = context.l10n;
    final araclar = <(CizimTuru?, String, _Ikon)>[
      (null, l.tegAracImlec, _Ikon.imlec),
      (CizimTuru.trend, l.tegAracTrend, _Ikon.trend),
      (CizimTuru.isin, l.tegAracIsin, _Ikon.isin),
      (CizimTuru.yatay, l.tegAracYatay, _Ikon.yatay),
      (CizimTuru.yatayIsin, l.tegAracYatayIsin, _Ikon.yatayIsin),
      (CizimTuru.kutu, l.tegAracKutu, _Ikon.kutu),
    ];
    return SizedBox(
      width: SandikTouch.min + SandikSpace.xs,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Column(
          children: [
            for (final (tur, ad, ikon) in araclar)
              _AracDugmesi(
                etiket: ad,
                ikon: ikon,
                secili: _arac == tur,
                onTap: () => _aracSec(tur),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
              child: SizedBox(
                  width: SandikSpace.lg,
                  height: 1,
                  child: ColoredBox(color: context.c.hairline)),
            ),
            _AracDugmesi(
              etiket: l.tegMiknatis,
              ikon: _Ikon.miknatis,
              secili: _miknatis,
              onTap: () {
                setState(() => _miknatis = !_miknatis);
                _bildir(_miknatis ? l.tegMiknatisAcik : l.tegMiknatisKapali);
              },
            ),
            _AracDugmesi(
              etiket: l.tegGeriAl,
              ikon: _Ikon.geri,
              secili: false,
              onTap: _geriAl,
            ),
            _AracDugmesi(
              etiket: l.tegHepsiniSil,
              ikon: _Ikon.cop,
              secili: false,
              onTap: _hepsiniSil,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grafik() {
    final c = context.c;
    final l = context.l10n;
    if (_yukleniyor && _mumlar.isEmpty) {
      return const Center(child: CustomLoadingIndicator());
    }
    if (_hata && _mumlar.length < 2) {
      return Center(
        child: TextButton(
          onPressed: () =>
              CrashReporter.arkaPlan(_yukle(), reason: 'TamEkranGrafik.mumlar'),
          child: Text(l.tegYuklenemedi,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: c.text58)),
        ),
      );
    }
    final eksenStili = (context.t.labelSmall ?? const TextStyle()).copyWith(
      color: c.text58,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(builder: (context, kutu) {
      final alan = Size(kutu.maxWidth, kutu.maxHeight);
      final o = _olcekKur(alan, eksenStili);
      if (o == null) return const SizedBox.shrink();
      final son = _mumlar.last;
      final ozet = l.tegGrafikSemantik(widget.ad, _aralik.uzunAdi(context),
          _fiyatMetni(son.kapanis), _cizimler.length);
      final ortalamalar = <({List<double> deger, Color renk, bool kesikli})>[
        if (ref.watch(chartMA20Provider))
          (deger: _ma20, renk: c.text58, kesikli: true),
        if (ref.watch(chartEma50Provider))
          (deger: _ema50, renk: c.gain, kesikli: false),
        if (ref.watch(chartEma200Provider))
          (deger: _ema200, renk: c.loss, kesikli: false),
      ];
      final secili =
          _secili >= 0 && _secili < _cizimler.length ? _cizimler[_secili] : null;
      return Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: ozet,
              image: true,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _asagi,
                onPointerMove: _hareket,
                onPointerHover: _hover,
                onPointerUp: _yukari,
                onPointerCancel: (e) => _yukari(e, iptal: true),
                onPointerSignal: _tekerlek,
                child: CustomPaint(
                  painter: _GrafikBoyaci(
                    olcek: o,
                    mumlar: _mumlar,
                    mumMu: _mumMu,
                    aralik: _aralik,
                    ortalamalar: ortalamalar,
                    cizimler: _cizimler,
                    bekleyen: _bekleyen,
                    secili: _secili,
                    imlec: _imlec,
                    fiyatEkseni: _fiyatEkseni,
                    zamanEkseni: _zamanEkseni,
                    renk: c,
                    eksenStili: eksenStili,
                    fiyatMetni: _fiyatMetni,
                    // Seçim ve çizim rengi: bilgi mavisi — kazanç/kayıp
                    // renkleriyle karışmasın, iki temada da okunur.
                    cizimRengi: c.info,
                    paylasim: _paylasimKipi,
                    ozel: _ozelKatmanlar(context),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: SandikSpace.sm,
            top: SandikSpace.xs,
            right: _fiyatEkseni + SandikSpace.sm,
            child: IgnorePointer(child: _lejant(o)),
          ),
          if (secili != null && !_paylasimKipi) _seciliCubugu(o, secili),
          if (_bildirim != null && !_paylasimKipi)
            Positioned(
              left: 0,
              right: _fiyatEkseni,
              bottom: _zamanEkseni + SandikSpace.sm,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.smd, vertical: SandikSpace.xs2),
                    decoration: BoxDecoration(
                      color: c.text90,
                      borderRadius: BorderRadius.circular(SandikRadius.lg),
                    ),
                    child: Text(_bildirim!,
                        style: context.t.labelMedium?.copyWith(
                            color: c.background, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  /// Boyacının okuduğu hâl: renkler token'dan burada çözülür (boyacıda
  /// `BuildContext` yok). Ayrı panel göstergeleri (RSI gibi, kendi ölçeği)
  /// yatayda ÇİZİLMEZ: alt panel bu ekranın tek ölçekli düzenini (çizim
  /// araçları, imleç, isabet) bölerdi; lejant "ayrı panel dik ekranda"
  /// der, kullanıcı dik grafikte görür (2026-10-29 kararı).
  List<_OzelKatman> _ozelKatmanlar(BuildContext context) => [
        for (final r in _ozel)
          if (r.s.fiyatUstunde)
            (
              s: r.s,
              kayma: r.v.uzunluk - r.s.x.length,
              kapanis: r.v.kapanis,
              renk: [
                for (final (i, c) in r.s.cizgiler.indexed)
                  betikRengi(context, c.renk, i)
              ],
              eksiRenk: [
                for (final (i, c) in r.s.cizgiler.indexed)
                  betikRengi(context, c.eksiRenk ?? c.renk, i)
              ],
              dolguRenk: [
                for (final d in r.s.dolgular)
                  d.a == null || d.b == null
                      ? null
                      : betikRengi(
                              context,
                              d.renk ?? r.s.cizgiler[d.a!].renk,
                              d.a!)
                          .withValues(alpha: 0.12)
              ],
              isaretRenk: [
                for (final m in r.s.isaretler) betikRengi(context, m.renk, 1)
              ],
            ),
      ];

  /// Lejantta bir kendi göstergen satırı: ad + her çizginin renk noktası,
  /// adı ve imlecin mumundaki değeri (renk tek başına anlam taşımaz).
  Widget _ozelLejantSatiri(OzelSonuc r, int i, TextStyle st) {
    final c = context.c;
    final k = i - (r.v.uzunluk - r.s.x.length);
    return Text.rich(TextSpan(style: st, children: [
      TextSpan(
          text: r.g.ad,
          style: st.copyWith(color: c.text90, fontWeight: FontWeight.w700)),
      for (final (j, cz) in r.s.cizgiler.indexed)
        if (!cz.gizli) ...[
          const TextSpan(text: '  '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: SandikSpace.sm,
              height: SandikSpace.sm,
              decoration: BoxDecoration(
                  color: betikRengi(context, cz.renk, j),
                  shape: BoxShape.circle),
            ),
          ),
          TextSpan(
              text: k >= 0 && k < cz.degerler.length && cz.degerler[k].isFinite
                  ? ' ${cz.ad} ${_fiyatMetni(cz.degerler[k])}'
                  : ' ${cz.ad}'),
        ],
    ]));
  }

  /// Sol üstte OHLC ve ortalama değerleri — imleç varsa onun mumu, yoksa
  /// son mum (TradingView'in lejantı).
  Widget _lejant(GrafikOlcegi o) {
    final c = context.c;
    final m = _mumlar;
    final im = _imlec;
    final i = im == null
        ? m.length - 1
        : o.i(im.dx).round().clamp(0, m.length - 1);
    final b = m[i];
    final onceki = m[math.max(0, i - 1)].kapanis;
    final d = onceki == 0 ? 0.0 : b.kapanis / onceki - 1;
    final st = (context.t.labelSmall ?? const TextStyle()).copyWith(
        color: c.text58, fontFeatures: const [FontFeature.tabularFigures()]);
    final satirlar = <Widget>[
      Text.rich(TextSpan(style: st, children: [
        TextSpan(
            text: 'A ${_fiyatMetni(b.acilis)}  Y ${_fiyatMetni(b.enYuksek)}  '
                'D ${_fiyatMetni(b.enDusuk)}  K ${_fiyatMetni(b.kapanis)}  '),
        TextSpan(
            text: fmtPct(d * 100),
            style: st.copyWith(color: d >= 0 ? c.gain : c.loss)),
      ])),
      for (final (on, ad, s, r) in [
        (ref.watch(chartMA20Provider), 'MA20', _ma20, c.text58),
        (ref.watch(chartEma50Provider), 'EMA50', _ema50, c.gain),
        (ref.watch(chartEma200Provider), 'EMA200', _ema200, c.loss),
      ])
        if (on && i < s.length && s[i].isFinite)
          Text('$ad ${_fiyatMetni(s[i])}', style: st.copyWith(color: r)),
      for (final r in _ozel)
        r.s.fiyatUstunde
            ? _ozelLejantSatiri(r, i, st)
            : Text(context.l10n.tegOzelPanelDikte(r.g.ad), style: st),
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: satirlar);
  }

  /// Seçili çizimin üstünde küçük araç çubuğu: zil (0170, birimi uyan
  /// sembolde) ve sil (TradingView'in yüzen araç çubuğu). Kenara taşmaz.
  /// Paylaşım kipinde hiç çizilmez (çağıran `!_paylasimKipi`).
  Widget _seciliCubugu(GrafikOlcegi o, GrafikCizimi s) {
    final zil = CizimAlarmDugmesi.sunulur(
        ref, s, widget.varlik, widget.canliBirim);
    final genislik = SandikTouch.min * (zil ? 2 : 1);
    final a = o.ekranda(s.a);
    final b = s.b == null ? a : o.ekranda(s.b!);
    final x = (s.tur == CizimTuru.yatay ? o.genislik / 2 : (a.dx + b.dx) / 2) -
        genislik / 2;
    var y = math.min(a.dy, b.dy) - SandikTouch.min - SandikSpace.smd;
    if (y < SandikSpace.xs) y = math.max(a.dy, b.dy) + SandikSpace.smd;
    final alan = _cizimAlani;
    return Positioned(
      left: x
          .clamp(SandikSpace.xs, math.max(SandikSpace.xs, alan.width - genislik))
          .toDouble(),
      top: y.clamp(SandikSpace.xs, alan.height - SandikTouch.min).toDouble(),
      child: Material(
        color: context.c.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          side: BorderSide(color: context.c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (zil)
              CizimAlarmDugmesi(
                cizim: s,
                varlik: widget.varlik,
                ad: widget.varlik.name.trim().isEmpty
                    ? widget.ad
                    : widget.varlik.name,
                canliBirim: widget.canliBirim,
                olcek: o,
                kimlikVer: _seciliKimligi,
                bildir: _bildir,
              ),
            IconButton(
              key: const ValueKey('tamEkranCizimiSil'),
              tooltip: context.l10n.tegCizimiSil,
              onPressed: _seciliyiSil,
              icon:
                  Icon(Icons.delete_outline_rounded, color: context.c.text90),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fiyatın üstündeki bir kendi göstergen, boyanmaya hazır: sonuç, sonucun
/// ilk çubuğunun mum indeksi ([kayma]; X'ler zaten mum indeksi) ve token'dan
/// çözülmüş renkler (`betikRengi` — dik grafikle aynı renk kuralı).
typedef _OzelKatman = ({
  BetikSonucu s,
  int kayma,
  List<double> kapanis,
  List<Color> renk,
  List<Color> eksiRenk,
  List<Color?> dolguRenk,
  List<Color> isaretRenk,
});

enum _JestTuru { kaydir, pinch, imlec, ciz, tasi, eksen }

class _Jest {
  _Jest(
    this.tur, {
    required this.baslangic,
    this.gorunum,
    this.mesafe = 1,
    this.ikinci = false,
    this.tutamak,
    this.cizim,
  });

  final _JestTuru tur;
  final Offset baslangic;
  final GrafikGorunumu? gorunum;
  final double mesafe;
  final bool ikinci;
  final String? tutamak;
  final GrafikCizimi? cizim;
  bool oynadi = false;
}

/// Sol araç çubuğunun 44pt düğmesi. Seçiliyken amber zemin + amber ikon;
/// durum yalnız renkle verilmez, ekran okuyucu "seçili" der.
class _AracDugmesi extends StatelessWidget {
  const _AracDugmesi({
    required this.etiket,
    required this.ikon,
    required this.secili,
    required this.onTap,
  });

  final String etiket;
  final _Ikon ikon;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: secili,
      label: etiket,
      excludeSemantics: true,
      child: Tooltip(
        message: etiket,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: Ink(
            width: SandikTouch.min,
            height: SandikTouch.min,
            decoration: BoxDecoration(
              color: secili ? c.amberFill.withValues(alpha: 0.22) : null,
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size.square(20),
                painter: _AracIkonu(ikon, secili ? c.amberText : c.text58),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Ikon { imlec, trend, isin, yatay, yatayIsin, kutu, miknatis, geri, cop, mum, cizgi }

/// Araç simgeleri — Material'da karşılığı olmayanlar (ışın, mıknatıs)
/// yüzünden hepsi aynı çizgi kalınlığıyla elle çizilir; araç çubuğu tek
/// dil konuşur. 20×20 kutuda.
class _AracIkonu extends CustomPainter {
  _AracIkonu(this.ikon, this.renk);
  final _Ikon ikon;
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 20;
    canvas.scale(s);
    final k = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final d = Paint()..color = renk;
    switch (ikon) {
      case _Ikon.imlec:
        canvas.drawPath(
            Path()
              ..moveTo(5, 3)
              ..lineTo(17, 9)
              ..lineTo(12, 10.5)
              ..lineTo(9.5, 16)
              ..close(),
            k);
      case _Ikon.trend:
        canvas.drawLine(const Offset(4, 16), const Offset(16, 4), k);
        canvas.drawCircle(const Offset(4, 16), 2, d);
        canvas.drawCircle(const Offset(16, 4), 2, d);
      case _Ikon.isin:
        canvas.drawLine(const Offset(4, 16), const Offset(18, 2), k);
        canvas.drawCircle(const Offset(4, 16), 2, d);
        canvas.drawCircle(const Offset(10, 10), 2, d);
      case _Ikon.yatay:
        canvas.drawLine(const Offset(2, 10), const Offset(18, 10), k);
        canvas.drawCircle(const Offset(10, 10), 2, d);
      case _Ikon.yatayIsin:
        canvas.drawLine(const Offset(5, 10), const Offset(18, 10), k);
        canvas.drawCircle(const Offset(5, 10), 2, d);
      case _Ikon.kutu:
        canvas.drawRRect(
            RRect.fromLTRBR(3.5, 5.5, 16.5, 14.5, const Radius.circular(1)),
            k);
      case _Ikon.miknatis:
        canvas.drawPath(
            Path()
              ..moveTo(5, 3)
              ..lineTo(5, 10)
              ..arcToPoint(const Offset(15, 10),
                  radius: const Radius.circular(5), clockwise: false)
              ..lineTo(15, 3)
              ..lineTo(12, 3)
              ..lineTo(12, 10)
              ..arcToPoint(const Offset(8, 10),
                  radius: const Radius.circular(2))
              ..lineTo(8, 3)
              ..close(),
            k);
      case _Ikon.geri:
        canvas.drawPath(
            Path()
              ..moveTo(7, 6)
              ..lineTo(3, 10)
              ..lineTo(7, 14),
            k);
        canvas.drawPath(
            Path()
              ..moveTo(3, 10)
              ..lineTo(12, 10)
              ..arcToPoint(const Offset(12, 18),
                  radius: const Radius.circular(4)),
            k);
      case _Ikon.cop:
        canvas.drawLine(const Offset(4, 6), const Offset(16, 6), k);
        canvas.drawPath(
            Path()
              ..moveTo(8, 6)
              ..lineTo(8, 4)
              ..lineTo(12, 4)
              ..lineTo(12, 6),
            k);
        canvas.drawPath(
            Path()
              ..moveTo(6, 6)
              ..lineTo(7, 17)
              ..lineTo(13, 17)
              ..lineTo(14, 6),
            k);
      case _Ikon.mum:
        canvas.drawLine(const Offset(6, 3), const Offset(6, 17), k);
        canvas.drawLine(const Offset(14, 5), const Offset(14, 17), k);
        canvas.drawRect(const Rect.fromLTWH(4, 6, 4, 7), d);
        canvas.drawRect(const Rect.fromLTWH(12, 8, 4, 5),
            Paint()..color = renk);
      case _Ikon.cizgi:
        canvas.drawPath(
            Path()
              ..moveTo(2, 15)
              ..lineTo(7, 9)
              ..lineTo(11, 12)
              ..lineTo(18, 4),
            k);
    }
  }

  @override
  bool shouldRepaint(_AracIkonu old) => old.ikon != ikon || old.renk != renk;
}

/// Grafiğin tamamı: ızgara, hacim, mumlar ya da çizgi, ortalamalar, son
/// fiyat, çizimler, imleç, eksenler. Hesap yok: ölçek ve seriler hazır
/// gelir.
class _GrafikBoyaci extends CustomPainter {
  _GrafikBoyaci({
    required this.olcek,
    required this.mumlar,
    required this.mumMu,
    required this.aralik,
    required this.ortalamalar,
    required this.cizimler,
    required this.bekleyen,
    required this.secili,
    required this.imlec,
    required this.fiyatEkseni,
    required this.zamanEkseni,
    required this.renk,
    required this.eksenStili,
    required this.fiyatMetni,
    required this.cizimRengi,
    this.paylasim = false,
    this.ozel = const [],
  });

  final GrafikOlcegi olcek;
  final List<OhlcBar> mumlar;
  final bool mumMu;
  final MumAraligi aralik;
  final List<({List<double> deger, Color renk, bool kesikli})> ortalamalar;
  final List<GrafikCizimi> cizimler;
  final GrafikCizimi? bekleyen;
  final int secili;
  final Offset? imlec;
  final double fiyatEkseni;
  final double zamanEkseni;
  final SandikPalette renk;
  final TextStyle eksenStili;
  final String Function(double) fiyatMetni;
  final Color cizimRengi;

  /// Paylaşım görseli çiziliyor: imleç, seçim tutamakları ve yarım çizim
  /// yok. Kişisel bir katman (maliyet, lot, alarm) bu boyacıya eklenirse
  /// `if (!paylasim)` ardında olmalı — görselde ASLA yer almaz.
  final bool paylasim;

  /// Fiyatın üstündeki kendi göstergelerin (Pine). Kişisel veri değil;
  /// paylaşım görselinde de çizilir.
  final List<_OzelKatman> ozel;

  TextPainter _metin(String s, [TextStyle? st]) => TextPainter(
        text: TextSpan(text: s, style: st ?? eksenStili),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final o = olcek;
    final pw = o.genislik;
    final ph = size.height - zamanEkseni;
    final alan = Size(pw, ph);
    final ince = Paint()
      ..color = renk.hairline
      ..strokeWidth = 1;

    // Izgara + fiyat ekseni etiketleri.
    final adim = guzelAdim(o.yuksek - o.dusuk, math.max(3, (o.fiyatAlani / 56).round()));
    for (var v = (o.dusuk / adim).ceil() * adim; v <= o.yuksek; v += adim) {
      final y = o.y(v);
      canvas.drawLine(Offset(0, y), Offset(pw, y), ince);
      final t = _metin(fiyatMetni(v));
      t.paint(canvas, Offset(pw + SandikSpace.xs2, y - t.height / 2));
    }

    // Zaman ekseni etiketleri — ~90pt aralıkla, mum sınırına oturur.
    final etiketAdimi = math.max(1, (90 / o.birim).ceil());
    final i0 = math.max(0, o.gorunum.bas.ceil());
    final i1 = math.min(mumlar.length - 1, o.gorunum.son.floor());
    for (var i = (i0 / etiketAdimi).ceil() * etiketAdimi;
        i <= i1;
        i += etiketAdimi) {
      final x = o.x(i.toDouble());
      canvas.drawLine(Offset(x, 0), Offset(x, ph), ince);
      final t = _metin(_zamanMetni(mumlar[i].t, i > 0 ? mumlar[i - 1].t : null));
      t.paint(canvas, Offset(x - t.width / 2, ph + (zamanEkseni - t.height) / 2));
    }
    canvas.drawLine(Offset(pw, 0), Offset(pw, ph), ince);
    canvas.drawLine(Offset(0, ph), Offset(pw, ph), ince);

    canvas.save();
    canvas.clipRect(Offset.zero & alan);

    // Hacim şeridi.
    final hacimler = [for (final b in mumlar) b.hacim ?? 0];
    final hacimTavan = hacimler.isEmpty ? 0.0 : hacimler.reduce(math.max);
    if (hacimTavan > 0) {
      final bant = ph - o.fiyatAlani;
      for (var i = i0 - 1; i <= i1 + 1; i++) {
        if (i < 0 || i >= mumlar.length) continue;
        final h = hacimler[i] / hacimTavan * bant * 0.9;
        final yukselen = mumlar[i].kapanis >= mumlar[i].acilis;
        canvas.drawRect(
            Rect.fromLTWH(o.x(i - 0.35), ph - h, o.birim * 0.7, h),
            Paint()
              ..color = (yukselen ? renk.gain : renk.loss)
                  .withValues(alpha: 0.22));
      }
    }

    // Mumlar ya da çizgi.
    if (mumMu) {
      final govde = math.max(1.0, o.birim * 0.7);
      for (var i = i0 - 1; i <= i1 + 1; i++) {
        if (i < 0 || i >= mumlar.length) continue;
        final b = mumlar[i];
        final yukselen = b.kapanis >= b.acilis;
        final r = yukselen ? renk.gain : renk.loss;
        final x = o.x(i.toDouble());
        canvas.drawLine(Offset(x, o.y(b.enYuksek)), Offset(x, o.y(b.enDusuk)),
            Paint()
              ..color = r
              ..strokeWidth = 1);
        final ust = o.y(math.max(b.acilis, b.kapanis));
        final alt = o.y(math.min(b.acilis, b.kapanis));
        final dikd = Rect.fromLTRB(
            x - govde / 2, ust, x + govde / 2, math.max(alt, ust + 1));
        // Yükselen mum içi boş, düşen dolu: renk körlüğünde de ayrılır
        // (HIG "yalnız renkle anlam yok").
        if (yukselen && govde > 3) {
          canvas.drawRect(dikd, Paint()..color = renk.background);
          canvas.drawRect(
              dikd.deflate(0.5),
              Paint()
                ..color = r
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1);
        } else {
          canvas.drawRect(dikd, Paint()..color = r);
        }
      }
    } else {
      final yol = Path();
      var ilk = true;
      for (var i = math.max(0, i0 - 1); i <= math.min(mumlar.length - 1, i1 + 1); i++) {
        final p = Offset(o.x(i.toDouble()), o.y(mumlar[i].kapanis));
        ilk ? yol.moveTo(p.dx, p.dy) : yol.lineTo(p.dx, p.dy);
        ilk = false;
      }
      canvas.drawPath(
          yol,
          Paint()
            ..color = renk.info
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round);
    }

    // Ortalamalar.
    for (final s in ortalamalar) {
      final yol = Path();
      var ilk = true;
      for (var i = math.max(0, i0 - 1);
          i <= math.min(s.deger.length - 1, i1 + 1);
          i++) {
        final v = s.deger[i];
        if (!v.isFinite) {
          ilk = true;
          continue;
        }
        final p = Offset(o.x(i.toDouble()), o.y(v));
        ilk ? yol.moveTo(p.dx, p.dy) : yol.lineTo(p.dx, p.dy);
        ilk = false;
      }
      final boya = Paint()
        ..color = s.renk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      if (s.kesikli) {
        for (final m in yol.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 7) {
            canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), boya);
          }
        }
      } else {
        canvas.drawPath(yol, boya);
      }
    }

    // Kendi göstergelerin — ortalamalarla aynı katmanda, çizimlerin altında.
    for (final k in ozel) {
      _ozelGosterge(canvas, k, ph, i0, i1);
    }

    // Son fiyat çizgisi.
    final son = mumlar.last;
    final sonY = o.y(son.kapanis);
    final sonRenk = son.kapanis >= son.acilis ? renk.gain : renk.loss;
    _kesikliCizgi(canvas, Offset(0, sonY), Offset(pw, sonY),
        Paint()
          ..color = sonRenk
          ..strokeWidth = 1);

    // Çizimler.
    for (var k = 0; k < cizimler.length; k++) {
      _cizim(canvas, cizimler[k], alan, !paylasim && k == secili);
    }
    final b = paylasim ? null : bekleyen;
    if (b != null) _cizim(canvas, b, alan, true);

    // İmleç (artı).
    final im = paylasim ? null : imlec;
    int? imlecMumu;
    if (im != null) {
      imlecMumu = o.i(im.dx).round().clamp(0, mumlar.length - 1);
      final x = o.x(imlecMumu.toDouble());
      final y = math.min(ph, im.dy);
      final p = Paint()
        ..color = renk.text36
        ..strokeWidth = 1;
      _kesikliCizgi(canvas, Offset(x, 0), Offset(x, ph), p);
      _kesikliCizgi(canvas, Offset(0, y), Offset(pw, y), p);
    }
    canvas.restore();

    // Eksen etiketleri (kırpma dışında).
    _eksenEtiketi(canvas, size, sonY, fiyatMetni(son.kapanis), sonRenk,
        renk.background);
    if (im != null && im.dy <= o.fiyatAlani) {
      _eksenEtiketi(canvas, size, im.dy, fiyatMetni(o.p(im.dy)), renk.text90,
          renk.background);
    }
    if (im != null && imlecMumu != null) {
      final t = _metin(
          _zamanMetni(mumlar[imlecMumu].t, null, uzun: true),
          eksenStili.copyWith(color: renk.background));
      final x = o.x(imlecMumu.toDouble());
      final w = t.width + SandikSpace.smd;
      final lx = (x - w / 2).clamp(0.0, math.max(0.0, pw - w)).toDouble();
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(lx, ph + 2, w, zamanEkseni - 4),
          const Radius.circular(SandikSpace.xs));
      canvas.drawRRect(r, Paint()..color = renk.text90);
      t.paint(canvas,
          Offset(lx + (w - t.width) / 2, ph + (zamanEkseni - t.height) / 2));
    }
  }

  /// Bir göstergenin çizgileri, dolguları ve işaretleri. Dik grafikteki
  /// (`gosterge_cizimi.dart`, fl_chart) karşılıklar: çizgi `na`'da bölünür,
  /// alan çizginin altını sıfıra (grafikte alt kenara) doldurur, histogram
  /// sıfırdan sütun, nokta daire; `fill` iki çizgi arası, `plotshape`
  /// kapanışın üstünde daire. Yatay seviye (`hline`) dik grafikte de
  /// fiyatın üstüne çizilmez; burada da yok.
  void _ozelGosterge(Canvas canvas, _OzelKatman k, double ph, int i0, int i1) {
    final o = olcek;
    final s = k.s;
    final x = s.x;
    bool gorunur(int j) => x[j] >= i0 - 1 && x[j] <= i1 + 1;
    Path parcali(List<double> d) {
      final yol = Path();
      var ilk = true;
      for (var j = 0; j < x.length; j++) {
        if (!gorunur(j) || !d[j].isFinite) {
          ilk = true;
          continue;
        }
        final p = Offset(o.x(x[j]), o.y(d[j]));
        ilk ? yol.moveTo(p.dx, p.dy) : yol.lineTo(p.dx, p.dy);
        ilk = false;
      }
      return yol;
    }

    // Dolgular önce: çizgiler üstte kalsın.
    for (final (n, d) in s.dolgular.indexed) {
      final renk = k.dolguRenk[n];
      if (renk == null) continue;
      final a = s.cizgiler[d.a!].degerler, b = s.cizgiler[d.b!].degerler;
      final dolgu = Paint()..color = renk;
      var j = 0;
      while (j < x.length) {
        if (!gorunur(j) || !a[j].isFinite || !b[j].isFinite) {
          j++;
          continue;
        }
        final bas = j;
        while (j < x.length && gorunur(j) && a[j].isFinite && b[j].isFinite) {
          j++;
        }
        final yol = Path()..moveTo(o.x(x[bas]), o.y(a[bas]));
        for (var t = bas + 1; t < j; t++) {
          yol.lineTo(o.x(x[t]), o.y(a[t]));
        }
        for (var t = j - 1; t >= bas; t--) {
          yol.lineTo(o.x(x[t]), o.y(b[t]));
        }
        canvas.drawPath(yol..close(), dolgu);
      }
    }

    for (final (n, c) in s.cizgiler.indexed) {
      if (c.gizli) continue;
      final renk = k.renk[n];
      switch (c.stil) {
        case BetikCizgiStili.cizgi || BetikCizgiStili.alan:
          final yol = parcali(c.degerler);
          if (c.stil == BetikCizgiStili.alan) {
            final taban = math.min(ph, o.y(0));
            for (final m in yol.computeMetrics()) {
              final bas = m.getTangentForOffset(0)?.position;
              final son = m.getTangentForOffset(m.length)?.position;
              if (bas == null || son == null) continue;
              canvas.drawPath(
                  m.extractPath(0, m.length)
                    ..lineTo(son.dx, taban)
                    ..lineTo(bas.dx, taban)
                    ..close(),
                  Paint()..color = renk.withValues(alpha: 0.14));
            }
          }
          canvas.drawPath(
              yol,
              Paint()
                ..color = renk
                ..style = PaintingStyle.stroke
                ..strokeWidth = c.kalinlik
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round);
        case BetikCizgiStili.histogram:
          final sifir = o.y(0);
          for (var j = 0; j < x.length; j++) {
            final v = c.degerler[j];
            if (!gorunur(j) || !v.isFinite) continue;
            final px = o.x(x[j]);
            canvas.drawLine(
                Offset(px, sifir),
                Offset(px, o.y(v)),
                Paint()
                  ..color = (v >= 0 ? renk : k.eksiRenk[n])
                      .withValues(alpha: 0.8)
                  ..strokeWidth = c.kalinlik + 0.6);
          }
        case BetikCizgiStili.nokta:
          final p = Paint()..color = renk;
          for (var j = 0; j < x.length; j++) {
            final v = c.degerler[j];
            if (!gorunur(j) || !v.isFinite) continue;
            canvas.drawCircle(Offset(o.x(x[j]), o.y(v)), c.kalinlik, p);
          }
      }
    }

    for (final (n, m) in s.isaretler.indexed) {
      final ic = Paint()..color = k.isaretRenk[n];
      final kenar = Paint()
        ..color = renk.surface1
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final j in m.indeksler) {
        if (j < 0 || j >= x.length || !gorunur(j)) continue;
        final mi = k.kayma + j;
        if (mi < 0 || mi >= k.kapanis.length || !k.kapanis[mi].isFinite) {
          continue;
        }
        final p = Offset(o.x(x[j]), o.y(k.kapanis[mi]));
        canvas.drawCircle(p, 4, ic);
        canvas.drawCircle(p, 4, kenar);
      }
    }
  }

  void _eksenEtiketi(
      Canvas canvas, Size size, double y, String s, Color zemin, Color yazi) {
    final t = _metin(s, eksenStili.copyWith(color: yazi, fontWeight: FontWeight.w600));
    final h = t.height + SandikSpace.xs;
    final x = olcek.genislik + 1;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y - h / 2, size.width - x, h),
            const Radius.circular(SandikSpace.xs)),
        Paint()..color = zemin);
    t.paint(canvas, Offset(x + SandikSpace.xs2 - 1, y - t.height / 2));
  }

  void _cizim(Canvas canvas, GrafikCizimi c, Size alan, bool vurgulu) {
    final o = olcek;
    final a = o.ekranda(c.a);
    final b = c.b == null ? a : o.ekranda(c.b!);
    final p = Paint()
      ..color = cizimRengi
      ..strokeWidth = vurgulu ? 2.2 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final tutamaklar = <Offset>[];
    switch (c.tur) {
      case CizimTuru.trend:
        canvas.drawLine(a, b, p);
        tutamaklar.addAll([a, b]);
      case CizimTuru.isin:
        canvas.drawLine(a, isinUcu(a, b, alan), p);
        tutamaklar.addAll([a, b]);
      case CizimTuru.yatay:
        canvas.drawLine(Offset(0, a.dy), Offset(alan.width, a.dy), p);
      case CizimTuru.yatayIsin:
        canvas.drawLine(a, Offset(alan.width, a.dy), p);
        tutamaklar.add(a);
      case CizimTuru.kutu:
        final r = Rect.fromPoints(a, b);
        canvas.drawRect(
            r, Paint()..color = cizimRengi.withValues(alpha: 0.12));
        canvas.drawRect(r, p);
        tutamaklar.addAll([a, b]);
    }
    if (vurgulu) {
      for (final h in tutamaklar) {
        canvas.drawCircle(h, 5, Paint()..color = renk.background);
        canvas.drawCircle(
            h,
            5,
            Paint()
              ..color = cizimRengi
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6);
      }
      if (c.tur.tekNokta) {
        // Yatay çizginin fiyatı eksende — taşırken hedef okunsun.
        _eksenEtiketi(canvas, Size(alan.width + fiyatEkseni, alan.height),
            a.dy, fiyatMetni(c.a.p), cizimRengi, renk.background);
      }
    }
  }

  void _kesikliCizgi(Canvas canvas, Offset a, Offset b, Paint p) {
    final d = b - a;
    final l = d.distance;
    if (l == 0) return;
    final u = d / l;
    for (var s = 0.0; s < l; s += 7) {
      canvas.drawLine(a + u * s, a + u * math.min(s + 4, l), p);
    }
  }

  String _zamanMetni(int t, int? onceki, {bool uzun = false}) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    if (uzun) {
      return aralik.gunIci
          ? DateFormat('d MMM HH:mm', 'tr_TR').format(d)
          : DateFormat('d MMM y', 'tr_TR').format(d);
    }
    if (aralik == MumAraligi.ay1) return DateFormat('MMM y', 'tr_TR').format(d);
    if (aralik.gunIci) {
      final o = onceki == null ? null : DateTime.fromMillisecondsSinceEpoch(onceki);
      final yeniGun = o == null || o.day != d.day;
      return yeniGun
          ? DateFormat('d MMM', 'tr_TR').format(d)
          : DateFormat('HH:mm', 'tr_TR').format(d);
    }
    return DateFormat('d MMM', 'tr_TR').format(d);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
