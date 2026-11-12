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
import '../utils/tr_iyelik.dart' show trSayiIyelikEki;
import 'para_akisi_karti.dart' show KilitSatiri;

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
///   Yüklenirken kart yok (iskelet de yok): liste sonunda duran ek bir
///   kart; iskelet her açılışta "bir şey eksik" der, kart çoğu zaman
///   önbellekten anında gelir.
///
/// ## Yerleşim (HIG Dynamic Type; yatay kaydırma YOK)
/// - Geniş (≥ 12 hücre sığıyor, iPad): yıl satırı = 12 ay + yıl sütunu.
/// - Dar (telefon): yıl başlığı satırında yıl toplamı, altında iki satır
///   (Oca–Haz / Tem–Ara). On iki sütun telefonda hücre başına ~25 pt
///   bırakırdı; "▲ %12,3" sığmaz.
/// - Metin ölçeği ≥ 2: tek sütun liste (her ay bir satır). İki satırlık
///   ızgara bile 2× metinde hücreyi taşırır.
///
/// ## Anlam renkte değil işarette (HIG renk körlüğü)
/// Her yüzde ▲/▼ ile yazılır; renk (kazanç/kayıp) yalnız destekler. Ekran
/// okuyucu oku değil "kazanç / kayıp" kelimesini okur.
class AylikGetiriKarti extends ConsumerWidget {
  const AylikGetiriKarti({super.key, required this.istek, this.simdi});

  final AylikGetiriIstegi istek;

  /// Test için "bugün"; verilmezse `DateTime.now()`.
  final DateTime? simdi;

  /// Hücre başına asgari genişlik (geniş yerleşim kararı). "▲ %12,3"
  /// numSmall'da ~52 pt.
  static const double _hucreAsgari = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final bugun = simdi ?? DateTime.now();
    if (ref.watch(premiumKilitliProvider)) {
      if (!aylikGetiriOnizlemesiGorunur(istek.hesapLotlari, bugun)) {
        return const SizedBox.shrink();
      }
      return _kabuk(
        context,
        KilitSatiri(
          metin: l.aylikGetiriKilitli,
          kaynak: 'aylik_getiri',
          ozellik: 'aylik_getiri',
          kilitEtiketi: l.goalDateLockedLabel,
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
    if (aySayisi <= 0) return const SizedBox.shrink();
    if (aySayisi < aylikGetiriAsgariAy) {
      return _kabuk(
        context,
        _Ilerleme(
          olculen: aySayisi,
          hazirAy: aylikGetiriHazirAyi(istek.hesapLotlari)!,
          bugun: bugun,
        ),
      );
    }
    final durum = ref.watch(aylikGetiriProvider(istek));
    final tablo = durum.valueOrNull;
    // Seri hatası: kart kalır, tek satır söyler (ham hata yok; bildirim
    // provider'da). Önceki tablo varsa (yenileme hatası) o kalır.
    if (tablo == null && durum.hasError) {
      return _kabuk(
        context,
        Text(l.aylikGetiriHata,
            style: context.t.bodySmall?.copyWith(color: context.c.text58)),
      );
    }
    // Aralık 6 ay ama seri delikli (ölçülen < 6): tablo birkaç hücre
    // olurdu. İlerleme cümlesi de yanlış olurdu ("Şubat'ta hazır" dediği
    // ay çoktan geçmiş), kart yok — eski davranış.
    if (tablo == null || tablo.olculenAySayisi < aylikGetiriAsgariAy) {
      return const SizedBox.shrink();
    }
    final olcek = MediaQuery.textScalerOf(context).scale(1);
    return _kabuk(
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
                  _YilBlogu(tablo: tablo, yil: yil, yerlesim: yerlesim),
                ],
              ],
            );
          }),
          const SizedBox(height: SandikSpace.sm),
          Text(
            l.aylikGetiriDipnot,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ],
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
  const _YilBlogu(
      {required this.tablo, required this.yil, required this.yerlesim});

  final AylikGetiriTablosu tablo;
  final int yil;
  final _Yerlesim yerlesim;

  @override
  Widget build(BuildContext context) {
    final hucreler = tablo.aylar[yil]!;
    final toplam = tablo.yilToplami[yil];
    Widget hucre(int ay) => _Hucre(
          tablo: tablo,
          yil: yil,
          ay: ay,
          deger: hucreler[ay - 1],
          satir: yerlesim == _Yerlesim.liste,
        );
    final yilEtiketi = Text('$yil',
        style: context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600));
    final toplamHucresi = _Hucre.yilToplami(
        yil: yil, deger: toplam, satir: yerlesim == _Yerlesim.liste);

    switch (yerlesim) {
      case _Yerlesim.genis:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: AylikGetiriKarti._hucreAsgari, child: yilEtiketi),
            for (var m = 1; m <= 12; m++) Expanded(child: hucre(m)),
            Expanded(child: toplamHucresi),
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
            Row(children: [
              Expanded(child: yilEtiketi),
              toplamHucresi,
            ]),
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
            yilEtiketi,
            const SizedBox(height: SandikSpace.xs),
            toplamHucresi,
            for (var m = 1; m <= 12; m++)
              if (tablo.aralikta(yil, m)) hucre(m),
          ],
        );
    }
  }
}

/// Tek hücre: ay etiketi + "▲ %2,1" / "—" / boş.
class _Hucre extends StatelessWidget {
  const _Hucre({
    required AylikGetiriTablosu this.tablo,
    required this.yil,
    required int this.ay,
    required this.deger,
    required this.satir,
  });

  const _Hucre.yilToplami({
    required this.yil,
    required this.deger,
    required this.satir,
  })  : tablo = null,
        ay = null;

  final AylikGetiriTablosu? tablo;
  final int yil;

  /// `null`: yıl toplamı hücresi.
  final int? ay;
  final double? deger;

  /// Liste yerleşimi: etiket solda, değer sağda, tek satır.
  final bool satir;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = context.tarihDili;
    final ay = this.ay;
    final tablo = this.tablo;
    final aralikta = ay == null || tablo!.aralikta(yil, ay);
    final buAy = ay != null &&
        tablo != null &&
        tablo.buAy.year == yil &&
        tablo.buAy.month == ay;
    final etiket = ay == null
        ? l.aylikGetiriYil
        : (buAy
            ? (satir
                ? '${ayAdi(ay, dil: dil)} · ${l.aylikGetiriBuAy}'
                : l.aylikGetiriBuAy)
            : ayAdi(ay, dil: dil, kisa: !satir));

    // Değer metni + ekran okuyucu cümlesi. Hane: 1 ondalık — tabloda on
    // iki sayı yan yana; ikinci ondalık okunmayan gürültü.
    final d = deger;
    final String metin;
    final String okunan;
    Color? renk;
    if (!aralikta) {
      metin = '';
      okunan = '';
    } else if (d == null) {
      metin = '—';
      okunan = l.aylikGetiriVeriYok;
    } else {
      final yuzde = fmtPct(d.abs(), digits: 1);
      final sifir = yuzde == fmtPct(0, digits: 1);
      metin = sifir ? yuzde : '${d > 0 ? '▲' : '▼'} $yuzde';
      okunan = sifir
          ? yuzde
          : (d > 0 ? l.aylikGetiriKazanc(yuzde) : l.aylikGetiriKayip(yuzde));
      if (!sifir) renk = d > 0 ? c.gain : c.loss;
    }

    final etiketStili = context.t.labelSmall?.copyWith(
        color: c.text36, fontWeight: ay == null ? FontWeight.w600 : null);
    final degerStili = context.t.numSmall.copyWith(
        color: renk ?? c.text58,
        fontWeight: ay == null ? FontWeight.w600 : null);

    final govde = satir
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
            child: Row(children: [
              Expanded(child: Text(etiket, style: etiketStili)),
              Text(metin, style: degerStili),
            ]),
          )
        : Column(
            crossAxisAlignment: ay == null
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(etiket,
                  style: etiketStili,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: SandikSpace.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(metin, style: degerStili, maxLines: 1),
              ),
            ],
          );
    if (!aralikta) return ExcludeSemantics(child: govde);
    final ayMetni = ay == null ? '$yil' : '${ayAdi(ay, dil: dil)} $yil';
    return Semantics(
      container: true,
      label: l.aylikGetiriHucre(
          ay == null ? '${l.aylikGetiriYil} $yil' : ayMetni, okunan),
      excludeSemantics: true,
      child: govde,
    );
  }
}
