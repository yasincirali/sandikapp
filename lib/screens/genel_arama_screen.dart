import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, DismissDirection, Dismissible, Icons, Material;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/arama_eylemleri.dart';
import '../models/asset_categories.dart' show goldTickerMap;
import '../models/hizli_hesap.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import '../providers/add_asset_form_provider.dart' show dovizOptFor;
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/fiyat_kaynagi.dart' show gorunurSatisFiyati;
import '../services/ozellik_olcumu.dart';
import '../services/price_service.dart';
import '../services/son_bakilanlar.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/varlik_rozeti.dart';
import '../l10n/l10n.dart';
import 'add_asset_screen.dart';
import 'add_watchlist_screen.dart';
import 'asset_detail_screen.dart';
import 'bulk_add_asset_screen.dart';
import 'comparison_screen.dart';
import 'csv_import_screen.dart';
import 'price_alerts_screen.dart';
import 'settings_screen.dart';
import 'signal_settings_screen.dart';
import 'varlik_sayfasi.dart';

/// Genel arama (bayrak `genel_arama`, sadeleştirme 2).
///
/// ## Neden ayrı bir ekran (takibe alma ekranının genişletilmesi değil)
/// `AddWatchlistScreen` piyasa şeridindeki "Ara" çipinin yeri ve takip
/// listesine EKLEME yüzeyi; satırında "+ Takip" var. Ana ekranın üst
/// çubuğundaki büyüteç ise "bir şeyi bul ve oraya git" sorusu: kendi
/// varlığım, piyasadaki bir sembol ya da uygulamada bir yer (alarm, ekstre…).
/// Üç grubu tek listede toplar; piyasa araması AYNI servisle
/// (`SymbolSearchService`, `aramaBeklemesi`) ve AYNI satırla
/// (`AramaSatirKutusu`) yapılır ki iki arama yüzeyi ayrışmasın.
///
/// ## Gruplar
/// - **Varlıklarım:** bugün açık pozisyonlar (`aramaPozisyonlari`) →
///   Portföy satırıyla aynı varlık ekranı.
/// - **Piyasa:** sembol araması → varlık sayfası (`showVarlikSayfasi`,
///   takibe alma ekranındaki satırla aynı).
/// - **Eylemler:** `arama_eylemleri.dart` anahtar sözcükleri; boş sorguda
///   öneri olarak hepsi.
/// - **Son baktıkların** (2026-10-26, yalnız boş sorguda, eylemlerin
///   ÜSTÜNDE): varlık sayfası açılan son varlıklar ([SonBakilanlar] —
///   takibe alma ekranının şeridiyle AYNI depo, kayıt varlık sayfasının
///   kendisinde). Takipte ve bugün portföyde olanlar süzülür (kendi
///   yüzeyleri var), en çok [SonBakilanlar.gosterimSiniri]. Satır piyasa
///   satırının aynısı; fiyat aramanın kotasyon yolundan tek toplu istekle
///   (`_fiyatla`), yoksa yalnız ad. Kaldırma satır başına: sola kaydır ya
///   da VoiceOver özel eylemi; ayrı "Temizle" düğmesi yok (beş satırlık
///   kısayolu toptan silmek nadir iş, eylem satırlarının yanında ikinci bir
///   metin düğmesi gürültü olurdu). Boşsa bölüm hiç çizilmez.
/// - **Hızlı hesap** (2026-10-24): sorgu "5 çeyrek", "100 dolar" gibi
///   sayı + birim ise ([hizliHesapCoz]) en üstte başlıksız tek satır
///   "5 Çeyrek Altın ≈ ₺X". Fiyat bilinmiyorsa satır YOK (uydurma sayı
///   yasak). Dokununca Varlık Ekle o tür ve miktarla açılır; kayıt yolu
///   formun, ikinci bir ekleme yolu yazılmadı.
///   İkinci adım (2026-10-25): "10.000 tl çeyrek" → "₺10.000 ≈ 2,6 Çeyrek
///   Altın", SATIŞ fiyatından (`gorunurSatisFiyati`; satış yoksa satır
///   yok), dokununca form Tutar kipinde o TL ile açılır. "100 THYAO" →
///   "100 THYAO ≈ ₺X": kod aramanın AYNI kaynağında (`aramaServisi` /
///   `SymbolSearchService`) aranır, yalnız birebir BIST hissesi ya da
///   TEFAS fonu kabul edilir (`hizliHesapCoz` → `sembolBul`).
///
/// Demo: ekran demoda AÇILMAZ — ana ekrandaki giriş, piyasa çipiyle aynı
/// `DemoModu.yazmaKapisi('arama')` kapısından geçer (bkz. `home_screen`).
class GenelAramaScreen extends ConsumerStatefulWidget {
  const GenelAramaScreen({
    super.key,
    this.tumHareketleriAc,
    this.bildirimleriAc,
    this.aramaServisi,
    this.kotasyonServisi,
  });

  /// Ana ekranın "Tüm hareketleri gör" açıcısı. Ekran kendi başına ortak
  /// görünümünü ve ortak defterlerini bilmez; aynı parametrelerle açılsın
  /// diye çağıran verir. `null` → eylem listelenmez.
  final VoidCallback? tumHareketleriAc;

  /// Ana ekranın bildirim zili sayfası (`_scrollToSignals`): sayfa ana
  /// ekranın durumuna (görüldü damgası, sunucu tazelemesi) bağlı; ancak
  /// oradan açılabilir. `null` → eylem listelenmez.
  final VoidCallback? bildirimleriAc;

  /// Testte ağ yerine verilen arama. Uygulamada `SymbolSearchService`.
  final Future<List<SymbolHit>> Function(String)? aramaServisi;

  /// Testte ağ yerine verilen kotasyon kaynağı. Uygulamada `PriceService`.
  final Future<Map<String, YahooQuote>> Function(List<String>)?
      kotasyonServisi;

  @override
  ConsumerState<GenelAramaScreen> createState() => _GenelAramaScreenState();
}

/// "Piyasa" grubunda en çok kaç satır. Tam liste takibe alma ekranında
/// (tür çipleri, "Tümü (n)"); burada üç grup yan yana, piyasa öteki ikisini
/// ekranın altına itmesin.
const _piyasaSiniri = 6;

/// Hızlı hesabın fiyat sembolü — formun KAYDEDECEĞİ sembol (vitrinle aynı
/// karar, `IlkVarlikVitrini.fiyatSembolu`): altında `goldTickerMap`,
/// dövizde `dovizOptFor`. Satırdaki tutar, dokununca formun önizlediği
/// fiyatla aynı ürünün fiyatı olsun diye ayrı bir sembol tablosu yok.
String? hizliHesapSembolu(HizliHesap h) {
  if (h.kimlik case final k?) return k.ticker;
  if (h.altin case final g?) return goldTickerMap[g.label];
  if (h.doviz case final d?) {
    final t = dovizOptFor(d).ticker;
    return t.isEmpty ? null : t;
  }
  return null;
}

class _GenelAramaScreenState extends ConsumerState<GenelAramaScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<VarlikKimligi> _piyasa = const [];
  bool _loading = false;
  Map<String, YahooQuote> _kotasyon = const {};

  /// Sorgu "sayı + birim" ise çözümü; değilse `null`. Her tuşta yeniden
  /// çözülür (saf, ucuz); fiyat `_kotasyon`'dan okunur.
  HizliHesap? _hesap;

  /// "100 THYAO" kalıbının kod → kimlik çözümleri (oturum boyu). Yalnız
  /// aramanın kaynağında BİREBİR bulunan kod girer; [_istenenKodlar] aynı
  /// kodun her tuşta yeniden aranmasını önler.
  final Map<String, VarlikKimligi> _kodlar = {};
  final Set<String> _istenenKodlar = {};

  HizliHesap? _coz(String v) =>
      hizliHesapCoz(v, sembolBul: (kod) => _kodlar[kod]);

  /// Yalnızca EN SON aramanın sonucu uygulanır (takibe alma ekranıyla aynı
  /// gerekçe: istekler sırasız dönebilir).
  int _seq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Oturum soğuk açılışta henüz çözülmemiş olabilir: kimlik gelince yükle
    // (takibe alma ekranıyla aynı yol).
    ref.listenManual(authProvider, (_, next) {
      final uid = next.valueOrNull?.id;
      if (uid == null) return;
      CrashReporter.arkaPlan(
          SonBakilanlar.instance.yukle(uid).then((_) => _sonBakilanFiyatla()),
          reason: 'GenelArama.sonBakilanlar');
    }, fireImmediately: true);
  }

  /// Takipte ya da BUGÜN portföyde olanların anahtarları — "Son
  /// baktıkların"da gösterilmezler. `aktifLotlar`: tamamen satılmış varlık
  /// portföyde sayılmaz (CLAUDE.md "Kapanmış pozisyon"); anahtar
  /// `varlikAnahtari`, takibe alma ekranındaki "Portföyünde" etiketiyle aynı.
  Set<String> _haricAnahtarlar({required bool izle}) {
    final takip = (izle
                ? ref.watch(watchlistProvider)
                : ref.read(watchlistProvider))
            .valueOrNull ??
        const [];
    final defter = (izle
                ? ref.watch(portfolioProvider)
                : ref.read(portfolioProvider))
            .valueOrNull
            ?.assets ??
        const [];
    return {
      for (final w in takip) w.key,
      for (final a in aktifLotlar(defter))
        varlikAnahtari(
            type: a.type, ticker: a.ticker, subCategory: a.subCategory),
    };
  }

  /// Görünen (en çok beş) satırın fiyatı — tek toplu istek, önbellekteki
  /// sembol yeniden istenmez (`_fiyatla`).
  Future<void> _sonBakilanFiyatla() async {
    if (!mounted) return;
    final gorunen = SonBakilanlar.gorunenler(
        SonBakilanlar.instance.liste.value, _haricAnahtarlar(izle: false));
    if (gorunen.isEmpty) return;
    await _fiyatla([for (final k in gorunen) k.ticker]);
  }

  Future<void> _sonBakilaniKaldir(VarlikKimligi k) async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    await SonBakilanlar.instance.kaldir(uid, k);
    // Altıncı kayıt yukarı çıktıysa onun fiyatı da gelsin.
    await _sonBakilanFiyatla();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _sorguDegisti(String v) {
    final hesap = _coz(v);
    setState(() {
      _q = v;
      _hesap = hesap;
    });
    if (hizliHesapKodAdayi(v) case final kod? when hesap == null) {
      CrashReporter.arkaPlan(_koduCoz(kod), reason: 'GenelArama.hizliKod');
    }
    // Hızlı hesabın fiyatı beklemesiz istenir: tek sembol, önbellekte
    // varsa hiç istek yok (`_fiyatla` eksik olanı ister).
    if (hesap != null) {
      if (hizliHesapSembolu(hesap) case final s?) {
        CrashReporter.arkaPlan(_fiyatla([s]),
            reason: 'GenelArama.hizliHesap');
      }
    }
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      // Boş sorguda piyasa önerisi YOK: öneri yeri eylemlerin. Süren
      // aramanın sonucu da artık uygulanmasın.
      _seq++;
      setState(() {
        _piyasa = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(SymbolSearchService.aramaBeklemesi, () => _ara(v));
  }

  List<VarlikKimligi> _kimlikler(List<SymbolHit> hits) => [
        for (final h in hits)
          if (VarlikKimligi.fromSymbolHit(h) case final c?) c,
      ].take(_piyasaSiniri).toList();

  Future<void> _ara(String q) async {
    final id = ++_seq;
    // Yerleşik sonuçlar ANINDA (takibe alma ekranıyla aynı iki katman).
    // Test servisi verildiyse yerel katman atlanır — test ağsız ve
    // belirlenimli kalsın.
    if (widget.aramaServisi == null) {
      final yerel = _kimlikler(SymbolSearchService.instance.yerelAra(q));
      if (mounted) {
        setState(() {
          _loading = true;
          _piyasa = yerel;
        });
      }
    } else if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final hits = await (widget.aramaServisi ??
          SymbolSearchService.instance.search)(q);
      if (!mounted || id != _seq) return;
      final sonuc = _kimlikler(hits);
      setState(() {
        _piyasa = sonuc;
        _loading = false;
      });
      CrashReporter.arkaPlan(_fiyatla([for (final c in sonuc) c.ticker]),
          reason: 'GenelArama.fiyat');
    } catch (_) {
      if (!mounted || id != _seq) return;
      setState(() => _loading = false);
    }
  }

  /// Kod adayını ("THYAO", "AFT") piyasa aramasının KENDİ kaynağında arar;
  /// kısa etiketi birebir aynı hisse/fon bulunursa kaydeder, sorgu hâlâ
  /// o kodu taşıyorsa satırı yeniden çözer ve fiyatını ister. Yarım kod
  /// ("THY") burada eşleşmez: `kisaEtiket` birebir karşılaştırılır.
  Future<void> _koduCoz(String kod) async {
    if (!_istenenKodlar.add(kod)) return;
    VarlikKimligi? birebir(List<SymbolHit> hits) {
      for (final h in hits) {
        final c = VarlikKimligi.fromSymbolHit(h);
        if (c == null) continue;
        if (c.type != AssetType.hisse && c.type != AssetType.fon) continue;
        if (c.kisaEtiket.toUpperCase() == kod) return c;
      }
      return null;
    }

    try {
      // Yerleşik BIST listesi ağsız ve anında; test servisi verildiyse
      // atlanır (belirlenimli kalsın, `_ara` ile aynı kural).
      var k = widget.aramaServisi == null
          ? birebir(SymbolSearchService.instance.yerelAra(kod))
          : null;
      k ??= birebir(await (widget.aramaServisi ??
          SymbolSearchService.instance.search)(kod));
      if (k == null || !mounted) return;
      final kimlik = k;
      setState(() {
        _kodlar[kod] = kimlik;
        _hesap = _coz(_q);
      });
      if (_hesap?.kimlik != null) await _fiyatla([kimlik.ticker]);
    } catch (_) {
      // Ağ hatasında kod bir sonraki tuşta yeniden denenebilsin.
      _istenenKodlar.remove(kod);
      rethrow;
    }
  }

  Future<void> _fiyatla(List<String> semboller) async {
    final eksik = [
      for (final s in semboller.toSet())
        if (!_kotasyon.containsKey(s.toUpperCase())) s,
    ];
    if (eksik.isEmpty) return;
    final q = await (widget.kotasyonServisi ??
        PriceService.instance.fetchQuotes)(eksik);
    if (!mounted || q.isEmpty) return;
    setState(() => _kotasyon = {..._kotasyon, ...q});
  }

  Set<AramaEylemi> get _mevcutEylemler => {
        ...AramaEylemi.values,
      }
        ..removeWhere((e) =>
            (e == AramaEylemi.tumHareketler &&
                widget.tumHareketleriAc == null) ||
            (e == AramaEylemi.bildirimler && widget.bildirimleriAc == null));

  @override
  Widget build(BuildContext context) {
    final defter =
        ref.watch(portfolioProvider).valueOrNull?.assets ?? const [];
    final bos = _q.trim().isEmpty;
    final varliklar = aramaPozisyonlari(defter, _q);
    final eylemler = aramaEylemleriniSuz(_q, mevcut: _mevcutEylemler);
    final hesap = _hesap;
    final hesapSatiri =
        hesap == null ? null : _hizliHesapSatiri(context, hesap);
    final hicYok = !bos &&
        !_loading &&
        hesapSatiri == null &&
        varliklar.isEmpty &&
        _piyasa.isEmpty &&
        eylemler.isEmpty;
    final hp = SandikSpace.screenH(context);
    // Boş sorguda süzgeç için; yazarken takip/portföy değişimi ekranı
    // yeniden kurmasın diye yalnız boşken izlenir.
    final haric = bos ? _haricAnahtarlar(izle: true) : const <String>{};

    return DefaultTextStyle(
      style: sandikFont(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                _aramaAlani(context),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                        hp, SandikSpace.sm, hp, SandikSpace.lgs),
                    children: [
                      if (hesapSatiri != null) ...[
                        hesapSatiri,
                        const SizedBox(height: SandikSpace.sm),
                      ],
                      if (hicYok)
                        // Boş durum: takibe alma ekranıyla aynı metin ve
                        // yerleşim (ortak boş durum bileşeni henüz yok,
                        // TASARIM_DILI §6.1).
                        Padding(
                          padding: const EdgeInsets.only(top: SandikSpace.xxl),
                          child: Text(
                            context.l10n.noResultForQuery(_q.trim()),
                            textAlign: TextAlign.center,
                            style: context.t.bodyMedium
                                ?.copyWith(color: context.c.text58),
                          ),
                        ),
                      if (varliklar.isNotEmpty) ...[
                        _Baslik(context.l10n.s7VarliklarimUpper),
                        for (final p in varliklar) _varlikSatiri(context, p),
                        const SizedBox(height: SandikSpace.sm),
                      ],
                      if (!bos && (_piyasa.isNotEmpty || _loading)) ...[
                        _Baslik(context.l10n.s7PiyasaUpper),
                        if (_piyasa.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: SandikSpace.sm),
                            child: Text(context.l10n.searchingEllipsis,
                                style: context.t.bodySmall
                                    ?.copyWith(color: context.c.text36)),
                          ),
                        for (final c in _piyasa) _piyasaSatiri(context, c),
                        const SizedBox(height: SandikSpace.sm),
                      ],
                      if (bos)
                        ValueListenableBuilder<List<VarlikKimligi>>(
                          valueListenable: SonBakilanlar.instance.liste,
                          builder: (context, son, _) {
                            final gorunen =
                                SonBakilanlar.gorunenler(son, haric);
                            if (gorunen.isEmpty) return const SizedBox.shrink();
                            return Column(
                              key: const ValueKey('genel-arama-son-bakilanlar'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Baslik(context.l10n.searchRecentUpper),
                                for (final c in gorunen)
                                  _sonBakilanSatiri(context, c),
                                const SizedBox(height: SandikSpace.sm),
                              ],
                            );
                          },
                        ),
                      if (eylemler.isNotEmpty) ...[
                        _Baslik(context.l10n.s7EylemlerUpper),
                        for (final e in eylemler) _eylemSatiri(context, e),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Arama alanı + "Vazgeç" — takibe alma ekranıyla aynı biçim.
  Widget _aramaAlani(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.smd, 0, SandikSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                key: const ValueKey('genel-arama-alani'),
                controller: _ctrl,
                onChanged: _sorguDegisti,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                placeholder: context.l10n.aramaIpucuOrnekli,
                placeholderStyle:
                    context.t.bodyMedium?.copyWith(color: context.c.text36),
                style: context.t.bodyMedium?.copyWith(color: context.c.text90),
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.smd, vertical: SandikSpace.smd),
                suffixMode: OverlayVisibilityMode.editing,
                suffix: SandikTappable(
                  semanticLabel: context.l10n.clearSearch,
                  onTap: () {
                    _ctrl.clear();
                    _sorguDegisti('');
                  },
                  child: SizedBox(
                    width: SandikTouch.min,
                    height: SandikTouch.min,
                    child: Icon(Icons.close_rounded,
                        size: 16, color: context.c.text58),
                  ),
                ),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: SandikSpace.sm2),
                  child: Icon(Icons.search_rounded,
                      size: 18, color: context.c.text58),
                ),
                decoration: BoxDecoration(
                  color: context.inputFill,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(color: context.c.hairline),
                ),
              ),
            ),
            CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel,
                  style: context.t.bodyMedium
                      ?.copyWith(color: context.c.amberText)),
            ),
          ],
        ),
      );

  /// Kendi pozisyonu → Portföy satırıyla AYNI açılış (`asDisplayAsset` +
  /// pozisyonun lot'ları; `portfolio_screen` onTap). Tutar yazılmaz:
  /// "tutarları gizle" burada ayrıca düşünülmesin, satır yalnızca bulur.
  Widget _varlikSatiri(BuildContext context, Position p) {
    final a = p.representative;
    // Mevduatın sembolü sözleşme UUID'si (`MEVDUAT:<id>`) — kullanıcıya bir
    // şey söylemez, alt satıra yazılmaz (tür dökümündeki GUID bulgusunun
    // eşi, TestFlight 2026-10-10; bkz. `pozisyonEtiketi`).
    final kod =
        mevduatSozlesmeId(a.ticker) != null ? '' : pozisyonKodu(a.ticker);
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikTappable(
        semanticLabel: a.name,
        onTap: () => pushGuarded(
          context,
          adaptiveRoute<void>(
            settings: const RouteSettings(name: 'asset_detail'),
            builder: (_) => AssetDetailScreen(
              asset: p.asDisplayAsset(),
              showBackButton: true,
              lots: p.lots,
            ),
          ),
        ),
        child: _SatirKabugu(
          bas: VarlikRozeti(type: a.type, ticker: a.ticker),
          baslik: a.name,
          alt: [
            if (kod.isNotEmpty && kod != a.name) kod,
            a.type.labelOf(context.l10n),
          ].join(' · '),
        ),
      ),
    );
  }

  /// "5 Çeyrek Altın ≈ ₺X" — fiyat yoksa `null` (satır çizilmez).
  /// Ad formdaki adla aynı: altında `GoldSubCategory.label` (formun
  /// seçicisi de bunu yazar), dövizde kodu (USD/EUR/GBP; iki dilde aynı).
  ///
  /// Ters kalıp ("10.000 tl çeyrek"): "₺10.000 ≈ 2,6 Çeyrek Altın", adet
  /// SATIŞ fiyatından (`gorunurSatisFiyati`, "Bozdurursan · Alırsan"
  /// satırıyla aynı kapı); kapı reddederse satır yok, alışa düşülmez.
  /// Adet kalıbı ("100 THYAO"): kotasyon TL değilse satır yok ("≈ ₺" yalan
  /// olurdu).
  Widget? _hizliHesapSatiri(BuildContext context, HizliHesap h) {
    final l = context.l10n;
    final sembol = hizliHesapSembolu(h);
    final q = sembol == null ? null : _kotasyon[sembol.toUpperCase()];
    if (sembol == null || q == null) return null;
    final ad = h.kimlik?.kisaEtiket ?? h.altin?.label ?? h.doviz!;
    final String baslik;
    final String alt;
    if (h.ters) {
      final satis = gorunurSatisFiyati(
        ticker: sembol,
        paraBirimi: q.currency ?? '',
        alis: q.regularMarketPrice,
        satis: q.satisFiyati,
      );
      final adet = h.alinabilecekAdet(satis);
      if (adet == null) return null;
      final tamTl = h.miktar == h.miktar.roundToDouble();
      baslik = l.aramaHizliHesapTers(
        fmtTRY(h.miktar, digits: tamTl ? 0 : 2),
        fmtNumFlex(adet, maxDigits: 2),
        ad,
      );
      final dayanak = h.altin != null
          ? l.aramaHizliHesapKuyumcuSatis
          : l.aramaHizliHesapSatis;
      alt = '$dayanak · ${l.aramaHizliHesapEkle}';
    } else {
      if (h.kimlik != null && (q.currency ?? 'TRY').toUpperCase() != 'TRY') {
        return null;
      }
      final tutar = h.tutar(q.regularMarketPrice);
      if (tutar == null) return null;
      baslik = l.aramaHizliHesap(fmtInputTr(h.miktar), ad, fmtTRY(tutar));
      alt = l.aramaHizliHesapEkle;
    }
    final k = h.kimlik;
    return Padding(
      key: const ValueKey('genel-arama-hizli-hesap'),
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikTappable(
        semanticLabel: '$baslik. $alt',
        onTap: () {
          // Yalnız özellik kodu sayılır; miktar/birim/arama metni değil.
          OzellikOlcumu.say(Ozellik.hizliHesap);
          pushGuarded(
            context,
            adaptiveRoute<void>(
              settings: const RouteSettings(name: 'add_asset'),
              // Hisse/fon: takip listesi ve varlık sayfasındaki "Portföye
              // ekle" ile aynı ön doldurma (sembol, ad, tür) + adet.
              builder: (_) => k == null
                  ? AddAssetScreen(hizliHesap: h, ekleYolu: 'arama')
                  : AddAssetScreen(
                      prefillTicker: k.ticker,
                      prefillName: k.name,
                      prefillType: k.type,
                      hizliHesap: h,
                      ekleYolu: 'arama',
                    ),
            ),
          );
        },
        child: _SatirKabugu(
          ikon: Icons.calculate_rounded,
          baslik: baslik,
          alt: alt,
        ),
      ),
    );
  }

  Widget _piyasaSatiri(BuildContext context, VarlikKimligi c) => Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        child: SandikTappable(
          onTap: () => showVarlikSayfasi(context, c),
          semanticLabel: context.l10n.vsOpenDetailSemantics(c.name),
          child: AramaSatirKutusu(
            kimlik: c,
            kotasyon: _kotasyon[c.ticker.toUpperCase()],
            sonu: const _Ok(),
          ),
        ),
      );

  /// "Son baktıkların" satırı: piyasa satırının AYNISI (aynı kutu, aynı
  /// fiyat yolu) + satır başına kaldırma. Kaldırma jesti takip listesinin
  /// kalıbı (`watchlist_screen`: sola kaydır, zemin işi yazar); kaydırma
  /// ekran okuyucuda yapılamadığı için aynı iş özel eylem olarak da var.
  /// Etiket dıştaki tek düğümde; dokunma eylemi `SandikTappable`'ın
  /// jestinden o düğüme katılır (iç etiket verilmez, iki düğüm olmasın).
  Widget _sonBakilanSatiri(BuildContext context, VarlikKimligi c) {
    final l = context.l10n;
    return Padding(
      key: ValueKey('son-bakilan-${c.key}'),
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: Semantics(
        container: true,
        button: true,
        label: l.vsOpenDetailSemantics(c.name),
        customSemanticsActions: {
          CustomSemanticsAction(label: l.searchRecentRemove): () =>
              CrashReporter.arkaPlan(_sonBakilaniKaldir(c),
                  reason: 'GenelArama.sonBakilanKaldir'),
        },
        child: Dismissible(
          key: ValueKey('son-bakilan-kaydir-${c.key}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: SandikSpace.md),
            decoration: BoxDecoration(
              color: context.c.loss,
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    l.searchRecentRemove,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelLarge
                        ?.copyWith(color: context.c.onStatus),
                  ),
                ),
                const SizedBox(width: SandikSpace.xs2),
                Icon(Icons.close_rounded,
                    color: context.c.onStatus, size: 20),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            SandikHaptic.medium.perform();
            return true;
          },
          onDismissed: (_) => CrashReporter.arkaPlan(_sonBakilaniKaldir(c),
              reason: 'GenelArama.sonBakilanKaldir'),
          child: SandikTappable(
            onTap: () {
              // Yalnız özellik kodu; hangi varlığa bakıldığı gitmez.
              OzellikOlcumu.say(Ozellik.sonBakilan);
              showVarlikSayfasi(context, c);
            },
            child: ExcludeSemantics(
              child: AramaSatirKutusu(
                kimlik: c,
                kotasyon: _kotasyon[c.ticker.toUpperCase()],
                sonu: const _Ok(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eylemSatiri(BuildContext context, AramaEylemi e) {
    final (ikon, etiket) = switch (e) {
      AramaEylemi.fiyatAlarmlari => (
          Icons.add_alert_rounded,
          context.l10n.s7EylemFiyatAlarmlari
        ),
      AramaEylemi.sinyalAyarlari => (
          Icons.tune_rounded,
          context.l10n.s7EylemSinyalAyarlari
        ),
      AramaEylemi.ekstreAktar => (
          Icons.upload_file_rounded,
          context.l10n.s7EylemEkstreAktar
        ),
      AramaEylemi.topluEkle => (
          Icons.playlist_add_rounded,
          context.l10n.s7EylemTopluEkle
        ),
      AramaEylemi.tumHareketler => (
          Icons.receipt_long_rounded,
          context.l10n.s7EylemTumHareketler
        ),
      AramaEylemi.karsilastir => (
          Icons.compare_arrows_rounded,
          context.l10n.s7EylemKarsilastir
        ),
      AramaEylemi.takipListesi => (
          Icons.visibility_rounded,
          context.l10n.s7EylemTakipListesi
        ),
      AramaEylemi.bildirimler => (
          Icons.notifications_rounded,
          context.l10n.s7EylemBildirimler
        ),
      AramaEylemi.ayarlar => (
          Icons.settings_rounded,
          context.l10n.s7EylemAyarlar
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikTappable(
        semanticLabel: etiket,
        onTap: () => _eylemiAc(e),
        child: _SatirKabugu(ikon: ikon, baslik: etiket),
      ),
    );
  }

  /// Her hedef BUGÜNKÜ giriş noktasıyla aynı rotadan açılır (aynı ekran,
  /// aynı parametre); arama yeni bir kapı açmaz, var olanlara kestirme olur.
  void _eylemiAc(AramaEylemi e) {
    // Ad ekran ölçümü içindir (`EkranOlcumu`); giriş noktasındakiyle aynı.
    void it(String ad, Widget Function(BuildContext) b) => pushGuarded(
        context,
        adaptiveRoute<void>(settings: RouteSettings(name: ad), builder: b));
    switch (e) {
      case AramaEylemi.fiyatAlarmlari:
        it('price_alerts', (_) => const PriceAlertsScreen());
      case AramaEylemi.sinyalAyarlari:
        it('signal_settings', (_) => const SignalSettingsScreen());
      case AramaEylemi.ekstreAktar:
        CrashReporter.arkaPlan(_ekstredenAktar(),
            reason: 'GenelArama.ekstredenAktar');
      case AramaEylemi.topluEkle:
        it('bulk_add_asset', (_) => const BulkAddAssetScreen());
      case AramaEylemi.karsilastir:
        it('comparison', (_) => const ComparisonScreen());
      case AramaEylemi.takipListesi:
        pushGuarded(
          context,
          adaptiveRoute<void>(
            settings: const RouteSettings(name: 'add_watchlist'),
            builder: (_) => const AddWatchlistScreen(),
            fullscreenDialog: true,
          ),
        );
      case AramaEylemi.ayarlar:
        it('settings', (_) => const SettingsScreen());
      case AramaEylemi.tumHareketler:
      case AramaEylemi.bildirimler:
        // İkisi de ana ekranın kendi açıcısı; arama kapanır, ana ekran açar
        // (zil sayfası ana ekranın üstünde açılmalı, aramanın değil).
        final ac = e == AramaEylemi.tumHareketler
            ? widget.tumHareketleriAc
            : widget.bildirimleriAc;
        Navigator.pop(context);
        ac?.call();
    }
  }

  /// Ekle formundaki "Ekstreden aktar" akışıyla aynı: içe aktarma sepeti
  /// doldurur, onay Toplu Ekle'de (`add_asset_screen._ekstredenAktar`).
  Future<void> _ekstredenAktar() async {
    final aktarildi = await pushGuarded<bool>(
      context,
      adaptiveRoute<bool>(settings: const RouteSettings(name: 'csv_import'), builder: (_) => const CsvImportScreen()),
    );
    if (aktarildi != true || !mounted) return;
    await pushGuarded<bool>(
      context,
      adaptiveRoute<bool>(settings: const RouteSettings(name: 'bulk_add_asset'), builder: (_) => const BulkAddAssetScreen()),
    );
  }
}

/// Bölüm başlığı — takibe alma ekranındaki gibi 44pt satır.
class _Baslik extends StatelessWidget {
  const _Baslik(this.metin);
  final String metin;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SandikSectionHeader(title: metin),
        ),
      );
}

/// Varlık ve eylem satırının ortak kabuğu: nokta ya da ikon, başlık,
/// isteğe bağlı alt satır, sağda ok. Piyasa satırıyla aynı kart ve boy.
class _SatirKabugu extends StatelessWidget {
  const _SatirKabugu({
    required this.baslik,
    this.alt,
    this.bas,
    this.ikon,
  });

  final String baslik;
  final String? alt;

  /// Varlık satırının başı (tür noktası ya da `goz_alici` rozeti).
  final Widget? bas;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: SandikCard(
          padding: const EdgeInsets.only(left: SandikSpace.smd),
          child: Row(
            children: [
              if (bas != null)
                bas!
              else if (ikon != null)
                Icon(ikon, size: 18, color: context.c.text58),
              const SizedBox(width: SandikSpace.sm2),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(baslik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text90)),
                      if (alt != null && alt!.isNotEmpty)
                        Text(alt!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.labelSmall
                                ?.copyWith(color: context.c.text36)),
                    ],
                  ),
                ),
              ),
              const _Ok(),
            ],
          ),
        ),
      );
}

/// Satır sonu gezinti oku (TASARIM_DILI §4 İkonlar: `chevron_right_rounded`,
/// `text36`).
class _Ok extends StatelessWidget {
  const _Ok();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: SandikSpace.smd),
        child: Icon(Icons.chevron_right_rounded,
            size: 20, color: context.c.text36),
      );
}
