import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Material,
        Colors,
        SnackBarAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/arama_gruplari.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/price_service.dart';
import '../services/son_bakilanlar.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../utils/tr_katla.dart';
import 'paywall_screen.dart';
import 'varlik_sayfasi.dart';
import '../l10n/l10n.dart';

/// Varlık arama ekranı — takibe alma ve "sadece bakma" TEK ekranda.
///
/// ## Giriş noktaları (arama tasarımı, kullanıcı onayı 2026-09-28)
/// - Ana ekrandaki piyasa bandının sağ ucundaki büyüteç: yalnızca izlemeye
///   gelen kullanıcının yolu. Alt çubuk (simetri) ve üst çubuk (çıkış
///   düğmesi, 5. düğmede taşma) bilinçli olarak değiştirilmedi.
/// - Takip listesindeki "Takibe al": aynı ekran; satırdaki "+" hızlı ekler.
///
/// Arama, karşılaştırma ekranıyla AYNI `SymbolSearchService` üzerinden
/// yapılır: BIST hisseleri, TEFAS fonları (kurucu-only fonlar dahil),
/// altın ürünleri, döviz, **endeksler**, **emtia** ve kripto. Eskiden bu
/// ekran kendi listesini tutuyordu ve endeksler/emtia takip listesine HİÇ
/// eklenemiyordu; tek kaynak bu ayrışmayı yapısal olarak engelliyor.
///
/// ## Yerleşim
/// - **Boş sorgu:** "Son baktıkların" (cihazda, en çok 8, temizlenebilir) +
///   "Piyasalar" (servisin öneri listesi). Kullanıcı yazmadan bir şey görür.
/// - **Sorgu:** sonuçlar türe göre gruplanır, grup başına 3 satır +
///   "Tümü (n)" (`aramaGrupla`). Tür çipleri tek türe odaklar.
/// - **Satır:** ad, sembol · tür, fiyat ve günlük değişim. Fiyat görünen
///   satırlar için TEK toplu `fetchQuotes` ile gelir (piyasa bandıyla aynı
///   yol); bilinmeyen fiyat/yüzde yazılmaz, yer tutucu sayı uydurulmaz.
///
/// **Portföyde olan varlık** kendi grubunda "Portföyünde" etiketiyle kalır —
/// gizlemek yanlış olurdu (kullanıcı aradığını bulamayınca uygulamanın onu
/// tanımadığını sanır), takip "+"sı ise anlamsız (aynı şeyi hem sahiplenip
/// hem takip etmek). Eskiden ayrı, soluk bir grupta duruyordu; türe göre
/// gruplamada ayrı grup aynı varlığı türünden koparırdı.
class AddWatchlistScreen extends ConsumerStatefulWidget {
  const AddWatchlistScreen({super.key, this.baslangicKotasyon = const {}});

  /// Testte ağ yerine verilen kotasyonlar (sembol büyük harf → kotasyon).
  /// Uygulamada boş; fiyatlar `PriceService`'ten gelir.
  final Map<String, YahooQuote> baslangicKotasyon;

  @override
  ConsumerState<AddWatchlistScreen> createState() => _AddWatchlistScreenState();
}

class _AddWatchlistScreenState extends ConsumerState<AddWatchlistScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<VarlikKimligi> _results = const [];
  bool _loading = true;

  /// Seçili tür çipi; `null` = Tümü. Yeni sorguda sıfırlanmaz — kullanıcı
  /// "Fon" seçip yazmaya devam ederse fonlarda kalmak ister.
  AssetType? _tur;

  /// Görünen satırların kotasyonu — sembol (büyük harf) → kotasyon.
  late Map<String, YahooQuote> _kotasyon = widget.baslangicKotasyon;

  /// Yalnızca EN SON aramanın sonucu uygulanır.
  ///
  /// Kullanıcı hızlı yazarken istekler sırasız dönebilir; sayaç olmadan
  /// eski bir sorgunun sonucu yenisinin üstüne yazılabilirdi.
  int _seq = 0;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ara(''); // boş sorgu → popüler öneriler
    // Oturum henüz çözülmemiş olabilir (soğuk açılış): kimlik gelince yükle.
    ref.listenManual(authProvider, (_, next) {
      final uid = next.valueOrNull?.id;
      if (uid == null) return;
      CrashReporter.arkaPlan(
          SonBakilanlar.instance.yukle(uid).then((_) => _fiyatla(
              SonBakilanlar.instance.liste.value.map((k) => k.ticker))),
          reason: 'Arama.sonBakilanlar');
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _sorguDegisti(String v) {
    setState(() => _q = v);
    // 250 ms: her tuş vuruşunda TEFAS'a gitmemek için. Yerleşik listeler
    // zaten bellekte ama fon araması ağa çıkabiliyor.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _ara(v));
  }

  Future<void> _ara(String q) async {
    final id = ++_seq;
    List<VarlikKimligi> kimlikler(List<SymbolHit> hits) => [
          for (final h in hits)
            if (VarlikKimligi.fromSymbolHit(h) case final c?) c,
        ];
    // Yerleşik sonuçlar ANINDA; fon/kripto katmanı gelince tam liste yerine
    // geçer. Soğuk TEFAS önbelleğinde ilk arama saniyeler sürebiliyor.
    final yerel = kimlikler(SymbolSearchService.instance.yerelAra(q));
    if (mounted) {
      setState(() {
        _loading = true;
        _results = yerel;
      });
    }
    try {
      final hits = await SymbolSearchService.instance.search(q);
      if (!mounted || id != _seq) return;
      final sonuc = kimlikler(hits);
      setState(() {
        _results = sonuc;
        _loading = false;
        // Seçili tür yeni sonuçta yoksa çip boşa düşmesin.
        if (_tur != null && !sonuc.any((c) => c.type == _tur)) _tur = null;
      });
      // Yalnızca GÖRÜNECEK satırların fiyatı istenir: gruplar 3'er satır,
      // ya da seçili türün tamamı. Binlerce fondan 20'si bile tek istek.
      CrashReporter.arkaPlan(
        _fiyatla([
          for (final g in aramaGrupla(sonuc, filtre: _tur))
            for (final c in g.ogeler) c.ticker,
        ]),
        reason: 'Arama.fiyat',
      );
    } catch (_) {
      if (!mounted || id != _seq) return;
      // Arama başarısızsa liste boş kalır; kullanıcı yeniden yazabilir.
      setState(() => _loading = false);
    }
  }

  /// Eksik kotasyonları TEK toplu istekle çeker. `PriceService` önbellekli:
  /// aynı sembol tekrar sorulursa ağa çıkmaz.
  Future<void> _fiyatla(Iterable<String> semboller) async {
    final eksik = [
      for (final s in semboller.toSet())
        if (!_kotasyon.containsKey(s.toUpperCase())) s,
    ];
    if (eksik.isEmpty) return;
    final q = await PriceService.instance.fetchQuotes(eksik);
    if (!mounted || q.isEmpty) return;
    setState(() => _kotasyon = {..._kotasyon, ...q});
  }

  void _turSec(AssetType? t) {
    setState(() => _tur = t);
    CrashReporter.arkaPlan(
      _fiyatla([
        for (final g in aramaGrupla(_results, filtre: t))
          for (final c in g.ogeler) c.ticker,
      ]),
      reason: 'Arama.fiyat',
    );
  }

  // Sembol → tür/alt kategori/para birimi kuralı `VarlikKimligi.fromSymbolHit`
  // içinde: varlık sayfası dört giriş noktasından aynı kimlikle açılır ve
  // "zaten takipte" tespiti ekranlar arasında ayrışmamalı.

  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(watchlistProvider).valueOrNull ?? const [];
    final watchedKeys = {for (final w in watchlist) w.key};

    // Portföydeki varlıkların anahtarları — "Portföyünde" etiketi için.
    //
    // `aktifLotlar`: tamamen satılmış pozisyon "portföyde var" sayılmamalı.
    // Ham `isActive` ile kullanıcı, elinden çıkardığı bir hisseyi takip
    // listesine EKLEYEMİYORDU — satır "zaten portföyünde" diye pasifti.
    final owned =
        aktifLotlar(ref.watch(portfolioProvider).valueOrNull?.assets ?? const []);
    final ownedKeys = <String>{
      for (final a in owned)
        '${a.type.name}|${(a.subCategory?.trim().isNotEmpty ?? false) ? 'sub:${a.subCategory!.trim().toUpperCase()}' : a.ticker.trim().toUpperCase()}',
    };

    Widget satir(VarlikKimligi c) => Padding(
          padding: const EdgeInsets.only(bottom: SandikSpace.sm),
          child: _tile(context, c,
              watched: watchedKeys.contains(c.key),
              owned: ownedKeys.contains(c.key)),
        );

    final bos = _q.trim().isEmpty;
    final gruplar = bos ? const <AramaGrubu>[] : aramaGrupla(_results, filtre: _tur);
    final turler = bos ? const <AssetType>[] : aramaTurleri(_results);
    final hp = SandikSpace.screenH(context);

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
                _searchField(context),
                if (turler.length > 1) _turCipleri(context, turler),
                if (_loading && !bos)
                  Padding(
                    padding: const EdgeInsets.only(top: SandikSpace.xs2),
                    child: Text(context.l10n.searchingEllipsis,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text36)),
                  ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, SandikSpace.lgs),
                    children: [
                      if (bos) ...[
                        ValueListenableBuilder<List<VarlikKimligi>>(
                          valueListenable: SonBakilanlar.instance.liste,
                          builder: (context, son, _) => son.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _Baslik(SandikSectionHeader(
                                      title: context.l10n.searchRecentUpper,
                                      trailing: _MetinDugmesi(
                                        metin: context.l10n.clearVerb,
                                        onTap: _sonBakilanlariTemizle,
                                      ),
                                    )),
                                    for (final c in son) satir(c),
                                    const SizedBox(height: SandikSpace.md),
                                  ],
                                ),
                        ),
                        if (_results.isNotEmpty) ...[
                          _Baslik(SandikSectionHeader(
                              title: context.l10n.searchMarketsUpper)),
                          for (final c in _results) satir(c),
                        ],
                      ] else if (gruplar.isEmpty && !_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: SandikSpace.xxl),
                          child: Text(
                            context.l10n.noResultForQuery(_q.trim()),
                            textAlign: TextAlign.center,
                            style: context.t.bodyMedium
                                ?.copyWith(color: context.c.text58),
                          ),
                        )
                      else
                        for (final g in gruplar) ...[
                          _Baslik(SandikSectionHeader(
                            title: buyukHarf(g.tur.labelOf(context.l10n),
                                turkce: context.l10n.localeName
                                    .startsWith('tr')),
                            trailing: g.kisaltildi
                                ? _MetinDugmesi(
                                    metin: context.l10n.searchShowAll(g.toplam),
                                    onTap: () => _turSec(g.tur),
                                  )
                                : null,
                          )),
                          for (final c in g.ogeler) satir(c),
                          const SizedBox(height: SandikSpace.sm),
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

  Future<void> _sonBakilanlariTemizle() async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    await SonBakilanlar.instance.temizle(uid);
  }

  /// Arama alanı + "Vazgeç". Başlık YOK: ekranın ne olduğunu alanın kendisi
  /// söylüyor; başlık satırı klavye açıkken sonuçlardan bir satır çalardı.
  Widget _searchField(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.smd, 0, SandikSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _ctrl,
                onChanged: _sorguDegisti,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                placeholder: context.l10n.searchShortHint,
                placeholderStyle:
                    context.t.bodyMedium?.copyWith(color: context.c.text36),
                style: context.t.bodyMedium?.copyWith(color: context.c.text90),
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.smd, vertical: SandikSpace.smd),
                // Cupertino'nun hazır silme düğmesi (gri dolu daire,
                // `systemGrey`) sandık paletine yabancı kalıyordu — koyu
                // zeminde açık gri bir yumru. Kendi düğmemiz: 20pt
                // saydam-beyaz daire, 12pt çarpı, 44pt dokunma alanı.
                // `_ctrl.clear()` onChanged tetiklemez; sorgu elle
                // sıfırlanır ki sonuçlar ve "son bakılanlar" geri gelsin.
                suffixMode: OverlayVisibilityMode.editing,
                suffix: SandikTappable(
                  semanticLabel: context.l10n.clearSearch,
                  onTap: () {
                    _ctrl.clear();
                    _sorguDegisti('');
                  },
                  child: Container(
                    width: SandikTouch.min,
                    height: SandikTouch.min,
                    alignment: Alignment.center,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: context.c.text36.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 12, color: context.c.text90),
                    ),
                  ),
                ),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: SandikSpace.sm2),
                  child: Icon(Icons.search_rounded,
                      size: 18, color: context.c.text58),
                ),
                decoration: BoxDecoration(
                  // Seçici alt sayfasıyla aynı dolgu (tema `inputFill`).
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

  Widget _turCipleri(BuildContext context, List<AssetType> turler) {
    final hp = SandikSpace.screenH(context);
    return SizedBox(
      height: SandikTouch.min,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hp),
        children: [
          _TurCipi(
            metin: context.l10n.allTypes,
            secili: _tur == null,
            onTap: () => _turSec(null),
          ),
          for (final t in turler)
            _TurCipi(
              metin: t.labelOf(context.l10n),
              secili: _tur == t,
              onTap: () => _turSec(_tur == t ? null : t),
            ),
        ],
      ),
    );
  }

  /// Arama sonucu satırı.
  ///
  /// **Satıra dokunmak ÖNİZLER, "+" hemen takibe alır** (kullanıcı kararı,
  /// 2026-09-28). Eskiden satırın tamamı "takibe al" idi; kullanıcı bir
  /// varlığa bakmak için önce listeye eklemek, sonra çıkarmak zorundaydı.
  /// Hızlı ekleme alışkanlığı bozulmasın diye "+" satırın sağında kaldı.
  /// Portföydeki varlık da önizlenebilir; sayfa onu pozisyona yönlendirir.
  Widget _tile(BuildContext context, VarlikKimligi c,
      {bool watched = false, bool owned = false}) {
    return SandikTappable(
      onTap: () => showVarlikSayfasi(context, c),
      semanticLabel: context.l10n.vsOpenDetailSemantics(c.name),
      child: _SatirKutusu(
        kimlik: c,
        kotasyon: _kotasyon[c.ticker.toUpperCase()],
        sonu: owned
            ? _SatirSonu(
                child: Text(context.l10n.searchInPortfolioTag,
                    style: context.t.labelSmall
                        ?.copyWith(color: context.c.text36)),
              )
            : watched
                ? _SatirSonu(
                    child: Text(context.l10n.watchlistInListLabel,
                        style: context.t.labelSmall
                            ?.copyWith(color: context.c.text36)),
                  )
                : _HizliTakipDugmesi(
                    semanticLabel: context.l10n.vsWatchSemantics(c.name),
                    onTap: () => _add(c),
                  ),
      ),
    );
  }

  Future<void> _add(VarlikKimligi c) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    try {
      await ref
          .read(watchlistProvider.notifier)
          .add(c.toWatchlistItem(userId: user.id));
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): satırdaki "+"
      // ikonu eklendi durumuna geçiyor, onay orada. Hata yolları (limit,
      // çakışma) toast'ını KORUR — orada geri bildirim tek kanal.
    } on WatchlistLimitException catch (e) {
      if (!mounted) return;
      // Limit hatası ağ hatasından AYRI ele alınır: kullanıcıya neden
      // eklenemediğini ve ÇIKIŞ YOLUNU söylemek gerekir. "Eklenemedi" deyip
      // bırakmak kullanıcıyı çıkışsız bırakırdı.
      // Paywall kapalıyken limit bir ÜRÜN sınırıdır (2026-09-25, 7 varlık):
      // "Premium" düğmesi olmayan bir şeyi satar, "ücretsiz plan" sözü de
      // olmayan bir planı ima ederdi. Çıkış yolu açıkça söylenir: birini çıkar.
      final paywallOn = ref.read(paywallVisibleProvider);
      sandikSnack(
        context,
        paywallOn
            ? context.l10n.watchlistLimitFree(e.limit)
            : context.l10n.watchlistLimitReached(e.limit),
        kind: SandikSnackKind.warning,
        action: paywallOn
            ? SnackBarAction(
                label: 'Premium',
                textColor: context.c.onAmber,
                onPressed: () =>
                    PaywallScreen.show(context, source: 'watchlist_limit'),
              )
            : null,
      );
    } catch (_) {
      if (!mounted) return;
      // Sunucudaki unique index çakışması da buraya düşer — kullanıcıya
      // teknik hata değil, ne olduğunu söyle.
      sandikSnack(context, 'Eklenemedi. Zaten takipte olabilir.',
          kind: SandikSnackKind.error);
    }
  }
}

/// Satırın sağ ucu — 44pt yükseklikte, sağ dolgulu.
class _SatirSonu extends StatelessWidget {
  const _SatirSonu({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: child,
      );
}

/// Satırın gövdesi: tür noktası, ad, sembol · tür, fiyat + günlük değişim.
class _SatirKutusu extends StatelessWidget {
  const _SatirKutusu({
    required this.kimlik,
    required this.kotasyon,
    required this.sonu,
  });

  final VarlikKimligi kimlik;
  final YahooQuote? kotasyon;
  final Widget sonu;

  @override
  Widget build(BuildContext context) {
    final c = kimlik;
    final fiyat = aramaFiyatMetni(c, kotasyon);
    final pct = aramaGunlukYuzde(c, kotasyon);
    return Container(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      padding: const EdgeInsets.only(left: SandikSpace.smd),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: SandikSpace.sm,
            height: SandikSpace.sm,
            decoration:
                BoxDecoration(color: c.type.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: SandikSpace.sm2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text90)),
                  Text(
                      [
                        if (aramaSembolEtiketi(c) case final e?) e,
                        c.type.labelOf(context.l10n),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelSmall
                          ?.copyWith(color: context.c.text36)),
                ],
              ),
            ),
          ),
          if (fiyat != null)
            Padding(
              padding: const EdgeInsets.only(left: SandikSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fiyat,
                      maxLines: 1,
                      style: context.t.bodySmall?.copyWith(
                          color: context.c.text90,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  if (pct != null)
                    Text(fmtPctIsaretli(pct),
                        maxLines: 1,
                        style: context.t.labelSmall?.copyWith(
                            color: pct.abs() < 0.005
                                ? context.c.text36
                                : context.signColor(pct),
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                ],
              ),
            ),
          const SizedBox(width: SandikSpace.xs),
          sonu,
        ],
      ),
    );
  }
}

/// Satırın ikinci satırındaki sembol; adı tekrar edecekse `null`.
///
/// Altın ürününde ad zaten "Çeyrek Altın"dır, sembol (`ALTIN_CEYREK`) bir
/// şey eklemez; kurda `USDTRY=X` Yahoo sözdizimidir, kullanıcı "USD" okur;
/// emtia vadelisinin kodu (`BZ=F`) anlamsızdır.
@visibleForTesting
String? aramaSembolEtiketi(VarlikKimligi c) {
  final t = c.ticker;
  if (t.startsWith('ALTIN_')) return null;
  if (t.endsWith('TRY=X')) return t.replaceAll('TRY=X', '');
  if (t.endsWith('=F')) return null;
  return c.kisaEtiket;
}

/// Satırda gösterilecek fiyat; bilinmiyorsa `null` (yazılmaz).
///
/// Endeks puandır: para simgesi ve kuruş anlamsız (piyasa bandıyla aynı
/// kural). Diğerleri kotasyonun kendi para birimiyle — emtia `$`, kalanı `₺`.
/// Kur çiftinin fiyatı KARŞI para birimindedir: `USDTRY=X` → "₺49,00"
/// ([kotasyonSembolu]; eskiden miktar sembolü "$49,00" yazılıyordu).
@visibleForTesting
String? aramaFiyatMetni(VarlikKimligi c, YahooQuote? q) {
  final f = q?.regularMarketPrice;
  if (f == null || !f.isFinite || f <= 0) return null;
  if (bistEndeksiMi(c.ticker)) {
    return fmtNum(f, digits: 0);
  }
  return tryFormatter(digits: 2, symbol: kotasyonSembolu(c.ticker, c.currency))
      .format(f);
}

/// Satırda gösterilecek günlük yüzde; bilinmiyorsa `null`.
///
/// Altında `altinGunlukYuzdeTam` kuralı: bir ayar bile yüzde taşımıyorsa
/// HİÇBİR altın ürün yüzdesi gösterilmez — yoksa aynı altın bu ekranda ve
/// Performans'ta iki farklı yüzde gösterirdi (bkz. `PriceService`).
@visibleForTesting
double? aramaGunlukYuzde(VarlikKimligi c, YahooQuote? q) {
  final p = q?.regularMarketChangePercent;
  if (p == null || !p.isFinite) return null;
  if (FiyatKaynagi.altinMi(c.ticker) &&
      !PriceService.instance.altinGunlukYuzdeTam) {
    return null;
  }
  return p;
}

/// Bölüm başlığı satırı — eylemli ya da eylemsiz, hep 44pt: "Tümü (n)"
/// olan grupla olmayan grup arasında satır aralığı zıplamasın.
class _Baslik extends StatelessWidget {
  const _Baslik(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
}

/// Bölüm başlığının sağındaki metin eylemi ("Temizle", "Tümü (n)").
class _MetinDugmesi extends StatelessWidget {
  const _MetinDugmesi({required this.metin, required this.onTap});
  final String metin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SandikTappable(
        onTap: onTap,
        semanticLabel: metin,
        child: Container(
          constraints: const BoxConstraints(
              minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          alignment: Alignment.centerRight,
          child: Text(metin,
              style: context.t.labelLarge?.copyWith(
                  color: context.c.amberText, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Tür çipi — seçiliyse amber dolgu.
class _TurCipi extends StatelessWidget {
  const _TurCipi(
      {required this.metin, required this.secili, required this.onTap});
  final String metin;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: secili,
        child: SandikTappable(
          onTap: onTap,
          semanticLabel: metin,
          child: Container(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            padding: const EdgeInsets.only(right: SandikSpace.xs2),
            alignment: Alignment.center,
            child: _CipGovdesi(metin: metin, secili: secili),
          ),
        ),
      );
}

class _CipGovdesi extends StatelessWidget {
  const _CipGovdesi({required this.metin, required this.secili});
  final String metin;
  final bool secili;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.move,
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.xs2),
        decoration: BoxDecoration(
          color: secili ? context.c.amberFill : context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          border: Border.all(
              color: secili ? context.c.amberFill : context.c.hairline),
        ),
        child: Text(metin,
            style: context.t.labelLarge?.copyWith(
                color: secili ? context.c.onAmber : context.c.text58,
                fontWeight: FontWeight.w600)),
      );
}

/// "+ Takip" — satırın içinde AYRI bir dokunma hedefi. Satırın geri kalanı
/// önizler; bu düğme önizlemeden geçmeden hemen takibe alır.
class _HizliTakipDugmesi extends StatelessWidget {
  const _HizliTakipDugmesi({required this.semanticLabel, required this.onTap});
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SandikTappable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: Container(
          constraints: const BoxConstraints(
              minWidth: SandikTouch.min, minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text('+ ${context.l10n.vsWatch}',
              style: context.t.titleSmall?.copyWith(
                  color: context.c.amberText, fontWeight: FontWeight.w700)),
        ),
      );
}
