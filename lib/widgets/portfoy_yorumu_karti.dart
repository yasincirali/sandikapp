import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/portfoy_yorumu_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/period_summary_service.dart'
    show PeriodSummaryService, SummaryPeriod;
import '../services/destek_direnc.dart';
import '../services/portfoy_yorumu_service.dart';
import '../services/remote_config_service.dart';
import '../services/yorum_notu.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart' show showSandikConfirm;
import '../utils/tr_format.dart' show dayKey;
import 'para_akisi_karti.dart' show KilitSatiri;
import 'sandik_async_button.dart';
import 'sandik_segment.dart';
import 'sandik_skeleton.dart';
import 'yorum_notu_sayfasi.dart';

/// Performans › Özet: kişiye özel AI portföy yorumu (0145, 2026-10-13).
///
/// Tasarım: https://claude.ai/artifact/DMeJXyFCGt2Ff4vjUgRb6z (yasin 12 Eki:
/// "seyrek periyotlar halinde özet sayfasında yapalım", "yatırım tavsiyesi
/// değildiri belirtelim").
///
/// - Yalnız GEÇEN HAFTA ve GEÇEN AY (kapanmış takvim dönemi). Günlük ve kayan
///   aralıklar yorumlanmaz.
/// - Yorum kaydedilir; kart açıldıkça tablodan okunur, model çağrılmaz.
///   Yalnız kullanıcı "Bu dönemi yorumla"ya basınca istek gider.
/// - "Yatırım tavsiyesi değildir" uyarısı kartın altında SABİT; modele
///   yazdırılmaz (`_shared/portfoy_yorum.ts`).
/// - İlk kullanımda açık rıza sayfası (Zirve'deki gibi, isteğe bağlı).
///
/// Bayrak `portfoy_ai_yorumu` kapalıyken [gorunur] false: kart ağaca hiç
/// girmez, istek atılmaz.
///
/// ## Seçili dönem (0151, 2026-10-14)
/// yasin: "varlık detayında ve varlıklar bütününde de seçili dönem için data
/// detaylı yorum yapılabilir". [secili] verilirse kartın İLK sekmesi
/// Performans'ın seçili dönemidir (varsayılan); geçen hafta/ay sekmeleri
/// kalır. GÜNLÜK seçiliyken o sekme neden yorumlanmadığını söyler. Seçili
/// dönemin yorumu gün başına saklanır (`portfoy_yorumu_service` notu).
/// Varlık detayındaki kardeşi [VarlikYorumuKarti].
class PortfoyYorumuKarti extends ConsumerStatefulWidget {
  const PortfoyYorumuKarti({super.key, this.secili});

  /// Performans'ın seçili dönemi; `null` → yalnız geçen hafta/ay.
  final SummaryPeriod? secili;

  static bool get gorunur => RemoteConfigService.instance.portfoyAiYorumu;

  @override
  ConsumerState<PortfoyYorumuKarti> createState() => _PortfoyYorumuKartiState();
}

/// Yorum isteği, rıza akışı ve "kapat" — iki kartın ortak davranışı.
mixin _YorumIstegi<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? hata;

  String _hataMetni(YorumHataTuru t) {
    final l = context.l10n;
    return switch (t) {
      YorumHataTuru.kota => l.pyzHataKota,
      YorumHataTuru.reddedildi => l.pyzHataRed,
      YorumHataTuru.kapali => l.pyzHataKapali,
      YorumHataTuru.premium => l.pyzKilit,
      _ => l.pyzHataGenel,
    };
  }

  /// Rıza yoksa önce sorar; paket [paket] ile o anda kurulur. Başarıda
  /// [yenile] kaydı yeniden okutur.
  Future<void> yorumIste(
      Future<PortfoyYorumPaketi?> Function() paket, void Function() yenile) async {
    setState(() => hata = null);
    final riza = await ref.read(portfoyYorumRizaProvider.future);
    if (riza != true) {
      if (!mounted) return;
      final kabul = await showSandikSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => const _RizaSayfasi(),
      );
      if (kabul != true) return;
      try {
        await PortfoyYorumuService.instance.rizaAyarla(true);
      } catch (_) {
        if (mounted) setState(() => hata = context.l10n.pyzHataGenel);
        return;
      }
      ref.invalidate(portfoyYorumRizaProvider);
    }
    try {
      final p = await paket();
      if (p == null || !p.yeterli) {
        if (mounted) setState(() => hata = context.l10n.pyzVeriYok);
        return;
      }
      await PortfoyYorumuService.instance.yorumla(p);
      yenile();
    } on PortfoyYorumHatasi catch (e) {
      if (mounted) setState(() => hata = _hataMetni(e.tur));
    } catch (_) {
      if (mounted) setState(() => hata = context.l10n.pyzHataGenel);
    }
  }

  Future<void> kapat() async {
    final l = context.l10n;
    final ok = await showSandikConfirm(
      context: context,
      title: l.pyzKapat,
      message: l.pyzKapatOnay,
      confirmLabel: l.pyzKapat,
      cancelLabel: l.pyzSimdiDegil,
      destructive: true,
      islem: () => PortfoyYorumuService.instance.rizaAyarla(false),
    );
    if (!ok) return;
    ref.invalidate(portfoyYorumRizaProvider);
    ref.invalidate(portfoyYorumuProvider);
    ref.invalidate(portfoySeciliYorumProvider);
    ref.invalidate(varlikYorumKaydiProvider);
  }
}

class _PortfoyYorumuKartiState extends ConsumerState<PortfoyYorumuKarti>
    with _YorumIstegi {
  /// 0 = seçili dönem (yalnız [PortfoyYorumuKarti.secili] varken),
  /// sonra geçen hafta, geçen ay.
  int _sekme = 0;

  List<YorumTuru> get _sekmeler => [
        if (widget.secili != null) YorumTuru.secili,
        YorumTuru.haftalik,
        YorumTuru.aylik,
      ];

  YorumTuru get _tur => _sekmeler[_sekme.clamp(0, _sekmeler.length - 1)];

  AsyncValue<PortfoyYorumDurumu?> _durum() => _tur == YorumTuru.secili
      ? ref.watch(portfoySeciliYorumProvider(widget.secili!))
      : ref.watch(portfoyYorumuProvider(_tur));

  void _yenile() => _tur == YorumTuru.secili
      ? ref.invalidate(portfoySeciliYorumProvider(widget.secili!))
      : ref.invalidate(portfoyYorumuProvider(_tur));

  String _sekmeAdi(YorumTuru t) {
    final l = context.l10n;
    return switch (t) {
      YorumTuru.secili => l.pyzSecili(widget.secili!.label),
      YorumTuru.haftalik => l.pyzGecenHafta,
      YorumTuru.aylik => l.pyzGecenAy,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final kilitli = ref.watch(premiumKilitliProvider);
    final riza = ref.watch(portfoyYorumRizaProvider).valueOrNull;
    final yer = Localizations.localeOf(context).toString();
    final gunAy = DateFormat('d MMM', yer);
    final tur = _tur;

    Widget govde;
    if (kilitli) {
      govde = KilitSatiri(metin: l.pyzKilit, kaynak: 'portfoy_yorumu');
    } else if (tur == YorumTuru.secili &&
        !seciliYorumlanabilir(widget.secili!)) {
      govde = Text(l.pyzGunIci, style: t.bodySmall?.copyWith(color: c.text58));
    } else {
      govde = _durum().when(
        loading: () => const _YorumIskeleti(),
        error: (_, __) =>
            Text(l.pyzHataGenel, style: t.bodySmall?.copyWith(color: c.text58)),
        data: (d) {
          if (d == null || !d.paket.yeterli) {
            return Text(l.pyzVeriYok,
                style: t.bodySmall?.copyWith(color: c.text58));
          }
          final aralik = l.flowRange(
              gunAy.format(d.paket.baslangic), gunAy.format(d.paket.bitis));
          final kayit = d.kayit;
          final aciklama = tur == YorumTuru.secili
              ? l.pyzSeciliAciklama(aralik)
              : l.pyzAciklama(
                  '${tur == YorumTuru.haftalik ? l.pyzGecenHafta : l.pyzGecenAy} ($aralik)');
          final meta = kayit == null
              ? null
              : tur == YorumTuru.secili
                  ? l.pyzSeciliMeta(DateFormat.Hm(yer).format(kayit.olusturuldu))
                  : l.pyzMeta(gunAy.format(kayit.olusturuldu),
                      gunAy.format(_siradaki(tur, d.paket.bitis)));
          return _YorumGovdesi(
            aciklama: aciklama,
            kayit: kayit,
            meta: meta,
            eskidi: kayit != null && !d.guncel ? l.pyzEskidi : null,
            gunAy: gunAy,
            onYorumla: () => yorumIste(() async => d.paket, _yenile),
            notu: kayit == null
                ? null
                : YorumNotu.kur(kayit,
                    kapsam: YorumKapsami.portfoy,
                    donemAdi: YorumNotu.donemAdiOf(tur, widget.secili?.label)),
          );
        },
      );
    }

    final sekmeler = _sekmeler;
    return _YorumCercevesi(
      ust: Semantics(
        container: true,
        label: l.pyzDonemSecici,
        child: SandikSegment(
          adet: sekmeler.length,
          secili: _sekme.clamp(0, sekmeler.length - 1),
          yukseklik: SandikTouch.min,
          onSec: (i) => setState(() {
            _sekme = i;
            hata = null;
          }),
          oge: (_, i, __) => Text(
            _sekmeAdi(sekmeler[i]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      govdeAnahtari: ValueKey((tur, widget.secili)),
      govde: govde,
      hata: hata,
      kapatGorunur: riza == true && !kilitli,
      onKapat: kapat,
    );
  }

  /// Bir sonraki yorumun yazılabileceği gün: haftalıkta bu Pazartesi + 7,
  /// aylıkta gelecek ayın 1'i (anlatılan dönemin bitişinden türetilir).
  static DateTime _siradaki(YorumTuru tur, DateTime bitis) =>
      tur == YorumTuru.haftalik
          ? DateTime(bitis.year, bitis.month, bitis.day + 8)
          : DateTime(bitis.year, bitis.month + 2, 1);
}

/// Varlık detayı: seçili dönemde bu varlığın AI yorumu (0151, 2026-10-14).
///
/// Paket ekranın o anki değerleriyle ([paketKur]) yalnız "Bu dönemi
/// yorumla"da kurulur: dönem istatistiği ve yüzdesi varlık detayının
/// gösterdiğiyle aynı sayı olur, canlı fiyat her nabızda paket kurdurmaz.
/// Kayıt gün başına (`varlikYorumKaydiProvider`). GÜNLÜK'te kart yorum
/// yazmaz, nedenini söyler.
class VarlikYorumuKarti extends ConsumerStatefulWidget {
  const VarlikYorumuKarti({
    super.key,
    required this.period,
    required this.positionKey,
    required this.miktar,
    this.varlikAdi,
    required this.veriHazir,
    required this.paketKur,
    this.seviyeler,
    this.fiyatYaz,
  });

  final SummaryPeriod period;
  final String positionKey;
  final double miktar;

  /// "Tamamını oku" sayfasının ve PDF'in başlığı; sunucuya ayrıca
  /// [paketKur] içinde gider.
  final String? varlikAdi;

  /// Dönem istatistiği ve yüzdesi yüklendi mi? Değilse düğme yerine
  /// "veri yok" yazar (uydurma paket gitmez).
  final bool veriHazir;
  final Future<PortfoyYorumPaketi?> Function() paketKur;

  /// Seçili dönemin destek/direnç bölgeleri ("Seviye bilgisi", 2026-10-17).
  /// Seviyenin KENDİSİ burada, varlık ekranının fiyat biçimiyle ([fiyatYaz])
  /// çizilir; AI'a yalnız yüzde uzaklık gider (sunucu tutar kapısı).
  final DestekDirenc? seviyeler;
  final String Function(double)? fiyatYaz;

  @override
  ConsumerState<VarlikYorumuKarti> createState() => _VarlikYorumuKartiState();
}

class _VarlikYorumuKartiState extends ConsumerState<VarlikYorumuKarti>
    with _YorumIstegi {
  VarlikYorumAnahtari get _anahtar => (
        varlikIzi: varlikIziOf(widget.positionKey),
        donemKodu: widget.period.label,
        bitis: dayKey(DateTime.now()),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final kilitli = ref.watch(premiumKilitliProvider);
    final riza = ref.watch(portfoyYorumRizaProvider).valueOrNull;
    final yer = Localizations.localeOf(context).toString();
    final gunAy = DateFormat('d MMM', yer);

    Widget govde;
    if (kilitli) {
      govde = KilitSatiri(metin: l.pyzKilit, kaynak: 'varlik_yorumu');
    } else if (!seciliYorumlanabilir(widget.period)) {
      govde = Text(l.pyzGunIci, style: t.bodySmall?.copyWith(color: c.text58));
    } else {
      final anahtar = _anahtar;
      govde = ref.watch(varlikYorumKaydiProvider(anahtar)).when(
            loading: () => const _YorumIskeleti(),
            error: (_, __) => Text(l.pyzHataGenel,
                style: t.bodySmall?.copyWith(color: c.text58)),
            data: (kayit) {
              if (kayit == null && !widget.veriHazir) {
                return Text(l.pyzVeriYok,
                    style: t.bodySmall?.copyWith(color: c.text58));
              }
              final w = PeriodSummaryService.pencere(widget.period, DateTime.now());
              final aralik =
                  l.flowRange(gunAy.format(w.start), gunAy.format(anahtar.bitis));
              final guncel = kayit != null &&
                  kayit.parmakIzi ==
                      varlikParmakIzi(widget.positionKey, widget.miktar);
              return _YorumGovdesi(
                aciklama: l.pyzVarlikAciklama(aralik),
                kayit: kayit,
                meta: kayit == null
                    ? null
                    : l.pyzSeciliMeta(DateFormat.Hm(yer).format(kayit.olusturuldu)),
                eskidi: kayit != null && !guncel && widget.veriHazir
                    ? l.pyzVarlikEskidi
                    : null,
                gunAy: gunAy,
                notu: kayit == null
                    ? null
                    : YorumNotu.kur(kayit,
                        kapsam: YorumKapsami.varlik,
                        varlikAdi: widget.varlikAdi,
                        donemAdi: YorumNotu.donemAdiOf(
                            YorumTuru.secili, widget.period.label)),
                onYorumla: () => yorumIste(widget.paketKur,
                    () => ref.invalidate(varlikYorumKaydiProvider(anahtar))),
              );
            },
          );
    }

    final seviyeler = widget.seviyeler;
    final fiyatYaz = widget.fiyatYaz;
    return _YorumCercevesi(
      // Kilitliyken gösterilmez: bölgeler Premium kartın parçası.
      // Gün içinde de gizli: 5 dakikalık seride "dönülen bölge" gürültüdür
      // ve yorum da orada yazılmıyor.
      ust: kilitli ||
              !seciliYorumlanabilir(widget.period) ||
              seviyeler == null ||
              seviyeler.bos ||
              fiyatYaz == null
          ? null
          : SeviyeSatiri(seviyeler: seviyeler, fiyatYaz: fiyatYaz),
      govdeAnahtari: ValueKey(widget.period),
      govde: govde,
      hata: hata,
      kapatGorunur: riza == true && !kilitli,
      onKapat: kapat,
    );
  }
}

/// Destek / direnç bölgeleri — kartın üstünde, yorumdan bağımsız (AI
/// yazmadan da görünür; bölge veridir, yorum değil).
///
/// Renk anlam taşımaz: bölgeler nötr metin rengiyle çizilir. Kazanç/kayıp
/// rengi "destek = al, direnç = sat" diye okunurdu — "Seviye bilgisi"
/// kararı tam olarak bunu dışarıda bırakıyor. Anlam yalnız sözcükte.
class SeviyeSatiri extends StatelessWidget {
  const SeviyeSatiri({super.key, required this.seviyeler, required this.fiyatYaz});

  final DestekDirenc seviyeler;
  final String Function(double) fiyatYaz;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    String aralik(FiyatBolgesi b) => b.alt == b.ust
        ? fiyatYaz(b.alt)
        : '${fiyatYaz(b.alt)} - ${fiyatYaz(b.ust)}';
    Widget satir(String ad, FiyatBolgesi b) {
      final metin = l.seviyeSatiri(ad, aralik(b), b.temas);
      return Semantics(
        label: metin,
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$ad  ',
                style: t.bodySmall?.copyWith(color: c.text58)),
            TextSpan(
                text: aralik(b),
                style: t.bodyMedium?.copyWith(
                    color: c.text90, fontWeight: FontWeight.w600)),
            TextSpan(
                text: '  ${l.seviyeTemas(b.temas)}',
                style: t.bodySmall?.copyWith(color: c.text58)),
          ]),
        ),
      );
    }

    final satirlar = <Widget>[
      if (seviyeler.direnc != null) satir(l.seviyeDirenc, seviyeler.direnc!),
      if (seviyeler.icinde != null) satir(l.seviyeIcinde, seviyeler.icinde!),
      if (seviyeler.destek != null) satir(l.seviyeDestek, seviyeler.destek!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < satirlar.length; i++) ...[
          if (i > 0) const SizedBox(height: SandikSpace.xs),
          satirlar[i],
        ],
      ],
    );
  }
}

/// Kart iskeleti: başlık, (isteğe bağlı) dönem seçici, gövde, hata, sabit
/// uyarı, "kapat". İki kart aynı çerçeveyi kullanır.
class _YorumCercevesi extends StatelessWidget {
  const _YorumCercevesi({
    this.ust,
    required this.govdeAnahtari,
    required this.govde,
    required this.hata,
    required this.kapatGorunur,
    required this.onKapat,
  });

  final Widget? ust;
  final Key govdeAnahtari;
  final Widget govde;
  final String? hata;
  final bool kapatGorunur;
  final VoidCallback onKapat;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: SandikSpace.md, color: c.amberText),
              const SizedBox(width: SandikSpace.xs),
              Expanded(
                child: Text(l.pyzBaslik,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ),
            ],
          ),
          if (ust != null) ...[
            const SizedBox(height: SandikSpace.sm),
            ust!,
          ],
          const SizedBox(height: SandikSpace.md),
          AnimatedSwitcher(
            duration: SandikMotion.stateOf(context),
            child: KeyedSubtree(key: govdeAnahtari, child: govde),
          ),
          if (hata != null) ...[
            const SizedBox(height: SandikSpace.sm),
            Text(hata!, style: t.bodySmall?.copyWith(color: c.danger)),
          ],
          const SizedBox(height: SandikSpace.md),
          _Uyari(metin: l.pyzUyari),
          if (kapatGorunur)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: onKapat,
                child: Text(l.pyzKapat),
              ),
            ),
        ],
      ),
    );
  }
}

class _YorumIskeleti extends StatelessWidget {
  const _YorumIskeleti();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SandikSkeleton(height: 16),
          SizedBox(height: SandikSpace.sm),
          SandikSkeleton(width: 220),
        ],
      );
}

/// Açıklama + "Bu dönemi yorumla" ya da saklı yorum + meta + "eskidi".
class _YorumGovdesi extends StatelessWidget {
  const _YorumGovdesi({
    required this.aciklama,
    required this.kayit,
    required this.meta,
    required this.eskidi,
    required this.gunAy,
    required this.onYorumla,
    this.notu,
  });

  /// "Tamamını oku" (açılır sayfa + PDF, 2026-10-14); kayıt yoksa `null`.
  final YorumNotu? notu;

  final String aciklama;
  final PortfoyYorumu? kayit;
  final String? meta;

  /// Kayıt bugünkü veriyle uyuşmuyorsa gösterilecek not; değilse `null`.
  final String? eskidi;
  final DateFormat gunAy;
  final Future<void> Function() onYorumla;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final k = kayit;
    if (k == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(aciklama, style: t.bodyMedium?.copyWith(color: c.text58)),
          const SizedBox(height: SandikSpace.md),
          SandikAsyncButton.kompakt(
            onPressed: onYorumla,
            child: Text(l.pyzYorumla),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Yorum(yorum: k, gunAy: gunAy),
        if (notu != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: SandikTouch.minSize,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => showYorumNotu(context, notu!),
              icon: const Icon(Icons.article_outlined),
              label: Text(l.pyzTamaminiOku),
            ),
          ),
        if (meta != null) ...[
          const SizedBox(height: SandikSpace.sm),
          Text(meta!, style: t.bodySmall?.copyWith(color: c.text36)),
        ],
        if (eskidi != null) ...[
          const SizedBox(height: SandikSpace.md),
          Text(eskidi!, style: t.bodySmall?.copyWith(color: c.text58)),
          const SizedBox(height: SandikSpace.sm),
          SandikAsyncButton.kompakt(
            tur: SandikAsyncTur.cerceve,
            onPressed: onYorumla,
            child: Text(l.pyzYeniden),
          ),
        ],
      ],
    );
  }
}

class _Yorum extends StatelessWidget {
  const _Yorum({required this.yorum, required this.gunAy});

  final PortfoyYorumu yorum;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(yorum.baslik,
            style: t.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        for (final m in yorum.maddeler) ...[
          const SizedBox(height: SandikSpace.md),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xs2),
                  child: Container(
                    width: SandikSpace.xs2,
                    height: SandikSpace.xs2,
                    decoration:
                        BoxDecoration(color: c.text58, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.metin,
                          style: t.bodyMedium?.copyWith(color: c.text90)),
                      if (yorum.kanitlar(m.kanit).isNotEmpty) ...[
                        const SizedBox(height: SandikSpace.xs),
                        Wrap(
                          spacing: SandikSpace.xs,
                          runSpacing: SandikSpace.xs,
                          children: [
                            for (final k in yorum.kanitlar(m.kanit))
                              _KanitCipi(olcum: k),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Dönem getirisi · +%4,2". Gösterim telefonun yazdığıyla AYNI.
class _KanitCipi extends StatelessWidget {
  const _KanitCipi({required this.olcum});

  final YorumOlcumu olcum;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
      elevated: true,
      radius: SandikRadius.sm,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${olcum.ad} · ', style: TextStyle(color: c.text58)),
          TextSpan(
              text: olcum.gosterim,
              style: TextStyle(color: c.text90, fontWeight: FontWeight.w700)),
        ]),
        style: t.labelSmall,
      ),
    );
  }
}

/// Sabit uyarı kutusu. Kapatılamaz, kaydırınca kaybolmaz (kartın parçası).
class _Uyari extends StatelessWidget {
  const _Uyari({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return SandikCard(
      elevated: true,
      bordered: false,
      radius: SandikRadius.sm,
      padding: const EdgeInsets.all(SandikSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.info_outline_rounded,
                size: SandikSpace.md, color: c.text58),
          ),
          const SizedBox(width: SandikSpace.xs),
          Expanded(
            child: Text(metin, style: t.bodySmall?.copyWith(color: c.text58)),
          ),
        ],
      ),
    );
  }
}

/// İlk kullanımda açık rıza (0145 `portfoy_yorum_rizalari`). Zirve rızası
/// deseni: isteğe bağlı, "Şimdi değil" hiçbir şeyi değiştirmez; aşağı çekip
/// kapatmak da aynı sonucu verir.
class _RizaSayfasi extends StatelessWidget {
  const _RizaSayfasi();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final yatay = SandikSpace.screenH(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.pyzRizaBaslik,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(l.pyzRizaMetin,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.md),
            _Uyari(metin: l.pyzRizaUyari),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.pyzKatiliyorum),
            ),
            const SizedBox(height: SandikSpace.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.pyzSimdiDegil),
            ),
          ],
        ),
      ),
    );
  }
}
