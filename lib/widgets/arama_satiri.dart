import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/price_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'varlik_rozeti.dart';

/// Satırın gövdesi: tür noktası, ad, sembol · tür, fiyat + günlük değişim.
///
/// Açık (public) çünkü genel arama (bayrak `genel_arama`) "Piyasa" grubunu
/// AYNI satırla çizer: aynı varlık iki arama yüzeyinde iki farklı satır
/// (fiyat biçimi, sembol etiketi) göstermesin.
class AramaSatirKutusu extends StatelessWidget {
  const AramaSatirKutusu({
    super.key,
    required this.kimlik,
    required this.kotasyon,
    required this.sonu,
  });

  final VarlikKimligi kimlik;
  final YahooQuote? kotasyon;
  final Widget sonu;

  @override
  Widget build(BuildContext context) {
    final c = kimlik;
    final fiyat = aramaFiyatMetni(c, kotasyon);
    final pct = aramaGunlukYuzde(c, kotasyon);
    // Kabuk `SandikCard` (2. tur, 2026-10-08) — piksel aynı; 44pt alt
    // sınır kartın dışından verilir (eski `Container.constraints`).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: SandikCard(
        padding: const EdgeInsets.only(left: SandikSpace.smd),
        child: Row(
          children: [
            // Bayrak `goz_alici`: sembol rozeti; kapalıyken tür noktası.
            VarlikRozeti(type: c.type, ticker: c.ticker),
            const SizedBox(width: SandikSpace.sm2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium
                            ?.copyWith(color: context.c.text90)),
                    Text(
                        [
                          if (aramaSembolEtiketi(c) case final e?) e,
                          c.type.labelOf(context.l10n),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.labelSmall
                            ?.copyWith(color: context.c.text36)),
                  ],
                ),
              ),
            ),
            if (fiyat != null)
              Padding(
                padding: const EdgeInsets.only(left: SandikSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fiyat,
                        maxLines: 1,
                        style: context.t.bodySmall?.copyWith(
                            color: context.c.text90,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    if (pct != null)
                      Text(fmtPctIsaretli(pct),
                          maxLines: 1,
                          style: context.t.labelSmall?.copyWith(
                              color: pct.abs() < 0.005
                                  ? context.c.text36
                                  : context.signColor(pct),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                  ],
                ),
              ),
            const SizedBox(width: SandikSpace.xs),
            sonu,
          ],
        ),
      ),
    );
  }
}

/// Satırın ikinci satırındaki sembol; adı tekrar edecekse `null`.
///
/// Altın ürününde ad zaten "Çeyrek Altın"dır, sembol (`ALTIN_CEYREK`) bir
/// şey eklemez; kurda `USDTRY=X` Yahoo sözdizimidir, kullanıcı "USD" okur;
/// emtia vadelisinin kodu (`BZ=F`) anlamsızdır.
String? aramaSembolEtiketi(VarlikKimligi c) {
  final t = c.ticker;
  if (t.startsWith('ALTIN_')) return null;
  if (t.endsWith('TRY=X')) return t.replaceAll('TRY=X', '');
  if (t.endsWith('=F')) return null;
  return c.kisaEtiket;
}

/// Satırda gösterilecek fiyat; bilinmiyorsa `null` (yazılmaz). Saatli
/// bildirim seçicisi ekran okuyucu etiketine de yazar (satırla aynı metin).
///
/// Endeks puandır: para simgesi ve kuruş anlamsız (piyasa bandıyla aynı
/// kural). Diğerleri kotasyonun kendi para birimiyle — emtia `$`, kalanı `₺`.
/// Kur çiftinin fiyatı KARŞI para birimindedir: `USDTRY=X` → "₺49,00"
/// ([kotasyonSembolu]; eskiden miktar sembolü "$49,00" yazılıyordu).
String? aramaFiyatMetni(VarlikKimligi c, YahooQuote? q) {
  final f = q?.regularMarketPrice;
  if (f == null || !f.isFinite || f <= 0) return null;
  if (endeksMi(c.ticker)) {
    return fmtNum(f, digits: 0);
  }
  // Ondalık [fiyatBicimi]'nden (sabit 2 hane: SHIB "₺0,00").
  return fmtFiyat(f,
      azami: c.type.fiyatHassasiyeti,
      symbol: kotasyonSembolu(c.ticker, c.currency));
}

/// Satırda gösterilecek günlük yüzde; bilinmiyorsa `null`.
///
/// Altında `altinGunlukYuzdeTam` kuralı: bir ayar bile yüzde taşımıyorsa
/// HİÇBİR altın ürün yüzdesi gösterilmez — yoksa aynı altın bu ekranda ve
/// Performans'ta iki farklı yüzde gösterirdi (bkz. `PriceService`).
@visibleForTesting
double? aramaGunlukYuzde(VarlikKimligi c, YahooQuote? q) {
  final p = q?.regularMarketChangePercent;
  if (p == null || !p.isFinite) return null;
  if (FiyatKaynagi.altinMi(c.ticker) &&
      !PriceService.instance.altinGunlukYuzdeTam) {
    return null;
  }
  return p;
}

