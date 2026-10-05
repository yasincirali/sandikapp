import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/l10n.dart';
import '../services/yasal_adim_plani.dart';
import '../services/yasal_metin_katalogu.dart';
import '../theme/sandik.dart';
import 'sandik_acilir.dart';
import 'sigan_metin.dart';

/// Belgenin ekrandaki adı — sığan yazım adayları (uzundan kısaya). Adım
/// listesi, bağlantılar ve okuyucu başlığı (`ZorunluMetin.belge`) aynı adı
/// buradan okur.
List<String> yasalBelgeAdaylari(AppLocalizations l, YasalBelge b) =>
    switch (b) {
      YasalBelge.kosullar => [l.yasalBelgeKosullar],
      YasalBelge.gizlilik => [l.yasalBelgeGizlilik],
      YasalBelge.kvkk => [l.yasalBelgeKvkk, l.yasalBelgeKvkkKisa],
      YasalBelge.acikRiza => [l.yasalBelgeAcikRiza],
    };

IconData yasalBelgeIkonu(YasalBelge b) => switch (b) {
      YasalBelge.kosullar => Icons.gavel_rounded,
      YasalBelge.gizlilik => Icons.shield_outlined,
      YasalBelge.kvkk => Icons.privacy_tip_outlined,
      YasalBelge.acikRiza => Icons.public_rounded,
    };

/// Adımın adı — başlıkta ve ekran okuyucu etiketinde aynı metin.
String yasalAdimAdi(AppLocalizations l, YasalAdim a) {
  switch (a.tur) {
    case YasalAdimTuru.yatirimUyarisi:
      return l.yasalBelgeYatirimUyarisi;
    case YasalAdimTuru.acikRiza:
      return l.yasalBelgeAcikRiza;
    case YasalAdimTuru.kutu:
      if (a.guncellenenler.isEmpty) return l.yasalAdimKutuBaslik;
      final adlar = [
        for (final b in a.guncellenenler) yasalBelgeAdaylari(l, b).first,
      ];
      final liste = adlar.length == 1
          ? adlar.single
          : l.yasalAdimListeVe(
              adlar.sublist(0, adlar.length - 1).join(', '), adlar.last);
      return l.yasalAdimGuncellendi(liste);
  }
}

/// Kayıt ekranının ve yeniden onay kapısının ORTAK adım listesi (kullanıcı
/// kararı 2026-10-05, seçenek "C · Adım adım"). İki ekran aynı bileşeni
/// çizer — iki ayrı görünüş olmasın.
///
/// ## Görünüm
/// - Kart başlığı ([baslik]): "Kayıt için N adım" / "N adım".
/// - Dikey numaralı adımlar, aralarında çizgi. Tamamlanan: yeşil onay
///   dairesi (okunanda "Okundu ve onaylandı"). Sıradaki: amber numara +
///   kısa açıklama + "Oku ve onayla" (en az [SandikTouch.min]). Bekleyen:
///   sönük numara, yalnız başlık.
/// - Kutu SON adımdır: içinde bugünkü kutu ([kutu], metni değişmedi).
///   İşaretlenince adım yeşil olur; işaret kaldırılabilir (adım yeniden
///   sıradaki olur).
/// - Bilgi amaçlı belgeler katlanır "Diğer belgeler (bilgi amaçlı) · N"
///   bölümünde bağlantıdır.
///
/// ## Neden yalnız sıradaki adımın eylemi var
/// "Yalnız bir şey yapılacak" netliği seçeneğin kendisidir: kullanıcı
/// hangi metnin zorunlu olduğunu listede aramaz, sıradaki düğmeye basar.
/// Kutu, okunacaklar bitmeden görünmez — kayıtta ve kapıda üçü de
/// zorunlu olduğundan bu, istenenleri değiştirmez, yalnız sıralar.
/// (2026-10-05 sabahki düzende kutu listeden bağımsız duruyordu ve
/// okumadan işaretlenebiliyordu; onay KAYDI aynı kaldı — `KayitOnayBaglami`,
/// `kapiOgeleri`.)
///
/// ## Okuma süresi neden yok
/// Taslakta "~2 dk" yer tutucuydu. Gösterilecek süre metnin kelime
/// sayısından hesaplanabilirdi, ama bölen (dakikada kaç kelime) yine bir
/// varsayım olurdu; büyük yazıyla ve ekran okuyucuyla okuyanda hiç tutmaz.
/// Uydurma sayı yazılmaz: adım bunun yerine metnin neyi istediğini söyler.
///
/// ## Erişilebilirlik
/// Her adımın başlığı tek bir düğümdür: "Adım 2/3, Açık Rıza Metni,
/// bekliyor" — sıra, ad ve durum birlikte, yukarıdan aşağı okunur. Daire
/// ve çizgi süstür, okunmaz. Eylem (düğme, kutu) başlıktan sonra gelir.
class YasalAdimListesi extends StatefulWidget {
  const YasalAdimListesi({
    super.key,
    required this.plan,
    required this.baslik,
    required this.onaylananlar,
    required this.kutuIsaretli,
    required this.kutu,
    required this.onOku,
    required this.onBelgeAc,
    this.acilanlar = const {},
    this.hata,
  });

  final YasalAdimPlani plan;
  final String baslik;

  /// Sonuna kadar okunup sonunda onaylanan türler (`YasalTur`).
  final Set<String> onaylananlar;
  final bool kutuIsaretli;

  /// Kutu adımının içeriği — `YasalOnayKutusu`.
  final Widget kutu;

  /// Okunacak adımın metnini zorunlu okumada açar.
  final ValueChanged<YasalAdimTuru> onOku;

  /// Bilgi amaçlı belgeyi salt okunur açar.
  final ValueChanged<YasalBelge> onBelgeAc;

  /// Bağlantıyla açılan belgeler (`YasalBelge.tur`) — "Açıldı" izi.
  final Set<String> acilanlar;

  /// Verilirse kart kırmızı çerçeve alır ve metin adımların altında
  /// yazar (kayıtta eksik adımla "Kayıt Ol"a basıldı).
  final String? hata;

  @override
  State<YasalAdimListesi> createState() => _YasalAdimListesiState();
}

class _YasalAdimListesiState extends State<YasalAdimListesi> {
  bool _digerAcik = false;

  /// Adım satırlarının anahtarları — sıradaki adıma kaydırmak için.
  final List<GlobalKey> _adimAnahtarlari = [];

  /// Bir adım tamamlanınca odak sıradakine geçer (kullanıcı geri bildirimi
  /// 2026-10-05: "dokümanlar onaylandıkça bir sonrakine odaklanmalı").
  /// Okuyucu tam ekran açılıp kapandığı için kullanıcı döndüğünde sıradaki
  /// adım ekranın altında kalabiliyordu ve kaydırması gerekiyordu. Sıradaki
  /// adım görünür alana kaydırılır ve ekran okuyucuya adın + durumun
  /// duyurulur. Yalnız sıra İLERİ gidince: işaret kaldırılınca (sıra geri
  /// gelir) kullanıcı zaten oradadır, ekran zıplamaz. Hareketi azalt
  /// açıkken kaydırma anında.
  ///
  /// Önceki sıra durumda tutulur, `eski` widget'tan hesaplanmaz: ekranlar
  /// `onaylananlar` kümesini yerinde değiştirir, eski ve yeni widget aynı
  /// kümeyi gösterir.
  int? _sonAktif;
  Timer? _odakZamanlayici;

  @override
  void initState() {
    super.initState();
    _sonAktif = _aktifSira(widget);
  }

  @override
  void dispose() {
    _odakZamanlayici?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(YasalAdimListesi eski) {
    super.didUpdateWidget(eski);
    final onceki = _sonAktif;
    final simdi = _sonAktif = _aktifSira(widget);
    if (simdi == null || (onceki != null && simdi <= onceki)) return;
    // Adımın içeriği (düğme / kutu) `AnimatedSize` ile açılıyor: kaydırma
    // o bitince hesaplanır, yoksa hedef açılmamış yüksekliğe göre kalır.
    _odakZamanlayici?.cancel();
    _odakZamanlayici = Timer(SandikMotion.surfaceOf(context), () {
      if (!mounted || simdi >= _adimAnahtarlari.length) return;
      final hedef = _adimAnahtarlari[simdi].currentContext;
      if (hedef == null) return;
      // Adımın ALTI görünür alana gelir: eylem (düğme, kutu) adımın en
      // altında. Adım zaten görünürse ekran kımıldamaz; görünür alandan
      // uzunsa başlığı yukarıda kalır, eylemin kendisi görünür.
      Scrollable.ensureVisible(
        hedef,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: SandikMotion.surfaceOf(hedef),
        curve: SandikMotion.move,
      );
      final l = hedef.l10n;
      final a = widget.plan.adimlar[simdi];
      SemanticsService.sendAnnouncement(
        View.of(hedef),
        l.yasalAdimSemantik(simdi + 1, widget.plan.adimlar.length,
            yasalAdimAdi(l, a), l.yasalAdimDurumBekliyor),
        Directionality.of(hedef),
      );
    });
  }

  /// Sıradaki (aktif) adımın indeksi; hepsi tamamsa `null`.
  static int? _aktifSira(YasalAdimListesi w) {
    final d = w.plan.durumlar(
        onaylananlar: w.onaylananlar, kutuIsaretli: w.kutuIsaretli);
    final i = d.indexOf(YasalAdimDurumu.aktif);
    return i < 0 ? null : i;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = widget.plan;
    final durumlar = plan.durumlar(
        onaylananlar: widget.onaylananlar, kutuIsaretli: widget.kutuIsaretli);
    final hata = widget.hata;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.all(SandikSpace.md),
          decoration: BoxDecoration(
            color: hata != null
                ? context.c.loss.withValues(alpha: 0.08)
                : context.c.surface1,
            borderRadius: SandikRadius.mdAll,
            border: Border.all(
              color: hata != null
                  ? context.c.loss.withValues(alpha: 0.5)
                  : context.c.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.baslik,
                  style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                  ),
                ),
              ),
              const SizedBox(height: SandikSpace.md),
              for (var i = 0; i < plan.adimlar.length; i++)
                _AdimSatiri(
                  key: _anahtar(i),
                  sira: i + 1,
                  toplam: plan.adimlar.length,
                  adim: plan.adimlar[i],
                  durum: durumlar[i],
                  son: i == plan.adimlar.length - 1,
                  icerik: _icerik(context, plan.adimlar[i], durumlar[i]),
                ),
              if (hata != null) ...[
                const SizedBox(height: SandikSpace.smd),
                Text(
                  hata,
                  style: context.t.bodySmall?.copyWith(color: context.c.loss),
                ),
              ],
            ],
          ),
        ),
        if (plan.digerBelgeler.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.sm),
          _digerBelgeler(context),
        ],
        // Belgeler yalnız Türkçe (çevirisi hukuk işi); İngilizce arayüzde
        // bunu baştan söyle.
        if (l.localeName != 'tr') ...[
          const SizedBox(height: SandikSpace.sm),
          Text(
            l.yasalBelgelerTurkce,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ],
      ],
    );
  }

  GlobalKey _anahtar(int i) {
    while (_adimAnahtarlari.length <= i) {
      _adimAnahtarlari.add(GlobalKey());
    }
    return _adimAnahtarlari[i];
  }

  /// Adımın başlığın altındaki içeriği; yoksa `null`.
  Widget? _icerik(BuildContext context, YasalAdim a, YasalAdimDurumu durum) {
    final l = context.l10n;
    final aciklamaStili = context.t.bodySmall?.copyWith(
      color: context.c.text58,
      height: 1.45,
    );
    if (a.tur.okunur) {
      if (durum != YasalAdimDurumu.aktif) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.tur == YasalAdimTuru.acikRiza
                ? l.yasalAdimRizaAciklama
                : l.yasalAdimUyariAciklama,
            style: aciklamaStili,
          ),
          const SizedBox(height: SandikSpace.sm2),
          _OkuDugmesi(onTap: () => widget.onOku(a.tur)),
        ],
      );
    }
    // Kutu: sırası gelince görünür ve tamamlandıktan sonra da durur
    // (işaret kaldırılabilir).
    if (durum == YasalAdimDurumu.bekliyor) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (a.guncellenenler.isNotEmpty) ...[
          Text(
            a.guncellenenler.contains(YasalBelge.kosullar)
                ? l.yasalAdimKosulGuncelAciklama
                : l.yasalAdimBilgiGuncelAciklama,
            style: aciklamaStili,
          ),
          for (final b in a.guncellenenler)
            _BelgeBaglantisi(
              belge: b,
              acildi: widget.acilanlar.contains(b.tur),
              onTap: () => widget.onBelgeAc(b),
            ),
        ],
        const SizedBox(height: SandikSpace.sm),
        widget.kutu,
      ],
    );
  }

  Widget _digerBelgeler(BuildContext context) {
    final l = context.l10n;
    final belgeler = widget.plan.digerBelgeler;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: SandikRadius.mdAll,
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _digerAcik,
            child: SandikBasma(
              olcek: 0.99,
              onTap: () => setState(() => _digerAcik = !_digerAcik),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: SandikTouch.min),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: SandikSpace.sm),
                        child: Text(
                          l.yasalAdimDigerBelgeler(belgeler.length),
                          style: context.t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.c.text58,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    SandikAcilirOk(
                      acik: _digerAcik,
                      child: Icon(Icons.expand_more_rounded,
                          size: 20, color: context.c.text36),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SandikAcilir(
            acik: _digerAcik,
            child: Padding(
              padding: const EdgeInsets.only(bottom: SandikSpace.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in belgeler)
                    _BelgeBaglantisi(
                      belge: b,
                      acildi: widget.acilanlar.contains(b.tur),
                      onTap: () => widget.onBelgeAc(b),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Numaralı daire + başlık + içerik; altında bir sonraki adıma çizgi.
class _AdimSatiri extends StatelessWidget {
  const _AdimSatiri({
    super.key,
    required this.sira,
    required this.toplam,
    required this.adim,
    required this.durum,
    required this.son,
    required this.icerik,
  });

  final int sira;
  final int toplam;
  final YasalAdim adim;
  final YasalAdimDurumu durum;
  final bool son;
  final Widget? icerik;

  static const double daire = 28;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ad = yasalAdimAdi(l, adim);
    final durumMetni = switch (durum) {
      YasalAdimDurumu.tamam => l.yasalAdimDurumTamam,
      YasalAdimDurumu.aktif => l.yasalAdimDurumBekliyor,
      YasalAdimDurumu.bekliyor => l.yasalAdimDurumSonra,
    };
    final tamam = durum == YasalAdimDurumu.tamam;
    final icerik = this.icerik;

    return Stack(
      children: [
        // Çizgi: tamamlanan adımdan sıradakine amber, ötesi saç teli.
        if (!son)
          Positioned(
            left: daire / 2 - 1,
            width: 2,
            top: daire + SandikSpace.xs,
            bottom: SandikSpace.xs,
            child: AnimatedContainer(
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              decoration: BoxDecoration(
                color: tamam ? context.c.amberFill : context.c.hairline,
                borderRadius: SandikRadius.smAll,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: _Daire(sira: sira, durum: durum)),
            const SizedBox(width: SandikSpace.md2),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: son ? 0 : SandikSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      container: true,
                      label: l.yasalAdimSemantik(sira, toplam, ad, durumMetni),
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: SandikSpace.xxs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ad,
                              style: context.t.bodyLarge?.copyWith(
                                fontWeight: durum == YasalAdimDurumu.aktif
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: durum == YasalAdimDurumu.bekliyor
                                    ? context.c.text36
                                    : context.c.text90,
                              ),
                            ),
                            if (tamam && adim.tur.okunur) ...[
                              const SizedBox(height: SandikSpace.xxs),
                              Text(
                                l.yasalAdimOkunduOnaylandi,
                                style: context.t.bodySmall
                                    ?.copyWith(color: context.c.gain),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _IcerikGecisi(
                      child: icerik == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding:
                                  const EdgeInsets.only(top: SandikSpace.xs2),
                              child: icerik,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Adım içeriğinin yükseklik geçişi; hareketi azalt açıkken HİÇ
/// `AnimatedSize` kurmaz. Sıfır süreli `AnimatedSize` boyut değişiminde
/// "RenderAnimatedSize was mutated in its own performLayout" assert'iyle
/// düşer (animasyonları kapalı CI emülatöründe duman testi, #96; aynı ders
/// `portfolio_summary_widget` `_BoyGecisi`). Süre sıfırsa geçiş zaten yok.
class _IcerikGecisi extends StatelessWidget {
  const _IcerikGecisi({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (SandikMotion.surfaceOf(context) == Duration.zero) return child;
    return AnimatedSize(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
}

/// Adım dairesi: tamam → yeşil onay; sıradaki → amber numara; bekleyen →
/// sönük numara. Durum geçişi kısa bir çapraz geçiş — kullanıcı okuyucudan
/// dönünce dairenin yeşile döndüğünü görür; zıplama yok (yasal akış, oyun
/// değil). Hareketi azalt açıkken anında.
class _Daire extends StatelessWidget {
  const _Daire({required this.sira, required this.durum});

  final int sira;
  final YasalAdimDurumu durum;

  @override
  Widget build(BuildContext context) {
    final tamam = durum == YasalAdimDurumu.tamam;
    final aktif = durum == YasalAdimDurumu.aktif;
    return AnimatedContainer(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.enter,
      width: _AdimSatiri.daire,
      height: _AdimSatiri.daire,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tamam
            ? context.c.gain
            : (aktif ? context.c.amberFill : context.c.surface1),
        border: Border.all(
          color: tamam
              ? context.c.gain
              : (aktif ? context.c.amberFill : context.c.text20),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: SandikMotion.stateOf(context),
        switchInCurve: SandikMotion.enter,
        switchOutCurve: SandikMotion.exit,
        child: tamam
            // `done_rounded`: kutunun içindeki `check_rounded` ile
            // karışmasın (testler kutunun işaretini ikonundan okur).
            ? Icon(Icons.done_rounded,
                key: const ValueKey('tamam'),
                size: 16,
                color: context.c.onStatus)
            : Padding(
                key: ValueKey(durum),
                padding: const EdgeInsets.all(SandikSpace.xxs),
                // Büyük yazıda numara daireyi taşırmasın: daire süstür,
                // sıra bilgisi ekran okuyucuya etikette gider.
                child: FittedBox(
                  child: Text(
                    '$sira',
                    style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: aktif ? context.c.onAmber : context.c.text36,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Sıradaki okuma adımının düğmesi — amber, en az [SandikTouch.min].
class _OkuDugmesi extends StatelessWidget {
  const _OkuDugmesi({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        child: SandikBasma(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.c.amberFill,
              borderRadius: SandikRadius.mdAll,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.md, vertical: SandikSpace.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          context.l10n.yasalAdimOkuOnayla,
                          style: context.t.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.onAmber,
                          ),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.xs2),
                      ExcludeSemantics(
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: context.c.onAmber),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilgi amaçlı belge bağlantısı — salt okunur açılır; açıldıysa hafif
/// "Açıldı" izi (onay değil: `belge_acildi` kanıt notu).
class _BelgeBaglantisi extends StatelessWidget {
  const _BelgeBaglantisi({
    required this.belge,
    required this.acildi,
    required this.onTap,
  });

  final YasalBelge belge;
  final bool acildi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      button: true,
      child: SandikBasma(
        olcek: 0.98,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Icon(yasalBelgeIkonu(belge),
                  size: 18, color: context.c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: SiganMetin(
                    yasalBelgeAdaylari(l, belge),
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.amberText,
                    ),
                  ),
                ),
              ),
              if (acildi) ...[
                const SizedBox(width: SandikSpace.sm),
                Text(
                  l.yasalBelgeAcildi,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ],
              const SizedBox(width: SandikSpace.xs),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: context.c.text36),
            ],
          ),
        ),
      ),
    );
  }
}
