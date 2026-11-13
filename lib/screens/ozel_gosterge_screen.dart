import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/ozel_gosterge.dart';
import '../providers/ozel_gosterge_provider.dart';
import '../services/gosterge_betigi/betik.dart';
import '../services/gosterge_betigi/katalog.dart';
import '../services/ozel_gosterge_calistirici.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/gosterge_cizimi.dart';
import '../widgets/sandik_acilir.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_error_view.dart';
import 'paywall_screen.dart' show PaywallScreen;

/// Kendi göstergeni yaz — liste (alt sayfa) ve düzenleyici (tam ekran).
///
/// ## Akış
/// Grafikteki `ƒx` çipi → [showOzelGostergeSayfasi]: göstergelerin, grafikte
/// aç/kapa anahtarı, "Yeni gösterge" ve şablonlar. Satıra ya da şablona
/// dokununca [OzelGostergeEditorScreen]. Kısa, bağlamdan kopmayan iş sheet'te;
/// kod yazmak odak istediği için tam ekran (TASARIM_DILI §7 madde 7).
///
/// ## Önizleme
/// Düzenleyici, açıldığı grafiğin O ANKİ çubuklarını ([BetikVerisi]) alır ve
/// betiği her değişiklikte onların üstünde çalıştırır: kullanıcı kaydetmeden
/// sonucu görür; hata satır numarasıyla yazılır.
///
/// ## Tadımlık (ücretsiz kullanıcı, 2026-11-13)
/// [kilitli] iken sayfa yine açılır: şablonlar, kod yazma/yapıştırma ve
/// varlığın çubuklarında önizleme serbest; KAYDETMEK kilitli ve paywall'u
/// açar (`grafik_ozel_gosterge` → `PaywallKarti.ozelGosterge`). Kayıtlı
/// liste okunmaz (sağlayıcı izlenmez), hiçbir şey yerelde ya da sunucuda
/// saklanmaz; grafik göstergeyi zaten yalnız kilit açıkken çizer. Sunucu
/// yazma kapısı 0141 aynen durur (istemci kilidi tek savunma değil).

/// Göstergeler sayfası. [onizleme] grafiğin çubukları (düzenleyiciye geçer).
Future<void> showOzelGostergeSayfasi(
  BuildContext context, {
  BetikVerisi? onizleme,
  String? varlikAdi,
  bool kilitli = false,
}) =>
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => OzelGostergeListesi(
          onizleme: onizleme, varlikAdi: varlikAdi, kilitli: kilitli),
    );

class OzelGostergeListesi extends ConsumerWidget {
  const OzelGostergeListesi(
      {super.key, this.onizleme, this.varlikAdi, this.kilitli = false});

  final BetikVerisi? onizleme;
  final String? varlikAdi;

  /// Ücretsiz kullanıcı: kayıtlı liste yok, düzenleyicide kaydet kilitli.
  final bool kilitli;

  void _ac(BuildContext context, {OzelGosterge? g, BetikSablonu? sablon}) {
    pushGuarded(
      context,
      adaptiveRoute<void>(
        settings: const RouteSettings(name: 'ozel_gosterge_editor'),
        fullscreenDialog: true,
        builder: (_) => OzelGostergeEditorScreen(
          gosterge: g,
          sablon: sablon,
          onizleme: onizleme,
          varlikAdi: varlikAdi,
          kilitli: kilitli,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    // Kilitliyken sağlayıcı izlenmez: kayıtlı göstergeler okunmaz, liste
    // bölümü hiç çizilmez (tadımlık yalnız şablon + önizleme).
    final durum = kilitli
        ? const AsyncValue<List<OzelGosterge>>.data([])
        : ref.watch(ozelGostergelerProvider);
    final ingilizce = context.l10n.localeName.startsWith('en');
    final liste = durum.valueOrNull ?? const <OzelGosterge>[];
    final doldu = liste.length >= OzelGosterge.azamiSayi;
    // Açık ama bu grafikte çizilemeyenler, nedeniyle. Grafiğin az önce
    // aynı veriyle yaptığı çalıştırmanın önbelleğinden okunur (betik yeniden
    // koşmaz); çip de aynı rapordan sayar, ikisi ayrışmaz.
    final veri = onizleme;
    final atlanan = veri == null || kilitli
        ? const <String, OzelAtlamaNedeni>{}
        : ozelGostergeleriCalistirRapor(grafiktekiGostergeler(liste), veri)
            .atlanan;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
              SandikSpace.md, SandikSpace.screenH(context), SandikSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.ozgBaslik,
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
              const SizedBox(height: SandikSpace.xs),
              Text(l.ozgAciklama,
                  style: context.t.bodySmall
                      ?.copyWith(color: context.c.text58, height: 1.4)),
              const SizedBox(height: SandikSpace.md),
              if (durum.hasError)
                SandikErrorView(
                  error: durum.error!,
                  onRetry: () => ref.invalidate(ozelGostergelerProvider),
                )
              else if (durum.isLoading && liste.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(SandikSpace.lg),
                  child: Center(child: CustomLoadingIndicator()),
                )
              else if (kilitli)
                const SizedBox.shrink()
              else if (liste.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
                  child: Text(l.ozgBos,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text58)),
                )
              else
                for (final g in liste)
                  _GostergeSatiri(
                    gosterge: g,
                    atlama: g.grafikte ? atlanan[g.id] : null,
                    onTap: () => _ac(context, g: g),
                  ),
              const SizedBox(height: SandikSpace.md),
              FilledButton.icon(
                onPressed: doldu ? null : () => _ac(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.ozgYeni),
              ),
              if (doldu) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(l.ozgSinir(OzelGosterge.azamiSayi),
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text58)),
              ],
              const SizedBox(height: SandikSpace.lg),
              Text(l.ozgSablondan,
                  style: context.t.labelSmall?.copyWith(
                      color: context.c.text58, fontWeight: FontWeight.w700)),
              const SizedBox(height: SandikSpace.sm),
              Wrap(
                spacing: SandikSpace.sm,
                runSpacing: SandikSpace.sm,
                children: [
                  for (final s in kBetikSablonlari)
                    ActionChip(
                      label: Text(ingilizce ? s.adEn : s.adTr),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onPressed: doldu ? null : () => _ac(context, sablon: s),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GostergeSatiri extends ConsumerWidget {
  const _GostergeSatiri(
      {required this.gosterge, required this.onTap, this.atlama});

  final OzelGosterge gosterge;
  final VoidCallback onTap;

  /// Açık ama bu grafikte çizilemediyse nedeni; satırın altında tek nötr
  /// satır (kırmızı değil: kod hatalı değil, veri ya da aralık uymuyor).
  final OzelAtlamaNedeni? atlama;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    DerlenmisBetik? derli;
    try {
      derli = GostergeBetigi.derle(gosterge.kod);
    } on BetikHatasi {
      derli = null;
    }
    final altYazi = derli == null
        ? l.ozgHatali
        : derli.fiyatUstunde
            ? l.ozgFiyatUstunde
            : l.ozgAyriPanel;
    final atlamaMetni = switch (atlama) {
      null => null,
      OzelAtlamaNedeni.hacimYok => l.ozgCizilemediHacim,
      OzelAtlamaNedeni.ohlcYok => l.ozgCizilemediOhlc,
      OzelAtlamaNedeni.agir => l.ozgCizilemediAgir,
      OzelAtlamaNedeni.genel => l.ozgCizilemedi,
    };
    final satir = SandikTappable(
      onTap: onTap,
      semanticLabel: atlamaMetni == null
          ? '${gosterge.ad}, $altYazi'
          : '${gosterge.ad}, $altYazi, $atlamaMetni',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min + 12),
        child: Row(
          children: [
            Icon(Icons.functions_rounded,
                size: 20,
                color: derli == null ? context.c.danger : context.c.text58),
            const SizedBox(width: SandikSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(gosterge.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyLarge?.copyWith(
                          color: context.c.text90,
                          fontWeight: FontWeight.w600)),
                  Text(altYazi,
                      style: context.t.bodySmall?.copyWith(
                          color: derli == null
                              ? context.c.danger
                              : context.c.text58)),
                ],
              ),
            ),
            Semantics(
              label: l.ozgGrafikteGoster(gosterge.ad),
              child: Switch.adaptive(
                value: gosterge.grafikte && derli != null,
                activeTrackColor: context.c.amberText,
                onChanged: derli == null
                    ? null
                    : (v) async {
                        SandikHaptic.selection.perform();
                        try {
                          await ref
                              .read(ozelGostergelerProvider.notifier)
                              .grafikteAyarla(gosterge.id, v);
                        } catch (e) {
                          if (context.mounted) sandikSnackError(context, e);
                        }
                      },
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.c.text36),
          ],
        ),
      ),
    );
    if (atlamaMetni == null) return satir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        satir,
        // Satırın metin sütunuyla hizalı (ikon 20 + boşluk md); bilgi ikonu
        // + cümle: durum yalnız renkle verilmez. Ekran okuyucu bunu satırın
        // etiketinde zaten duyar.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(
                left: 20 + SandikSpace.md, bottom: SandikSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: context.c.text58),
                const SizedBox(width: SandikSpace.xs),
                Expanded(
                  child: Text(atlamaMetni,
                      key: ValueKey('ozgAtlama-${gosterge.id}'),
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Düzenleyici. [gosterge] null ise yeni; [sablon] verilirse kod oradan.
class OzelGostergeEditorScreen extends ConsumerStatefulWidget {
  const OzelGostergeEditorScreen({
    super.key,
    this.gosterge,
    this.sablon,
    this.onizleme,
    this.varlikAdi,
    this.kilitli = false,
  });

  final OzelGosterge? gosterge;
  final BetikSablonu? sablon;
  final BetikVerisi? onizleme;
  final String? varlikAdi;

  /// Ücretsiz kullanıcı (tadımlık): yazma ve önizleme serbest, kaydet
  /// paywall'u açar; sağlayıcıya hiç yazılmaz.
  final bool kilitli;

  /// Boş başlangıç: en basit çalışan betik, ne yazılacağını gösterir.
  static const baslangicKodu = '// close = kapanış. Ör: 20 çubukluk ortalama\n'
      'plot(sma(close, 20), "SMA 20", color.blue)\n';

  @override
  ConsumerState<OzelGostergeEditorScreen> createState() =>
      _OzelGostergeEditorScreenState();
}

class _OzelGostergeEditorScreenState
    extends ConsumerState<OzelGostergeEditorScreen> {
  /// Kaydet düğmesinin ✓ anı (Ar-Ge 11 Kas 19:04 #3/#6).
  final _basari = SandikBasariSinyali();
  late final TextEditingController _ad;
  late final TextEditingController _kod;
  late final String _ilkAd;
  late final String _ilkKod;
  Timer? _bekleme;
  BetikSonucu? _sonuc;
  BetikHatasi? _hata;
  DerlenmisBetik? _derli;
  bool _fonksiyonlarAcik = false;
  bool _adHatasi = false;

  @override
  void initState() {
    super.initState();
    final g = widget.gosterge;
    final s = widget.sablon;
    _ilkAd = g?.ad ?? '';
    _ilkKod = g?.kod ?? s?.kod ?? OzelGostergeEditorScreen.baslangicKodu;
    _ad = TextEditingController(text: _ilkAd);
    _kod = TextEditingController(text: _ilkKod)..addListener(_degisti);
    _dene();
    // Şablonun adı form açılınca dolar (dil bağlamı initState'te yok).
    if (g == null && s != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _ad.text.isNotEmpty) return;
        final en = context.l10n.localeName.startsWith('en');
        setState(() => _ad.text = en ? s.adEn : s.adTr);
      });
    }
  }

  @override
  void dispose() {
    _bekleme?.cancel();
    _ad.dispose();
    _kod.dispose();
    super.dispose();
  }

  bool get _kirli => _ad.text != _ilkAd || _kod.text != _ilkKod;

  void _degisti() {
    // Her tuşta değil, yazma durunca: ağır bir betik klavyeyi takmasın.
    // Süre hareket değil, bekleme; ölçekteki en yakın değer.
    _bekleme?.cancel();
    _bekleme = Timer(SandikMotion.surface, () {
      if (mounted) setState(_dene);
    });
  }

  void _dene() {
    try {
      final d = GostergeBetigi.derle(_kod.text);
      _derli = d;
      _hata = null;
      final v = widget.onizleme;
      _sonuc = v == null || v.uzunluk == 0 ? null : d.calistir(v);
    } on BetikHatasi catch (e) {
      _derli = null;
      _hata = e;
      _sonuc = null;
    }
  }

  Future<void> _kaydet() async {
    if (widget.kilitli) {
      // Kaydetmek ücretli (yasin 2026-10-10); ad/kod denetiminden ÖNCE:
      // ücretsiz kullanıcıya "ad yaz" deyip sonra paywall açmak boşa iş.
      await PaywallScreen.show(context, source: 'grafik_ozel_gosterge');
      return;
    }
    if (!OzelGosterge.adGecerli(_ad.text)) {
      setState(() => _adHatasi = true);
      return;
    }
    setState(_dene);
    if (_hata != null) return;
    final n = ref.read(ozelGostergelerProvider.notifier);
    try {
      final g = widget.gosterge;
      if (g == null) {
        await n.ekle(ad: _ad.text, kod: _kod.text);
      } else {
        await n.kaydet(g.kopya(ad: _ad.text.trim(), kod: _kod.text));
      }
      if (!mounted) return;
      // "Gösterge kaydedildi" snack'ı kalktı (Ar-Ge 11 Kas 19:04 #6): editör
      // kapanınca gösterge alttaki listede görünür. Onay düğmede ✓.
      await _basari.goster();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _sil() async {
    final g = widget.gosterge;
    if (g == null) return;
    final l = context.l10n;
    try {
      // Silme hatası diyalogda kalır (`showSandikConfirm(islem:)`); buraya
      // düşen yalnız diyalog dışı beklenmedik hata.
      final tamam = await showSandikConfirm(
        context: context,
        title: l.ozgSilBaslik,
        message: l.ozgSilMesaj(g.ad),
        confirmLabel: l.delete,
        destructive: true,
        islem: () => ref.read(ozelGostergelerProvider.notifier).sil(g.id),
      );
      if (tamam && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _cikisSor() async {
    final l = context.l10n;
    final cik = await showSandikConfirm(
      context: context,
      title: l.ozgVazgecBaslik,
      message: l.ozgVazgecMesaj,
      confirmLabel: l.ozgVazgecOnay,
      cancelLabel: l.ozgVazgecIptal,
      destructive: true,
    );
    if (cik && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final en = context.l10n.localeName.startsWith('en');
    final hata = _hata;
    final sonuc = _sonuc;
    final derli = _derli;
    final kenar = SandikSpace.screenH(context);
    // Kaydedilmemiş kod gerçek bir kayıp: geri jesti sorar (HIG madde 6
    // istisnası, yalnız değişiklik varken).
    return PopScope(
      canPop: !_kirli,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cikisSor();
      },
      child: Scaffold(
        backgroundColor: context.c.background,
        appBar: SandikAppBar(
          title: widget.gosterge == null ? l.ozgEditorYeni : l.ozgEditorDuzenle,
          actions: [
            if (widget.gosterge != null)
              IconButton(
                tooltip: l.ozgSil,
                icon:
                    Icon(Icons.delete_outline_rounded, color: context.c.text58),
                onPressed: _sil,
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    kenar, SandikSpace.sm, kenar, SandikSpace.lg),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  TextField(
                    controller: _ad,
                    maxLength: OzelGosterge.adAzami,
                    textCapitalization: TextCapitalization.sentences,
                    // Ad önizleme lejantında da yazılı: her harfte tazelenir.
                    onChanged: (_) => setState(() => _adHatasi = false),
                    decoration: context.inputDecoration(
                      l.ozgAdIpucu,
                      labelText: l.ozgAdEtiket,
                      errorText: _adHatasi ? l.ozgAdGerekli : null,
                    ),
                  ),
                  const SizedBox(height: SandikSpace.sm),
                  TextField(
                    controller: _kod,
                    minLines: 8,
                    maxLines: 18,
                    maxLength: kBetikAzamiKarakter,
                    keyboardType: TextInputType.multiline,
                    // Kod yazılıyor: iOS'un akıllı tırnak/tirelerini ve
                    // otomatik düzeltmeyi kapat ("“" betikte geçersiz).
                    autocorrect: false,
                    enableSuggestions: false,
                    smartQuotesType: SmartQuotesType.disabled,
                    smartDashesType: SmartDashesType.disabled,
                    textCapitalization: TextCapitalization.none,
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.text90,
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Menlo', 'Courier'],
                      height: 1.45,
                    ),
                    decoration: context.inputDecoration(
                      '',
                      labelText: l.ozgKodEtiket,
                    ),
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  _Durum(
                    hata: hata,
                    derli: derli,
                    ingilizce: en,
                  ),
                  if (sonuc != null && sonuc.eksikVeri.isNotEmpty) ...[
                    const SizedBox(height: SandikSpace.xs),
                    Text(l.ozgEksikVeri,
                        style: context.t.bodySmall
                            ?.copyWith(color: context.c.text58)),
                  ],
                  // Kodun çalışıp ekranda karşılığı olmayan kısımları
                  // (Pine'dan gelen label/bgcolor/strateji) sessizce
                  // yutulmaz. İki ve fazlası tek katlı satırda toplanır
                  // (2026-11-13): yığılan notlar önizlemeyi aşağı itiyordu.
                  if (sonuc != null && sonuc.notlar.isNotEmpty)
                    SandikKatliNotlar(
                      ozet: l.ozgNotOzet(sonuc.notlar.length),
                      notlar: [
                        for (final not in sonuc.notlar)
                          switch (not) {
                            BetikNotu.cizimNesnesi => l.ozgNotCizimNesnesi,
                            BetikNotu.boyama => l.ozgNotBoyama,
                            BetikNotu.strateji => l.ozgNotStrateji,
                            BetikNotu.fazlaCizgi =>
                              l.ozgNotFazlaCizgi(kBetikAzamiCizgi),
                            BetikNotu.paneldeIsaret => l.ozgNotPaneldeIsaret,
                          },
                      ],
                    ),
                  const SizedBox(height: SandikSpace.md),
                  _OnizlemeKarti(
                    sonuc: sonuc,
                    veri: widget.onizleme,
                    varlikAdi: widget.varlikAdi,
                    ad: _ad.text.trim().isEmpty
                        ? l.ozgEditorYeni
                        : _ad.text.trim(),
                  ),
                  const SizedBox(height: SandikSpace.md),
                  SandikTappable(
                    onTap: () =>
                        setState(() => _fonksiyonlarAcik = !_fonksiyonlarAcik),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: SandikTouch.min),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.ozgFonksiyonlar,
                                style: context.t.titleSmall?.copyWith(
                                    color: context.c.text90,
                                    fontWeight: FontWeight.w700)),
                          ),
                          SandikAcilirOk(
                            acik: _fonksiyonlarAcik,
                            child: Icon(Icons.expand_more_rounded,
                                color: context.c.text36),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SandikAcilir(
                    acik: _fonksiyonlarAcik,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final f in kBetikFonksiyonlari)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: SandikSpace.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.imza,
                                    style: context.t.bodySmall?.copyWith(
                                      color: context.c.text90,
                                      fontFamily: 'monospace',
                                      fontFamilyFallback: const [
                                        'Menlo',
                                        'Courier'
                                      ],
                                    )),
                                Text(en ? f.en : f.tr,
                                    style: context.t.bodySmall
                                        ?.copyWith(color: context.c.text58)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SandikSpace.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 16, color: context.c.text58),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(l.ozgGuvenlik,
                            style: context.t.bodySmall?.copyWith(
                                color: context.c.text58, height: 1.4)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Eylem klavyenin üstünde kalır (gövde klavyeyle kısalır).
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    kenar, SandikSpace.sm, kenar, SandikSpace.sm),
                child: SandikAsyncButton(
                  basari: _basari,
                  onPressed: hata == null ? _kaydet : null,
                  // Kilit ikonu + metin: neyin ücretli olduğu düğmede
                  // söylenir, basınca sürpriz paywall değil.
                  child: widget.kilitli
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 18),
                            const SizedBox(width: SandikSpace.sm),
                            Flexible(child: Text(l.ozgKaydetKilitli)),
                          ],
                        )
                      : Text(l.save),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Derleme durumu: geçerli (✓ + özet) ya da hata (satır + neden). İkon ve
/// metin birlikte — durum yalnız renkle anlatılmaz.
class _Durum extends StatelessWidget {
  const _Durum({
    required this.hata,
    required this.derli,
    required this.ingilizce,
  });

  final BetikHatasi? hata;
  final DerlenmisBetik? derli;
  final bool ingilizce;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final h = hata;
    final d = derli;
    final (ikon, renk, metin) = h != null
        ? (
            Icons.error_outline_rounded,
            context.c.danger,
            h.satir > 0
                ? l.ozgHataSatir(h.satir, h.metin(ingilizce))
                : h.metin(ingilizce),
          )
        : (
            Icons.check_circle_outline_rounded,
            context.c.text58,
            l.ozgGecerli(d?.cizgiSayisi ?? 0,
                d?.fiyatUstunde ?? true ? l.ozgFiyatUstunde : l.ozgAyriPanel),
          );
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: renk),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(metin,
                style: context.t.bodySmall?.copyWith(color: renk, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _OnizlemeKarti extends StatelessWidget {
  const _OnizlemeKarti({
    required this.sonuc,
    required this.veri,
    required this.varlikAdi,
    required this.ad,
  });

  final BetikSonucu? sonuc;
  final BetikVerisi? veri;
  final String? varlikAdi;
  final String ad;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = sonuc;
    final v = veri;
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v == null || v.uzunluk == 0
                ? l.ozgOnizlemeYok
                : l.ozgOnizleme(varlikAdi ?? '', s?.x.length ?? v.uzunluk),
            style: context.t.labelSmall?.copyWith(color: context.c.text58),
          ),
          if (s != null && v != null) ...[
            const SizedBox(height: SandikSpace.sm),
            BetikLejandi(baslik: ad, sonuc: s),
            const SizedBox(height: SandikSpace.sm),
            BetikOnizleme(sonuc: s, veri: v),
          ],
        ],
      ),
    );
  }
}
