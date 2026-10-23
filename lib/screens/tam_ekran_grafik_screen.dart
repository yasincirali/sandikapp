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
import '../providers/preferences_provider.dart';
import '../services/cizim_deposu.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart' show FiyatKaynagi, MumKaynakTuru;
import '../services/mum_verisi.dart';
import '../services/technical_analysis_service.dart';
import '../theme/sandik.dart';
import '../utils/hareketli_ortalama.dart' show kEmaKisa, kEmaUzun;
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/grafik_arac_cubugu.dart' show GrafikCipi, MumAraligiAdi;
import '../widgets/tam_ekran/grafik_olcegi.dart';

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

  // ── Test okumaları ────────────────────────────────────────────────────
  List<GrafikCizimi> get cizimler => _cizimler;
  GrafikGorunumu? get gorunum => _gorunum;
  GrafikOlcegi? get olcek => _olcek;
  int get secili => _secili;
  Offset? get imlec => _imlec;
  CizimTuru? get arac => _arac;
  MumAraligi get aralik => _aralik;

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

  void _kaydet() => CrashReporter.arkaPlan(
      CizimDeposu.instance.yaz(widget.varlik.ticker, _cizimler),
      reason: 'TamEkranGrafik.cizimYaz');

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
      _hata = temiz.length < 2;
      _yukleniyor = false;
      _ma20 = TechnicalAnalysisService.smaSeries(kapanis, 20);
      _ema50 = TechnicalAnalysisService.emaSeries(kapanis, kEmaKisa);
      _ema200 = TechnicalAnalysisService.emaSeries(kapanis, kEmaUzun);
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
        _bekleyen = GrafikCizimi(tur: arac, a: n, b: arac.tekNokta ? null : n);
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
              b: c0.b == null ? null : kaydir(c0.b!));
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

  // ── Görünüm ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final yatay = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (!yatay && widget.dikteKapan && !_kapaniyor) {
      // Telefon dik döndü: sayfa kendini kapatır, alttaki dik grafik kalır.
      _kapaniyor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
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
                    Expanded(child: _grafik()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ustCubuk() {
    final l = context.l10n;
    final c = context.c;
    final ma20 = ref.watch(chartMA20Provider);
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
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: SandikSpace.sm,
            top: SandikSpace.xs,
            child: IgnorePointer(child: _lejant(o)),
          ),
          if (secili != null) _seciliCubugu(o, secili),
          if (_bildirim != null)
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
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: satirlar);
  }

  /// Seçili çizimin üstünde küçük sil düğmesi (TradingView'in yüzen araç
  /// çubuğu). Kenara taşmaz.
  Widget _seciliCubugu(GrafikOlcegi o, GrafikCizimi s) {
    final a = o.ekranda(s.a);
    final b = s.b == null ? a : o.ekranda(s.b!);
    final x = (s.tur == CizimTuru.yatay ? o.genislik / 2 : (a.dx + b.dx) / 2) -
        SandikTouch.min / 2;
    var y = math.min(a.dy, b.dy) - SandikTouch.min - SandikSpace.smd;
    if (y < SandikSpace.xs) y = math.max(a.dy, b.dy) + SandikSpace.smd;
    final alan = _cizimAlani;
    return Positioned(
      left: x.clamp(SandikSpace.xs, alan.width - SandikTouch.min).toDouble(),
      top: y.clamp(SandikSpace.xs, alan.height - SandikTouch.min).toDouble(),
      child: Material(
        color: context.c.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          side: BorderSide(color: context.c.hairline),
        ),
        child: IconButton(
          key: const ValueKey('tamEkranCizimiSil'),
          tooltip: context.l10n.tegCizimiSil,
          onPressed: _seciliyiSil,
          icon: Icon(Icons.delete_outline_rounded, color: context.c.text90),
        ),
      ),
    );
  }
}

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
      _cizim(canvas, cizimler[k], alan, k == secili);
    }
    final b = bekleyen;
    if (b != null) _cizim(canvas, b, alan, true);

    // İmleç (artı).
    final im = imlec;
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
