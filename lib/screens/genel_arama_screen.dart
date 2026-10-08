import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Material, Colors;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/arama_eylemleri.dart';
import '../models/arama_gruplari.dart';
import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/price_service.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../l10n/l10n.dart';
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
/// (`SymbolSearchService`, `aramaGecikmesi`) ve AYNI satırla
/// (`AramaSatirKutusu`) yapılır ki iki arama yüzeyi ayrışmasın.
///
/// ## Gruplar
/// - **Varlıklarım:** bugün açık pozisyonlar (`aramaPozisyonlari`) →
///   Portföy satırıyla aynı varlık ekranı.
/// - **Piyasa:** sembol araması → varlık sayfası (`showVarlikSayfasi`,
///   takibe alma ekranındaki satırla aynı).
/// - **Eylemler:** `arama_eylemleri.dart` anahtar sözcükleri; boş sorguda
///   öneri olarak hepsi.
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

class _GenelAramaScreenState extends ConsumerState<GenelAramaScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<VarlikKimligi> _piyasa = const [];
  bool _loading = false;
  Map<String, YahooQuote> _kotasyon = const {};

  /// Yalnızca EN SON aramanın sonucu uygulanır (takibe alma ekranıyla aynı
  /// gerekçe: istekler sırasız dönebilir).
  int _seq = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _sorguDegisti(String v) {
    setState(() => _q = v);
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
    _debounce = Timer(aramaGecikmesi, () => _ara(v));
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
    final hicYok = !bos &&
        !_loading &&
        varliklar.isEmpty &&
        _piyasa.isEmpty &&
        eylemler.isEmpty;
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
                _aramaAlani(context),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                        hp, SandikSpace.sm, hp, SandikSpace.lgs),
                    children: [
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
                placeholder: context.l10n.s7AramaIpucu,
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
    final kod = pozisyonKodu(a.ticker);
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikTappable(
        semanticLabel: a.name,
        onTap: () => pushGuarded(
          context,
          adaptiveRoute<void>(
            builder: (_) => AssetDetailScreen(
              asset: p.asDisplayAsset(),
              showBackButton: true,
              lots: p.lots,
            ),
          ),
        ),
        child: _SatirKabugu(
          nokta: a.type.color,
          baslik: a.name,
          alt: [
            if (kod.isNotEmpty && kod != a.name) kod,
            a.type.labelOf(context.l10n),
          ].join(' · '),
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
    void it(Widget Function(BuildContext) b) =>
        pushGuarded(context, adaptiveRoute<void>(builder: b));
    switch (e) {
      case AramaEylemi.fiyatAlarmlari:
        it((_) => const PriceAlertsScreen());
      case AramaEylemi.sinyalAyarlari:
        it((_) => const SignalSettingsScreen());
      case AramaEylemi.ekstreAktar:
        unawaited(_ekstredenAktar());
      case AramaEylemi.topluEkle:
        it((_) => const BulkAddAssetScreen());
      case AramaEylemi.karsilastir:
        it((_) => const ComparisonScreen());
      case AramaEylemi.takipListesi:
        pushGuarded(
          context,
          adaptiveRoute<void>(
            builder: (_) => const AddWatchlistScreen(),
            fullscreenDialog: true,
          ),
        );
      case AramaEylemi.ayarlar:
        it((_) => const SettingsScreen());
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
      adaptiveRoute<bool>(builder: (_) => const CsvImportScreen()),
    );
    if (aktarildi != true || !mounted) return;
    await pushGuarded<bool>(
      context,
      adaptiveRoute<bool>(builder: (_) => const BulkAddAssetScreen()),
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
    this.nokta,
    this.ikon,
  });

  final String baslik;
  final String? alt;
  final Color? nokta;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: SandikCard(
          padding: const EdgeInsets.only(left: SandikSpace.smd),
          child: Row(
            children: [
              if (nokta != null)
                Container(
                  width: SandikSpace.sm,
                  height: SandikSpace.sm,
                  decoration:
                      BoxDecoration(color: nokta, shape: BoxShape.circle),
                )
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
