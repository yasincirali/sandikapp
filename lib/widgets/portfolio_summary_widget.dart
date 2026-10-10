import 'package:flutter/material.dart';
import '../providers/portfolio_provider.dart';
import '../utils/money_format.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';
import 'degisim_vurgusu.dart';

class PortfolioSummaryWidget extends StatelessWidget {
  final PortfolioState state;
  final bool hideBalance;

  /// Gösterim birimi (Faz 3.2); varsayılan ₺ — testler ve eski çağıranlar
  /// değişmeden çalışır.
  final BazPara baz;

  /// Başlık satırının sağı — görünüm çipi (Ben/ortak/Birlikte). Yoksa boş.
  final Widget? trailing;

  /// Toplamın kime ait olduğu (Ben / ortak / Birlikte). Değişince toplam
  /// değer vurgusu YAKILMAZ — görünüm değişimi fiyat hareketi değildir.
  final Object? vurguKimligi;

  /// Toplamın KISMİ olduğunu söyleyen tek satır (0135): ortak bu kullanıcıya
  /// yalnız bazı portföylerini gösteriyorsa ortak/Birlikte görünümünde
  /// "Yalnız paylaştığı portföyler". Yoksa satır yok, kart birebir eski.
  ///
  /// Neden: kısmi toplam etiketsiz kalırsa ortağın BÜTÜN varlığı sanılır
  /// (ve Birlikte "hanenin toplamı" diye okunur). Kendi görünümünde hiç
  /// çizilmez — ana sayfa kendi toplamında hep bütün portföyleri gösterir.
  final String? kapsamNotu;

  const PortfolioSummaryWidget({
    super.key,
    required this.state,
    this.hideBalance = false,
    this.baz = const BazPara.lira(),
    this.trailing,
    this.vurguKimligi,
    this.kapsamNotu,
  });

  @override
  Widget build(BuildContext context) {
    final isPos = state.gainLoss >= 0;
    final gainColor = isPos ? context.c.gain : context.c.loss;
    final tryFmt = baz.formatter(digits: 0);
    final w = MediaQuery.of(context).size.width;
    final heroFontSize = w < 360
        ? 28.0
        : w < 400
            ? 32.0
            : 38.0;
    final subFontSize = w < 360 ? 12.0 : 14.0;
    final hPad = w < 360 ? 16.0 : 24.0;

    // Ekran okuyucu bu kartı tek bir cümle olarak okumalı. Aksi halde
    // "TOPLAM NET VARLIK", "₺1.240.000", "+₺32.000", "%2,7" dört ayrı
    // odak durağı olur ve aralarındaki ilişki kaybolur. Yön (artı/eksi)
    // metne yazılır: kazanç/kayıp yalnızca renkle anlatılırsa renk körü
    // kullanıcı ile ekran okuyucu kullanıcısı aynı bilgiyi alamaz.
    final semanticSummary = hideBalance
        ? context.l10n.totalNetHidden
        : [
            context.l10n.totalNetWorth(tryFmt.format(state.totalValue)),
            if (kapsamNotu != null) kapsamNotu!,
            // "Maliyetine göre" (2026-10-01): bu rakam MALİYETE göre kâr —
            // dönem getirisi (Özet, para ağırlıklı) değil. Çıplak "kazanç"
            // iki sayıyı aynı soru sandırıyordu.
            if (state.totalCost > 0)
              '${isPos ? context.l10n.costBasisGain : context.l10n.costBasisLoss} '
                  '${tryFmt.format(state.gainLoss.abs())}, '
                  '${fmtPct(state.gainLossPercentage.abs(), digits: 2)}',
            if (state.totalDividend.abs() >= 0.005)
              '${context.l10n.includedDividend}'
                  '${tryFmt.format(state.totalDividend)}',
            if (state.hasRealized)
              '${context.l10n.realisedFromSalesSemantics}'
                  '${state.realizedGainLoss >= 0 ? context.l10n.gainWord : context.l10n.lossWord} '
                  '${tryFmt.format(state.realizedGainLoss.abs())}',
          ].join(', ');

    return Semantics(
      container: true,
      label: semanticSummary,
      child: ExcludeSemantics(
        // BackdropFilter + ClipRRect KALKTI (animasyon denetimi, 2026-09-30):
        // kartın arkasında düz arka plan rengi var, bulanıklık görünmüyordu;
        // kart kaydırmayla hareket ettiği için her karede arka plan okuması +
        // blur + kırpma ödeniyordu. Köşeleri kartın kendi `borderRadius`'u
        // yuvarlıyor. Yerine RepaintBoundary: fiyat tikinde kart kendi
        // katmanında yeniden çizilir, sayfanın geri kalanı çizilmez.
        child: RepaintBoundary(
          // Stack: yenileme çizgisi kartın ALT BOŞLUĞUNA bindirilir (bkz.
          // aşağıdaki `Positioned`).
          child: Stack(
            children: [
          KeyedSubtree(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
              decoration: BoxDecoration(
                // Hero kart sabit koyu yeşildi; light modda ekranın geri
                // kalanına ait olmayan bir levha gibi duruyordu. Artık
                // yükseklik moda göre kurulur: dark'ta yarı saydam koyu
                // yüzey, light'ta beyaz yüzey + gölge.
                color: context.isLight
                    ? context.c.surface2
                    : const Color(0xFF14332B).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(SandikRadius.lg),
                border: Border.all(
                  color: context.isLight
                      ? context.c.hairline
                      : context.c.gain.withValues(alpha: 0.18),
                  width: 1.0,
                ),
                boxShadow: context.isLight
                    ? context.c.cardShadow
                    : [
                        BoxShadow(
                          color: context.c.golge.withValues(alpha: 0.22),
                          blurRadius: 28,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              // Bakiyeyi gizle/göster temettü ve gerçekleşen satırlarını
              // kaldırıp geri koyar; kart eskiden tek karede kısalıyordu.
              // Yalnız bu satırlar değişince oynar (fiyat tiki yüksekliği
              // değiştirmez → maliyet yok).
              child: _BoyGecisi(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'TOPLAM NET VARLIK',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            // Alfa düşürmek kontrastı da düşürür. Light'ta tam
                            // opak gain (5.14:1) kullanılır; dark'ta zemin zaten
                            // koyu olduğu için hafif yumuşatma güvenli.
                            color: context.isLight
                                ? context.c.gain
                                : context.c.gain.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      // Görünüm çipi (Ben/ortak/Birlikte) — 2026-09-21'de
                      // kendi satırından buraya; kart "kimin toplamı"nı
                      // başlığında söyler.
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    // Fiyat turu toplamı değiştirince kısa renk vurgusu
                    // (`DegisimVurgusu`, 2026-09-29). Karşılaştırma TRY
                    // toplamı üzerinden: gösterim birimi değişimi yakmaz.
                    child: DegisimVurgusu(
                      deger: state.totalValue,
                      renk: context.c.gold,
                      kimlik: vurguKimligi,
                      etkin: !hideBalance,
                      builder: (context, renk) => Text(
                        hideBalance ? '••••••' : tryFmt.format(state.totalValue),
                        style: context.t.numLarge.copyWith(
                          fontSize: heroFontSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: renk,
                        ),
                      ),
                    ),
                  ),
                  if (kapsamNotu != null)
                    Padding(
                      padding: const EdgeInsets.only(top: SandikSpace.xxs),
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off_outlined,
                              size: 14, color: context.c.text58),
                          const SizedBox(width: SandikSpace.xxs),
                          Flexible(
                            child: Text(
                              kapsamNotu!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.bodySmall
                                  ?.copyWith(color: context.c.text58),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  // Satırın ADI (2026-10-01, kullanıcı kararı "tek getiri
                  // dili"): aşağıdaki tutar ve yüzde MALİYETE göre kâr —
                  // Özet'in dönem getirisi (para ağırlıklı) başka bir soru.
                  // Etiketsiz rakam iki sayının aynı şeyi ölçtüğünü
                  // düşündürüyordu. Hesap değişmedi.
                  if (state.totalCost > 0) ...[
                    Text(
                      isPos
                          ? context.l10n.costBasisGain
                          : context.l10n.costBasisLoss,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelSmall
                          ?.copyWith(color: context.c.text58),
                    ),
                    const SizedBox(height: SandikSpace.xxs),
                  ],
                  if (state.totalCost > 0)
                    Row(
                      children: [
                        if (!hideBalance) ...[
                          Icon(
                            isPos
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                            color: gainColor,
                            size: 20,
                          ),
                          Flexible(
                            child: Text(
                              '${isPos ? '+' : ''}${tryFmt.format(state.gainLoss)}',
                              style: context.t.numSmall.copyWith(
                                fontSize: subFontSize,
                                fontWeight: FontWeight.w600,
                                color: gainColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            // U14 (2026-09-23 denetimi): 3 hane "%0,000"
                            // gürültüsüydü; uygulamanın yüzde standardı 2.
                            fmtPct(state.gainLossPercentage),
                            style: context.t.numSmall.copyWith(
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: gainColor,
                            ),
                          ),
                        ] else
                          Text(
                            '•••• / ••••',
                            style: context.t.numSmall.copyWith(
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: context.c.text36,
                            ),
                          ),
                      ],
                    ),
                  // Satışlardan gerçekleşen K/Z — yalnızca satış varsa.
                  // Üstteki rakam "bugün satsan" (gerçekleşmemiş); bu satır
                  // "zaten sattın". İkisini karıştırmak en sık sorulan
                  // "neden toplam kârım tutmuyor" sorusunun kaynağıydı.
                  // Temettü AÇIKÇA yazılır — üstteki kâr/zarar onu İÇERİR.
                  //
                  // Denetim bulgusu (2026-09-22): `state.gainLoss` temettüyü
                  // dahil ediyor, `Position.gainLoss` etmiyor. Hesap doğru
                  // (biri "toplam getirim", diğeri "bu pozisyonun fiyat
                  // hareketi") ama ekran bunu SÖYLEMİYORDU: kullanıcı
                  // pozisyon satırlarını toplayınca üst rakamı tutturamıyordu.
                  //
                  // "Satışlardan gerçekleşen" satırı zaten aynı sorunu
                  // (`neden toplam kârım tutmuyor`) çözmek için eklenmişti;
                  // temettü o listede eksikti.
                  if (state.totalDividend.abs() >= 0.005 && !hideBalance)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${context.l10n.includedDividend}'
                        '+${tryFmt.format(state.totalDividend)}',
                        style: context.t.bodySmall?.copyWith(
                          color: context.c.gain,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (state.hasRealized && !hideBalance)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${context.l10n.realisedFromSales}'
                        '${state.realizedGainLoss >= 0 ? '+' : ''}'
                        '${tryFmt.format(state.realizedGainLoss)}',
                        style: context.t.bodySmall?.copyWith(
                          color: context.signColor(state.realizedGainLoss),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              ),
            ),
          ),
              // Yenileme çizgisi AKIŞIN DIŞINDA: eskiden Column'a 9 pt'lik
              // satır olarak ekleniyordu — her fiyat yenilemesinde kart
              // uzayıp kısalıyor, altındaki ana sayfa iki kez zıplıyordu
              // (animasyon denetimi 2026-10-01). Kartın 20 pt'lik alt
              // boşluğuna oturur; yerleşim hiç değişmez.
              if (state.isLoading)
                Positioned(
                  left: hPad,
                  right: hPad,
                  bottom: 10,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    color: context.c.amberFill,
                    minHeight: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartın yükseklik geçişi; hareketi azalt açıkken HİÇ `AnimatedSize` kurmaz.
///
/// ## Neden (integration kırmızısı, 2026-10-01)
/// Sıfır süreli `AnimatedSize` boyut değişiminde kendi
/// `performLayout`'u içinden denetleyiciyi `forward()` eder; sıfır sürede
/// denetleyici aynı karede biter, dinleyicisi `markNeedsLayout` çağırır ve
/// Flutter "RenderAnimatedSize was mutated in its own performLayout"
/// assert'iyle düşer. Animasyonları kapalı CI emülatöründe (ve hareketi
/// azalt açık cihazda) varlık eklenince kart uzadığı anda duman testi
/// buradan kırılıyordu. Süre sıfırsa geçiş zaten yok: çocuğu doğrudan koy.
class _BoyGecisi extends StatelessWidget {
  const _BoyGecisi({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (SandikMotion.stateOf(context) == Duration.zero) return child;
    return AnimatedSize(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.move,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
