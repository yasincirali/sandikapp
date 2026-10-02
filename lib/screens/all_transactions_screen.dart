import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/transaction_row.dart';
import '../services/islem_notu.dart';
import '../widgets/islem_notu_sheet.dart';
import '../l10n/l10n.dart';
import '../widgets/gorunum_cipi.dart';

/// Portföy hareketleri — tam liste.
///
/// Ana sayfadaki "PORTFÖY HAREKETLERİ" bölümü yalnızca son 3 kaydı gösterir;
/// "Tümünü Gör" buraya getirir. Bu ekran bir LOG'dur: her Al/Sat/Temettü ve
/// her silme işlemi ayrı satırdır, dolayısıyla kayıt sayısı zamanla büyür.
/// Bu yüzden üç şey gerekiyor:
///
///   1. **Sayfalama** — hepsini birden kurmak uzun listede kare düşürür.
///      `ListView.builder` zaten tembel çalışır ama satır sayısı arttıkça
///      filtre/sıralama maliyeti de büyüdüğü için [_pageSize]'lık parçalar
///      hâlinde büyütüyoruz.
///   2. **Tarih aralığı** — "geçen ay ne yaptım" sorusu.
///   3. **Metin araması** — varlık adı / ticker üzerinde.
///
/// Ana sayfadan farklı olarak burada AGGREGATE YOK: liste ham ledger'dır.
/// Silinen kayıtlar varsayılan listede YOK; "Silinenler" filtresiyle
/// görünür (bkz. [hareketleriAyir], `_silinenler`).
class AllTransactionsScreen extends ConsumerStatefulWidget {
  final Map<String, List<Asset>> allPartnerAssets;
  final List<AppUser> partners;

  /// Ana sayfadaki sahiplik sekmesi ('' = Ben, null = Birlikte, id = ortak).
  final String? initialView;
  final AssetType? initialTypeFilter;

  const AllTransactionsScreen({
    super.key,
    required this.allPartnerAssets,
    required this.partners,
    this.initialView,
    this.initialTypeFilter,
  });

  @override
  ConsumerState<AllTransactionsScreen> createState() =>
      _AllTransactionsScreenState();
}

/// Bir aya düşen hareketler; `ay` o ayın ilk günü (yerel saat).
class HareketAyGrubu {
  const HareketAyGrubu(this.ay, this.kayitlar);
  final DateTime ay;
  final List<Asset> kayitlar;
}

/// Sıralı (yeni → eski) kayıtları aya böler; kayıt sırası korunur.
///
/// Giriş zaten tarihe göre sıralı olmalı — burada yeniden sıralanmaz,
/// çünkü sıralama ve filtre ekranın işi; bu fonksiyon yalnızca ardışık
/// kayıtları ay sınırından keser. Sırasız giriş aynı ayı iki kaba bölerdi.
///
/// [tarih]: hangi ana göre bölüneceği. Varsayılan işlem tarihi; silinenler
/// filtresinde silinme anı ([silinmeAni]) — liste o sıradadır.
List<HareketAyGrubu> hareketleriAylaGrupla(
  List<Asset> kayitlar, {
  DateTime Function(Asset) tarih = _islemTarihi,
}) {
  final out = <HareketAyGrubu>[];
  for (final a in kayitlar) {
    final t = tarih(a).toLocal();
    final ay = DateTime(t.year, t.month);
    if (out.isNotEmpty && out.last.ay == ay) {
      out.last.kayitlar.add(a);
    } else {
      out.add(HareketAyGrubu(ay, [a]));
    }
  }
  return out;
}

DateTime _islemTarihi(Asset a) => a.addedDate;

/// Defteri iki kümeye ayırır: süren hareketler ve silinenler.
///
/// **Kullanıcı kararı 2026-09-29:** silinen varlık ana sayfadaki "Portföy
/// hareketleri"nde GÖRÜNMEZ; "Tümünü gör" ekranında "Silinenler"
/// filtresiyle, alım ve silinme tarihleriyle görünür. (Aynı gün ilk hâli
/// listenin sonunda ayrı bir alandı; kullanıcı "varsayılanda ayrıca
/// listelenmemeli, filtre olsun" dedi.) Eskiden damgalı lot'lar
/// soluk satır olarak akışın içindeydi ve silme işlemi ayrıca "Silindi"
/// mezar taşı yazıyordu — ana sayfanın üç satırı çoğu zaman artık
/// portföyde olmayan şeyleri anlatıyordu.
///
/// `aktif`: [Asset.isActive] (damgasız, mezar taşı değil), yeni → eski.
///
/// `silinen`: damgalı lot'lar, silinme anına göre yeni → eski. Mezar taşı
/// (`deleteLog`) YALNIZCA anlattığı lot'lar defterde yoksa girer: yumuşak
/// silmeden (`deleted_at`) önceki fiziksel silmelerde geriye kalan tek iz
/// odur. Yumuşak silmede lot'lar zaten kendi tarihleriyle listelendiği
/// için taş ikinci bir satır olurdu. Taşın "silinme anı" kendi eklenme
/// tarihidir (silme sırasında yazılır).
({List<Asset> aktif, List<Asset> silinen}) hareketleriAyir(
    List<Asset> defter) {
  final idler = {for (final a in defter) a.id};
  final aktif = <Asset>[];
  final silinen = <Asset>[];
  for (final a in defter) {
    if (a.isDeleteLog) {
      // Pozisyon silmesi (`deletedCount > 0`) lot'ları damgalar, hiçbiri
      // defterden gitmez. Tek lot silmesi `refAssetId` taşır.
      final kapsandi = a.deletedCount > 0 ||
          (a.refAssetId != null && idler.contains(a.refAssetId));
      if (!kapsandi) silinen.add(a);
    } else if (a.isDeleted) {
      silinen.add(a);
    } else {
      aktif.add(a);
    }
  }
  aktif.sort((a, b) => b.addedDate.compareTo(a.addedDate));
  final birlesik = eskiMezarTaslariniBirlestir(silinen)
    ..sort((a, b) => silinmeAni(b).compareTo(silinmeAni(a)));
  return (aktif: aktif, silinen: birlesik);
}

/// ESKİ tip mezar taşlarını tek satırda toplar.
///
/// ## Neden (kullanıcı bildirimi 2026-09-29: "silinenler doğru şekilde
/// gözükmeli")
/// Yumuşak silmeden (`deleted_at`) ve pozisyon başına tek mezar taşından
/// ÖNCE, pozisyon silmek her lot için AYRI bir `deleteLog` yazıyordu
/// (`deletedCount` 0) ve lot'ları fiziksel siliyordu. Canlı defterde bir
/// silme işlemi böylece 17 ayrı "Silindi" satırı olarak duruyor (ölçüldü:
/// AVOD, 2026-08-10, aynı dakikada 17 taş). Liste bunları alt alta
/// basınca silinenler tekrarlı ve okunmaz görünüyordu.
///
/// Aynı sahip + aynı varlık + aynı DAKİKADA yazılmış eski taşlar tek bir
/// işlemdir: miktarlar toplanır, tutar korunur (Σ miktar × fiyat),
/// `deletedCount` taş sayısı olur → satır "Silindi · 17 kayıt" der.
/// Yeni tip taşlara (`deletedCount > 0`) ve tek kalan eski taşa dokunulmaz.
/// Veri değişmez; yalnızca gösterim.
List<Asset> eskiMezarTaslariniBirlestir(List<Asset> silinen) {
  final gruplar = <String, List<Asset>>{};
  final out = <Asset>[];
  for (final a in silinen) {
    if (!a.isDeleteLog || a.deletedCount > 0) {
      out.add(a);
      continue;
    }
    final t = a.addedDate.toUtc();
    final anahtar = [
      a.userId,
      a.type.name,
      a.ticker,
      a.subCategory ?? '',
      a.unitType,
      t.year, t.month, t.day, t.hour, t.minute,
    ].join('|');
    gruplar.putIfAbsent(anahtar, () => []).add(a);
  }
  for (final g in gruplar.values) {
    if (g.length == 1) {
      out.add(g.single);
      continue;
    }
    final miktar = g.fold<double>(0, (t, a) => t + a.quantity);
    final tutar = g.fold<double>(0, (t, a) => t + a.quantity * a.purchasePrice);
    final r = g.first;
    out.add(Asset(
      id: 'mezar-grup:${r.id}',
      userId: r.userId,
      name: r.name,
      ticker: r.ticker,
      type: r.type,
      quantity: miktar,
      purchasePrice: miktar > 0 ? tutar / miktar : r.purchasePrice,
      currency: r.currency,
      notes: '',
      subCategory: r.subCategory,
      unitType: r.unitType,
      purchaseFxRate: r.purchaseFxRate,
      currentPrice: r.currentPrice,
      lastUpdated: r.lastUpdated,
      addedDate: g
          .map((a) => a.addedDate)
          .reduce((x, y) => x.isAfter(y) ? x : y),
      isManualPrice: r.isManualPrice,
      kind: AssetKind.deleteLog,
      deletedCount: g.length,
    ));
  }
  return out;
}

/// Silinen kaydın silinme anı: damga, yoksa (mezar taşı) kaydın kendisi.
DateTime silinmeAni(Asset a) => a.deletedAt ?? a.addedDate;

/// Tarih aralığı ön ayarları — mutlak tarih seçtirmek yerine yaygın
/// pencereleri tek dokunuşla veriyoruz; "Özel" takvim açar.
enum _DateRange { all, days7, days30, days90, thisYear, custom }

extension _DateRangeLabel on _DateRange {
  /// Sözlüğü çağıran verir: `extension` bağlamsız.
  String labelOf(AppLocalizations l) {
    switch (this) {
      case _DateRange.all:
        return l.rangeAllTime;
      case _DateRange.days7:
        return l.rangeLast7;
      case _DateRange.days30:
        return l.rangeLast30;
      case _DateRange.days90:
        return l.rangeLast90;
      case _DateRange.thisYear:
        return l.rangeThisYear;
      case _DateRange.custom:
        return l.rangeCustom;
    }
  }
}

class _AllTransactionsScreenState extends ConsumerState<AllTransactionsScreen>
    with SingleTickerProviderStateMixin {
  /// Filtre değişiminin görünür işareti (animasyon denetimi 2026-10-01).
  ///
  /// "Silinenler", dönem ya da tür değişince liste tek karede başka bir
  /// sonuç kümesine dönüyordu; yalnız çip değişiyordu, liste "değişti mi?"
  /// sorusunu bırakıyordu. Liste %35'ten 180 ms'de belirir. Eski ve yeni
  /// liste ÜST ÜSTE kurulmaz (`AnimatedSwitcher` uzun iki listeyi aynı anda
  /// kurardı) — yalnız yeni liste solarak gelir. Hareketi azalt'ta yok.
  late final AnimationController _filtreGecisi =
      AnimationController(vsync: this, value: 1);
  late final Animation<double> _filtreSolma = Tween<double>(begin: 0.35, end: 1)
      .animate(CurvedAnimation(parent: _filtreGecisi, curve: SandikMotion.enter));

  static const int _pageSize = 25;

  late String? _view;
  AssetType? _typeFilter;
  _DateRange _range = _DateRange.all;
  DateTimeRange? _customRange;
  String _query = '';

  /// "Silinenler" filtresi. Varsayılan KAPALI: liste yalnızca süren
  /// hareketleri gösterir. Açıkken yalnızca silinenler, silinme ayına göre
  /// kaplarda (kullanıcı kararı 2026-09-29).
  bool _silinenler = false;

  int _visible = _pageSize;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Ana ekrandan gelen görünüm gizlenmiş bir ortağı işaret edebilir.
    _view = GorunumCipi.gecerli(
        ref.read(activePartnersProvider), widget.initialView ?? '');
    _typeFilter = widget.initialTypeFilter;
    // Kullanıcı listenin sonuna yaklaşınca sessizce büyüt — "daha fazla
    // yükle" düğmesi log okumada akışı bölerdi.
    _scrollCtrl.addListener(_maybeGrow);
  }

  @override
  void dispose() {
    _filtreGecisi.dispose();
    _scrollCtrl.removeListener(_maybeGrow);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _maybeGrow() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      final total = _liste.length;
      if (_visible < total) {
        setState(() => _visible = (_visible + _pageSize).clamp(0, total));
      }
    }
  }

  /// Filtre değişince sayfalama başa sarmalı; aksi halde kullanıcı dar bir
  /// sonuç kümesinde "zaten hepsi yüklü" sanır ya da tersi.
  ///
  /// Kaydırma konumu da başa sarar (emülatör testi #25, 2026-09-29): liste
  /// eski ofsette kalıyordu — Silinenler'in dibinden dönem filtresine
  /// geçince yeni sonucun ilk 7 kaydı ekranın üstünde, görünmez kalıyordu.
  /// Anında `jumpTo` (animasyon değil): yeni sonuç kümesi eski konumla
  /// ilişkili değil, oraya "kayarak" gelmek bir süreklilik ima ederdi.
  /// Tüm filtre değişiklikleri bu tek noktadan geçer.
  void _resetPaging() {
    _visible = _pageSize;
    final sure = SandikMotion.stateOf(context);
    if (sure != Duration.zero) {
      _filtreGecisi
        ..duration = sure
        ..forward(from: 0);
    }
    if (_scrollCtrl.hasClients && _scrollCtrl.offset != 0) {
      _scrollCtrl.jumpTo(0);
      // Kare sonrası bir kez daha (CI kırmızısı 2026-10-02, tarihe bağlı):
      // `jumpTo` setState İÇİNDE eski içerikte koşuyor; yeni filtrenin
      // satırları yerleşince konum bir "ballistic" düzeltmeyle eski
      // ofsete (≈1.750) geri kayıyordu — liste başa dönmüş gibi yapıp
      // dibe dönüyordu. Ay kapları tarihe göre değiştiği için yalnız bazı
      // günlerde görünüyordu.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollCtrl.hasClients && _scrollCtrl.offset != 0) {
          _scrollCtrl.jumpTo(0);
        }
      });
    }
  }

  /// Sahiplik sekmesine göre ham ledger.
  List<Asset> get _ledger {
    final myAssets =
        ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    if (_view == '') return myAssets;
    if (_view != null && _view!.isNotEmpty) {
      return widget.allPartnerAssets[_view!] ?? const [];
    }
    return [
      ...myAssets,
      for (final list in widget.allPartnerAssets.values) ...list,
    ];
  }

  /// Seçili dönemin sınırları — sayfa taslağı için de aynı kural.
  static (DateTime?, DateTime?) _sinirlar(
      _DateRange range, DateTimeRange? customRange) {
    final now = DateTime.now();
    switch (range) {
      case _DateRange.all:
        return (null, null);
      case _DateRange.days7:
        return (now.subtract(const Duration(days: 7)), null);
      case _DateRange.days30:
        return (now.subtract(const Duration(days: 30)), null);
      case _DateRange.days90:
        return (now.subtract(const Duration(days: 90)), null);
      case _DateRange.thisYear:
        return (DateTime(now.year), null);
      case _DateRange.custom:
        final r = customRange;
        if (r == null) return (null, null);
        // Bitiş günü DAHİL olmalı: kullanıcı 5 Mart seçtiyse o günün
        // işlemleri de listeye girsin.
        return (
          dayKey(r.start),
          DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59),
        );
    }
  }

  List<Asset> get _filtered =>
      _suz(_FiltreSecimi(_range, _customRange, _typeFilter));

  /// Defteri [secim] + arama + görünümle süzer. Ekran ve filtre sayfası
  /// ("N kaydı göster") AYNI yoldan sayar; iki kopya ayrışırsa düğme bir
  /// sayı söyleyip liste başka bir sayı gösterirdi.
  List<Asset> _suz(_FiltreSecimi secim) {
    final (from, to) = _sinirlar(secim.range, secim.customRange);
    final q = _query.trim().toLowerCase();

    final out = <Asset>[];
    final ledger = _ledger;
    for (final a in ledger) {
      if (secim.tur != null && a.type != secim.tur) continue;
      if (from != null && a.addedDate.isBefore(from)) continue;
      if (to != null && a.addedDate.isAfter(to)) continue;
      if (q.isNotEmpty) {
        final name = a.name.toLowerCase();
        final ticker = a.ticker.toLowerCase();
        final sub = (a.subCategory ?? '').toLowerCase();
        if (!name.contains(q) &&
            !ticker.contains(q) &&
            !sub.contains(q) &&
            // Not da aranır (2026-09-29): "maaş" yazınca notunda maaş
            // geçen alışlar bulunur — not, kullanıcının işlemini kendi
            // cümlesiyle hatırladığı tek yer.
            !islemNotuEslesir(a, ledger, q)) {
          continue;
        }
      }
      out.add(a);
    }
    out.sort((a, b) => b.addedDate.compareTo(a.addedDate));
    return out;
  }

  /// Filtrelenmiş defter, süren/silinen diye ayrılmış. Filtreler iki
  /// kümeye de uygulanır: "THYAO" araması silinmiş THYAO'yu da bulur.
  ({List<Asset> aktif, List<Asset> silinen}) get _ayrim =>
      hareketleriAyir(_filtered);

  /// Görünen liste: filtreye göre süren ya da silinen kayıtlar.
  List<Asset> get _liste => _silinenler ? _ayrim.silinen : _ayrim.aktif;

  bool get _hasActiveFilter =>
      _silinenler ||
      _typeFilter != null ||
      _range != _DateRange.all ||
      _query.trim().isNotEmpty;

  /// Hareket satırı + işlem notu bağlantısı.
  ///
  /// Not görünürlüğü ve düzenlenebilirlik tek yerden (`islem_notu.dart`);
  /// satır, notu olan ya da not yazılabilen kayıtta dokunulur. Ortağın
  /// notsuz kaydında açılacak bir şey yok — satır eskisi gibi durur.
  Widget _hareketSatiri(
    Asset a,
    List<Asset> defter, {
    required BazPara baz,
    required PortfolioState portfolioState,
    required bool hideBalance,
  }) {
    final not = islemNotu(a, defter);
    final benimId = ref.watch(authProvider).valueOrNull?.id;
    final acilir =
        not != null || islemNotuDuzenlenebilir(a, benimId: benimId);
    return TransactionRow(
      baz: baz,
      asset: a,
      portfolioState: portfolioState,
      hideBalance: hideBalance,
      yilGoster: _silinenler,
      silinenGorunumu: _silinenler,
      not: not,
      onTap: acilir
          ? () => showIslemNotuSheet(context, ref, asset: a, not: not)
          : null,
    );
  }


  @override
  Widget build(BuildContext context) {
    final activePartners = ref.watch(activePartnersProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final hideBalance = ref.watch(balanceHiddenProvider);
    // Not görünürlüğü (eski kopya ayıklaması) tüm defterle karar verir,
    // filtrelenmiş sayfayla değil — bkz. `islemNotu`.
    final ledger = _ledger;
    // Gizlenen/çıkarılan ortak seçili görünümde KALMASIN: toplam ₺0'a düşer
    // (bkz. `GorunumCipi.gecerli`, 2026-09-28).
    ref.listen(activePartnersProvider, (_, next) {
      final v = GorunumCipi.gecerli(next, _view);
      if (v != _view) {
        setState(() {
          _view = v;
          _resetPaging();
        });
      }
    });

    final ayrim = _ayrim;
    final rows = _silinenler ? ayrim.silinen : ayrim.aktif;
    final silinenSayisi = ayrim.silinen.length;
    final toplam = rows.length;
    final shown = _visible.clamp(0, rows.length);

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        title: context.l10n.portfolioActivityTitle,
        transparent: true,
      ),
      body: Column(
        children: [
          if (activePartners.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8, SandikSpace.screenH(context), 0),
              child: ModernTabSelector(
                partners: activePartners,
                selectedId: _view,
                onChanged: (v) => setState(() {
                  _view = v;
                  _resetPaging();
                }),
              ),
            ),

          // ── Arama ────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() {
                _query = v;
                _resetPaging();
              }),
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
              decoration: context.inputDecoration(
                context.l10n.searchAssetSymbolOrNote,
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: context.c.text36),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: context.c.text36),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                          _resetPaging();
                        }),
                      ),
              ),
            ),
          ),

          // ── Filtre satırı (seçenek C, kullanıcı kararı 2026-09-29) ─────
          //
          // Eskiden dönem ve tür iki ayrı, yatay kayan çip satırıydı: ilk
          // kayıt ekranın ortasında başlıyordu, "Bu yıl" / "Özel" /
          // "Kripto" kaydırmanın arkasında kalıyordu, iki satır birbirinin
          // aynısı görünüyordu. Şimdi: [Filtrele] dönem + tür sayfasını
          // açar; hemen yanındaki [Silinenler] sayfaya girmeden TEK
          // dokunuşla silinenleri getirir (kullanıcı isteği); etkin dönem ve
          // tür aynı satırda × ile kaldırılabilir çip olarak durur.
          Padding(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                SandikSpace.smd, SandikSpace.screenH(context), 0),
            child: HScrollWithFade(
              child: Row(
                children: [
                  _filtreCipi(),
                  if (_range != _DateRange.all) ...[
                    const SizedBox(width: SandikSpace.sm),
                    _EtkinCip(
                      etiket: _donemEtiketi(context, _range, _customRange),
                      renk: context.c.amberText,
                      onKaldir: () => setState(() {
                        _range = _DateRange.all;
                        _customRange = null;
                        _resetPaging();
                      }),
                    ),
                  ],
                  if (_typeFilter != null) ...[
                    const SizedBox(width: SandikSpace.sm),
                    _EtkinCip(
                      etiket: _typeFilter!.labelOf(context.l10n),
                      renk: _typeFilter!.color,
                      onKaldir: () => setState(() {
                        _typeFilter = null;
                        _resetPaging();
                      }),
                    ),
                  ],
                  // "Silinenler" HER ZAMAN durur (kullanıcı bildirimi
                  // 2026-09-29: "silinenler filtresi silinmiş gibi"). Eskiden
                  // silinmiş kayıt yokken gizleniyordu: filtre bir hesapta var,
                  // ötekinde yok görünüyor, özellik kaybolmuş sanılıyordu.
                  // Kayıt yoksa sayı yazılmaz; açınca boş durum anlatır.
                  //
                  // Yeri satırın SONU: etkin dönem/tür çipleri [Filtrele]'nin
                  // parçası, onun yanında kalır. Filtre yokken bu çip zaten
                  // [Filtrele]'nin hemen yanına düşer (istenen yer); filtre
                  // varken araya girip etkin çipleri kaydırmanın arkasına
                  // itmez (ölçüldü: 390pt'de "Son 7 gün" görünmez oluyordu).
                  const SizedBox(width: SandikSpace.sm),
                  _silinenCipi(silinenSayisi),
                ],
              ),
            ),
          ),

          // ── Sonuç sayacı ─────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                SandikSpace.xs, SandikSpace.screenH(context), SandikSpace.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    toplam == 0
                        ? context.l10n.noRecords
                        : '${context.l10n.nRecords(toplam)}'
                            '${shown < rows.length ? context.l10n.nShown(shown) : ''}',
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ),
                if (_hasActiveFilter)
                  SandikTappable(
                    semanticLabel: context.l10n.clearFilters,
                    onTap: () => setState(() {
                      _silinenler = false;
                      _typeFilter = null;
                      _range = _DateRange.all;
                      _customRange = null;
                      _query = '';
                      _searchCtrl.clear();
                      _resetPaging();
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: SandikSpace.smd),
                      child: Text(
                        context.l10n.clearFilters,
                        style: context.t.bodySmall?.copyWith(
                            color: context.c.amberText,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: context.c.hairline, height: 1),

          // ── Liste ────────────────────────────────────────────────────
          Expanded(
            child: toplam == 0
                ? _empty()
                : RefreshIndicator.adaptive(
                    color: context.c.amberText,
                    onRefresh: () => ref
                        .read(portfolioProvider.notifier)
                        .refreshPrices(force: true),
                    child: Builder(builder: (context) {
                      // Ay kapları (seçenek A, 2026-09-28): satırlar düz,
                      // her ay bir SandikCard. 125 kaydı tek kapta
                      // göstermek kabı anlamsızlaştırırdı; ay hem doğal
                      // kronoloji hem de "geçen ay ne yaptım" sorusunun
                      // birimi. Yıl kap başlığında olduğu için satırlar
                      // yılsız tarih yazar (`yilGoster: false`).
                      //
                      // Silinenler filtresinde kaplar SİLİNME ayına göre
                      // (liste o sırada). Satır iki tarih yazar ve alım
                      // başka bir yılda olabilir; yıl satırda kalır.
                      final gruplar = hareketleriAylaGrupla(
                        rows.take(shown).toList(),
                        tarih: _silinenler ? silinmeAni : _islemTarihi,
                      );
                      final dahaVar = shown < rows.length;
                      final hp = SandikSpace.screenH(context);
                      final ayAdi = DateFormat(
                          'LLLL yyyy', Localizations.localeOf(context).languageCode);
                      final tr = Localizations.localeOf(context).languageCode == 'tr';
                      // Filtre değişince yeni sonuç kısa bir solmayla gelir
                      // (bkz. `_filtreGecisi`); iki liste üst üste kurulmaz.
                      return FadeTransition(
                        opacity: _filtreSolma,
                        child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        controller: _scrollCtrl,
                        padding: EdgeInsets.fromLTRB(hp, 16, hp, 32),
                        // +1: son satırda "yükleniyor" göstergesi (daha var ise).
                        itemCount: gruplar.length + (dahaVar ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i >= gruplar.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  context.l10n.loadingEllipsis,
                                  style: context.t.bodySmall
                                      ?.copyWith(color: context.c.text36),
                                ),
                              ),
                            );
                          }
                          final g = gruplar[i];
                          final baslik = ayAdi.format(g.ay);
                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: i == gruplar.length - 1
                                    ? 0
                                    : SandikSpace.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: SandikSpace.xxs,
                                      right: SandikSpace.xxs,
                                      bottom: SandikSpace.sm),
                                  child: SandikSectionHeader(
                                    title: tr
                                        ? trBuyukHarf(baslik)
                                        : baslik.toUpperCase(),
                                    trailing: Text(
                                      context.l10n
                                          .nTransactions(g.kayitlar.length),
                                      style: context.t.bodySmall
                                          ?.copyWith(color: context.c.text36),
                                    ),
                                  ),
                                ),
                                SandikCard(
                                  padding: EdgeInsets.zero,
                                  radius: SandikRadius.lg,
                                  child: Column(
                                    children: [
                                      for (var k = 0;
                                          k < g.kayitlar.length;
                                          k++) ...[
                                        if (k > 0) const HareketAyraci(),
                                        _hareketSatiri(
                                          g.kayitlar[k],
                                          ledger,
                                          baz: ref.watch(bazParaProvider),
                                          portfolioState:
                                              pState ?? const PortfolioState(),
                                          hideBalance: hideBalance,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  /// "Silinenler" çipi — [Filtrele]'nin hemen yanında, dokununca listeyi
  /// DOĞRUDAN silinenlere çevirir (sayfa açılmaz). Sayı, açık filtrelerle
  /// eşleşen silinmiş kayıt sayısıdır.
  Widget _silinenCipi(int sayi) {
    final secili = _silinenler;
    final etiket = sayi > 0
        ? '${context.l10n.deletedFilter} · $sayi'
        : context.l10n.deletedFilter;
    return Semantics(
      selected: secili,
      child: SandikTappable(
        semanticLabel: etiket,
        onTap: () => setState(() {
          _silinenler = !_silinenler;
          _resetPaging();
        }),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md, vertical: SandikSpace.sm),
          decoration:
              context.chip(selected: secili, radius: SandikRadius.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 16,
                  color: secili ? context.c.amberText : context.c.text58),
              const SizedBox(width: SandikSpace.xs),
              Text(
                etiket,
                style: context.t.titleSmall?.copyWith(
                  fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                  color: secili ? context.c.amberText : context.c.text58,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    // Silinenler açık ve başka filtre yok: "eşleşme yok / aralığı genişlet"
    // yanlış yönlendirir — filtre değil, silinmiş kayıt yok.
    if (_silinenler && _sayfaFiltreSayisi == 0 && _query.trim().isEmpty) {
      return _bosDurum(Icons.delete_outline_rounded,
          context.l10n.deletedEmptyTitle, context.l10n.deletedEmptyBody);
    }
    return _emptyGenel();
  }

  Widget _bosDurum(IconData ikon, String baslik, String govde) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: 52, color: context.c.text36),
              const SizedBox(height: SandikSpace.smd),
              Text(baslik,
                  textAlign: TextAlign.center,
                  style: context.t.titleMedium?.copyWith(color: context.c.text58)),
              const SizedBox(height: SandikSpace.sm),
              Text(govde,
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36)),
            ],
          ),
        ),
      );

  Widget _emptyGenel() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 52, color: context.c.text36),
            const SizedBox(height: 12),
            Text(
              _hasActiveFilter ? context.l10n.noMatchingRecords : context.l10n.noTransactionsYet,
              style: context.t.titleMedium?.copyWith(color: context.c.text36),
            ),
            if (_hasActiveFilter) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.widenDateRangeHint,
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ],
          ],
        ),
      );

  /// Etkin sayfa filtresi sayısı (dönem + tür). Silinenler kendi çipinde
  /// göründüğü için sayılmaz.
  int get _sayfaFiltreSayisi =>
      (_range != _DateRange.all ? 1 : 0) + (_typeFilter != null ? 1 : 0);

  Widget _filtreCipi() {
    final n = _sayfaFiltreSayisi;
    final secili = n > 0;
    final renk = secili ? context.c.amberText : context.c.text58;
    return SandikTappable(
      semanticLabel: secili
          ? context.l10n.filterButtonActive(n)
          : context.l10n.filterButton,
      onTap: _filtreSayfasiniAc,
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.sm),
        decoration: context.chip(selected: secili, radius: SandikRadius.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 16, color: renk),
            const SizedBox(width: SandikSpace.xs2),
            Text(
              context.l10n.filterButton,
              style: context.t.titleSmall?.copyWith(
                fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                color: renk,
              ),
            ),
            if (secili) ...[
              const SizedBox(width: SandikSpace.xs2),
              Container(
                constraints: const BoxConstraints(
                    minWidth: SandikSpace.lgs - SandikSpace.xxs),
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
                decoration: BoxDecoration(
                  color: context.c.amberFill,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$n',
                  style: context.t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.c.onAmber,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _filtreSayfasiniAc() async {
    final secim = await showModalBottomSheet<_FiltreSecimi>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.c.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _FiltreSayfasi(
        ilk: _FiltreSecimi(_range, _customRange, _typeFilter),
        // Görünen listeyle aynı küme: silinenler açıksa silinenleri sayar.
        sayac: (x) {
          final ayr = hareketleriAyir(_suz(x));
          return (_silinenler ? ayr.silinen : ayr.aktif).length;
        },
      ),
    );
    if (secim == null || !mounted) return;
    setState(() {
      _range = secim.range;
      _customRange = secim.customRange;
      _typeFilter = secim.tur;
      _resetPaging();
    });
  }
}

/// Dönem etiketi; özel aralıkta seçilen günleri yazar ("3 Mar – 12 Nis") —
/// yoksa kullanıcı hangi aralıkta olduğunu çipten okuyamaz.
String _donemEtiketi(
    BuildContext context, _DateRange r, DateTimeRange? customRange) {
  if (r == _DateRange.custom && customRange != null) {
    final f = DateFormat('d MMM', Localizations.localeOf(context).toString());
    return '${f.format(customRange.start)} - ${f.format(customRange.end)}';
  }
  return r.labelOf(context.l10n);
}

/// Filtre sayfasının seçtiği değerler (dönem + özel aralık + tür).
class _FiltreSecimi {
  const _FiltreSecimi(this.range, this.customRange, this.tur);
  final _DateRange range;
  final DateTimeRange? customRange;
  final AssetType? tur;
}

/// Satırdaki etkin filtre: rengini taşır, dokununca kalkar.
class _EtkinCip extends StatelessWidget {
  const _EtkinCip({
    required this.etiket,
    required this.renk,
    required this.onKaldir,
  });

  final String etiket;
  final Color renk;
  final VoidCallback onKaldir;

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      semanticLabel: context.l10n.filterRemove(etiket),
      onTap: onKaldir,
      child: Container(
        padding: const EdgeInsets.fromLTRB(SandikSpace.smd, SandikSpace.sm,
            SandikSpace.sm, SandikSpace.sm),
        decoration: context.chip(
            selected: true, accent: renk, radius: SandikRadius.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiket,
              style: context.t.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: renk),
            ),
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.close_rounded, size: 16, color: renk),
          ],
        ),
      ),
    );
  }
}

/// Filtre sayfası: DÖNEM + TÜR ızgarası, altta canlı sayılı "Göster".
///
/// Seçimler bir TASLAKTIR; "N kaydı göster"e basılınca uygulanır. Düğme
/// taslağın sonucunu önceden söyler, boş sonuca gidilmez. Silinenler burada
/// DEĞİL: ekrandaki çipinden tek dokunuşla açılıp kapanır (kullanıcı kararı
/// 2026-09-29) — iki yerden yönetilen tek bir anahtar kafa karıştırırdı.
class _FiltreSayfasi extends StatefulWidget {
  const _FiltreSayfasi({required this.ilk, required this.sayac});

  final _FiltreSecimi ilk;
  final int Function(_FiltreSecimi) sayac;

  @override
  State<_FiltreSayfasi> createState() => _FiltreSayfasiState();
}

class _FiltreSayfasiState extends State<_FiltreSayfasi> {
  late _DateRange _range = widget.ilk.range;
  late DateTimeRange? _custom = widget.ilk.customRange;
  late AssetType? _tur = widget.ilk.tur;

  _FiltreSecimi get _taslak => _FiltreSecimi(_range, _custom, _tur);

  Future<void> _ozelSec() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      // Locale MaterialApp'ten gelir (tr_TR).
      initialDateRange: _custom,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = picked;
      _range = _DateRange.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final n = widget.sayac(_taslak);
    final hp = SandikSpace.screenH(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.filterButton,
                  style: context.t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90),
                ),
              ),
              SandikTappable(
                semanticLabel: l.filterReset,
                onTap: () => setState(() {
                  _range = _DateRange.all;
                  _custom = null;
                  _tur = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(SandikSpace.smd),
                  child: Text(
                    l.filterReset,
                    style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.amberText),
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SandikSectionHeader(title: l.filterPeriodHeader),
                const SizedBox(height: SandikSpace.sm),
                _Izgara(
                  sutun: 2,
                  children: [
                    for (final r in _DateRange.values)
                      _SecimKutusu(
                        etiket: r == _DateRange.custom && _custom != null
                            ? _donemEtiketi(context, r, _custom)
                            : r.labelOf(l),
                        ikon: r == _DateRange.custom
                            ? Icons.calendar_month_rounded
                            : null,
                        secili: _range == r,
                        renk: context.c.amberText,
                        onTap: r == _DateRange.custom
                            ? _ozelSec
                            : () => setState(() {
                                  _range = r;
                                  _custom = null;
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l.filterTypeHeader),
                const SizedBox(height: SandikSpace.sm),
                _Izgara(
                  sutun: 3,
                  children: [
                    _SecimKutusu(
                      etiket: l.allTypes,
                      ikon: Icons.apps_rounded,
                      secili: _tur == null,
                      renk: context.c.amberText,
                      onTap: () => setState(() => _tur = null),
                    ),
                    for (final t in AssetType.values)
                      _SecimKutusu(
                        etiket: t.labelOf(l),
                        ikon: t.icon,
                        secili: _tur == t,
                        renk: t.color,
                        onTap: () => setState(() => _tur = t),
                      ),
                  ],
                ),
                const SizedBox(height: SandikSpace.lg),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(hp, SandikSpace.smd, hp, SandikSpace.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.c.hairline)),
          ),
          child: SizedBox(
            height: SandikTouch.min + SandikSpace.sm2,
            child: FilledButton(
              onPressed: n == 0 ? null : () => Navigator.pop(context, _taslak),
              style: FilledButton.styleFrom(
                backgroundColor: context.c.amberFill,
                foregroundColor: context.c.onAmber,
                disabledBackgroundColor:
                    context.c.amberFill.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md)),
                elevation: 0,
              ),
              // Canlandırma YOK (hareket denetimi 2026-09-29): sayı her
              // filtre dokunuşunda değişir; `AnimatedSwitcher` iki sayıyı
              // aynı yerde üst üste soldurup bir an "12/13" karışık
              // okutuyordu. Anında değişen sayı daha net.
              child: Text(
                n == 0 ? l.filterNoMatch : l.filterShowN(n),
                style:
                    context.t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Eşit genişlikte sütunlar; satır yüksekliği içeriğe göre (büyük yazıda
/// sabit oranlı ızgara kırpardı).
class _Izgara extends StatelessWidget {
  const _Izgara({required this.sutun, required this.children});
  final int sutun;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const ara = SandikSpace.sm;
      final w = (c.maxWidth - ara * (sutun - 1)) / sutun;
      return Wrap(
        spacing: ara,
        runSpacing: ara,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class _SecimKutusu extends StatelessWidget {
  const _SecimKutusu({
    required this.etiket,
    required this.secili,
    required this.renk,
    required this.onTap,
    this.ikon,
  });

  final String etiket;
  final bool secili;
  final Color renk;
  final VoidCallback onTap;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final metinRengi = secili ? renk : context.c.text58;
    return Semantics(
      selected: secili,
      child: SandikTappable(
        semanticLabel: etiket,
        onTap: onTap,
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.sm, vertical: SandikSpace.sm2),
          alignment: Alignment.center,
          decoration: context.chip(
              selected: secili, accent: renk, radius: SandikRadius.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ikon != null) ...[
                Icon(ikon, size: 16, color: secili ? renk : context.c.text36),
                const SizedBox(width: SandikSpace.xs2),
              ],
              Flexible(
                child: Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.titleSmall?.copyWith(
                    fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                    color: metinRengi,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
