import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/kur_ayrismasi.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart' show fmtTRYFiyat, tryFormatter;
import 'para_akisi_karti.dart' show KilitSatiri;

/// "Fiyattan +₺X · Kurdan +₺Y" — varlık detayı pozisyon kartında enflasyon
/// satırının altı (Ar-Ge 2026-11-07 #1, Premium). Hesap [kurAyrismasi]'nda.
///
/// ## Görünürlük (temettü "maliyetine göre verim" satırıyla aynı desen, #309)
/// - Premium özellikleri görünmüyorsa (paywall kapalı, admin değil) hiçbir
///   şey çizilmez.
/// - Kilitliyse [KilitSatiri] (kaynak `kur_ayrismasi` → paywall'da X-Ray
///   kartı: "paran gerçekte nerede"). Kilit de ancak hesaplanacak sayı
///   varken çıkar — çağıran [ayrisma] `null` ise bu widget'ı kurmaz;
///   kaydı olmayana "Premium'da kur ayrışman var" demek boş vaat olurdu.
/// - Açıksa iki işaretli tutar. Anlam işarette (+/−) ve kelimede
///   ("Fiyattan/Kurdan"); renk yalnız pekiştirir (HIG renk körlüğü).
///
/// Tutarlar kartın öteki TL tutarları gibi [baz]'dan geçer: bakiye gizliyken
/// `₺••••` yazar, baz birim seçiliyse o birimde. İşaret gizli modda da
/// kalır — kartın "Toplam kâr/zarar" satırı da öyle (`kazancSatiri`).
///
/// Dokununca (2026-11-13) [KurAyrismasiSayfasi] açılır: iki sayının
/// kaynağı gerçek sayılarla. Eskiden dokunulmazdı; "kurdan −₺1.200" nereden
/// çıktı sorusu ekranda cevapsızdı. Satır ≥44 pt, sonda chevron (sistem
/// kalıbı: dokunulabilir satır), ekran okuyucuya düğme + tek cümle.
class KurAyrismasiSatiri extends ConsumerWidget {
  const KurAyrismasiSatiri(
      {super.key, required this.ayrisma, required this.baz});

  final KurAyrismasi ayrisma;
  final BazPara baz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Padding(
        padding: const EdgeInsets.only(top: SandikSpace.xs),
        child: KilitSatiri(
          metin: l.fxSplitLocked,
          kaynak: 'kur_ayrismasi',
          ozellik: 'kur_ayrismasi',
          kilitEtiketi: l.goalDateLockedLabel,
        ),
      );
    }
    final c = context.c;
    final bicim = baz.formatter(digits: 0);
    String isaretli(double v) {
      if (v.abs().round() == 0) return bicim.format(0);
      return '${v > 0 ? '+' : '−'}${bicim.format(v.abs())}';
    }

    Color renk(double v) =>
        v.abs().round() == 0 ? c.text58 : (v > 0 ? c.gain : c.loss);

    final fiyat = isaretli(ayrisma.fiyatEtkisi);
    final kur = isaretli(ayrisma.kurEtkisi);
    final stil = context.t.labelSmall?.copyWith(color: c.text58);
    final vurgu = stil?.copyWith(fontWeight: FontWeight.w600);
    return Semantics(
      container: true,
      button: true,
      label: l.fxSplitA11y(fiyat, kur),
      hint: l.fxSplitOpenHint,
      excludeSemantics: true,
      child: SandikTappable(
        onTap: () =>
            KurAyrismasiSayfasi.goster(context, ayrisma: ayrisma, baz: baz),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Icon(Icons.currency_exchange_rounded,
                  size: SandikSpace.md, color: c.text58),
              const SizedBox(width: SandikSpace.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: stil,
                    children: [
                      TextSpan(text: '${l.fxSplitPrice} '),
                      TextSpan(
                          text: fiyat,
                          style: vurgu?.copyWith(
                              color: renk(ayrisma.fiyatEtkisi))),
                      TextSpan(text: ' · ${l.fxSplitFx} '),
                      TextSpan(
                          text: kur,
                          style:
                              vurgu?.copyWith(color: renk(ayrisma.kurEtkisi))),
                    ],
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: SandikSpace.lgs, color: c.text58),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alış kuru kayıtlı olmayan döviz pozisyonunda ayrışmanın yerine tek
/// nötr satır (2026-11-13). Eskiden satır sessizce kayboluyordu; Premium
/// kullanıcı nedenini öğrenmiyordu. Kapı [kurAyrismasiAlisKuruEksik].
///
/// Gezinme YOK: varlık ekranından tek lotu düzenleyen basit bir giriş yok
/// ("Varlığı güncelle" bayraklı ve tüm lotları tek kayda indirir; alış
/// kurunu düzeltmek için o ağır akışa göndermek yanlış olurdu). Satır yolu
/// söyler, chevron koymaz — dokunulamayan satırda chevron yalan olurdu.
///
/// Yalnız Premium AÇIKKEN: ücretsiz kullanıcıda davranış değişmez (eskiden
/// de hiçbir şey çizilmiyordu; kilitli kullanıcıya "kuru ekle" demek,
/// ekleyince yine kilit görecek birine boş iş vermek olurdu).
class KurAyrismasiEksikSatiri extends ConsumerWidget {
  const KurAyrismasiEksikSatiri({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider) ||
        ref.watch(premiumKilitliProvider)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.currency_exchange_rounded,
              size: SandikSpace.md, color: c.text58),
          const SizedBox(width: SandikSpace.xs),
          Expanded(
            child: Text(context.l10n.fxSplitMissingRate,
                style: context.t.labelSmall?.copyWith(color: c.text58)),
          ),
        ],
      ),
    );
  }
}

/// "Kâr nereden geldi" sayfası: [KurAyrismasi]'nın kaynak sayıları.
///
/// Sayfa hesap YAPMAZ; her sayı modelde üretildi (`kurAyrismasi`), burada
/// yalnız biçimlenir. TL tutarları satırla aynı [baz]'dan geçer — bakiye
/// gizliyken maskeli; döviz tutarları da aynı gizlilikle maskelenir (tutar
/// tutardır). Kurlar kamuya açık piyasa verisi, maskelenmez.
class KurAyrismasiSayfasi extends StatelessWidget {
  const KurAyrismasiSayfasi(
      {super.key, required this.ayrisma, required this.baz});

  final KurAyrismasi ayrisma;
  final BazPara baz;

  static Future<void> goster(BuildContext context,
          {required KurAyrismasi ayrisma, required BazPara baz}) =>
      showSandikSheet<void>(
        context: context,
        baslik: context.l10n.fxSplitSheetTitle,
        builder: (_) => KurAyrismasiSayfasi(ayrisma: ayrisma, baz: baz),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final bicim = baz.formatter(digits: 0);
    String isaretli(double v) {
      if (v.abs().round() == 0) return bicim.format(0);
      return '${v > 0 ? '+' : '−'}${bicim.format(v.abs())}';
    }

    final s = ayrisma.sembol;
    String doviz(double v) {
      if (baz.gizli) return '$s••••';
      final metin = tryFormatter(digits: 0, symbol: s).format(v.abs());
      return v < 0 ? '−$metin' : metin;
    }

    String kurMetni(double v) => fmtTRYFiyat(v);
    final fark = ayrisma.kurFarki;
    final farkMetni =
        '${fark > 0 ? '+' : (fark < 0 ? '−' : '')}${kurMetni(fark.abs())}';

    Widget satir(String baslik, String deger, {String? alt}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: Text(baslik,
                          style:
                              context.t.bodyMedium?.copyWith(color: c.text90))),
                  const SizedBox(width: SandikSpace.sm),
                  Text(deger,
                      style: context.t.bodyMedium?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w600)),
                ],
              ),
              if (alt != null) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(alt,
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
              ],
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.lg, 0, SandikSpace.lg, SandikSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          satir(
              l.fxSplitSheetRate,
              l.fxSplitSheetRateValue(
                  kurMetni(ayrisma.alisKuru), kurMetni(ayrisma.guncelKur))),
          Divider(height: 1, thickness: 1, color: c.hairline),
          satir(l.fxSplitPrice, isaretli(ayrisma.fiyatEtkisi),
              alt: l.fxSplitSheetPriceBody(
                  doviz(ayrisma.dovizKar), kurMetni(ayrisma.alisKuru))),
          satir(l.fxSplitFx, isaretli(ayrisma.kurEtkisi),
              alt: l.fxSplitSheetFxBody(doviz(ayrisma.dovizDeger), farkMetni)),
          Divider(height: 1, thickness: 1, color: c.hairline),
          satir(l.fxSplitSheetTotal, isaretli(ayrisma.toplam)),
        ],
      ),
    );
  }
}
