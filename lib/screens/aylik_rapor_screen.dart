import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../providers/aylik_rapor_provider.dart';
import '../services/aylik_rapor_disa_aktarim.dart';
import '../services/crash_reporter.dart';
import '../services/aylik_rapor_ozeti.dart';
import '../models/asset_type.dart';
import '../services/aylik_rapor_kalemleri.dart';
import '../utils/pozisyon_etiketi.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../utils/friendly_error.dart';
import '../widgets/sandik_paylas_dugmesi.dart';
import '../providers/analiz_provider.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/varlik_analizi.dart';
import '../widgets/hikaye_akisi.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_cizimi.dart';
import '../widgets/sandik_error_view.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/aylik_rapor_bolumleri.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import 'analiz_notu_screen.dart';
import 'hafta_ozeti_screen.dart' show HaftaRozetCipi;

/// Aylık rapor (S18-B, 2026-10-05) — tek özet cümlesi + varlık kartları.
///
/// Rapor, tuttuğun her varlığın o ayki yapay zekâ notunun bir araya
/// gelmesidir; ayrı bir "portföy yorumu" üretilmez (portföyün aylık
/// getirisi Performans'ta, tek kaynak orası). Özet cümlesi yalnız sayar:
/// kaç varlığın notu var, kaçında belirgin hareket (rozet ≠ sakin) olmuş;
/// notu çıkmayan varlıklar sonda adlarıyla anılır.
/// Sıra haftanın özetiyle aynı (rozet önemi), kullanıcı iki ekranı aynı
/// mantıkla okur.
///
/// ## Kapsam genişledi (yasin 2026-11-07)
/// *"aylık raporda neden sadece fonların raporları var tüm varlıkların …
/// para giriş çıkışları … önemli haber detayları vs de olmalı"*. Not yalnız
/// radar varlıklarına (fon, BIST hissesi, coin) yazılıyor ve kapıdan
/// geçemeyen not yayımlanmıyor; rapor yalnız notlardan kurulunca altın,
/// döviz, mevduat hiç, notu çıkmayan hisse de yalnız "not çıkmadı"
/// satırında görünüyordu. Artık notların ÜSTÜNDE üç sayısal bölüm var
/// (ayın varlıkları, para girişi ve çıkışı, önemli gelişmeler;
/// `AylikRaporOzeti`) ve en üstte kapsadığı günler. Haber metni yok:
/// lisanslı kaynak yok, rapor bunu sonunda söyler. "Portföy getirisi
/// Performans'ta" kararı sürer: yüzde kutusu yalnız PDF'te (müşavir), ekran
/// varlık bazında ay başı → ay sonu değişimi gösterir.
class AylikRaporScreen extends ConsumerWidget {
  const AylikRaporScreen({super.key, required this.donem});

  /// Ayın 1'i.
  final DateTime donem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ay = DateFormat('MMMM y', Localizations.localeOf(context).toString())
        .format(donem);
    // Aylık rapor Premium (yasin, 2026-10-10). Haftanın özeti ücretsiz
    // kalır (alışkanlık döngüsü); ay sonu derlemesi ücret ödeyenin. Raporun
    // girişleri (haftanın özeti satırı, Raporlar kapısı) görünür kalır ve
    // buraya düşer: kilit ekranda, satış anı korunur. Paywall kapalıyken
    // birebir eski.
    if (ref.watch(premiumKilitliProvider)) {
      return Scaffold(
        appBar: SandikAppBar(title: l10n.anzAylikBaslik(ay)),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.summarize_rounded,
            baslik: l10n.prmAylikKilitBaslik,
            govde: l10n.prmAylikKilitGovde,
            kilitMetni: l10n.prmAylikKilitSatir,
            kaynak: 'aylik_rapor',
          ),
        ),
      );
    }
    final anahtarlar = ref.watch(tutulanNotAnahtarlariProvider);
    final notlar =
        ref.watch(notOzetleriProvider(notKumesi(anahtarlar, 'aylik')));
    final ozetHal = ref.watch(aylikRaporOzetiProvider(donem));
    final dil = context.tarihDili;

    return Scaffold(
      appBar: SandikAppBar(title: l10n.anzAylikBaslik(ay)),
      body: SandikIcerikGecisi(
        // Yükleme → içerik çapraz solar (2026-10-14).
        tamEkran: true,
        anahtar: SandikIcerikGecisi.hal([notlar]),
        child: notlar.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(SandikSpace.md),
            child: SandikSkeletonList(rows: 3),
          ),
          // Hata BOŞ değildir (TASARIM_DILI §6.1): neden ve yeniden dene.
          error: (e, _) => SandikErrorView(
            error: e,
            onRetry: () => ref.invalidate(
                notOzetleriProvider(notKumesi(anahtarlar, 'aylik'))),
          ),
          data: (m) {
            final buAy = [
              for (final n in m.values)
                if (n.donem == donem) n
            ]..sort((a, b) {
                final ra =
                    (haftaRozetiSunucudan(a.rozet) ?? HaftaRozeti.sakin).index;
                final rb =
                    (haftaRozetiSunucudan(b.rozet) ?? HaftaRozeti.sakin).index;
                return ra != rb ? ra - rb : a.ticker.compareTo(b.ticker);
              });
            final ozet = ozetHal.valueOrNull;
            // Sayısal bölümler (2026-11-07) not çıkmayan ayda da raporu
            // taşır: rapor ancak ikisi de boşsa "hazır değil" der. Bölümler
            // yüklenirken boş durum gösterilmez (bir an sonra dolacak).
            if (buAy.isEmpty && ozetHal.isLoading) {
              return const Padding(
                padding: EdgeInsets.all(SandikSpace.md),
                child: SandikSkeletonList(rows: 3),
              );
            }
            if (buAy.isEmpty && (ozet == null || ozet.bos)) {
              return _Bos(metin: l10n.anzAylikBos);
            }
            final hareketli = buAy.where((n) => n.rozet != 'sakin').length;
            // Tutup notu çıkmayan varlıklar (ay boyu veri yetmedi ya da not
            // sayı kapısından geçmedi). Sessizce düşerse titiz okur "5
            // varlığım var, rapor 3 diyor" diye takılır; adlarıyla söylenir.
            final notlu = {for (final n in buAy) n.ticker};
            final pozisyonlar = ref.watch(notPozisyonlariProvider(l10n));
            final adlar = {
              for (final p in pozisyonlar.values) p.notAnahtari: p.ad
            };
            String notunAdi(String k) => adlar[k] ?? notAdi(k, l10n);
            final eksik = [
              for (final k in anahtarlar)
                if (!notlu.contains(k)) notunAdi(k)
            ]..sort();
            // Sıra (yasin 2026-11-07, "anlaşılır olmalı"): önce önemli
            // gelişmeler, sonra her varlık tek satır, en sonda kaynak ve
            // kısıt. PDF aynı listeyi kullanır (`raporKalemleri`).
            final kalemler = raporKalemleri(
              notlar: buAy,
              varliklar: ozet?.varliklar ?? const [],
              pozisyonlar: pozisyonlar,
              varlikAdi: (v) => pozisyonEtiketi(v.anahtar, v.tur, l10n, ad: v.ad),
              notAdi: notunAdi,
            );
            void notuAc(AnalizOzeti n, String ad) => pushGuarded(
                  context,
                  adaptiveRoute<void>(
                    settings: const RouteSettings(name: 'analiz_notu'),
                    builder: (_) => AnalizNotuScreen(
                      ticker: n.ticker,
                      tur: 'aylik',
                      donem: n.donem,
                      kod: ad,
                      baslik: n.baslik,
                    ),
                  ),
                );
            // Kapsam satırı (yasin 2026-11-07, "zaman aralığı belirtilmeli"):
            // raporun saydığı günler açık tarihle. Pencere ekran ve PDF'te
            // aynı kaynaktan (`AylikRaporOzeti.pencere`).
            final (kBas, kBit, suren) =
                AylikRaporOzeti.pencere(donem, DateTime.now());
            final aralik = fmtTarihAraligi(kBas, kBit, dil: dil);
            final yatay = SandikSpace.screenH(context);
            Widget liste({VoidCallback? onHikaye}) => ListView(
                  padding: EdgeInsets.fromLTRB(
                      yatay, SandikSpace.md, yatay, SandikSpace.xl),
                  children: [
                    if (onHikaye != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                              minimumSize: SandikTouch.minSize,
                              padding: EdgeInsets.zero),
                          onPressed: onHikaye,
                          icon: const Icon(Icons.auto_stories_rounded),
                          label: Text(l10n.hkyAylikTekrar),
                        ),
                      ),
                    // PDF (2026-10-31, müşteri raporu 31 Eki #1, yasin "yap"):
                    // özet cümlesinin sağ üstünde, uygulamanın tek paylaş
                    // simgesi (`SandikPaylasDugmesi`). Hikâyedeki "PAYLAŞIM
                    // KARTI YOK" kararı (aşağıda) sosyal görsel içindir; PDF
                    // kişinin kendi seçtiği alıcıya (müşavir, aile) giden özel
                    // belge, portföy dökümüyle aynı sınıf.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suren
                                    ? l10n.raporKapsamSuren(aralik)
                                    : l10n.raporKapsam(aralik),
                                style: t.bodySmall?.copyWith(
                                    color: c.text58,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: SandikSpace.xxs),
                              Text(
                                buAy.isEmpty
                                    ? l10n.anzAylikOzetYok
                                    : hareketli > 0
                                        ? l10n.anzAylikOzetVar(
                                            '${buAy.length}', '$hareketli')
                                        : l10n.anzAylikOzetYok,
                                style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: c.text90),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: SandikSpace.xs),
                        // Cümle iki satıra sarabilir: simge ilk satırla
                        // hizalı (`topEnd`), sağ kenarı kartların kenarında.
                        SandikPaylasDugmesi.istekli(
                          hiza: AlignmentDirectional.topEnd,
                          tooltip: l10n.anzAylikPdfPaylas,
                          onPaylas: (kaynak) => _pdfPaylas(context, ref,
                              notlar: buAy,
                              kalemler: kalemler,
                              eksik: eksik,
                              ozet: ozet,
                              kaynak: kaynak),
                        ),
                      ],
                    ),
                    if (ozetHal.isLoading) ...[
                      const SizedBox(height: SandikSpace.lg),
                      // Liste içinde kaydırmasız blok (iç içe kaydırma yok).
                      const SandikSkeleton(
                          height: SandikTouch.min * 2,
                          radius: SandikRadius.md),
                    ],
                    if (kalemler.onemli.isNotEmpty) ...[
                      const SizedBox(height: SandikSpace.lg),
                      SandikSectionHeader(title: l10n.anzAylikOnemliBaslik),
                      const SizedBox(height: SandikSpace.sm),
                      for (final k in kalemler.onemli) ...[
                        _OnemliKart(kalem: k, ac: notuAc),
                        const SizedBox(height: SandikSpace.smd),
                      ],
                    ],
                    if (kalemler.diger.isNotEmpty)
                      _VarlikAyiBolumu(
                          kalemler: kalemler.diger, ozet: ozet, ac: notuAc),
                    if (ozet != null) ...[
                      if (!ozet.akis.bos) ParaAkisiBolumu(akis: ozet.akis),
                      if (ozet.gelismeler.isNotEmpty)
                        GelismelerBolumu(gelismeler: ozet.gelismeler),
                    ],
                    if (eksik.isNotEmpty) ...[
                      const SizedBox(height: SandikSpace.sm),
                      Text(l10n.anzAylikEksik(eksik.join(', ')),
                          style: t.bodySmall?.copyWith(color: c.text58)),
                    ],
                    const SizedBox(height: SandikSpace.md),
                    // Haber yok (2026-11-07): yasin "önemli haber detayları"
                    // istedi; lisanslı haber/KAP kaynağı yok
                    // (`docs/KAP_VERI_LISANSI_2026_09.md`). Haber metni
                    // uydurulmaz, eksiklik raporun kendisinde söylenir.
                    Text(l10n.anzAylikHaberYok,
                        style: t.bodySmall?.copyWith(color: c.text58)),
                    const SizedBox(height: SandikSpace.sm),
                    Text(l10n.anzAylikKaynak,
                        style: t.bodySmall?.copyWith(color: c.text36)),
                  ],
                );
            // Bayrak `goz_alici`: ayın ilk açılışında hikâye; kapalıyken
            // birebir eski liste. Not yoksa hikâye yok (anlatacak not yok).
            if (!RemoteConfigService.instance.gozAlici || buAy.isEmpty) {
              return liste();
            }
            return AylikHikayeKapisi(
              donem: donem,
              notlar: buAy,
              hareketli: hareketli,
              liste: liste,
            );
          },
        ),
      ),
    );
  }

  /// Aylık raporun PDF'i: ekrandaki bölümlerin aynısı (kapsam, ayın
  /// varlıkları, para girişi/çıkışı, gelişmeler, notların tamamı) + ayın
  /// getirisi ve TÜFE'si (`AylikRaporDisaAktarim`). Sayısal bölümler ekranın
  /// elindeki [ozet]'ten: PDF ikinci kez hesaplamaz, iki yüzey ayrışmaz.
  /// Ekran Premium kilidinin ardında; buraya kilitli kullanıcı gelmez.
  Future<void> _pdfPaylas(
    BuildContext context,
    WidgetRef ref, {
    required List<AnalizOzeti> notlar,
    required ({List<RaporKalemi> onemli, List<RaporKalemi> diger}) kalemler,
    required List<String> eksik,
    required AylikRaporOzeti? ozet,
    Rect? kaynak,
  }) async {
    final kullanici = ref.read(authProvider).valueOrNull;
    try {
      final belge = await AylikRaporDisaAktarim.belgeHazirla(
        donem: donem,
        notlar: notlar,
        kalemler: kalemler,
        eksik: eksik,
        ozet: ozet,
        kim: kullanici?.username ?? kullanici?.email ?? '',
      );
      await DisaAktarimService.instance.paylas(belge,
          bicim: DisaAktarimBicimi.pdf, tur: 'aylik_rapor', kaynak: kaynak);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AylikRapor.pdf');
      if (context.mounted) showAppError(context, e);
    }
  }
}

/// Aylık hikâye (göz alıcılık D, 2026-10-09; bayrak `goz_alici`).
///
/// ## Neden
/// Rapor tek uzun listeydi: ayın en çok ne söylediği (hangi varlıkta
/// belirgin hareket oldu) kartların arasında kayboluyordu. Yıllık "sandık
/// Özeti"nin işleyen biçimi aylığa taşındı: her kartta tek büyük öğe.
///
/// ## Kurallar
/// - Hikâye her ay İLK açılışta bir kez oynar (`goruldu` anahtarı ayı
///   tutar); sonra doğrudan liste, en üstte "Hikâye olarak izle".
///   Her açılışta zorla izletmek raporu okumaya gelen kullanıcıyı bekletir.
/// - Uydurma yok: hikâye yalnız listedeki verinin sırasını değiştirir —
///   sayı notu çıkan varlık sayısı, öne çıkanlar rozeti `sakin` olmayan
///   ilk üç not (listeyle aynı önem sırası). Yeni hesap yapılmaz.
/// - PAYLAŞIM KARTI YOK (raporun ilk planından bilinçli sapma): aylık
///   rapor portföy rakamı değil, TUTTUĞUN varlıkların adlarını ve yapay
///   zekâ notlarını taşır. Paylaşmak elindekileri ifşa eder ve notu
///   yatırım yorumu gibi dolaştırırdı; yıllık özetin kartında ise yalnız
///   yüzde ve karakter vardır.
/// - "Atla" ve son düğme ayı görüldü sayar; yarıda kapanan uygulama
///   saymaz (hikâye bir dahakine yine açılır).
class AylikHikayeKapisi extends StatefulWidget {
  const AylikHikayeKapisi({
    super.key,
    required this.donem,
    required this.notlar,
    required this.hareketli,
    required this.liste,
  });

  final DateTime donem;

  /// Raporla aynı sırada (rozet önemi).
  final List<AnalizOzeti> notlar;
  final int hareketli;
  final Widget Function({VoidCallback? onHikaye}) liste;

  /// Son izlenen hikâyenin ayı (`yyyy-MM`).
  static const goruldu = 'aylik_hikaye_goruldu';

  /// Hikâyede en çok kaç öne çıkan kartı: dördüncüsü artık "liste".
  static const enCokOneCikan = 3;

  @override
  State<AylikHikayeKapisi> createState() => _AylikHikayeKapisiState();
}

class _AylikHikayeKapisiState extends State<AylikHikayeKapisi> {
  /// `null`: tercih okunuyor (bir kare; boş çizilir, liste zıplamasın).
  bool? _hikaye;

  String get _ay =>
      '${widget.donem.year}-${widget.donem.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _oku();
  }

  Future<void> _oku() async {
    var goster = true;
    try {
      final p = await SharedPreferences.getInstance();
      goster = p.getString(AylikHikayeKapisi.goruldu) != _ay;
    } catch (_) {
      // Tercih okunamazsa liste: hikâye süs, rapor asıl iş.
      goster = false;
    }
    if (mounted) setState(() => _hikaye = goster);
  }

  Future<void> _bitir() async {
    setState(() => _hikaye = false);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(AylikHikayeKapisi.goruldu, _ay);
    } catch (_) {
      // Yazılamazsa hikâye bir dahakine yine açılır; zararsız.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hikaye = _hikaye;
    if (hikaye == null) return const SizedBox.shrink();
    if (!hikaye) {
      return widget.liste(onHikaye: () => setState(() => _hikaye = true));
    }
    final l10n = context.l10n;
    final c = context.c;
    final ay = DateFormat('MMMM y', Localizations.localeOf(context).toString())
        .format(widget.donem);
    final oneCikanlar = widget.notlar
        .where((n) => n.rozet != 'sakin')
        .take(AylikHikayeKapisi.enCokOneCikan);
    return HikayeAkisi(
      devamMetni: l10n.hkyDevam,
      sonEylemMetni: l10n.hkyAylikRaporuAc,
      atlaMetni: l10n.hkyAtla,
      onAtla: _bitir,
      onBitti: _bitir,
      sayfalar: [
        HikayeSayfasi(
          bas: const SandikCizimi(
            zemin: SandikZemini.yuzey,
            dokunulabilir: false,
            olcek: 0.7,
          ),
          ust: ay,
          baslik: l10n.hkyAylikAcilis,
          alt: l10n.hkyAylikAcilisAlt,
          renk: c.amberText,
        ),
        HikayeSayfasi(
          ust: l10n.hkyAylikSayiUst,
          baslik: '${widget.notlar.length}',
          alt: widget.hareketli > 0
              ? l10n.hkyAylikHareketli('${widget.hareketli}')
              : l10n.hkyAylikSakin,
          renk: c.gold,
        ),
        for (final n in oneCikanlar)
          HikayeSayfasi(
            bas: switch (haftaRozetiSunucudan(n.rozet)) {
              final r? => HaftaRozetCipi(rozet: r),
              null => null,
            },
            ust: l10n.hkyAylikOneCikan,
            baslik: notAdi(n.ticker, l10n),
            alt: n.baslik,
            renk: _rozetRengi(context, haftaRozetiSunucudan(n.rozet)),
          ),
      ],
    );
  }
}

/// Öne çıkan kartının başlık rengi — `HaftaRozetCipi` ile aynı yön dili
/// (giriş/alıcı yeşil, çıkış/satıcı kırmızı). Yön yalnız renkte kalmaz:
/// çip metni yanında.
Color _rozetRengi(BuildContext context, HaftaRozeti? r) {
  final c = context.c;
  return switch (r) {
    HaftaRozeti.buyukGiris || HaftaRozeti.aliciIstekli => c.gain,
    HaftaRozeti.buyukCikis || HaftaRozeti.saticiIstekli => c.loss,
    _ => c.amberText,
  };
}

class _Bos extends StatelessWidget {
  const _Bos({required this.metin});
  final String metin;

  // Bayrak `goz_alici`: ortak boş durum (kapalı sandık); kapalıyken eski
  // düz metin birebir.
  @override
  Widget build(BuildContext context) => RemoteConfigService.instance.gozAlici
      ? SandikBosDurum(metin: metin)
      : Center(
          child: Padding(
            padding: const EdgeInsets.all(SandikSpace.lg),
            child: Text(metin,
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
          ),
        );
}

/// Önemli gelişme kartı: varlığın adı ve türü, durum etiketi, "ne oldu"
/// satırı (kullanıcının pozisyonu, istemci hesabı), notun başlığı ve
/// notun dayandığı tarih aralığı. Ad kullanıcının tanıdığı ad; ham kod
/// ('THYAO.IS', 'KRIPTO:BTC') görünmez.
class _OnemliKart extends StatelessWidget {
  const _OnemliKart({required this.kalem, required this.ac});

  final RaporKalemi kalem;
  final void Function(AnalizOzeti not, String ad) ac;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final not = kalem.not!;
    final rozet = haftaRozetiSunucudan(not.rozet);
    final v = kalem.varlik;
    final aralik = _notAraligi(context, not);
    return SandikCard(
      onTap: () => ac(not, kalem.ad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kalem.ad,
                        style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600, color: c.text90)),
                    if (kalem.tur case final tur?)
                      Text(tur.labelOf(l10n),
                          style: t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ),
              ),
              if (rozet != null) HaftaRozetCipi(rozet: rozet),
            ],
          ),
          if (v != null) ...[
            const SizedBox(height: SandikSpace.xs),
            Text(
                l10n.anzAylikNeOldu(fmtPctIsaretli(v.pct, digits: 1),
                    isaretliTL(v.piyasaTRY)),
                style: t.bodyMedium?.copyWith(
                    color: c.text90, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: SandikSpace.xs),
          Text(not.baslik, style: t.bodyMedium?.copyWith(color: c.text90)),
          if (aralik != null) ...[
            const SizedBox(height: SandikSpace.xxs),
            Text(aralik, style: t.bodySmall?.copyWith(color: c.text58)),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: () => ac(not, kalem.ad),
              child: Text(l10n.anzNotuOku),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Not 1–31 Eki verisinden": her not kapsadığı günleri yazar (kullanıcı
/// kuralı: her rapor/özet tarih aralığı yazar). Eski satırda veri aralığı
/// yoksa null.
String? _notAraligi(BuildContext context, AnalizOzeti n) {
  final bas = n.veriBaslangic, bit = n.veriBitis;
  if (bas == null || bit == null) return null;
  return context.l10n
      .anzAylikNotVerisi(fmtTarihAraligi(bas, bit, dil: context.tarihDili));
}

/// "Varlıklarının ayı": her pozisyon tek satır — ad ve tür, ayın yüzdesi
/// ve piyasa etkisi; öne çıkmayan notun başlığı alt cümle. Notu olan satır
/// dokununca notu açar (satır ≥ 44 pt).
class _VarlikAyiBolumu extends StatelessWidget {
  const _VarlikAyiBolumu(
      {required this.kalemler, required this.ozet, required this.ac});

  final List<RaporKalemi> kalemler;
  final AylikRaporOzeti? ozet;
  final void Function(AnalizOzeti not, String ad) ac;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final dil = context.tarihDili;
    final fiyat = ozet?.fiyatTarihi;
    final olculemeyen = [
      for (final (k, tur, ad) in ozet?.olculemeyen ?? const <(String, AssetType, String)>[])
        pozisyonEtiketi(k, tur, l10n, ad: ad)
    ]..sort();
    final dipnotlar = [
      l10n.anzAylikTumDipnot,
      if (fiyat != null) l10n.raporFiyatTarihi(fmtTarih(fiyat, dil: dil, saat: true)),
      if (olculemeyen.isNotEmpty)
        l10n.anzAylikOlculemeyen(olculemeyen.join(', ')),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.anzAylikTumBaslik),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.md, vertical: SandikSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < kalemler.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: c.hairline),
                  _KalemSatiri(kalem: kalemler[i], ac: ac),
                ],
              ],
            ),
          ),
          for (final d in dipnotlar) ...[
            const SizedBox(height: SandikSpace.xs),
            Text(d, style: t.bodySmall?.copyWith(color: c.text58)),
          ],
        ],
      ),
    );
  }
}

class _KalemSatiri extends StatelessWidget {
  const _KalemSatiri({required this.kalem, required this.ac});

  final RaporKalemi kalem;
  final void Function(AnalizOzeti not, String ad) ac;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final v = kalem.varlik;
    final not = kalem.not;
    final yuzde = v == null ? null : fmtPctIsaretli(v.pct, digits: 1);
    final tutar = v == null ? null : isaretliTL(v.piyasaTRY);
    final tur = kalem.tur?.labelOf(l10n);
    final satir = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kalem.ad,
                      style: t.bodyMedium?.copyWith(color: c.text90)),
                  if (tur != null)
                    Text(tur, style: t.bodySmall?.copyWith(color: c.text58)),
                  if (not != null) ...[
                    const SizedBox(height: SandikSpace.xxs),
                    Text(not.baslik,
                        style: t.bodySmall?.copyWith(color: c.text90)),
                    if (_notAraligi(context, not) case final a?)
                      Text(a, style: t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ],
              ),
            ),
            if (v != null) ...[
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(yuzde!,
                        textAlign: TextAlign.end,
                        style: t.numSmall
                            .copyWith(color: context.signColor(v.pct))),
                    Text(tutar!,
                        textAlign: TextAlign.end,
                        style: t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final etiket = [
      v == null ? kalem.ad : l10n.anzAylikSemVarlik(kalem.ad, yuzde!, tutar!),
      if (not != null) not.baslik,
    ].join('. ');
    if (not == null) {
      return Semantics(label: etiket, excludeSemantics: true, child: satir);
    }
    return Semantics(
      label: etiket,
      button: true,
      excludeSemantics: true,
      child: InkWell(onTap: () => ac(not, kalem.ad), child: satir),
    );
  }
}
