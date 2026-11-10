import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/gecmis_fiyatlar.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// Grafiğin altındaki "Tablo olarak gör" satırı → seçili dönemin gün sonu
/// kapanışları alt sayfada (Premium, 2026-11-10).
///
/// ## Neden ortak bileşen
/// Grafik iki yüzeyde var: portföy varlık detayı (`asset_detail_screen`) ve
/// varlık sayfası (`varlik_sayfasi`). Satır ve sayfa bir kez yazılır, iki
/// kabuk kendi elindeki seriyi ve fiyat biçimini verir — "aynı varlık sayfası
/// iki kez yazılmış" hatası (Sadeleştirme 2 madde 6) burada tekrarlanmasın.
///
/// ## Veri
/// [seri] grafiğin şu an çizdiği seçili dönem serisidir; yeni istek yok.
/// Satırlar dokunuşta bir kez hesaplanır ([gunlukKapanislar], saf), `build`
/// içinde değil.
///
/// ## GÜNLÜK dönemde satır yok (karar)
/// Gün içi seri 5 dakikalık ve tek (ya da birkaç) günü kapsar: gün sonu
/// tablosu bir-iki satır olurdu, "geçmiş fiyatlar" diye açılan sayfada boşluk
/// gibi okunur. Gün içinde başka dönemlerin serisinden kapanış ödünç almak
/// da tablo ile grafiği ayrıştırırdı (tek kaynak). Bu yüzden [gunIci]
/// iken satır çizilmez; kullanıcı 1H ve üstünde görür.
///
/// ## Premium kilidi — mevcut desen
/// Temettü verimi / yıllık getiri / kur ayrışması satırlarıyla aynı:
/// `premiumOzellikleriGorunurProvider` false (paywall kapalı, admin değil)
/// → hiçbir şey; `premiumKilitliProvider` → aynı yerde [KilitSatiri]
/// (kaynak `gecmis_fiyatlar`, paywall rapor kartıyla açılır); aksi halde
/// açık satır. Paywall kapalıyken canlı kullanıcının ekranı birebir eskisi.
class GecmisFiyatlarSatiri extends ConsumerWidget {
  const GecmisFiyatlarSatiri({
    super.key,
    required this.seri,
    required this.bicim,
    required this.donemEtiketi,
    this.gunIci = false,
  });

  /// Grafiğin seçili dönem serisi (epoch ms → birim fiyat).
  final Map<int, double> seri;

  /// Ekrandaki büyük fiyatın biçimi: tablo aynı hane ve simgeyle yazar.
  final NumberFormat bicim;

  /// Sayfanın alt satırındaki dönem adı ("1 yıl").
  final String donemEtiketi;

  final bool gunIci;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (gunIci || seri.length < 2) return const SizedBox.shrink();
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return KilitSatiri(
        metin: l.gecmisFiyatlarKilitli,
        kaynak: 'gecmis_fiyatlar',
        ozellik: 'gecmis_fiyatlar',
        kilitEtiketi: l.goalDateLockedLabel,
      );
    }
    final c = context.c;
    return SandikTappable(
      onTap: () => _ac(context),
      semanticLabel: l.gecmisFiyatlarSatiri,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Row(
          children: [
            Icon(Icons.table_rows_outlined,
                size: SandikSpace.md, color: c.text58),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(l.gecmisFiyatlarSatiri,
                  style: context.t.bodySmall
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: SandikSpace.lgs, color: c.text58),
          ],
        ),
      ),
    );
  }

  void _ac(BuildContext context) {
    final satirlar = gunlukKapanislar(seri);
    if (satirlar.isEmpty) return;
    final l = context.l10n;
    showSandikSheet<void>(
      context: context,
      baslik: l.gecmisFiyatlarBaslik,
      altMetin: l.gecmisFiyatlarAltMetin(donemEtiketi, '${satirlar.length}'),
      builder: (_) => GecmisFiyatlarTablosu(satirlar: satirlar, bicim: bicim),
    );
  }
}

/// Sayfanın gövdesi: sütun başlıkları, satırlar (en yeni üstte), dipnot.
///
/// Yön yalnız renkle verilmez: ok ikonu + işaretli yüzde (`fmtPctIsaretli`),
/// ekran okuyucu satırı tek cümle okur ("… önceki kapanışa göre %1,20 artış").
class GecmisFiyatlarTablosu extends StatelessWidget {
  const GecmisFiyatlarTablosu(
      {super.key, required this.satirlar, required this.bicim});

  final List<GunlukKapanis> satirlar;
  final NumberFormat bicim;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final yatay = SandikSpace.screenH(context);
    final baslikStili = context.t.labelSmall?.copyWith(color: c.text58);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(yatay, SandikSpace.md, yatay, 0),
          child: ExcludeSemantics(
            child: _SatirDuzeni(
              tarih: Text(l.gecmisFiyatlarTarih, style: baslikStili),
              kapanis: Text(l.gecmisFiyatlarKapanis, style: baslikStili),
              degisim: Text(l.gecmisFiyatlarDegisim, style: baslikStili),
            ),
          ),
        ),
        Divider(height: SandikSpace.md, color: c.hairline),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(horizontal: yatay),
            itemCount: satirlar.length,
            separatorBuilder: (context, i) =>
                Divider(height: SandikSpace.xxs, color: c.hairline),
            itemBuilder: (context, i) =>
                _KapanisSatiri(satir: satirlar[i], bicim: bicim),
          ),
        ),
        Padding(
          padding:
              EdgeInsets.fromLTRB(yatay, SandikSpace.sm, yatay, SandikSpace.lg),
          child: Text(l.gecmisFiyatlarDipnot,
              style: context.t.bodySmall?.copyWith(color: c.text58)),
        ),
      ],
    );
  }
}

class _KapanisSatiri extends StatelessWidget {
  const _KapanisSatiri({required this.satir, required this.bicim});

  final GunlukKapanis satir;
  final NumberFormat bicim;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final tarih = fmtTarihAraligi(satir.gun, satir.gun,
        dil: context.tarihDili, kisa: true);
    final fiyat = bicim.format(satir.kapanis);
    final pct = satir.degisimPct;
    // Düz eşiği: iki haneli yüzdede "%0,00" yazılan değişim yön taşımaz.
    final duz = pct != null && pct.abs() < 0.005;
    final IconData ikon;
    final Color renk;
    final String metin;
    final String okunus;
    if (pct == null) {
      ikon = Icons.remove_rounded;
      renk = c.text36;
      metin = '—';
      okunus = l.gecmisFiyatlarOncekiYok;
    } else if (duz) {
      ikon = Icons.remove_rounded;
      renk = c.text58;
      metin = fmtPct(0);
      okunus = l.gecmisFiyatlarDegismedi;
    } else {
      ikon =
          pct > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      renk = pct > 0 ? c.gain : c.loss;
      metin = fmtPctIsaretli(pct);
      okunus = pct > 0
          ? l.gecmisFiyatlarArtis(fmtPct(pct.abs()))
          : l.gecmisFiyatlarDusus(fmtPct(pct.abs()));
    }
    final sayi = context.t.numSmall;
    return Semantics(
      label: l.gecmisFiyatlarSatirA11y(tarih, fiyat, okunus),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
        child: _SatirDuzeni(
          tarih: Text(tarih,
              style: context.t.bodyMedium?.copyWith(color: c.text90)),
          kapanis: Text(fiyat, style: sayi.copyWith(color: c.text90)),
          degisim: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: SandikSpace.md, color: renk),
              const SizedBox(width: SandikSpace.xxs),
              Text(metin, style: sayi.copyWith(color: renk)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Üç sütun: tarih solda, kapanış ve değişim sağa yaslı. Sayılar büyük
/// yazıda (Dynamic Type ×2) kesilmez, sütununa sığacak kadar küçülür —
/// üç nokta bir fiyatı yanlış okuturdu.
class _SatirDuzeni extends StatelessWidget {
  const _SatirDuzeni(
      {required this.tarih, required this.kapanis, required this.degisim});

  final Widget tarih;
  final Widget kapanis;
  final Widget degisim;

  @override
  Widget build(BuildContext context) {
    Widget sag(Widget w) => FittedBox(
        fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: w);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: tarih),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(flex: 5, child: sag(kapanis)),
        const SizedBox(width: SandikSpace.sm),
        Expanded(flex: 4, child: sag(degisim)),
      ],
    );
  }
}
