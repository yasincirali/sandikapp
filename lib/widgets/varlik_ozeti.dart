import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'donem_istatistik.dart' show donemDuzMu;
import 'varlik_baslik_hero.dart';
import 'para_metni.dart';

/// Varlık yüzeylerinin ORTAK üst özeti: başlık (kısa etiket + "ad · tür")
/// ve fiyat bloğu (etiket, büyük fiyat, dönem değişimi satırı).
///
/// ## Neden (Sadeleştirme 2, madde 6 — "aynı varlık sayfası iki kez
/// yazılmış", kullanıcı 2026-10-04)
/// Portföy varlık detayı (`asset_detail_screen.dart`, tam ekran) ile varlık
/// sayfası (`varlik_sayfasi.dart`, alt sayfa) A tasarımından beri aynı üst
/// düzeni çiziyor ve ikisi bu düzeni AYRI AYRI yazıyordu: aynı stil zinciri,
/// aynı "%x · +₺y · dönem" biçimi, aynı düz-değişim kuralı. İlk düzeltmede
/// ayrışırlardı (bu projede tekrar eden hata sınıfı; `donem_istatistik.dart`
/// ızgara/aralık için aynı kararı verdi). Burada tek kez yazılır, iki kabuk
/// da kullanır.
///
/// ## Sınır — sayı HESAPLANMAZ
/// `donem_istatistik.dart` ile aynı ilke: her ekran kendi kaynağından hazır
/// değeri verir. Detay ekranı yüzdeyi BİRİM seriden ve canlı birim fiyattan
/// (`asset_detail/ozet.dart`), varlık sayfası sembol serisinden
/// (`DonemIstatistigi`) ölçer. Bu iki veri yolu bilinçli olarak ayrı kaldı:
/// birleştirmek ya varlık sayfasına `Asset` sokar (`varlik_sayfasi_test`'in
/// yasakladığı sızıntı) ya da detay ekranının "grafik = 1 birim, tutar =
/// piyasa etkisi" sözleşmesini bozar. Ortak olan yalnız GÖRÜNÜŞ ve biçim.

/// Varlık başlığı — kısa etiket (THYAO) + "ad · tür" alt satırı.
class VarlikBasligi extends StatelessWidget {
  const VarlikBasligi({
    super.key,
    required this.kimlik,
    this.adTekrariniAtla = false,
    this.semantikEtiket,
    this.heroEtiketi,
  });

  /// Portföy satırından gelen başlık uçuşunun etiketi (bkz.
  /// `varlik_baslik_hero.dart`); `null` → uçuş yok. Yalnız kısa etiket uçar.
  final Object? heroEtiketi;

  final VarlikKimligi kimlik;

  /// Sembolü olmayan (elle fiyatlanan, mevduat) varlıkta kısa etiket adın
  /// kendisidir; alt satırda adı tekrarlamak "Kadıköy daire / Kadıköy
  /// daire · Diğer" gibi okunur. `true` iken o durumda alt satır yalnız
  /// türü yazar. Portföy varlık detayı verir; varlık sayfası vermez —
  /// orada açılan varlıkların sembolü vardır ve davranış birebir eski kalır.
  final bool adTekrariniAtla;

  /// Verilirse başlık tek bir ekran okuyucu başlığı olarak okunur (detay
  /// ekranı: "THYAO performansı"); `null` → iki satır ayrı okunur.
  final String? semantikEtiket;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // ABD hissesi: "Apple · Hisse · ABD". Portföy lot'u alt kategoriyle
    // (`'abd'`), aramadan açılan kimlik USD kotasyonla tanınır — ikincisi
    // bayrağa bağlı: bayraktan önce elle USD girilmiş hisse için başlık
    // birebir eski kalsın.
    final abd = kimlik.type == AssetType.hisse &&
        (kimlik.subCategory == StockSubCategory.abd.name ||
            (RemoteConfigService.instance.abdHisse &&
                kimlik.currency.toUpperCase() == 'USD'));
    final tur = abd
        ? '${kimlik.type.labelOf(l)} · ${l.stockMarketUs}'
        : kimlik.type.labelOf(l);
    final kolon = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VarlikBaslikHero(
          etiket: heroEtiketi,
          child: Text(
            kimlik.kisaEtiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: context.c.text90),
          ),
        ),
        Text(
          adTekrariniAtla && kimlik.kisaEtiket == kimlik.name
              ? tur
              : '${kimlik.name} · $tur',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
      ],
    );
    final etiket = semantikEtiket;
    if (etiket == null) return kolon;
    return Semantics(
      header: true,
      label: etiket,
      excludeSemantics: true,
      child: kolon,
    );
  }
}

/// Fiyat bloğunun dönem değişimi satırı: metin ve rengi.
typedef DonemDegisimSatiri = ({String metin, Color renk});

/// "+%2,66 · +₺8,00 · 1 yıl" satırını kurar — iki varlık yüzeyinin TEK
/// biçimi.
///
///   · [pct] `null` → boş satır (yer tutulur, yerleşim zıplamaz).
///   · düz değişim → "1 yıl boyunca değişmedi", nötr renk. [duz] verilmezse
///     [donemDuzMu] (= `DonemIstatistigi.isFlat` eşiği).
///   · [fark] `null` → yalnız yüzde (mevduat: birim fark anlamsız).
DonemDegisimSatiri donemDegisimSatiri(
  BuildContext context, {
  required double? pct,
  required String donem,
  required NumberFormat bicim,
  double? fark,
  bool? duz,
}) {
  final l = context.l10n;
  if (pct == null) return (metin: ' ', renk: context.c.text36);
  if (duz ?? donemDuzMu(pct)) {
    return (metin: l.periodNoChange(donem), renk: context.c.text36);
  }
  final yuzde = fmtPctIsaretli(pct);
  if (fark == null) {
    return (metin: '$yuzde · $donem', renk: context.signColor(pct));
  }
  return (
    metin: '$yuzde · ${fark >= 0 ? '+' : '−'}'
        '${bicim.format(fark.abs())} · $donem',
    renk: context.signColor(pct),
  );
}

/// Güncel fiyat bloğu: üst etiket ("GÜNCEL FİYAT"), büyük fiyat ve dönem
/// değişimi satırı; isteğe bağlı etiket yanı ve alt satır.
class VarlikFiyatBlogu extends StatelessWidget {
  const VarlikFiyatBlogu({
    super.key,
    required this.etiket,
    required this.fiyat,
    required this.fiyatRengi,
    required this.degisim,
    this.etiketYani,
    this.altSatir,
    this.kimlik,
  });

  final String etiket;

  /// Fiyatın ait olduğu varlık; değişirse akan rakam dönmez (başka
  /// varlığın fiyatı "artış" değildir).
  final Object? kimlik;

  /// Etiketin yanında duran parça (detay: kripto gecikme etiketi).
  final Widget? etiketYani;

  /// Biçimlenmiş fiyat metni (bilinmiyorsa "—").
  final String fiyat;

  /// Detay ekranında altın (portföy kimliği), varlık sayfasında metin rengi.
  final Color fiyatRengi;

  final DonemDegisimSatiri degisim;

  /// Değişim satırının altındaki satır (detay: "Pozisyonun: …").
  final Widget? altSatir;

  @override
  Widget build(BuildContext context) {
    final ust = Text(
      etiket,
      style: context.t.labelSmall?.copyWith(
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
          color: context.c.text36),
    );
    final yan = etiketYani;
    final alt = altSatir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (yan == null)
          ust
        else
          Row(
            children: [
              ust,
              const SizedBox(width: SandikSpace.sm),
              Flexible(child: yan),
            ],
          ),
        const SizedBox(height: SandikSpace.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          // Bayrak `goz_alici`: değişen hane döner, ₺ ve kuruş geri çekilir
          // (gerekçe `para_metni.dart`). Kapalıyken düz metin, birebir eski.
          child: RemoteConfigService.instance.gozAlici
              ? ParaMetni(
                  fiyat,
                  kimlik: kimlik,
                  stil: context.t.numLarge.copyWith(color: fiyatRengi),
                )
              : Text(
                  fiyat,
                  maxLines: 1,
                  style: context.t.numLarge.copyWith(color: fiyatRengi),
                ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          degisim.metin,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.numSmall.copyWith(color: degisim.renk),
        ),
        if (alt != null) ...[
          const SizedBox(height: SandikSpace.xs2),
          alt,
        ],
      ],
    );
  }
}
