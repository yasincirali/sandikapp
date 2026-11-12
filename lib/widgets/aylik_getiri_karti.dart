import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/aylik_getiri_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../services/aylik_getiri_tablosu.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart'
    show trSayiIyelikBelirtmeEki, trSayiIyelikEki;
import 'para_akisi_karti.dart' show KilitSatiri;
import 'sandik_acilir.dart';
import 'sandik_skeleton.dart' show SandikIcerikGecisi;

/// Performans'ta "hangi ay kazandım, hangi ay kaybettim" kartı — yıl × ay
/// getiri tablosu (2026-11-11, Premium; paywall kaynağı `aylik_getiri`).
///
/// Hesap `aylikGetiriTablosu`'nda (servis, saf), önbellek
/// [aylikGetiriProvider]'da; bu widget yalnız yazar.
///
/// ## Görünürlük (en iyi / zor gün ve başa baş deseni)
/// - Premium özellikleri görünmüyorsa (paywall kapalı, admin değil) kart
///   hiç yok — canlı kullanıcı birebir eski ekranı görür.
/// - Kilitliyse başlık + [KilitSatiri]; seri çekilmez. Önizleme ancak
///   defter en az 6 ay geriye gidiyorsa (`aylikGetiriOnizlemesiGorunur`).
/// - Açıksa tablo, en az 6 ayın getirisi ölçülmüşse. Daha kısa geçmişte
///   birkaç hücrelik tablo dönem çiplerinin cevabını tekrar ederdi; orada
///   (2026-11-12'den beri) aynı başlıkla 6 bölmeli ilerleme ve tablonun
///   hazır olacağı ay görünür. Eskiden kart hiç yoktu: Premium alan
///   kullanıcı özelliği arayıp bulamıyordu.
/// - Seri hatasında kart kalır, tek satır "hesaplanamadı" der.
/// - Yüklenirken kart yok (iskelet de yok): liste sonunda duran ek bir
///   kart; iskelet her açılışta "bir şey eksik" der, kart çoğu zaman
///   önbellekten anında gelir. Geç geldiğinde liste zıplamasın diye
///   [SandikIcerikGecisi] boyu akıtır, kart solarak belirir (2026-11-12;
///   hareketi azalt açıkken anında).
///
/// ## Yerleşim (HIG Dynamic Type; yatay kaydırma YOK)
/// Her yıl önce yıl satırı ("2025 ▲ %12,4"), altında aylar.
/// - Geniş (≥ 14 hücre sığıyor, iPad): 12 ay tek satır.
/// - Dar (telefon): iki satır (Oca–Haz / Tem–Ara). On iki sütun telefonda
///   hücre başına ~25 pt bırakırdı; "▲ %12,3" sığmaz.
/// - Metin ölçeği ≥ 2: tek sütun liste (her ay bir satır). İki satırlık
///   ızgara bile 2× metinde hücreyi taşırır.
///
/// ## Anlam renkte değil işarette (HIG renk körlüğü)
/// Her yüzde ▲/▼ ile yazılır; renk (kazanç/kayıp) yalnız destekler. Ekran
/// okuyucu oku değil "kazanç / kayıp" kelimesini okur.
///
/// ## Hücre tonu ve çerçeve (tasarım turu 2026-11-12)
/// Tablo bir bakışta "yeşil mi kırmızı mı" okunsun diye hücre zemini
/// kazanç/kayıp tonunun [_tonAlfa]'sı. Ölçüldü: yüzde metni ton renginde
/// kalsaydı bu zeminde 4,5:1'in altına düşüyordu (açık tema kazanç 4,36,
/// kayıp 4,47); bu yüzden sayı `text90` (≥ 9:1), ay etiketi `text58`
/// (≥ 5,7:1), yalnız ok ton renginde (grafik öğe, ≥ 3:1). Renk okuyamayan
/// kullanıcı için ok + yüzde aynen duruyor. Tablonun en iyi ve en zor
/// (kapanmış) ayı ince çerçeveli — yalnız iki hücre; hangisi olduğu alt
/// cümlede ve ekran okuyucu etiketinde yazılı.
class AylikGetiriKarti extends ConsumerWidget {
  const AylikGetiriKarti({super.key, required this.istek, this.simdi});

  final AylikGetiriIstegi istek;

  /// Test için "bugün"; verilmezse `DateTime.now()`.
  final DateTime? simdi;

  /// Hücre başına asgari genişlik (geniş yerleşim kararı). "▲ %12,3"
  /// numSmall'da ~52 pt.
  static const double _hucreAsgari = 56;

  /// Hücre zemin tonunun saydamlığı. %12: aralığın (%12–16) en düşüğü;
  /// %16'da açık temada ay etiketi bile (text36 olsaydı) 4,5'in altına
  /// iniyordu, %12 tüm metinlerde payı en geniş bırakan değer.
  static const double _tonAlfa = 0.12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (hal, govde) = _icerik(context, ref);
    // Anahtar yalnız hal: tablo yerinde güncellenir (fiyat tiki solma
    // oynatmaz); yok → kart, ilerleme → tablo geçişleri boyu akıtır.
    return SandikIcerikGecisi(anahtar: hal, child: govde);
  }

  (String, Widget) _icerik(BuildContext context, WidgetRef ref) {
    const yok = ('yok', SizedBox.shrink());
    if (!ref.watch(premiumOzellikleriGorunurProvider)) return yok;
    final l = context.l10n;
    final bugun = simdi ?? DateTime.now();
    if (ref.watch(premiumKilitliProvider)) {
      if (!aylikGetiriOnizlemesiGorunur(istek.hesapLotlari, bugun)) {
        return yok;
      }
      return (
        'kilit',
        _kabuk(
          context,
          KilitSatiri(
            metin: l.aylikGetiriKilitli,
            kaynak: 'aylik_getiri',
            ozellik: 'aylik_getiri',
            kilitEtiketi: l.goalDateLockedLabel,
          ),
        ),
      );
    }
    // Kısa geçmiş (2026-11-12): eskiden kart hiç yoktu; Premium kullanıcı
    // aldığı özelliği bulamıyordu. Aralık defterden sayılır, seri
    // çekilmez — 3 aylık defter için beş yıllık seri indirmek boşa ağ.
    // 0 ay (ilk alım yok / gelecekte) kart yok: ölçülecek bir şey yok ve
    // Performans'ın boş hâli zaten "ilk varlığını ekle" der; "0 ay
    // ölçüldü" o çağrının yanında ikinci, daha zayıf bir boş durum olurdu.
    final aySayisi = aylikGetiriAralikAySayisi(istek.hesapLotlari, bugun);
    if (aySayisi <= 0) return yok;
    if (aySayisi < aylikGetiriAsgariAy) {
      return (
        'ilerleme',
        _kabuk(
          context,
          _Ilerleme(
            olculen: aySayisi,
            hazirAy: aylikGetiriHazirAyi(istek.hesapLotlari)!,
            bugun: bugun,
          ),
        ),
      );
    }
    final durum = ref.watch(aylikGetiriProvider(istek));
    final tablo = durum.valueOrNull;
    // Seri hatası: kart kalır, tek satır söyler (ham hata yok; bildirim
    // provider'da). Önceki tablo varsa (yenileme hatası) o kalır.
    if (tablo == null && durum.hasError) {
      return (
        'hata',
        _kabuk(
          context,
          Text(l.aylikGetiriHata,
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
        ),
      );
    }
    // Aralık 6 ay ama seri delikli (ölçülen < 6): tablo birkaç hücre
    // olurdu. İlerleme cümlesi de yanlış olurdu ("Şubat'ta hazır" dediği
    // ay çoktan geçmiş), kart yok — eski davranış.
    if (tablo == null || tablo.olculenAySayisi < aylikGetiriAsgariAy) {
      return yok;
    }
    final olcek = MediaQuery.textScalerOf(context).scale(1);
    final ozet = tablo.ozet;
    return (
      'tablo',
      _kabuk(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, k) {
              final yerlesim = olcek >= 2
                  ? _Yerlesim.liste
                  : (k.maxWidth >= _hucreAsgari * 14
                      ? _Yerlesim.genis
                      : _Yerlesim.dar);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, yil) in tablo.yillar.indexed) ...[
                    if (i > 0) const SizedBox(height: SandikSpace.md),
                    _YilBlogu(
                        tablo: tablo,
                        ozet: ozet,
                        yil: yil,
                        yerlesim: yerlesim),
                  ],
                ],
              );
            }),
            if (ozet != null) ...[
              const SizedBox(height: SandikSpace.smd),
              _OzetCumlesi(ozet: ozet),
            ],
            const SizedBox(height: SandikSpace.xs),
            const _Dipnot(),
          ],
        ),
      ),
    );
  }

  Widget _kabuk(BuildContext context, Widget govde) => Padding(
        padding: const EdgeInsets.only(top: SandikSpace.md),
        child: SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SandikSectionHeader(title: context.l10n.aylikGetiriBaslik),
              const SizedBox(height: SandikSpace.sm),
              govde,
            ],
          ),
        ),
      );
}

enum _Yerlesim { genis, dar, liste }

/// Yüzdenin ekranda yazılışı ("▲ %2,1", sıfırda "%0,0") ve ekran okuyucu
/// cümlesi ("yüzde 2,1 kazanç"). Hane: 1 ondalık — tabloda on iki sayı
/// yan yana; ikinci ondalık okunmayan gürültü. Ok ayrı döner ki çağıran
/// onu ton renginde, sayıyı metin renginde yazabilsin.
({String ok, String yuzde, String okunan, int yon}) _yuzdeParcalari(
    AppLocalizations l, double d) {
  final yuzde = fmtPct(d.abs(), digits: 1);
  if (yuzde == fmtPct(0, digits: 1)) {
    return (
      ok: '',
      yuzde: yuzde,
      okunan: l.aylikGetiriYuzde(fmtNum(0, digits: 1)),
      yon: 0
    );
  }
  final sayi = fmtNum(d.abs(), digits: 1);
  return d > 0
      ? (ok: '▲', yuzde: yuzde, okunan: l.aylikGetiriKazanc(sayi), yon: 1)
      : (ok: '▼', yuzde: yuzde, okunan: l.aylikGetiriKayip(sayi), yon: -1);
}

Color? _tonRengi(BuildContext context, int yon) =>
    yon == 0 ? null : (yon > 0 ? context.c.gain : context.c.loss);

/// "▲ %2,1": ok ton renginde, sayı [stil]in renginde.
InlineSpan _yuzdeSpan(BuildContext context,
    ({String ok, String yuzde, String okunan, int yon}) p,
    {String arasi = ' '}) {
  final ton = _tonRengi(context, p.yon);
  return TextSpan(children: [
    if (p.ok.isNotEmpty)
      TextSpan(text: '${p.ok}$arasi', style: TextStyle(color: ton)),
    TextSpan(text: p.yuzde),
  ]);
}

/// Kısa geçmişin ilerlemesi: 6 bölme + "Tablo 6 ay dolunca burada açılır.
/// Şu an 3 ay ölçüldü, Şubat'ta hazır." (2026-11-12).
///
/// Bölmeler süs değil sayaç: dolu bölme ölçülen ay. Anlam renkte değil,
/// cümle aynı sayıyı yazar; ekran okuyucu bölmeleri tek cümleyle okur
/// ("6 aydan 3'ü ölçüldü"), cümle ayrıca okunur. Dolgu/boş renkleri
/// kilometre taşı çubuğuyla aynı (`amberText` / `overlay`).
class _Ilerleme extends StatelessWidget {
  const _Ilerleme(
      {required this.olculen, required this.hazirAy, required this.bugun});

  final int olculen;
  final DateTime hazirAy;
  final DateTime bugun;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = context.tarihDili;
    final ekli = dil.startsWith('en')
        ? '$olculen'
        : "$olculen'${trSayiIyelikEki(olculen)}";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: l.aylikGetiriIlerlemeOkunan(aylikGetiriAsgariAy, ekli),
          excludeSemantics: true,
          child: Row(
            children: [
              for (var i = 0; i < aylikGetiriAsgariAy; i++) ...[
                if (i > 0) const SizedBox(width: SandikSpace.xs),
                Expanded(
                  child: ClipRRect(
                    borderRadius: SandikRadius.smAll,
                    child: SizedBox(
                      height: SandikSpace.xs2,
                      child: ColoredBox(
                          color: i < olculen ? c.amberText : c.overlay),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          l.aylikGetiriIlerleme(aylikGetiriAsgariAy, olculen,
              ayBulunmaParcasi(hazirAy, dil: dil, bugun: bugun)),
          style: context.t.bodySmall?.copyWith(color: c.text58),
        ),
      ],
    );
  }
}

class _YilBlogu extends StatelessWidget {
  const _YilBlogu({
    required this.tablo,
    required this.ozet,
    required this.yil,
    required this.yerlesim,
  });

  final AylikGetiriTablosu tablo;
  final AylikGetiriOzeti? ozet;
  final int yil;
  final _Yerlesim yerlesim;

  @override
  Widget build(BuildContext context) {
    final hucreler = tablo.aylar[yil]!;
    Widget hucre(int ay) => _Hucre(
          tablo: tablo,
          yil: yil,
          ay: ay,
          deger: hucreler[ay - 1],
          satir: yerlesim == _Yerlesim.liste,
          vurgu: ozet == null
              ? _Vurgu.yok
              : (ozet!.enIyi.ayni(yil, ay)
                  ? _Vurgu.enIyi
                  : (ozet!.enZor?.ayni(yil, ay) ?? false)
                      ? _Vurgu.enZor
                      : _Vurgu.yok),
        );
    final baslik = _YilSatiri(yil: yil, toplam: tablo.yilToplami[yil]);

    switch (yerlesim) {
      case _Yerlesim.genis:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            baslik,
            const SizedBox(height: SandikSpace.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var m = 1; m <= 12; m++) Expanded(child: hucre(m)),
              ],
            ),
          ],
        );
      case _Yerlesim.dar:
        Widget satir(int bas) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var m = bas; m < bas + 6; m++) Expanded(child: hucre(m)),
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            baslik,
            const SizedBox(height: SandikSpace.xs),
            satir(1),
            const SizedBox(height: SandikSpace.xs),
            satir(7),
          ],
        );
      case _Yerlesim.liste:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            baslik,
            const SizedBox(height: SandikSpace.xs),
            for (var m = 1; m <= 12; m++)
              if (tablo.aralikta(yil, m)) ...[
                hucre(m),
                const SizedBox(height: SandikSpace.xxs),
              ],
          ],
        );
    }
  }
}

/// Yıl satırı: "2025 ▲ %12,4". Yıl toplamı `titleSmall` w600 — satırın
/// cevabı odur, hücrelerden bir kademe büyük. [Wrap]: dar ekranda ve
/// büyük yazıda parçalar alt satıra iner, taşmaz.
class _YilSatiri extends StatelessWidget {
  const _YilSatiri({required this.yil, required this.toplam});

  final int yil;
  final double? toplam;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final stil =
        context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final t = toplam;
    final p = t == null ? null : _yuzdeParcalari(l, t);
    final yilAdi = '${l.aylikGetiriYil} $yil';
    return Semantics(
      container: true,
      label: p == null ? yilAdi : l.aylikGetiriHucre(yilAdi, p.okunan),
      excludeSemantics: true,
      child: Wrap(
        spacing: SandikSpace.sm,
        runSpacing: SandikSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$yil', style: stil?.copyWith(color: c.text90)),
          if (p != null)
            Text.rich(_yuzdeSpan(context, p),
                style: stil?.copyWith(color: c.text90)),
        ],
      ),
    );
  }
}

enum _Vurgu { yok, enIyi, enZor }

/// Tek ay hücresi: ay etiketi + "▲ %2,1" / "—" / boş. Kazanç/kayıp
/// ayında zemin tonlu; en iyi / en zor ayda ince çerçeve.
class _Hucre extends StatelessWidget {
  const _Hucre({
    required this.tablo,
    required this.yil,
    required this.ay,
    required this.deger,
    required this.satir,
    required this.vurgu,
  });

  final AylikGetiriTablosu tablo;
  final int yil;
  final int ay;
  final double? deger;

  /// Liste yerleşimi: etiket solda, değer sağda, tek satır.
  final bool satir;
  final _Vurgu vurgu;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = context.tarihDili;
    final aralikta = tablo.aralikta(yil, ay);
    final buAy = tablo.buAy.year == yil && tablo.buAy.month == ay;
    final etiket = buAy
        ? (satir
            ? '${ayAdi(ay, dil: dil)} · ${l.aylikGetiriBuAy}'
            : l.aylikGetiriBuAy)
        : ayAdi(ay, dil: dil, kisa: !satir);

    final d = deger;
    final p = (aralikta && d != null) ? _yuzdeParcalari(l, d) : null;
    final ton = p == null ? null : _tonRengi(context, p.yon);
    final String okunan = !aralikta
        ? ''
        : (p == null ? l.aylikGetiriVeriYok : p.okunan);

    final etiketStili = context.t.labelSmall?.copyWith(color: c.text58);
    final degerStili =
        context.t.numSmall.copyWith(color: ton == null ? c.text58 : c.text90);
    final InlineSpan degerMetni = p == null
        ? TextSpan(text: aralikta ? '—' : '')
        : _yuzdeSpan(context, p);

    final icerik = satir
        ? Row(children: [
            Expanded(child: Text(etiket, style: etiketStili)),
            const SizedBox(width: SandikSpace.sm),
            Text.rich(degerMetni, style: degerStili),
          ])
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(etiket,
                  style: etiketStili,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: SandikSpace.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(degerMetni, style: degerStili, maxLines: 1),
              ),
            ],
          );
    final cerceve = switch (vurgu) {
      _Vurgu.yok => null,
      // Çerçeve hücrenin kendi tonunda: bütün aylar eksideyse "en iyi"
      // de kayıp tonundadır — renk yön söyler, çerçeve "uç" söyler.
      _ => ton ?? c.text58,
    };
    final govde = Container(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      margin: satir
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
      padding: EdgeInsets.symmetric(
          horizontal: satir ? SandikSpace.sm : SandikSpace.xxs,
          vertical: SandikSpace.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ton?.withValues(alpha: AylikGetiriKarti._tonAlfa),
        borderRadius: SandikRadius.smAll,
      ),
      // Çerçeve ön planda: yerleşimi kaydırmaz, çerçeveli hücre
      // komşularıyla aynı boyda kalır.
      foregroundDecoration: cerceve == null
          ? null
          : BoxDecoration(
              borderRadius: SandikRadius.smAll,
              border: Border.all(color: cerceve),
            ),
      child: icerik,
    );
    if (!aralikta) return ExcludeSemantics(child: govde);
    final ayMetni = '${ayAdi(ay, dil: dil)} $yil';
    return Semantics(
      container: true,
      label: switch (vurgu) {
        _Vurgu.enIyi => l.aylikGetiriHucreEnIyi(ayMetni, okunan),
        _Vurgu.enZor => l.aylikGetiriHucreEnZor(ayMetni, okunan),
        _Vurgu.yok => l.aylikGetiriHucre(ayMetni, okunan),
      },
      excludeSemantics: true,
      child: govde,
    );
  }
}

/// Kartın alt cümlesi: "20 ayın 14'ünü artıda kapattın. En iyi ay Tem
/// 2026 ▲%6,4, en zor Eki 2025 ▼%6,1." Sayılar [AylikGetiriOzeti]'nden
/// (model); burada yalnız cümle kurulur. Ekran okuyucu ay adını tam,
/// yüzdeyi "yüzde 6,4 kazanç" diye okur (ok işareti okunmaz).
class _OzetCumlesi extends StatelessWidget {
  const _OzetCumlesi({required this.ozet});

  final AylikGetiriOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dil = context.tarihDili;
    final en = dil.startsWith('en');
    final artiEkli = en
        ? '${ozet.arti}'
        : "${ozet.arti}'${trSayiIyelikBelirtmeEki(ozet.arti)}";
    final ilk = ozet.arti == 0
        ? l.aylikGetiriOzetArtiYok(ozet.kapanan)
        : l.aylikGetiriOzetArti(ozet.kapanan, artiEkli);

    String ay(AylikGetiriAyi a, {required bool kisa}) =>
        '${ayAdi(a.ay, dil: dil, kisa: kisa)} ${a.yil}';
    String gorunen(AylikGetiriAyi a) {
      final p = _yuzdeParcalari(l, a.deger);
      return '${p.ok}${p.yuzde}';
    }

    String uclar({required bool okunan}) {
      String deger(AylikGetiriAyi a) =>
          okunan ? _yuzdeParcalari(l, a.deger).okunan : gorunen(a);
      final zor = ozet.enZor;
      return zor == null
          ? l.aylikGetiriOzetEnIyi(
              ay(ozet.enIyi, kisa: !okunan), deger(ozet.enIyi))
          : l.aylikGetiriOzetUclar(ay(ozet.enIyi, kisa: !okunan),
              deger(ozet.enIyi), ay(zor, kisa: !okunan), deger(zor));
    }

    return Semantics(
      label: '$ilk ${uclar(okunan: true)}',
      excludeSemantics: true,
      child: Text('$ilk ${uclar(okunan: false)}',
          style: context.t.bodyMedium?.copyWith(color: context.c.text90)),
    );
  }
}

/// Tek satır dipnot + dokununca açılan ayrıntı (2026-11-12). Eskiden üç
/// satırlık yöntem notu her açılışta tablonun altında duruyordu; asıl
/// soru ("para eklemem yüzdeyi bozar mı") tek satırda cevaplanır, yöntem
/// isteyen için açılır. Uygulamanın tek katlanır hareketi [SandikAcilir].
class _Dipnot extends StatefulWidget {
  const _Dipnot();

  @override
  State<_Dipnot> createState() => _DipnotState();
}

class _DipnotState extends State<_Dipnot> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _acik,
          child: SandikTappable(
            soluk: true,
            haptic: SandikHaptic.none,
            scale: 0.99,
            onTap: () => setState(() => _acik = !_acik),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.aylikGetiriDipnotKisa,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  SandikAcilirOk(
                    acik: _acik,
                    child: Icon(Icons.expand_more_rounded,
                        size: SandikSpace.lgs, color: c.text36),
                  ),
                ],
              ),
            ),
          ),
        ),
        SandikAcilir(
          acik: _acik,
          child: Padding(
            padding: const EdgeInsets.only(bottom: SandikSpace.xs),
            child: Text(
              l.aylikGetiriDipnot,
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
          ),
        ),
      ],
    );
  }
}
