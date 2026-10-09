import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../providers/analiz_provider.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../services/varlik_analizi.dart';
import '../widgets/hikaye_akisi.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_cizimi.dart';
import '../widgets/sandik_error_view.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
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
    final anahtarlar = ref.watch(tutulanNotAnahtarlariProvider);
    final notlar =
        ref.watch(notOzetleriProvider(notKumesi(anahtarlar, 'aylik')));

    return Scaffold(
      appBar: SandikAppBar(title: l10n.anzAylikBaslik(ay)),
      body: notlar.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(SandikSpace.md),
          child: SandikSkeletonList(rows: 3),
        ),
        // Hata BOŞ değildir (TASARIM_DILI §6.1): neden ve yeniden dene.
        error: (e, _) => SandikErrorView(
          error: e,
          onRetry: () => ref
              .invalidate(notOzetleriProvider(notKumesi(anahtarlar, 'aylik'))),
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
          if (buAy.isEmpty) return _Bos(metin: l10n.anzAylikBos);
          final hareketli = buAy.where((n) => n.rozet != 'sakin').length;
          // Tutup notu çıkmayan varlıklar (ay boyu veri yetmedi ya da not
          // sayı kapısından geçmedi). Sessizce düşerse titiz okur "5
          // varlığım var, rapor 3 diyor" diye takılır; adlarıyla söylenir.
          final notlu = {for (final n in buAy) n.ticker};
          final eksik = [
            for (final k in anahtarlar)
              if (!notlu.contains(k)) notKodu(k)
          ]..sort();
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
                  Text(
                    hareketli > 0
                        ? l10n.anzAylikOzetVar('${buAy.length}', '$hareketli')
                        : l10n.anzAylikOzetYok,
                    style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90),
                  ),
                  const SizedBox(height: SandikSpace.md),
                  for (final n in buAy) ...[
                    _VarlikKarti(not: n),
                    const SizedBox(height: SandikSpace.smd),
                  ],
                  if (eksik.isNotEmpty) ...[
                    Text(l10n.anzAylikEksik(eksik.join(', ')),
                        style: t.bodySmall?.copyWith(color: c.text58)),
                    const SizedBox(height: SandikSpace.sm),
                  ],
                  Text(l10n.rdrHaftaKaynak,
                      style: t.bodySmall?.copyWith(color: c.text36)),
                ],
              );
          // Bayrak `goz_alici`: ayın ilk açılışında hikâye; kapalıyken
          // birebir eski liste.
          if (!RemoteConfigService.instance.gozAlici) return liste();
          return AylikHikayeKapisi(
            donem: donem,
            notlar: buAy,
            hareketli: hareketli,
            liste: liste,
          );
        },
      ),
    );
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
            baslik: notKodu(n.ticker),
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

class _VarlikKarti extends StatelessWidget {
  const _VarlikKarti({required this.not});

  final AnalizOzeti not;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final kod = notKodu(not.ticker);
    final rozet = haftaRozetiSunucudan(not.rozet);
    void ac() => pushGuarded(
          context,
          adaptiveRoute<void>(
            builder: (_) => AnalizNotuScreen(
              ticker: not.ticker,
              tur: 'aylik',
              donem: not.donem,
              kod: kod,
              baslik: not.baslik,
            ),
          ),
        );
    return SandikCard(
      onTap: ac,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kod,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ),
              if (rozet != null) HaftaRozetCipi(rozet: rozet),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(not.baslik, style: t.bodyMedium?.copyWith(color: c.text90)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: ac,
              child: Text(l10n.anzNotuOku),
            ),
          ),
        ],
      ),
    );
  }
}
