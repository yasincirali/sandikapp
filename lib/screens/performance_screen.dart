import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/chart_line_width.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/spot_lookup.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/zoomable_chart.dart';
import '../providers/preferences_provider.dart';
import '../widgets/fullscreen_chart_route.dart';
import 'signal_settings_screen.dart';
import '../models/signal_alert.dart';
import '../providers/signal_provider.dart';
import '../models/asset_categories.dart';
import '../services/tefas_service.dart';
import '../widgets/custom_loading_indicator.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class GoldTransaction {
  final DateTime date;
  final double gramChange;
  final String label;

  GoldTransaction({
    required this.date,
    required this.gramChange,
    required this.label,
  });
}

// ── Teknik Sinyal Paneli ─────────────────────────────────────────────────────

// ── Kayıtlı sinyal rozeti ────────────────────────────────────────────────────

/// Bu varlık için ÜRETİLMİŞ VE KAYDEDİLMİŞ son sinyal.
///
/// ## Neden ayrı bir kart
/// Ekranın altındaki [TechnicalSignalPanel] göstergeleri O AN yeniden
/// hesaplar. Kullanıcının bildirim olarak aldığı sinyal ise `signal_notifications`
/// tablosunda duran, ZAMAN DAMGALI bir kayıttır. İkisi aynı şey değildir:
/// panel "şu anda göstergeler ne diyor" sorusunu, bu kart "bana ne zaman ne
/// bildirildi" sorusunu yanıtlar.
///
/// Kullanıcı isteği (2026-09-10): "Sinyal bilgisi varsa varlık performans
/// ekranında gözükmeli." Kayıt yoksa kart HİÇ çizilmez — boş bir "sinyal yok"
/// kutusu ekranın en değerli yerini kaplardı.
///
/// ## Eşleştirme neden `positionKey` benzeri
/// Sinyal kaydı bir LOT id'si taşır (`assetId`) ve o lot bu ekrandaki
/// pozisyonun temsilcisi olmayabilir — kullanıcı aynı varlıktan birkaç kez
/// almış olabilir, sunucu da kendi temsilcisini seçiyor. Bu yüzden eşleşme
/// id ile DEĞİL, ticker + tür ile yapılır: sinyalin ürettiği şey zaten
/// sembole aittir.
class AssetSignalCard extends ConsumerStatefulWidget {
  const AssetSignalCard({super.key, required this.asset, this.onTap});

  final Asset asset;

  /// Şeride dokununca çağrılır — ekran bunu aşağıdaki tam panele kaydırmak
  /// için kullanır. Özet bir şerit, hangi göstergenin ne dediğini
  /// söylemez; kullanıcı merak ettiğinde detayın yolu bir dokunuş olmalı.
  final VoidCallback? onTap;

  /// [alerts] içinden bu varlığa ait EN YENİ kaydı seçer.
  ///
  /// Saf fonksiyon — widget kurmadan test edilir.
  static SignalAlert? sonSinyal(List<SignalAlert> alerts, Asset asset) {
    final ticker = asset.ticker.trim().toUpperCase();
    SignalAlert? best;
    for (final a in alerts) {
      if (a.assetType != asset.type) continue;
      final at = a.assetTicker.trim().toUpperCase();
      // Ticker'ı olmayan varlıklarda (altın alt kategorileri, "diğer")
      // isim eşleşmesine düşülür.
      final eslesti = ticker.isNotEmpty
          ? at == ticker
          : a.assetName.trim().toLowerCase() ==
              asset.name.trim().toLowerCase();
      if (!eslesti) continue;
      if (best == null || a.detectedAt.isAfter(best.detectedAt)) best = a;
    }
    return best;
  }

  @override
  ConsumerState<AssetSignalCard> createState() => _AssetSignalCardState();
}

class _AssetSignalCardState extends ConsumerState<AssetSignalCard> {
  /// Panelle AYNI fiyat serisi. `HistoryService` (tier, sembol) başına
  /// önbellekli olduğu için ikinci çağrı ağa çıkmaz — şerit ve panel aynı
  /// yanıtı paylaşır ve **aynı sayıyı** gösterir. Ayrı seri çekilseydi
  /// üstteki özet ile alttaki panel farklı sonuç verebilirdi.
  Future<List<double>>? _pricesFuture;
  String? _pricesKey;

  Future<List<double>> _loadPrices() {
    final key = '${widget.asset.ticker}|${widget.asset.type.name}';
    if (_pricesKey == key && _pricesFuture != null) return _pricesFuture!;
    _pricesKey = key;
    _pricesFuture = HistoryService.instance
        .getSymbolHistory(widget.asset.ticker, periodDays: 180)
        .then((map) {
      final keys = map.keys.toList()..sort();
      return [for (final k in keys) map[k]!];
    }).catchError((_) => <double>[]);
    return _pricesFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final alerts =
        ref.watch(signalProvider).valueOrNull ?? const <SignalAlert>[];
    final kayit = AssetSignalCard.sonSinyal(alerts, widget.asset);

    final prefs = ref.watch(indicatorPrefsProvider);
    final premium = ref.watch(premiumUnlockedProvider);
    final enabledIds = prefs[widget.asset.type] ??
        TechnicalAnalysisService.defaultEnabledFor(widget.asset.type);

    // Kullanıcı bu tür için hiçbir gösterge seçmemişse hesaplanacak bir
    // şey yok; alttaki panel bunu zaten açıklıyor, şeritte tekrar etmek
    // ekranın en değerli yerini bir uyarıya harcardı.
    if (enabledIds.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<double>>(
      future: _loadPrices(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _kabuk(
            renk: context.c.text36,
            child: Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: context.c.amberFill),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Sinyal hesaplanıyor…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ),
              ],
            ),
          );
        }

        final prices = snap.data ?? const <double>[];
        // Göstergelerin çoğu 20-26 nokta ister; 30 altı güvenilir değil.
        // Uydurma veriyle sinyal göstermektense hiç göstermemek doğru
        // (bkz. `TechnicalSignalPanel` — aynı eşik, aynı gerekçe).
        //
        // Kayıtlı bir bildirim VARSA yine de gösterilir: o sinyal geçmişte
        // gerçekten üretilmiş ve kullanıcıya gönderilmiştir; bugün seri
        // çekilemiyor diye onu saklamak bilgi gizlemek olurdu.
        if (prices.length < 30) {
          if (kayit == null) return const SizedBox.shrink();
          return _satir(
            signal: kayit.signal,
            lehte: kayit.signal == SignalType.sell
                ? kayit.sellCount
                : kayit.buyCount,
            toplam: kayit.buyCount + kayit.sellCount,
            guven: kayit.confidence,
            canli: false,
            kayit: kayit,
          );
        }

        final indicators = TechnicalAnalysisService.analyzeSeries(
          prices,
          widget.asset.type,
          enabledIds: enabledIds,
          premiumUnlocked: premium,
        );
        if (indicators.isEmpty) return const SizedBox.shrink();

        final ozet = TechnicalAnalysisService.summarize(indicators);
        return _satir(
          signal: ozet.signal,
          lehte:
              ozet.signal == SignalType.sell ? ozet.sellCount : ozet.buyCount,
          toplam: ozet.buyCount + ozet.sellCount,
          guven: ozet.confidence,
          canli: true,
          kayit: kayit,
        );
      },
    );
  }

  /// Şeridin dış kabuğu — dolgu, kenarlık, dokunma alanı.
  Widget _kabuk({required Color renk, required Widget child}) {
    final govde = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: SandikSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: renk.withValues(alpha: 0.28)),
      ),
      child: child,
    );
    if (widget.onTap == null) return govde;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: govde,
    );
  }

  /// Tek satırlık sinyal özeti.
  ///
  /// [canli] true ise göstergeler ŞU AN yeniden hesaplanmıştır; false ise
  /// gösterilen şey geçmişte kaydedilmiş bir bildirimdir. Ayrım kullanıcıya
  /// açıkça yazılır — "şu an yukarı yönlü" ile "üç gün önce yukarı sinyali
  /// gelmişti" aynı şey değildir.
  Widget _satir({
    required SignalType signal,
    required int lehte,
    required int toplam,
    required double guven,
    required bool canli,
    required SignalAlert? kayit,
  }) {
    final isBuy = signal == SignalType.buy;
    final isSell = signal == SignalType.sell;
    final renk = isBuy
        ? context.c.gain
        : isSell
            ? context.c.loss
            : context.c.text58;
    // Yasal not: kesin "AL/SAT" yerine trend yönü — ekranın geri kalanıyla
    // aynı dil (bkz. `TechnicalSignalPanel`).
    final etiket = isBuy
        ? 'YUKARI TREND'
        : isSell
            ? 'AŞAĞI TREND'
            : 'YATAY';
    final ikon = isBuy
        ? Icons.trending_up_rounded
        : isSell
            ? Icons.trending_down_rounded
            : Icons.remove_rounded;

    final detay = toplam > 0
        ? '$lehte/$toplam gösterge · güven %${guven.round()}'
        : 'güven %${guven.round()}';

    // Kayıtlı bildirim, CANLI özetten ayrı bir satırda durur. İkisi
    // çeliştiğinde (bildirim "yukarı" derken göstergeler bugün "aşağı"
    // diyorsa) bu fark kullanıcı için bilginin kendisidir — gizlemek
    // yerine yan yana gösteriyoruz.
    final kayitSatiri = (canli && kayit != null)
        ? 'Son bildirim: ${_kisaYon(kayit.signal)} · '
            '${DateFormat('d MMM', 'tr_TR').format(kayit.detectedAt)}'
        : null;

    return _kabuk(
      renk: renk,
      child: Row(
        children: [
          Icon(ikon, color: renk, size: 20),
          const SizedBox(width: 10),
          // Metin bloğu esner; sağdaki zaman etiketi sabit kalır. Uzun
          // varlık adlarında satır taşmasın diye Expanded şart.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: renk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
                if (kayitSatiri != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    kayitSatiri,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                canli
                    ? 'ŞU AN'
                    : DateFormat('d MMM', 'tr_TR').format(kayit!.detectedAt),
                style: context.t.labelMedium?.copyWith(
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w700,
                  color: context.c.text36,
                ),
              ),
              if (widget.onTap != null) ...[
                const SizedBox(height: 2),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: context.c.text36),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _kisaYon(SignalType s) => switch (s) {
        SignalType.buy => '▲ yukarı',
        SignalType.sell => '▼ aşağı',
        SignalType.neutral => '◆ yatay',
      };
}

// ── Aktif sinyal bölümü (ekranın en altı) ────────────────────────────────────

/// Bu varlık için GÖNDERİLMİŞ ve hâlâ geçerli sayılan son sinyal.
///
/// ## Neden var
/// Kullanıcı isteği (2026-09-10): push bildirimine dokunup bu ekrana gelen
/// kişi, en altta "bana ne bildirildi" sorusunun cevabını ayrıntısıyla
/// görmeli. Push yalnızca `assetId` taşır; ayrıntı burada okunur.
///
/// ## Üstteki şeritten farkı
/// [AssetSignalCard] ekranın ÜSTÜNDE tek satırlık bir özettir ve öncelikle
/// CANLI hesabı gösterir. Bu bölüm ise yalnızca `signal_notifications`
/// kaydını gösterir — zaman damgalı, gerçekten gönderilmiş olayı. İkisi
/// çelişebilir ve bu çelişki kullanıcı için bilginin kendisidir.
///
/// ## "Aktif" tanımı (kullanıcı kararı, 2026-09-10)
/// Kullanıcı bildirimi sildiyse (`dismissedAt`) VEYA kayıt [_omur]'den
/// eskiyse bölüm HİÇ çizilmez. Teknik sinyallerin ömrü kısadır; iki hafta
/// önceki bir kaydı "aktif" diye sunmak yanıltıcı olurdu.
class AktifSinyalBolumu extends ConsumerWidget {
  const AktifSinyalBolumu({super.key, required this.asset, this.icerikKey});

  final Asset asset;

  /// Kaydırma hedefi — YALNIZCA kart gerçekten çizildiğinde bağlanır.
  ///
  /// Widget'ın kendi `key`'ine bağlansaydı işe yaramazdı: aktif kayıt
  /// yokken bu widget `SizedBox.shrink()` döndürüyor, yani ağaçta duruyor
  /// ve `currentContext` DOLU oluyor. Üstteki şeritten gelen kaydırma
  /// sıfır yükseklikli bir kutuya gider, kullanıcı boş ekrana bakardı.
  /// Anahtar içeriğe bağlıysa `currentContext` gerçekten null olur ve
  /// çağıran taraf teknik panele düşebilir.
  final Key? icerikKey;

  /// Bir sinyalin "aktif" sayıldığı süre.
  static const Duration omur = Duration(days: 7);

  /// Gösterilecek kaydı seçer — yoksa `null`.
  ///
  /// Saf fonksiyon: `now` DIŞARIDAN verilir. `DateTime.now()` içeride
  /// çağrılsaydı "eskimiş kayıt" dalı ancak gerçek zaman geçtiğinde
  /// çalışırdı ve test onu hiç görmezdi.
  static SignalAlert? aktifKayit(
    List<SignalAlert> alerts,
    Asset asset, {
    required DateTime now,
  }) {
    final son = AssetSignalCard.sonSinyal(alerts, asset);
    if (son == null) return null;
    // Kullanıcı bildirimi kapattıysa ekranda diriltmeyiz.
    if (son.isDismissed) return null;
    if (now.difference(son.detectedAt) > omur) return null;
    return son;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts =
        ref.watch(signalProvider).valueOrNull ?? const <SignalAlert>[];
    final kayit = aktifKayit(alerts, asset, now: DateTime.now());

    // Aktif sinyal yoksa BOŞ kalır — kullanıcı isteğinin açık kısmı.
    // "Sinyal yok" kutusu çizmek ekranın sonunu bir olumsuzlamayla
    // doldururdu; bölümün yokluğu zaten aynı şeyi söylüyor.
    if (kayit == null) return const SizedBox.shrink();

    final c = context.c;
    final isBuy = kayit.signal == SignalType.buy;
    final isSell = kayit.signal == SignalType.sell;
    final renk = isBuy
        ? c.gain
        : isSell
            ? c.loss
            : c.text58;

    // Yasal dil: kesin "AL/SAT" değil, trend yönü. Ekranın geri kalanıyla
    // aynı sözcükler (bkz. `_AssetSignalCardState._satir`).
    final baslik = isBuy
        ? 'YUKARI TREND'
        : isSell
            ? 'AŞAĞI TREND'
            : 'YATAY SEYİR';

    final toplam = kayit.buyCount + kayit.sellCount;
    final lehte = isSell ? kayit.sellCount : kayit.buyCount;

    return Column(
      key: icerikKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: SandikSpace.lg),
        // `Spacer` idi ve 320pt × 1.6'da 141px taşıyordu: iki metin de
        // doğal genişliğini ister, `Spacer` sıkıştırmaz. Başlık esner
        // (kısalırsa "…" ile kesilir), zaman etiketi tam kalır — hangisinin
        // feda edileceği burada bilinçli bir seçim.
        Row(
          children: [
            Expanded(
              child: Text(
                'AKTİF SİNYAL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelMedium?.copyWith(
                  color: c.text58,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Text(
              _neZaman(kayit.detectedAt, DateTime.now()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelMedium?.copyWith(color: c.text36),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.sm2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SandikSpace.md),
          decoration: BoxDecoration(
            color: renk.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: renk.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isBuy
                          ? Icons.trending_up_rounded
                          : isSell
                              ? Icons.trending_down_rounded
                              : Icons.remove_rounded,
                      color: renk,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: SandikSpace.smd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          baslik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.titleMedium?.copyWith(
                            color: renk,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // KISA ay adı ("10 Eyl" ≠ "10 Eylül"): uzun biçim
                        // 320pt × 1.6 ölçekte tek başına 470px istiyordu ve
                        // satırı taşırıyordu. Yıl da atıldı — 7 günden eski
                        // kayıt zaten gösterilmiyor, yıl bilgi taşımıyor.
                        Text(
                          DateFormat("d MMM · HH:mm", 'tr_TR')
                              .format(kayit.detectedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              context.t.bodySmall?.copyWith(color: c.text58),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  // Güven skoru blokunun kendi genişliği YOK; büyük yazı
                  // ölçeğinde başlıkla birlikte satırı 141px taşırıyordu
                  // (320pt × 1.6). Esnek bir kutuya alınıp metinler tek
                  // satıra sabitlendi — skor okunaklılığını korurken
                  // taşmayı imkânsız kılar.
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '%${kayit.confidence.round()}',
                            maxLines: 1,
                            style: context.t.numMedium.copyWith(
                              color: renk,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        Text(
                          'güven',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              context.t.labelSmall?.copyWith(color: c.text36),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Gösterge kırılımı yalnızca sayı VARSA çizilir. Sıfır/sıfır
              // bir dağılım çubuğu bilgi taşımaz, yalnızca yer kaplar.
              if (toplam > 0) ...[
                const SizedBox(height: SandikSpace.smd),
                Divider(height: 1, color: c.hairline),
                const SizedBox(height: SandikSpace.smd),
                // `Row` + `Spacer` idi ve büyük yazıda 266px taşıyordu:
                // üç öğe de doğal genişliğini istiyor, sığmayınca Row
                // kırılıyor. `Wrap` sığmayanı alt satıra indirir — dar
                // ekranda düzen bozulmak yerine yumuşakça sarılır.
                Wrap(
                  spacing: SandikSpace.md,
                  runSpacing: SandikSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Sayac(
                      etiket: 'Yukarı',
                      deger: kayit.buyCount,
                      renk: c.gain,
                    ),
                    _Sayac(
                      etiket: 'Aşağı',
                      deger: kayit.sellCount,
                      renk: c.loss,
                    ),
                    Text(
                      '$lehte/$toplam gösterge',
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// "2 saat önce" / "3 gün önce" — kayıt tazeliğini tek bakışta verir.
  ///
  /// Mutlak tarih kartın içinde zaten var; buradaki göreli ifade
  /// "bu bilgi ne kadar yeni" sorusunu okumadan yanıtlar.
  static String _neZaman(DateTime an, DateTime now) {
    final fark = now.difference(an);
    if (fark.inMinutes < 1) return 'az önce';
    if (fark.inMinutes < 60) return '${fark.inMinutes} dk önce';
    if (fark.inHours < 24) return '${fark.inHours} saat önce';
    return '${fark.inDays} gün önce';
  }
}

/// Kartın altındaki tek sayaç (yukarı / aşağı gösterge adedi).
class _Sayac extends StatelessWidget {
  const _Sayac({
    required this.etiket,
    required this.deger,
    required this.renk,
  });

  final String etiket;
  final int deger;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
        ),
        const SizedBox(width: SandikSpace.xs2),
        Text(
          '$deger',
          style: context.t.numSmall.copyWith(
            color: renk,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: SandikSpace.xs),
        Text(
          etiket,
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
      ],
    );
  }
}

/// Teknik gösterge paneli.
///
/// **Bir `Asset` İSTEMEZ** — yalnızca sembol, tür ve alt kategori. Göstergeler
/// miktar/maliyet okumaz; sahiplikle ilgisi yoktur. Bu sayede aynı panel hem
/// sahip olunan varlıkta (`PerformanceScreen`) hem de yalnızca izlenen
/// varlıkta (`WatchlistDetailScreen`) kullanılabiliyor — panelin ~400 satırlık
/// gösterge arayüzü kopyalanmadan.
class TechnicalSignalPanel extends ConsumerStatefulWidget {
  final String ticker;
  final AssetType type;
  final String? subCategory;

  /// Dağılım görselleştirmesi (oran çubuğu + gruplu liste) çizilsin mi?
  ///
  /// YALNIZCA varlık performans ekranında `true`. Kullanıcı bunu oraya
  /// istedi ve isteğin "sadece" kısmı bilinçli: takip listesi detayı,
  /// sahip OLMADIĞIN bir varlığa hızlı bakış ekranıdır — orada özet + düz
  /// liste yeterli, üç katmanlı bir dağılım paneli ekranı ağırlaştırır.
  ///
  /// Bayrak varsayılan olarak `false`: yeni bir çağrı yeri eklendiğinde
  /// ağır sürüm kazara sızmasın.
  final bool detayli;

  const TechnicalSignalPanel({
    super.key,
    required this.ticker,
    required this.type,
    this.subCategory,
    this.detayli = false,
  });

  /// Sahip olunan bir varlıktan kurar — çağrı yerlerini kısaltır.
  TechnicalSignalPanel.forAsset(Asset asset, {Key? key, bool detayli = false})
      : this(
          key: key,
          ticker: asset.ticker,
          type: asset.type,
          subCategory: asset.subCategory,
          detayli: detayli,
        );

  @override
  ConsumerState<TechnicalSignalPanel> createState() =>
      _TechnicalSignalPanelState();
}

class _TechnicalSignalPanelState extends ConsumerState<TechnicalSignalPanel> {
  /// GERÇEK fiyat geçmişi. Boş liste `analyze`'ı simülasyona düşürdüğü için
  /// bu future çözülene kadar panel "hesaplanıyor" gösterir.
  Future<List<double>>? _pricesFuture;
  String? _pricesKey;

  /// Kaçıncı deneme.
  ///
  /// Future bir kez BAŞARISIZ olduğunda `_pricesFuture` o başarısız sonucu
  /// widget ömrü boyunca tutuyordu: ağ geri gelse bile panel "geçmiş yok"
  /// demeye devam ediyor, kullanıcının ekranı kapatıp açmaktan başka çaresi
  /// kalmıyordu. Sayaç önbellek anahtarının parçası — artırmak yeni bir
  /// istek demek.
  int _deneme = 0;

  /// Push bildirimiyle AYNI kaynaktan besleme: sunucu sinyali gerçek piyasa
  /// serisinden üretir, bu panel de öyle yapmalı.
  ///
  /// **Bug (2026-08-31):** panel `analyze(asset, const [])` çağırıyordu.
  /// `TechnicalAnalysisService.analyze` boş seri gelince `_simulate()`'e
  /// düşer — `Random` ile UYDURMA fiyat üretir. Yani ekrandaki sinyal
  /// rastgele veriden hesaplanıyordu. Push "yukarı yönlü" derken ekranın
  /// "SAT" göstermesinin sebebi buydu: iki taraf farklı sayılara bakıyordu.
  /// Sunucu tarafında bu tuzak zaten kapalı (`fiyat geçmişi yoksa sinyal
  /// üretilmez (simülasyona düşmez)` testi).
  Future<List<double>> _loadPrices() {
    final key = '${widget.ticker}|${widget.type.name}|'
        '${widget.subCategory ?? ''}|$_deneme';
    if (_pricesKey == key && _pricesFuture != null) return _pricesFuture!;
    _pricesKey = key;
    // Göstergelerin çoğu 100+ nokta ister (MACD 26, Bollinger 20, ADX 14×2).
    // 180 gün hepsini rahatça besler.
    _pricesFuture = HistoryService.instance
        .getSymbolHistory(widget.ticker, periodDays: 180)
        .then((map) {
      final keys = map.keys.toList()..sort();
      return [for (final k in keys) map[k]!];
    }).catchError((_) => <double>[]);
    return _pricesFuture!;
  }

  @override
  Widget build(BuildContext context) {
    // Kullanıcı tercihleri değiştikçe otomatik yeniden hesapla
    final prefs = ref.watch(indicatorPrefsProvider);
    final premium = ref.watch(premiumUnlockedProvider);
    final enabledIds = prefs[widget.type] ??
        TechnicalAnalysisService.defaultEnabledFor(widget.type);

    return FutureBuilder<List<double>>(
      future: _loadPrices(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _panelShell(
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.c.amberFill,
                  ),
                ),
                const SizedBox(width: 10),
                // Expanded + ellipsis: dar ekranda (320pt) satır taşmasın.
                Expanded(
                  child: Text('Göstergeler hesaplanıyor…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ),
              ],
            ),
          );
        }

        final prices = snap.data ?? const <double>[];
        // Fiyat geçmişi YOKSA sinyal üretme — uydurma veriyle sinyal
        // göstermektense hiç göstermemek doğru. Sunucu da aynısını yapar.
        if (prices.length < 30) return _gecmisYok(context);

        return _buildPanel(context, prices, enabledIds, premium);
      },
    );
  }

  Widget _panelShell({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: child,
      );

  // NOT (2026-09-10): "fiyat geçmişi yok" panelinde kayıtlı bildirimi
  // tekrarlayan bir blok ve onun iki yardımcısı vardı; kullanıcı isteğiyle
  // kaldırıldı. Aynı bilgi zaten ekranın en altındaki [AktifSinyalBolumu]
  // ile üstteki şeritte duruyor — üç yerde tekrar ediyordu.
  // Geri gelmesini `sinyal_dagilimi_test.dart` engelliyor.

  /// Fiyat geçmişi çekilemediğinde çizilen panel.
  ///
  /// ## Neden ölü bir cümle yetmiyor
  /// Bu ekranın ÜSTÜNDEKİ şerit aynı boş seride kayıtlı bildirime düşüp
  /// "2/3 gösterge · güven %67" yazıyor. Alt panel yalnızca "geçmiş yok"
  /// dediğinde kullanıcı üstte bir sinyal, altta hiçbir şey görüyor ve
  /// haklı olarak "hangi algoritmalar dedi?" diye soruyor (kullanıcı
  /// bildirimi 2026-09-10).
  ///
  /// Store sürümünde liste hep doluydu çünkü panel fiyat geçmişi yokken
  /// `_simulate()` ile UYDURMA seri üretiyordu (2026-08-31'de kapatıldı).
  /// Doğru çözüm o tuzağı geri açmak değil; elde GERÇEKTEN ne varsa onu
  /// göstermek ve isteği tekrarlanabilir kılmak.
  ///
  /// Kayıtlı bildirim yön ve sayıları taşır ama HANGİ göstergelerin öyle
  /// dediğini taşımaz (`signal_notifications` tek tek göstergeleri
  /// yazmıyor) — bu yüzden liste vaat edilmez, sınır açıkça söylenir.
  Widget _gecmisYok(BuildContext context) {
    final p = context.c;

    return _panelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: p.text36),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text(
                  'Bu varlığın fiyat geçmişi şu an çekilemedi — göstergeler '
                  'hesaplanamıyor.',
                  style: context.t.bodySmall?.copyWith(color: p.text58),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _deneme++),
              child: Container(
                // HIG'in en küçük dokunma hedefi 44pt; metin 11pt olduğu
                // için sarmalayıcı olmadan hedef ~14pt'ye düşerdi.
                height: 44,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: p.amberText),
                    const SizedBox(width: SandikSpace.xs2),
                    Text(
                      'Tekrar dene',
                      style: context.t.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: p.amberText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    List<double> prices,
    Set<String> enabledIds,
    bool premium,
  ) {
    final indicators = TechnicalAnalysisService.analyzeSeries(
      prices,
      widget.type,
      enabledIds: enabledIds,
      premiumUnlocked: premium,
    );

    final summary = TechnicalAnalysisService.summarize(indicators);
    // NOT: Push bildirimi burada tetiklenmez — bu widget her ekran açılışında
    // yeniden build olduğu için her tıklamada yeni push atardı. Sinyal push'u
    // artık sadece günlük cron (analyze-signals edge function → analyzePortfolio)
    // tarafından üretilir. Bu panel sadece göstergelerin özetini gösterir.

    if (indicators.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: context.c.text58, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bu varlık türü için hiçbir gösterge seçilmemiş. '
                'Profil → Sinyal Ayarları\'ndan aktifleştir.',
                style: context.t.titleSmall?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
    }
    final isBuy = summary.signal == SignalType.buy;
    final isSell = summary.signal == SignalType.sell;
    final isNeutral = summary.signal == SignalType.neutral;

    final signalColor = isBuy ? context.c.gain : isSell ? context.c.loss : context.c.text58;
    // Yasal not: kesin "AL/SAT" ifadesi yerine trend yönü kullanıyoruz.
    final signalLabel = isBuy ? 'YUKARI TREND' : isSell ? 'AŞAĞI TREND' : 'YATAY';
    final signalIcon = isBuy ? Icons.trending_up_rounded
        : isSell ? Icons.trending_down_rounded
        : Icons.remove_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Başlık ──────────────────────────────────────────────────────────
        Row(
          children: [
            // Başlık + sayaç dar ekranda sağdaki ayar bağlantısını taşırıyordu.
            // Flexible: önce sayaç, gerekirse başlık kırpılır.
            Flexible(
              child: Text(
                'TEKNİK ANALİZ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.c.text58,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '· ${enabledIds.length}/${IndicatorId.all.length} gösterge',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                adaptiveRoute(
                    builder: (_) => const SignalSettingsScreen()),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: context.c.amberText),
                  const SizedBox(width: 4),
                  Text(
                    'Göstergeleri Ayarla',
                    style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.amberText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const DisclaimerWidget(),
        const SizedBox(height: 12),

        // ── Özet sinyal kartı ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: signalColor.withValues(alpha: isNeutral ? 0.04 : 0.08),
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: signalColor.withValues(alpha: isNeutral ? 0.08 : 0.25),
              width: isNeutral ? 1 : 1.5,
            ),
          ),
          child: Row(
            children: [
              // Sinyal ikonu
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(signalIcon, color: signalColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signalLabel,
                      style: context.t.headlineLarge?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: signalColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.buyCount} AL · ${summary.sellCount} SAT · ${indicators.length - summary.buyCount - summary.sellCount} NÖTR',
                      style: context.t.titleSmall?.copyWith(color: context.c.text58),
                    ),
                  ],
                ),
              ),
              // Güven skoru
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtPct(summary.confidence, digits: 0),
                    // Güven skoru (%) — tabular figür, değişince zıplamasın.
                    style: context.t.numLarge.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: signalColor,
                    ),
                  ),
                  Text(
                    'güven',
                    style: context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Dağılım çubuğu (YALNIZCA detaylı mod) ───────────────────────────
        //
        // Kullanıcı isteği (2026-09-10): "hangi algoritmalar al ve sat
        // verenleri ve yüzdesi görsel olarak da tatmin edici ve göz alıcı
        // şekilde SADECE varlık performans ekranına eklenmeli."
        //
        // İlk sürümde çubuğun ALTINA gruplu kutular konmuş, düz liste ise
        // kaldırılmıştı. Kullanıcı bunu geri istedi (2026-09-10, ikinci
        // bildirim): "hangi algoritmalar bunu dedi ekranın en altında
        // görmeyi bekliyorum … tasarımı da store'da şu an olan şekliyle
        // olmalı." Gruplu kutular düz listenin taşıdığı bilgiyi zaten
        // tekrarlıyordu; kaldırıldı.
        //
        // Kalan iş bölümü net: çubuk ORANI verir (kaçı hangi yönde),
        // altındaki liste KİMLİĞİ (hangi gösterge, hangi değer, ne diyor).
        if (widget.detayli) ...[
          SinyalDagilimi(indicators: indicators),
          const SizedBox(height: SandikSpace.md),
        ],
        // ── Gösterge listesi (düz) ──────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
          child: Column(
            children: indicators.asMap().entries.map((entry) {
              final i = entry.key;
              final ind = entry.value;
              final isLast = i == indicators.length - 1;
              final c = ind.signal == SignalType.buy
                  ? context.c.gain
                  : ind.signal == SignalType.sell
                      ? context.c.loss
                      : context.c.text58;
              final lbl = ind.signal == SignalType.buy
                  ? 'AL'
                  : ind.signal == SignalType.sell
                      ? 'SAT'
                      : 'NÖTR';

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(
                      children: [
                        // Renkli gösterge çubuğu
                        Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ind.name,
                                style: context.t.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.c.text90,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ind.description,
                                style: context.t.bodySmall
                                    ?.copyWith(color: context.c.text36),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                          child: Text(
                            lbl,
                            style: context.t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: context.c.overlay,
                      indent: 31,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const DisclaimerWidget(),
      ],
    );
  }
}


// ── Sinyal dağılımı: oran çubuğu + gruplu gösterge listesi ───────────────────

/// Göstergelerin AL / SAT / NÖTR dağılımı — SEGMENT BAŞINA BİR GÖSTERGE.
///
/// ## Neden düz bir yüzde çubuğu değil
/// Gösterge sayısı küçük (4–8). Sürekli bir yüzde çubuğu "%67" der ama
/// kaç göstergeden geldiğini gizler; oysa "6 göstergeden 4'ü" ifadesi
/// kullanıcının gerçekten kurduğu cümle. Her göstergeye bir hücre vermek
/// aynı anda İKİ şeyi okutuyor: oran (yeşilin kapladığı alan) ve SAYI
/// (hücreleri saymak). Aradaki 2px boşluk hücreleri ayırır.
///
/// ## Renk TEK BAŞINA anlam taşımaz
/// Marka yeşili ile kırmızısı koyu temada deuteranopi altında ΔE ≈ 7,6
/// ayrışıyor — yani kırmızı-yeşil renk körlüğünde birbirine yakın. Bu
/// yüzden her hücre bir GLİF (▲ ▼ ◆) taşır, her grup metin başlıklıdır ve
/// sayılar rakamla yazılır. Renk yalnızca hızlı taramaya yardım eder;
/// bilgiyi tek başına taşımaz.
class SinyalDagilimi extends StatelessWidget {
  const SinyalDagilimi({super.key, required this.indicators});

  final List<TechnicalIndicator> indicators;

  static const _yukseklik = 14.0;
  static const _bosluk = 2.0;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) return const SizedBox.shrink();

    // Sıra SABİT: önce AL, sonra SAT, sonra NÖTR. Çubuk her varlıkta aynı
    // şekilde okunmalı — sıralama gösterge kimliğine göre değişirse
    // kullanıcı her ekranda yeniden yön bulmak zorunda kalır.
    final al = indicators.where((i) => i.signal == SignalType.buy).toList();
    final sat = indicators.where((i) => i.signal == SignalType.sell).toList();
    final notr =
        indicators.where((i) => i.signal == SignalType.neutral).toList();
    final toplam = indicators.length;

    final sirali = [...al, ...sat, ...notr];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Oran çubuğu ──────────────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: SizedBox(
            height: _yukseklik,
            child: Row(
              children: [
                for (var i = 0; i < sirali.length; i++) ...[
                  if (i > 0) const SizedBox(width: _bosluk),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _renk(context, sirali[i].signal),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.sm2),

        // ── Lejant ───────────────────────────────────────────────────────
        //
        // `Wrap`: dar ekranda ve büyük sistem yazı tipinde üç rozet tek
        // satıra sığmaz; taşma çizgisi yerine alt satıra iner.
        Wrap(
          spacing: SandikSpace.smd,
          runSpacing: SandikSpace.xs,
          children: [
            _lejant(context, SignalType.buy, al.length, toplam),
            _lejant(context, SignalType.sell, sat.length, toplam),
            if (notr.isNotEmpty)
              _lejant(context, SignalType.neutral, notr.length, toplam),
          ],
        ),
      ],
    );
  }

  Widget _lejant(
      BuildContext context, SignalType tur, int adet, int toplam) {
    final renk = _renk(context, tur);
    final yuzde = toplam > 0 ? (adet / toplam) * 100 : 0.0;
    // ## Neden metin parçaları `Flexible`
    //
    // `Wrap` çocuklarına kendi genişliğini ÜST SINIR olarak verir; içerik
    // o sınırı aşarsa `mainAxisSize.min` bir şey kurtarmaz ve satır taşar.
    // Ölçüldü: 320pt ekranda 2,0× sistem yazı tipinde rozet 1,3px ve 30px
    // taşıyordu (bkz. `sinyal_dagilimi_test.dart`).
    //
    // Çözüm metni KÜÇÜLTMEK değil (büyük yazı tipi bir erişilebilirlik
    // ayarıdır, geri almak onu boşa çıkarır) — metin parçalarına esneme
    // izni vermek. Pratikte ellipsis neredeyse hiç tetiklenmez; rozet
    // kısa. Glif sabit kalır: kimliği o taşıyor.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_glif(tur),
            style: context.t.bodySmall?.copyWith(
                color: renk, fontWeight: FontWeight.w700, height: 1)),
        const SizedBox(width: SandikSpace.xs2),
        Flexible(
          child: Text(
            _etiket(tur),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: context.c.text58,
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.xs2),
        // Sayı METİN tokenıyla yazılır, seri rengiyle değil: rakamı
        // renklendirmek onu "durum" gibi okutur, oysa burada sadece bir
        // sayı var. Kimliği soldaki glif + renk taşıyor.
        Flexible(
          child: Text(
            '%${yuzde.round()} · $adet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.numSmall.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.c.text90,
            ),
          ),
        ),
      ],
    );
  }

  static Color _renk(BuildContext context, SignalType t) => switch (t) {
        SignalType.buy => context.c.gain,
        SignalType.sell => context.c.loss,
        SignalType.neutral => context.c.text36,
      };

  static String _glif(SignalType t) => switch (t) {
        SignalType.buy => '▲',
        SignalType.sell => '▼',
        SignalType.neutral => '◆',
      };

  static String _etiket(SignalType t) => switch (t) {
        SignalType.buy => 'AL',
        SignalType.sell => 'SAT',
        SignalType.neutral => 'NÖTR',
      };
}

// ─────────────────────────────────────────────────────────────────────────────

class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;
  final bool dashed;

  TransactionSegment({
    required this.spots,
    required this.lineColor,
    required this.areaGradientStart,
    required this.areaGradientEnd,
    required this.thickness,
    this.dashed = false,
  });
}

// ── Widget ───────────────────────────────────────────────────────────────────

class PerformanceScreen extends ConsumerStatefulWidget {
  final Asset asset;
  final bool showBackButton;
  /// Aggregate edilmiş pozisyonun tüm lot'ları (buy + sell). Grafik üstünde
  /// işlem marker'ları çizmek için kullanılır. Boş bırakılırsa sadece
  /// [asset]'in kendisi tek buy olarak varsayılır.
  final List<Asset>? lots;
  /// Landscape fullscreen'de açılınca grafik hemen görünsün diye body
  /// başlangıçta bu offset kadar aşağı kayar. Kullanıcı yukarı swipe ile
  /// header'a döner.
  final double initialScrollOffset;

  const PerformanceScreen({
    super.key,
    required this.asset,
    this.showBackButton = false,
    this.lots,
    this.initialScrollOffset = 0,
  });

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  /// Y/X ekseni interval'i için TradingView tarzı "nice number" —
  /// 1/2/2.5/5/10 tabanında yuvarlar. Örn: 34398 → 50000, 137 → 200.
  double _niceRound(double raw) {
    if (raw <= 0) return 1;
    final magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 2.5) {
      nice = 2.5;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  late int _selectedPeriodIdx;
  String? _view = ''; // '' = Ben (Default), null = Tümü, uuid = Ortak
  late Future<Map<int, double>> _historyFuture;
  late ScrollController _scrollController;
  // Compare mode: seçili karşılaştırma varlığı (kullanıcının portföyünden).
  // null = compare kapalı. Bu varlığın history serisi ana varlıkla aynı
  // periyotta fetch edilir, ilk nokta 100 kabul edilip % normalize edilir.
  Asset? _compareAsset;
  Future<Map<int, double>>? _compareHistoryFuture;

  /// Periyot sekmeleri. `days: 0` → GÜN İÇİ (5 dakikalık çözünürlük).
  ///
  /// Etiketler portföy performans ekranıyla AYNI: iki ekran aynı soruyu
  /// soruyor, farklı kelimelerle sormamalı. Ayrıca beş uzun etiket
  /// ("HAFTALIK", "6 AYLIK"…) 360pt genişlikte yan yana sığmıyordu.
  static const List<({String label, int days})> _allPeriods = [
    (label: 'GÜNLÜK', days: 0),
    (label: '1H', days: 7),
    (label: '1A', days: 30),
    (label: '6A', days: 180),
    (label: '1Y', days: 365),
  ];

  /// Bu varlık için gün içi fiyat verisi ANLAMLI mı?
  ///
  /// Vadeli mevduatın ve elle fiyatlanan varlıkların ("Ev", "Araba") bir
  /// piyasa serisi yoktur; onlarda GÜNLÜK sekmesi kullanıcıya boş ya da
  /// dümdüz bir grafik gösterir ve sekmeyi açmanın hiçbir karşılığı olmaz.
  ///
  /// Fon DAHİLDİR: TEFAS gün içi NAV yayınlamasa da seri, gün içinde bir
  /// basamak olarak fonun günlük NAV değişimini taşır
  /// (bkz. `HistoryService.gunIciFonBirimFiyati`).
  bool get _gunIciDestekli =>
      !widget.asset.isManualPrice &&
      widget.asset.type != AssetType.mevduat &&
      widget.asset.type != AssetType.diger;

  List<({String label, int days})> get _periods =>
      _gunIciDestekli ? _allPeriods : _allPeriods.sublist(1);

  /// Alttaki teknik gösterge panelinin konumu.
  ///
  /// Üstteki sinyal şeridi yalnızca ÖZET verir (yön + kaç gösterge + güven).
  /// "Hangi gösterge ne diyor" sorusunun cevabı sayfanın dibindeki panelde;
  /// kullanıcı şeride dokununca oraya kaydırılır. Aksi halde özet, cevabı
  /// olmayan bir merak uyandırırdı.
  final GlobalKey _sinyalPaneliKey = GlobalKey();

  /// Ekranın en altındaki "Aktif Sinyal" bölümünün konumu.
  ///
  /// Kullanıcı isteği (2026-09-10): "ekranın en üstündeki kısım kalabilir,
  /// tıklanınca en alta inebilir." Şeride dokunmak artık öncelikle BURAYA
  /// kaydırır.
  final GlobalKey _aktifSinyalKey = GlobalKey();

  /// Şeritten aşağıya kaydır.
  ///
  /// Hedef sırası bilinçli: önce en alttaki [AktifSinyalBolumu], o
  /// çizilmemişse (aktif kayıt yok) teknik panel. Bölüm koşullu olduğu
  /// için `currentContext` null olabilir — tek hedefe bağlansaydı dokunuş
  /// sessizce hiçbir şey yapmazdı, ki bu en kötü sonuç: kullanıcı
  /// dokunulabilir görünen bir şeye dokunur ve ekran kıpırdamaz.
  void _sinyalPaneline() {
    final ctx = _aktifSinyalKey.currentContext ??
        _sinyalPaneliKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
      // Hedef ekranın üst kenarına yapışmasın; başlığı görünür kalsın.
      alignment: 0.1,
    );
  }

  /// Gün içi serinin çizildiği günün 00:00'ı.
  ///
  /// Bugün olmak ZORUNDA değil: piyasa kapalıyken (hafta sonu, tatil,
  /// açılıştan önce) servis SON SEANSI döndürür. Seri geldiğinde
  /// buradan okunur; X ekseni ve saat etiketleri o güne oturur.
  DateTime? _gunIciBaslangic;

  // Son başarılı history sonucu. Periyot değiştiğinde FutureBuilder yeni
  // future'ı "waiting" sayar ve snapshot.data null olur; bu alan olmadan
  // grafik + altındaki tüm kontroller (compare, MA20/LOG, fullscreen) o
  // sürede ağaçtan düşüyordu. Artık eski seri yerinde kalır, sadece grafik
  // alanı "yükleniyor" hissi verir ve filtreler tıklanabilir kalır.
  Map<int, double>? _lastHistory;

  @override
  void initState() {
    super.initState();
    // Varsayılan sekme HAFTALIK olarak KALIR.
    //
    // GÜNLÜK sekmesi listeye eklendi ama varsayılan yapılmadı: varlık
    // detayına giren kullanıcı çoğunlukla trendi arıyor, tek seansı değil.
    // Gün içi görünüm bir tıkla, hep aynı yerde (en solda) duruyor.
    _selectedPeriodIdx = _gunIciDestekli ? 1 : 0;
    _historyFuture = _loadHistory(_periods[_selectedPeriodIdx].days);
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
  }

  /// History fetch + son başarılı sonucu sakla.
  ///
  /// [days] 0 ise GÜN İÇİ seri istenir: 24 saat, 5 dakikalık slotlar.
  /// Gün içi yolu ayrı bir servistir (`...HourlyBreakdown`) ve çizilen
  /// günü de bildirir — X ekseni ona göre kurulur.
  Future<Map<int, double>> _loadHistory(int days) {
    if (days == 0) {
      return HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([widget.asset], 24)
          .then((b) {
        if (mounted) {
          _gunIciBaslangic = b.seansGunu;
          if (b.total.isNotEmpty) _lastHistory = b.total;
        }
        return b.total;
      });
    }
    return HistoryService.instance
        .getPortfolioHistory([widget.asset], days)
      ..then((v) {
        if (mounted && v.isNotEmpty) _lastHistory = v;
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPeriod(int idx) {
    // Eski sekme gün içi miydi? Index güncellenmeden ÖNCE okunmalı.
    final oncekiGunIci = _gunIciMi;
    setState(() {
      _selectedPeriodIdx = idx;
      final days = _periods[idx].days;
      // Bayat seri periyotlar arasında köprü kurar (bkz. `_lastHistory`).
      // Gün içi ile günlük seriler AYNI ölçekte DEĞİL: biri 5 dakikalık
      // slot, öteki gün kapanışı. Birinden ötekine geçerken eski seriyi
      // taşımak, yeni eksene ait olmayan noktalar çizerdi.
      if ((days == 0) != oncekiGunIci) _lastHistory = null;
      _historyFuture = _loadHistory(days);
      // Compare aktifse aynı yeni periyot için compare history'yi de yenile.
      // Gün içinde karşılaştırma YOK: iki varlığın 5 dakikalık serisini
      // yüzdeye normalize etmek ayrı bir iş ve bu ekranda karşılığı yok.
      if (_compareAsset != null) {
        _compareHistoryFuture = days == 0
            ? null
            : HistoryService.instance
                .getPortfolioHistory([_compareAsset!], days);
        if (days == 0) _compareAsset = null;
      }
    });
  }

  /// Seçili sekme gün içi mi?
  bool get _gunIciMi => _periods[_selectedPeriodIdx].days == 0;

  void _openComparePicker() {
    final pState = ref.read(portfolioProvider).valueOrNull;
    final all = pState?.assets ?? const <Asset>[];
    // Aynı ticker hariç — kendisiyle karşılaştırma yok. Aynı ticker'ın
    // birden fazla lot'u olabilir (birden çok alım); ticker bazlı dedup.
    final seen = <String>{};
    final choices = <Asset>[];
    for (final a in all) {
      if (a.ticker == widget.asset.ticker) continue;
      if (!seen.add(a.ticker)) continue;
      choices.add(a);
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.c.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return _ComparePickerSheet(
          choices: choices,
          currentSelectionTicker: _compareAsset?.ticker,
          onSelected: (choice) {
            final vAsset = choice?.toVirtualAsset();
            setState(() {
              _compareAsset = vAsset;
              _compareHistoryFuture = vAsset == null
                  ? null
                  : HistoryService.instance.getPortfolioHistory(
                      [vAsset], _periods[_selectedPeriodIdx].days);
            });
            Navigator.pop(sheetCtx);
          },
        );
      },
    );
  }


  void _confirmDelete(BuildContext ctx) {
    // Bu ekran aggregate edilmiş bir pozisyonla açılabiliyor; o durumda
    // `widget.asset` sentetik bir görüntü nesnesidir (`id` = "pos:...") ve
    // DB'de karşılığı yoktur. Silinecek gerçek kayıtlar `lots`'tur.
    final lots =
        (widget.lots ?? [widget.asset]).where((l) => !l.isDeleteLog).toList();
    final multi = lots.length > 1;
    showDialog<void>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(SandikRadius.lg)),
        title: const Text('Varlığı Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(multi
                ? '"${widget.asset.name}" için ${lots.length} işlem kaydı '
                    '(alım/satım/temettü) kalıcı olarak silinsin mi?'
                : '"${widget.asset.name}" kalıcı olarak silinsin mi?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.c.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color:
                        context.c.danger.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'Bu bir satış değil — varlık portföyden çıkar, toplamlardan '
                've geçmiş grafiğinden düşer. İşlem kayıtları "Portföy '
                'Hareketleri"nde kalır. Sattıysan bunun yerine "Sat" kullan; '
                'realize kâr/zararın hesaba dahil olur.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: context.c.danger,
                foregroundColor: context.c.onStatus),
            onPressed: () async {
              Navigator.pop(dlg);
              try {
                await ref
                    .read(portfolioProvider.notifier)
                    .deletePositionLots(lots);
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Varlık silindi')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Silinemedi: $e')),
                );
              }
            },
            child: const Text('Yine de sil'),
          ),
        ],
      ),
    );
  }

  /// Bir sahibin lot'ları arasından BU ekranın varlığına karşılık gelen
  /// pozisyonu döndürür — yoksa `null`.
  ///
  /// **Neden `firstWhere` değil.** Burada eskiden `assets.where(...).first`
  /// vardı ve sahibin YALNIZCA İLK lot'unu alıyordu. Kendi tarafımızda
  /// `widget.asset` `aggregatePositions`'tan gelen bir pozisyon temsilcisidir
  /// (ağırlıklı ortalama maliyet, toplam miktar); ortak tarafında ise tek bir
  /// lot'tu. Aynı değişken, iki farklı anlam → aynı üründe iki farklı
  /// kâr/zarar. Ortak birden çok kez alım yaptıysa oranı yalnızca bir
  /// alımına göre hesaplanıyordu.
  ///
  /// `aggregatePositions` sahip başına AYRI çağrılır: farklı sahiplerin
  /// lot'ları asla tek havuzda toplanmaz (bkz. `aggregatePositionsByOwner`
  /// açıklaması) — aksi halde iki kişinin aynı hissesi tek pozisyonda
  /// birleşir ve toplam değer tek kişinin fiyatıyla hesaplanırdı.
  Position? _positionOf(List<Asset> ownerLots) {
    final hedef = positionKey(widget.asset);
    for (final p in aggregatePositions(ownerLots)) {
      if (p.key == hedef) return p;
    }
    return null;
  }

  double get _currentQuantity {
    if (_view == '') return widget.asset.quantity;

    final allAssetsMap = ref.read(allPartnerAssetsProvider).valueOrNull ?? {};

    if (_view != null) {
      return _positionOf(allAssetsMap[_view] ?? [])?.totalQuantity ?? 0;
    }

    // Tümü
    double total = widget.asset.quantity;
    final activePartners = ref.read(activePartnersProvider);
    for (final p in activePartners) {
      total += _positionOf(allAssetsMap[p.id] ?? [])?.totalQuantity ?? 0;
    }
    return total;
  }

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    DateTime startDate,
    DateTime endDate, {
    double? currentUnitPriceOverride,

    /// GÜN İÇİ seri mi? Gün içinde İLK NOKTA ORTALAMA MALİYETLE EZİLMEZ.
    ///
    /// Uzun periyotlarda ilk noktayı maliyete çekmek bilinçli bir tercih:
    /// grafik "aldığım fiyattan bugüne" hikâyesini anlatıyor. Gün içi seri
    /// bambaşka bir soruyu yanıtlar — "bugün ne oldu". Orada ilk noktayı
    /// maliyete çekmek, günlük değişimi maliyetle bugün arasındaki farka
    /// çevirir ve sekmeyi anlamsız kılardı.
    bool intraday = false,
  }) {
    if (history.isEmpty) return [];

    final segments = <TransactionSegment>[];
    final firstAssetDate = widget.asset.addedDate;
    final firstAssetMidnight =
        DateTime(firstAssetDate.year, firstAssetDate.month, firstAssetDate.day);

    // Grafik "birim fiyat" (TL) gösterir — HistoryService'in döndürdüğü
    // toplam pozisyon değerini quantity'ye bölerek per-unit fiyata çeviririz.
    // Böylece ek alım/sell miktarı değiştirdiğinde grafik çizgisinde suni
    // sıçrama olmaz; sadece cost basis (yatay çizgi) rebase olur.
    final qty = widget.asset.quantity;
    final divisor = qty > 0 ? qty : 1.0;

    // Anchor = alım anındaki birim fiyat (TL cinsinden).
    final anchorUnitPrice =
        widget.asset.purchasePrice * widget.asset.purchaseFxRate;

    final sortedTs = history.keys.toList()..sort();
    final activeSpots = <FlSpot>[];
    bool firstActiveReplaced = false;

    // Passive segment (alış öncesi dashed çizgi) kaldırıldı — portfolio
    // performance ekranıyla görsel bütünlük için. Grafik sadece alış → şimdi
    // aralığını gösterir; kullanıcı "elimde olmadığı dönemin" fiyatını
    // aramaz, bu aralık zaten periyot seçimi ile ayarlanır.
    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      // Saatlik veride (haftalık) her saat farklı X'e düşmeli — inDays saati
      // keser ve tüm saatler aynı X'e sıkışırdı, grafik dikey zigzag olurdu.
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      final y = history[ts]! / divisor;

      if (!intraday && !firstActiveReplaced && anchorUnitPrice > 0) {
        // Aktif segmentin İLK noktası her zaman anchor (ort. maliyet).
        activeSpots.add(FlSpot(x, anchorUnitPrice));
        firstActiveReplaced = true;
      } else {
        activeSpots.add(FlSpot(x, y));
      }
    }

    // Son aktif spot'u canlı fiyat ile değiştir — böylece grafik bitiş
    // noktası ve üstteki PnL chip aynı değeri gösterir (Yahoo history son
    // bar'ı ile canlı `currentPrice` arasındaki gecikme/ölçek farkını kapat).
    // ANCAK aktif segmentte tek spot varsa (yani ilk alım = bugün), o spot
    // anchor'dır — override edersen anchor "bugünkü fiyat" olur ve ALIŞ
    // çizgisi yanlış yerde çizilir. Bu durumda anchor'ı olduğu gibi bırakıp
    // canlı fiyat için ayrı bir "son" spot ekleriz (biraz farklı X ile).
    if (currentUnitPriceOverride != null &&
        currentUnitPriceOverride > 0 &&
        activeSpots.isNotEmpty) {
      if (activeSpots.length >= 2) {
        final last = activeSpots.last;
        activeSpots[activeSpots.length - 1] =
            FlSpot(last.x, currentUnitPriceOverride);
      } else {
        // Tek spot (anchor) var — ayrı bir "bugün" noktası ekle. X biraz
        // ileride (bugünün offset'i) olsun.
        final anchorX = activeSpots.first.x;
        final todayX =
            DateTime.now().difference(startDate).inMinutes / (60.0 * 24.0);
        // Aynı gün ise minik bir ε ekle ki iki nokta farklı X'te olsun.
        final endX = todayX > anchorX ? todayX : anchorX + 0.01;
        activeSpots.add(FlSpot(endX, currentUnitPriceOverride));
      }
    }

    if (activeSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: activeSpots,
        lineColor: Sandik
            .amber, // Use Amber for active tracking to match design system focus
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5, // Thicker active line
      ));
    }

    return segments;
  }


  Widget _buildPeriodToggle() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectPeriod(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: SandikMotion.of(context, const Duration(milliseconds: 200)),
                curve: SandikMotion.enter,
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  // Sekme sayısı 4'ten 5'e çıktı (GÜNLÜK eklendi) ve
                  // "GÜNLÜK" en uzun etiket. 375pt'lik bir ekranda sekme
                  // başına ~72pt kalıyor; sistem yazı tipi büyütülmüşse
                  // (Dynamic Type 1,5×–2×) etiket bu kutuya sığmıyor.
                  // `FittedBox` küçülterek sığdırır — kırpmak, hangi
                  // dönemde olduğunu okunmaz hâle getirirdi.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _periods[i].label,
                      maxLines: 1,
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? context.c.gold
                            : context.c.text36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final endDate = DateTime.now();
    final period = _periods[_selectedPeriodIdx];
    final isIntraday = period.days == 0;
    // GÜNLÜK sekmesinde eksen ÇİZİLEN GÜNÜN 00:00'ında başlar ve tam gün
    // (24 saat) boyunca uzanır.
    //
    // İki karar da bilinçli:
    //   · 00:00: kullanıcı isteği — "GÜNLÜK seçildiğinde 00:00'dan
    //     başlayarak gözükmeli" (2026-09-10). Ekseni ilk fiyat noktasında
    //     başlatmak, sabah 09:00'da bakınca başka, öğlen bakınca başka bir
    //     zaman ölçeği gösterirdi.
    //   · Çizilen gün bugün OLMAYABİLİR: piyasa kapalıyken servis son
    //     seansı döndürür (`seansGunu`). Ekseni `now`'a kurmak hafta sonu
    //     Cuma seansını grafiğin dışına atardı.
    final startDate = isIntraday
        ? (_gunIciBaslangic ??
            DateTime(endDate.year, endDate.month, endDate.day))
        : endDate.subtract(Duration(days: period.days));
    // Kesirli gün — saatlik veride son X gün sınırında değil, gerçek
    // anlarında olmalı. Yoksa nokta grafiğin ortasında yalnız kalır.
    final maxX = isIntraday
        ? 1.0
        : endDate.difference(startDate).inMinutes / (60.0 * 24.0);

    // Logic moved inside FutureBuilder

    final activePartners = ref.watch(activePartnersProvider);
    final allPartnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;
    final isOwnAsset = currentUserId != null && widget.asset.userId == currentUserId;

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: context.c.text90),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Performans: ${widget.asset.name}',
          style: context.t.headlineSmall?.copyWith(color: context.c.text90),
          // Varlık adı kullanıcı girdisidir ve uzun olabilir ("Yapı Kredi
          // Koray Gayrimenkul Yatırım Ortaklığı"). AppBar başlığı tek
          // satırdır; koruma olmadan taşma çizgileri çıkar.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isOwnAsset && !widget.showBackButton)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: context.c.text90),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SandikRadius.md)),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: context.c.danger, size: 20),
                      const SizedBox(width: 10),
                      Text('Sil',
                          style: TextStyle(color: context.c.danger)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              children: [
                if (!widget.showBackButton)
                  allPartnerAssetsAsync.maybeWhen(
                    data: (allAssetsMap) {
                      // Sekme yalnızca bu ürüne SAHİP ortaklar için çıkar.
                      // Eşleşme `ticker` ile değil `positionKey` ile yapılır:
                      // altın türleri (Gram/Çeyrek/Reşat) `subCategory` ile
                      // ayrışır ve ticker eşleşmesi farklı türleri aynı sayardı.
                      final matchingPartners = <AppUser>[
                        for (final p in activePartners)
                          if (_positionOf(allAssetsMap[p.id] ?? []) != null) p,
                      ];

                      if (matchingPartners.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        children: [
                          ModernTabSelector(
                            partners: matchingPartners,
                            selectedId: _view,
                            onChanged: (v) => setState(() => _view = v),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                // Sinyal özeti EN ÜSTTE.
                //
                // Şerit ÖNCE canlı göstergeleri okur, kayıtlı bildirimi
                // beklemez. İlk sürümde yalnızca `signal_notifications`
                // satırı varsa çiziliyordu; o satır ancak bir sinyal güven
                // eşiğini geçtiğinde VE öncekinden farklı olduğunda yazılır,
                // yani çoğu varlıkta çoğu zaman hiç yoktu ve sinyal bilgisi
                // pratikte yalnızca sayfanın dibindeki panelde kalıyordu
                // (kullanıcı bildirimi 2026-09-10: "sinyaller varlık
                // performansta gözükmeli").
                //
                // Kayıtlı bildirim varsa şeridin ikinci satırında durur —
                // "şu an ne diyor" ile "bana ne bildirilmişti" farklı
                // sorulardır.
                if (widget.asset.type != AssetType.mevduat)
                  AssetSignalCard(
                    asset: widget.asset,
                    onTap: _sinyalPaneline,
                  ),
                _buildPeriodToggle(),
                const SizedBox(height: 24),
                FutureBuilder<Map<int, double>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final waiting =
                        snapshot.connectionState == ConnectionState.waiting;
                    // Periyot değişiminde eski seriye düş — böylece bu
                    // FutureBuilder'ın altındaki compare/MA20/LOG kontrolleri
                    // ve özet şeritleri ağaçta kalır. Hiç veri yoksa (ilk
                    // açılış) yalnızca grafik alanı spinner gösterir.
                    // Bayat seri ÖNCEKİ periyoda ait. Yeni periyot daha darsa
                    // aralık dışı noktalar negatif X'e düşüp ekseni kaydırırdı
                    // — bu yüzden seçili pencereye kırpılır.
                    Map<int, double>? fallback;
                    if (snapshot.data == null && _lastHistory != null) {
                      final fromMs = startDate.millisecondsSinceEpoch;
                      final toMs = endDate.millisecondsSinceEpoch;
                      final clipped = <int, double>{
                        for (final e in _lastHistory!.entries)
                          if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
                      };
                      if (clipped.length >= 2) fallback = clipped;
                    }
                    final data = snapshot.data ?? fallback;
                    final isStale = snapshot.data == null && data != null;
                    if (data == null) {
                      return const SizedBox(
                          height: 400,
                          child: CustomLoadingView());
                    }

                    final historyMap = data;

                    // ── PnL: KART İLE BİREBİR AYNI FORMÜL ───────────────────
                    // Grafiğin son noktasını da bu canlı değerle sabitliyoruz
                    // (aşağıdaki `currentUnitPriceOverride`) — böylece grafik
                    // bitiş noktası ve chip her zaman aynı sayıyı gösterir.
                    final asset = widget.asset;
                    final qty = asset.quantity;
                    final anchorUnitTRY =
                        asset.purchasePrice * asset.purchaseFxRate;
                    final currentValueTRY = pState != null
                        ? pState.toTRY(asset.totalValue, asset.currency)
                        : asset.totalValue;
                    final currentUnitTRY = qty > 0 ? currentValueTRY / qty : 0.0;

                    // Compare mode devrede mi? Öncelikli — log-scale ile
                    // aynı anda anlamlı değil (biri % biri log), compare
                    // aktifken log ignore edilir.
                    final compareOn = _compareAsset != null;
                    final logOnPref = ref.watch(chartLogScaleProvider);
                    final logOn = compareOn ? false : logOnPref;

                    final rawSegments = _convertHistoryToSegments(
                        historyMap, startDate, endDate,
                        currentUnitPriceOverride: currentUnitTRY,
                        intraday: isIntraday);

                    // Normalize base: aktif segmentin ilk noktası. Bunun
                    // altında ana varlığın Y'leri (y / base) * 100 → % olur.
                    final rawActiveForBase = rawSegments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final normBase = rawActiveForBase.spots.isNotEmpty
                        ? rawActiveForBase.spots.first.y
                        : 1.0;

                    // Y ekseni transform: compare → % normalize; log → log10;
                    // default → identity. `fromY` label/tooltip'te ters
                    // çeviren fonksiyon (compare'de gösterim değişik: "+%12.4"
                    // formatı için ayrıca handle edilir).
                    double toY(double y) {
                      if (compareOn) return (y / (normBase.abs() < 1e-9 ? 1 : normBase)) * 100.0;
                      if (logOn) return math.log(y < 1e-6 ? 1e-6 : y) / math.ln10;
                      return y;
                    }
                    double fromY(double v) {
                      if (compareOn) return v; // % zaten, ters çevirme yok
                      if (logOn) return math.pow(10, v).toDouble();
                      return v;
                    }

                    final segments = (compareOn || logOn)
                        ? rawSegments
                            .map((s) => TransactionSegment(
                                  spots: s.spots
                                      .map((sp) =>
                                          FlSpot(sp.x, toY(sp.y)))
                                      .toList(),
                                  lineColor: s.lineColor,
                                  areaGradientStart: s.areaGradientStart,
                                  areaGradientEnd: s.areaGradientEnd,
                                  thickness: s.thickness,
                                  dashed: s.dashed,
                                ))
                            .toList()
                        : rawSegments;

                    // Aktif segmenti bul (kesikli olmayan, yani alım sonrası)
                    final activeSeg = segments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final anchorSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.first : null;
                    final lastSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.last : null;

                    // Compare mode: ikinci varlığın history'sini alt bir
                    // FutureBuilder ile fetch ediyoruz. Veri hazır olunca
                    // ilk noktası 100 kabul edilip (val/first)*100 normalize.

                    // MA20 overlay: aktif segmentin fiyat serisi üzerinden
                    // hesaplanır. İlk 19 nokta NaN olur (yetersiz veri) →
                    // atlanır. Kullanıcı chip ile açıp kapatır.
                    final ma20On = ref.watch(chartMA20Provider);
                    List<FlSpot>? ma20Spots;
                    if (ma20On && activeSeg.spots.length >= 20) {
                      // MA20 her zaman ham fiyat serisinden hesaplanır;
                      // sonra grafiğe koyulurken log domain'e alınır.
                      final rawActive = rawSegments.firstWhere(
                        (s) => !s.dashed && s.spots.isNotEmpty,
                        orElse: () => TransactionSegment(
                          spots: const [],
                          lineColor: context.c.amberText,
                          areaGradientStart: Colors.transparent,
                          areaGradientEnd: Colors.transparent,
                          thickness: 3.5,
                        ),
                      );
                      final prices =
                          rawActive.spots.map((s) => s.y).toList();
                      final sma = TechnicalAnalysisService.smaSeries(
                          prices, 20);
                      ma20Spots = <FlSpot>[];
                      for (int i = 0; i < sma.length; i++) {
                        if (sma[i].isNaN) continue;
                        ma20Spots
                            .add(FlSpot(rawActive.spots[i].x, toY(sma[i])));
                      }
                    }
                    // Seçili periyodun değişimi — HAM fiyat serisinden.
                    double? periodChangeTRY;
                    double? periodChangePct;
                    {
                      // DÖNEM DEĞİŞİMİ SAHİPTEN BAĞIMSIZ OLMALI.
                      //
                      // Bu yüzde "bu üründe bu dönemde ne oldu" sorusunu
                      // yanıtlar; "ben ne kadar kazandım" sorusunu DEĞİL.
                      // Dolayısıyla iki ortak aynı ürüne aynı dönemde
                      // baktığında AYNI yüzdeyi görmelidir — alım tarihleri
                      // farklı olsa bile.
                      //
                      // `rawActiveSeg` bu iş için KULLANILAMAZ, çünkü
                      // `_convertHistoryToSegments` onu sahibe göre bozar:
                      //   · seri sahibin alım gününde kesilir (`isBefore`
                      //     kontrolü) → 6 ay önce alan ile 3 ay önce alan
                      //     farklı noktadan başlar,
                      //   · ilk nokta piyasa fiyatı yerine sahibin ORTALAMA
                      //     MALİYETİ ile değiştirilir (anchor).
                      // İkisi birleşince bölen (`f`) sahibin maliyeti olur ve
                      // yüzde kişiye göre değişir; hatta biri kârda diğeri
                      // zararda görünür. Kullanıcı bunu altında yakaladı.
                      //
                      // Ham `historyMap` ise saf piyasa serisidir: sahibin
                      // alım tarihinden ve maliyetinden etkilenmez.
                      final sortedTs = historyMap.keys.toList()..sort();
                      if (sortedTs.length >= 2) {
                        // `historyMap` toplam pozisyon değeri taşır; birim
                        // fiyata inmek için miktara bölünür. Oran alındığı
                        // için bölen sadeleşir — yüzde miktardan bağımsızdır.
                        final divisor = qty > 0 ? qty : 1.0;
                        final f = historyMap[sortedTs.first]! / divisor;
                        final l = historyMap[sortedTs.last]! / divisor;
                        // Tutar ise sahibe özgüdür: aynı yüzde hareketi,
                        // elde tutulan miktara göre farklı TL eder.
                        periodChangeTRY = (l - f) * qty;
                        if (f > 0) periodChangePct = ((l - f) / f) * 100;
                      }
                    }

                    final anchorY = anchorSpot?.y ?? 0.0;
                    final totalCostTRY = asset.totalCostTRY;
                    final totalPnlTRY = currentValueTRY - totalCostTRY;
                    final pnlPct = totalCostTRY > 0
                        ? (totalPnlTRY / totalCostTRY) * 100
                        : 0.0;
                    final gainPositive = totalPnlTRY >= 0;
                    final endpointColor =
                        gainPositive ? context.c.gain : context.c.loss;

                    // Lot marker'ları için: gün-hassasiyetli tarih → (isSell) map.
                    // Aynı güne birden fazla işlem düşerse buy önceliklidir
                    // (ek alım genelde daha anlamlı sinyal).
                    // `isDeleteLog` tek başına yetmiyordu: yumuşak silinmiş
                    // lot'lar (deletedAt != null) ve TEMETTÜ satırları da
                    // nokta üretiyordu. Temettü bir alım/satım değil ve
                    // miktara hiç dokunmaz — noktası olmamalı. `isActive`
                    // mezar taşı + yumuşak silmeyi birlikte eler.
                    //
                    // Anahtar GERÇEK spot X'i (kesirli gün), tam sayı gün
                    // DEĞİL. Eskiden `spot.x.toInt()` ile tam gün eşleşmesi
                    // aranıyordu ve 6A/1Y'de noktalar kayboluyordu: o
                    // periyotlarda veri `ResolutionTier.weekly` gelir ve her
                    // nokta haftanın PAZARTESİSİNE snap edilir, dolayısıyla
                    // çarşamba yapılan bir işlemin gün anahtarı hiçbir spot'a
                    // denk gelmiyordu. Artık her işlem, içine düştüğü bar'a
                    // (`coveringSpotIndex`) bağlanıyor.
                    final Map<double, bool> lotDayIsSell = {};
                    final activeLots = widget.lots ?? [widget.asset];
                    final startMidnight = DateTime(
                        startDate.year, startDate.month, startDate.day);
                    final primarySpots = segments
                        .firstWhere((s) => !s.dashed && s.spots.isNotEmpty,
                            orElse: () => TransactionSegment(
                                  spots: const [],
                                  lineColor: context.c.amberText,
                                  areaGradientStart: Colors.transparent,
                                  areaGradientEnd: Colors.transparent,
                                  thickness: 3.5,
                                ))
                        .spots;
                    for (final lot in activeLots) {
                      if (!lot.isActive) continue;
                      if (!lot.isBuy && !lot.isSell) continue;
                      // GÜN İÇİNDE saat KIRPILMAZ. Diğer periyotlarda bir
                      // günün çözünürlüğü zaten bir noktadır ve işlemi gece
                      // yarısına çekmek doğrudur; gün içi seride ise 14:00'te
                      // yapılan bir alımın noktası 00:00'a düşer ve grafikteki
                      // sıçramayla hiç örtüşmezdi.
                      final d = isIntraday
                          ? lot.addedDate
                          : DateTime(lot.addedDate.year, lot.addedDate.month,
                              lot.addedDate.day);
                      if (d.isBefore(startMidnight)) continue;
                      final txX =
                          d.difference(startMidnight).inMinutes / (60.0 * 24.0);
                      final i = coveringSpotIndex(primarySpots, txX);
                      if (i < 0) continue;
                      final key = primarySpots[i].x;
                      final isSell = lot.isSell;
                      // Buy varsa buy kalsın (override etme)
                      if (lotDayIsSell.containsKey(key) &&
                          !lotDayIsSell[key]!) {
                        continue;
                      }
                      lotDayIsSell[key] = isSell;
                    }

                    // Y sınırlarını görünür X aralığındaki spot'lara göre
                    // hesaplayan closure — zoom sırasında yeniden çağrılır.
                    ({double minY, double maxY}) computeY(
                        double viewMinX, double viewMaxX,
                        {List<FlSpot>? extraSpots}) {
                      double minY = double.infinity;
                      double maxY = -double.infinity;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      // Compare barı da Y aralığına dahil edilsin ki
                      // 2. varlığın çizgisi grafik dışına düşmesin.
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      if (minY == double.infinity) minY = 0;
                      if (maxY == -double.infinity) maxY = 1000;

                      // Compare modda anchor 100 (normalize base). Aksi
                      // halde anchorY (ham ilk noktanın normalize hali).
                      final center = compareOn
                          ? 100.0
                          : (anchorY > 0 ? anchorY : (minY + maxY) / 2);
                      double maxAbsDev = 0;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      // Asgari yarı-bant. Eksen yalnızca veriye göre
                      // ölçeklenirse yatay giden bir fiyatın kuruşluk
                      // dalgalanması tuvale yayılır ve olmayan bir "çöküş"
                      // çizilir; taban bunu keser.
                      //
                      // GÜN İÇİNDE taban DARDIR: bir hissenin günlük
                      // hareketi tipik olarak ±%0,5–2'dir ve %1'lik yarı-bant
                      // (yani %2'lik tam bant) o hareketi grafiğin onda
                      // birine sıkıştırıp çizgiyi DÜMDÜZ gösterir. Portföy
                      // performans ekranı aynı dersi `gunIciAsgariBantOrani`
                      // ile öğrenmişti (tam bant %0,5) — burada da yarısı,
                      // yani %0,25 yarı-bant kullanılır.
                      //
                      // Mutlak 1 TL tabanı gün içinde UYGULANMAZ: birim
                      // fiyatı 10 TL olan bir fonda ±1 TL, ±%10'luk bir
                      // bant demektir ve fonun gerçek günlük değişimini
                      // (binde birkaç) yine görünmez kılardı.
                      final oransalTaban =
                          center * (isIntraday ? 0.0025 : 0.01);
                      final minDev = isIntraday
                          ? (oransalTaban > 0 ? oransalTaban : 1.0)
                          : oransalTaban.clamp(1.0, double.infinity);
                      final halfRange =
                          maxAbsDev < minDev ? minDev : maxAbsDev;
                      final yPad = halfRange * 0.35;
                      final rawMaxY = center + halfRange + yPad;
                      // Compare modda negatif % olabilir (varlık düşmüş) —
                      // 0'a clamp'lemeyelim; ham hesabı bırak.
                      final rawMinY = compareOn
                          ? (center - halfRange - yPad)
                          : (center - halfRange - yPad)
                              .clamp(0, double.infinity)
                              .toDouble();
                      // TradingView tarzı nice-round Y bound: label'lar temiz
                      // yuvarlak sayılar olsun ve grid çizgilerine denk gelsin.
                      final rawInterval = (rawMaxY - rawMinY) / 4;
                      if (rawInterval <= 0) {
                        return (
                          minY: rawMinY.toDouble(),
                          maxY: rawMaxY.toDouble()
                        );
                      }
                      final niceInterval = _niceRound(rawInterval);
                      final niceMin = compareOn
                          ? (rawMinY / niceInterval).floor() * niceInterval
                          : ((rawMinY / niceInterval).floor() *
                                  niceInterval)
                              .clamp(0.0, double.infinity);
                      final niceMax =
                          (rawMaxY / niceInterval).ceil() * niceInterval;
                      return (
                        minY: niceMin.toDouble(),
                        maxY: niceMax.toDouble()
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Yeni periyot yüklenirken ince bar — eski grafik
                        // ekranda kalır, kontroller tıklanabilir.
                        if (waiting)
                          SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: context.c.amberFill,
                            ),
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          _PnlSummaryStrip(
                            anchorUnitPrice: anchorUnitTRY,
                            currentUnitPrice: currentUnitTRY,
                            pnlPct: pnlPct,
                            totalPnl: totalPnlTRY,
                            unitLabel: widget.asset.unitLabel,
                            isPositive: gainPositive,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: SandikSpace.sm),
                        // Seçili periyodun değişimi — üstteki strip alış→bugün
                        // toplam PnL'i gösterir, bu satır "bu dönemde ne oldu"
                        // sorusunu yanıtlar. İkisi farklı sorular.
                        // Bayat seride GİZLENİR: rakam hâlâ eski periyoda ait
                        // olurdu ama etiket yeni periyodu yazardı — yanıltıcı.
                        // (Üstteki strip periyottan bağımsız, o kalır.)
                        if (periodChangeTRY != null && !isStale)
                          _PeriodChangeRow(
                            label: _periods[_selectedPeriodIdx].label,
                            changeTRY: periodChangeTRY,
                            changePct: periodChangePct,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: 12),
                        // Grafik overlay chip'leri (MA20 vb.). Basit toggle.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _OverlayChip(
                              label: 'MA20',
                              active: ma20On,
                              onTap: () {
                                ref
                                    .read(chartMA20Provider.notifier)
                                    .set(!ma20On);
                              },
                            ),
                            const SizedBox(width: 6),
                            _OverlayChip(
                              label: 'LOG',
                              active: logOn,
                              onTap: () {
                                ref
                                    .read(chartLogScaleProvider.notifier)
                                    .set(!logOn);
                              },
                            ),
                            const SizedBox(width: 6),
                            _FullscreenChip(
                              onTap: () {
                                FullscreenChartRoute.open(
                                  context,
                                  title: widget.asset.name,
                                  builder: (_) => PerformanceScreen(
                                    asset: widget.asset,
                                    lots: widget.lots,
                                    showBackButton: false,
                                    // Landscape'te grafiği hemen üste getir;
                                    // header/tab/chip'ler yukarı swipe ile.
                                    initialScrollOffset: 240,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Karşılaştırma GÜN İÇİNDE kapalı.
                        //
                        // Karşılaştırma serisi `getPortfolioHistory(days)`
                        // ile çekiliyor; gün içi sekmesi `days: 0` taşıdığı
                        // için o çağrı boş bir pencere isterdi. Ayrıca iki
                        // varlığın 5 dakikalık serisini yüzdeye normalize
                        // etmek ayrı bir iş — yarım yapılmış hâli, kullanıcı
                        // bakıp yanlış okuyacağı bir çizgi üretirdi.
                        if (!isIntraday)
                          _CompareStrip(
                            primaryTicker: widget.asset.ticker,
                            compare: _compareAsset,
                            onAddPressed: _openComparePicker,
                            onClearPressed: () {
                              setState(() {
                                _compareAsset = null;
                                _compareHistoryFuture = null;
                              });
                            },
                          ),
                        const SizedBox(height: 8),
                        FutureBuilder<Map<int, double>>(
                          future: _compareHistoryFuture,
                          builder: (context, compareSnap) {
                            // Compare barı — snapshot hazır olduğunda
                            // normalize edilip LineChartBarData olur.
                            LineChartBarData? compareBar;
                            if (compareOn &&
                                compareSnap.hasData &&
                                compareSnap.data!.isNotEmpty) {
                              final entries = compareSnap.data!.entries
                                  .toList()
                                ..sort((a, b) => a.key.compareTo(b.key));
                              final firstY = entries.first.value;
                              if (firstY.abs() > 1e-9) {
                                final spots = <FlSpot>[];
                                for (final e in entries) {
                                  final ts = e.key;
                                  final date = DateTime
                                      .fromMillisecondsSinceEpoch(ts);
                                  final x = date
                                          .difference(startDate)
                                          .inMinutes /
                                      (60.0 * 24.0);
                                  if (x < 0) continue;
                                  spots.add(FlSpot(
                                      x, (e.value / firstY) * 100.0));
                                }
                                if (spots.length >= 2) {
                                  compareBar = LineChartBarData(
                                    spots: spots,
                                    isCurved: false,
                                    color: _kCompareColor,
                                    barWidth: 1.6,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData:
                                        BarAreaData(show: false),
                                  );
                                }
                              }
                            }
                            // Bayat seri soluk çizilir — spinner yerine
                            // bağlam sunar, ama "bu henüz yeni periyodun
                            // verisi değil" hissini korur.
                            return AnimatedOpacity(
                              opacity: isStale ? 0.35 : 1.0,
                              duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
                              curve: SandikMotion.enter,
                              child: Container(
                          height: 400,
                          decoration: BoxDecoration(
                            color: context.c.surface1,
                            borderRadius: BorderRadius.circular(SandikRadius.md),
                            border: Border.all(
                                color: context.c.overlay),
                          ),
                          padding: const EdgeInsets.only(
                              top: 36, right: 16, left: 8, bottom: 16),
                          child: Builder(builder: (_) {
                            // Aktif segment (alış → bugün) tüm dönemin
                            // %25'inden azsa viewport'u aktif segmentin
                            // etrafına daralt — kullanıcı yıllık seçse
                            // bile 2 gün önce aldığı varlık için grafik
                            // dolgun görünsün, dikey çubuk gibi değil.
                            // Sağa daha fazla pay (~%8) → son nokta ve
                            // "ŞİMDİ" etiketi x-tick'lerle çakışmasın.
                            double focusMin = -maxX * 0.03;
                            double focusMax = maxX * 1.08;
                            // GÜNLÜK sekmesinde daraltma YOK: gün bir
                            // TAKVİM GÜNÜDÜR. Bugün 14:00'te alınan bir
                            // varlık için ekseni alım anının etrafına
                            // daraltmak, aynı sekmeye her bakışta farklı
                            // bir zaman ölçeği gösterirdi — hareket gün
                            // içindeki YERİYLE birlikte okunmalı.
                            if (!isIntraday &&
                                anchorSpot != null &&
                                lastSpot != null) {
                              final firstX = anchorSpot.x;
                              final lastX = lastSpot.x;
                              final activeSpan = lastX - firstX;
                              if (activeSpan < maxX * 0.25) {
                                final pad = activeSpan < 1.0
                                    ? 1.0
                                    : activeSpan * 0.8;
                                focusMin = (firstX - pad).clamp(-maxX * 0.03, maxX);
                                // Sağa fazladan %25 pay → son nokta
                                // grafiğin sağ kenarında değil, biraz
                                // içeride kalsın ki "şimdi" etiketi ve
                                // dot rahat okunsun.
                                focusMax = (lastX + pad * 1.25)
                                    .clamp(focusMin + 0.5, maxX * 1.08);
                              }
                            }
                            // Seyreltme adayları viewport'a bağlı DEĞİL —
                            // yalnızca segment'lere ve lot günlerine bağlı.
                            // Builder içinde bırakılırsa her pinch/pan
                            // karesinde expand+map+where zinciri baştan
                            // kurulurdu. Bir kez hesapla.
                            // Anahtarlar zaten gerçek spot X'leri — doğrudan
                            // aday listesi olarak kullanılabilir.
                            final dotCandidates =
                                lotDayIsSell.keys.toList(growable: false);
                            return ZoomableChart(
                            fullMinX: focusMin,
                            fullMaxX: focusMax,
                            height: 400 - 36 - 16,
                            plotPaddingRight: 60,
                            builder: (viewMinX, viewMaxX) {
                              final yBounds = computeY(
                                viewMinX,
                                viewMaxX,
                                extraSpots: compareBar?.spots,
                              );
                              final viewMinY = yBounds.minY;
                              final viewMaxY = yBounds.maxY;
                              // Lot marker'ları piksel bazlı seyreltmeden
                              // geçer — arka arkaya alım yapılan günlerde
                              // dot'lar üst üste binip yığın gibi
                              // görünüyordu. Zoom'da viewport daralınca
                              // gizlenenler tek tek ortaya çıkar.
                              // Adaylar gerçek spot X'leridir: `spot.x`
                              // kesirli gün (dakika/1440), gün anahtarı ise
                              // `spot.x.toInt()`. Gün anahtarını doğrudan
                              // aday yaparsak hiçbir spot'a eşleşmez.
                              final dotThinner = DotThinner.build(
                                candidates: dotCandidates,
                                viewMinX: viewMinX,
                                viewMaxX: viewMaxX,
                                plotWidthPx: (MediaQuery.of(context)
                                            .size
                                            .width -
                                        60 -
                                        40)
                                    .clamp(120.0, 2000.0),
                                // Nokta çapı küçüldü (r=3 + 1.2 halka) →
                                // ayrım eşiği de düşebilir: daha az nokta
                                // gizlenir, üst üste binme yine olmaz.
                                minSeparationPx: 11,
                                // Uç noktalara (r=5.5) yakın işlemler kalıcı
                                // olarak gizlenmesin — bkz. DotThinner.
                                anchorSeparationPx: 8,
                                alwaysKeep: {
                                  if (anchorSpot != null) anchorSpot.x,
                                  if (lastSpot != null) lastSpot.x,
                                },
                              );
                              return LineChartData(
                          minX: viewMinX,
                          maxX: viewMaxX,
                          minY: viewMinY,
                          maxY: viewMaxY,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: (viewMaxY - viewMinY) > 0
                                ? _niceRound(
                                    (viewMaxY - viewMinY) / 4)
                                : 50000,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: context.c.overlay,
                              strokeWidth: 1,
                            ),
                          ),
                          // TradingView paritesi: plot area sağ kenarına
                          // ince Y-ekseni ayraç çizgisi — Y bandı görsel
                          // olarak plot area'dan ayrılsın.
                          borderData: FlBorderData(
                            show: true,
                            border: Border(
                              right: BorderSide(
                                color: context.c.overlay,
                                width: 1,
                              ),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            // Y ekseni SAĞDA (TradingView convention).
                            // leftTitles kapalı. rightTitles nice-round
                            // interval ile temiz sayılar (100K/200K/...).
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                interval: (viewMaxY - viewMinY) > 0
                                    ? _niceRound(
                                        (viewMaxY - viewMinY) / 4)
                                    : 50000,
                                getTitlesWidget: (value, meta) {
                                  if (value == meta.min ||
                                      value == meta.max) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = compareOn
                                      ? '${(value - 100).toStringAsFixed(1)}%'
                                      : fmtTRYCompact(fromY(value));
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.left,
                                      // Eksen etiketi — tabular figür, tik
                                      // değerleri değişince kaymasın.
                                      style: context.t.numSmall.copyWith(
                                        color: context.c.text58,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // X ekseni: dinamik format (span'a göre yıl/saat
                            // ekle), nice-round interval.
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: (viewMaxX - viewMinX) > 0
                                    ? _niceRound(
                                        (viewMaxX - viewMinX) / 5)
                                    : 1,
                                getTitlesWidget: (value, meta) {
                                  final span =
                                      (meta.max - meta.min).abs();
                                  // Etiket tick'in üzerinde ortalanır; kenara
                                  // çok yakın tick'in etiketi plot alanının
                                  // dışına taşar. Zoom'da interval sınırlara
                                  // denk gelmediği için min/max eşitliği
                                  // yetmiyor — %6 kenar payı bırak.
                                  final edge = span * 0.06;
                                  if (value <= meta.min + edge ||
                                      value >= meta.max - edge) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = startDate.add(Duration(
                                      minutes:
                                          (value * 60 * 24).round()));
                                  final showYearOnly = span > 400;
                                  final showTime = span < 3;
                                  final showYear = !showYearOnly &&
                                      date.year != DateTime.now().year;
                                  // Gün içi sekmesinde tek bir gün çizilir;
                                  // her etikette aynı tarihi tekrarlamak
                                  // 74pt'lik etiketi kırpar ve okunması
                                  // gereken SAATİ gölgeler.
                                  final label = isIntraday
                                      ? DateFormat('HH:mm', 'tr_TR')
                                          .format(date)
                                      : showYearOnly
                                          ? DateFormat('MMM yy', 'tr_TR')
                                              .format(date)
                                          : showTime
                                              ? DateFormat('d MMM HH:mm',
                                                      'tr_TR')
                                                  .format(date)
                                              : DateFormat(
                                                      showYear
                                                          ? 'd MMM yy'
                                                          : 'd MMM',
                                                      'tr_TR')
                                                  .format(date);
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(top: 10),
                                    // Sabit genişlik + ortalama: taşan metin
                                    // ellipsis olur, komşu etiketle çakışmaz.
                                    child: SizedBox(
                                      width: 74,
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        // Eksen etiketi — tabular figür, tik
                                        // değerleri değişince kaymasın.
                                        style: context.t.numSmall.copyWith(
                                          color: context.c.text58,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          extraLinesData: anchorSpot != null
                              ? ExtraLinesData(
                                  horizontalLines: [
                                    HorizontalLine(
                                      y: anchorY,
                                      color: context.c.text36,
                                      strokeWidth: 1,
                                      dashArray: const [4, 4],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        alignment: Alignment.topLeft,
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 2),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w800,
                                          color: context.c.text90
                                              .withValues(alpha: 0.75),
                                        ),
                                        // Gün içinde çapa ALIŞ FİYATI DEĞİL,
                                        // günün ilk noktasıdır (bkz.
                                        // `_convertHistoryToSegments`
                                        // `intraday`). Etiketi "ALIŞ"
                                        // bırakmak doğrudan yanlış bilgi
                                        // olurdu.
                                        labelResolver: (_) =>
                                            '${isIntraday ? 'AÇILIŞ' : 'ALIŞ'}  ${NumberFormat('#,##0.00', 'tr_TR').format(anchorY)} ₺',
                                      ),
                                    ),
                                  ],
                                  verticalLines: [
                                    // Başlangıç (alış) X'i — tarih etiketli
                                    // dashed vertical marker.
                                    VerticalLine(
                                      x: anchorSpot.x,
                                      color: context.c.amberText
                                          .withValues(alpha: 0.4),
                                      strokeWidth: 1.2,
                                      dashArray: const [4, 4],
                                      label: VerticalLineLabel(
                                        show: true,
                                        alignment: Alignment.topRight,
                                        padding: const EdgeInsets.only(
                                            bottom: 8, left: 6),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w700,
                                          color: context.c.amberText,
                                        ),
                                        labelResolver: (_) {
                                          final buyDate = startDate.add(
                                              Duration(
                                                  minutes:
                                                      (anchorSpot.x * 1440)
                                                          .round()));
                                          if (isIntraday) {
                                            return 'AÇILIŞ ${DateFormat('HH:mm', 'tr_TR').format(buyDate)}';
                                          }
                                          return 'ALIŞ ${DateFormat('d MMM', 'tr_TR').format(buyDate)}';
                                        },
                                      ),
                                    ),
                                    // Bitiş (bugün) X'i — "ŞİMDİ" etiketi
                                    // ile net görünsün.
                                    if (lastSpot != null)
                                      VerticalLine(
                                        x: lastSpot.x,
                                        color: endpointColor
                                            .withValues(alpha: 0.55),
                                        strokeWidth: 1.2,
                                        dashArray: const [4, 4],
                                        label: VerticalLineLabel(
                                          show: true,
                                          alignment: Alignment.topLeft,
                                          padding: const EdgeInsets.only(
                                              bottom: 8, right: 6),
                                          style: context.t.labelMedium?.copyWith(
                                            letterSpacing: 0,
                                            fontWeight: FontWeight.w700,
                                            color: endpointColor,
                                          ),
                                          labelResolver: (_) => 'ŞİMDİ',
                                        ),
                                      ),
                                  ],
                                )
                              : const ExtraLinesData(),
                          lineBarsData: <LineChartBarData>[
                            if (ma20Spots != null && ma20Spots.length >= 2)
                              LineChartBarData(
                                spots: ma20Spots,
                                isCurved: false,
                                color: context.c.text58,
                                barWidth: 1.4,
                                isStrokeCapRound: true,
                                dashArray: const [3, 3],
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            if (compareBar != null) compareBar,
                            ...segments
                              .map((seg) {
                                // Trading estetiği: dönem uzadıkça ince
                                // çizgi, kısa dönemde biraz belirgin.
                                // Merdiven `chart_line_width.dart`'ta —
                                // takip/karşılaştır grafiği de aynı
                                // fonksiyonu çağırır.
                                final periodDays = _periods[_selectedPeriodIdx].days;
                                final baseWidth =
                                    donemCizgiKalinligi(periodDays);
                                final effective = seg.dashed ? seg.thickness : baseWidth;
                                return LineChartBarData(
                                    spots: seg.spots,
                                    isCurved: false,
                                    color: seg.lineColor,
                                    barWidth: effective,
                                    isStrokeCapRound: true,
                                    dashArray: seg.dashed ? const [4, 4] : null,
                                    dotData: FlDotData(
                                      show: !seg.dashed,
                                      checkToShowDot: (spot, barData) {
                                        if (seg.dashed) return false;
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return true;
                                        }
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return true;
                                        }
                                        if (!lotDayIsSell.containsKey(spot.x)) {
                                          return false;
                                        }
                                        return dotThinner.shows(spot.x);
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        // Alış: beyaz halkalı amber (ince).
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: context.c.amberText,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 2,
                                          );
                                        }
                                        // Son (şimdi): kar/zarar rengi.
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: endpointColor,
                                            strokeColor: context.c.text90
                                                .withValues(alpha: 0.85),
                                            strokeWidth: 1.5,
                                          );
                                        }
                                        // Ek alım / satış marker'ları
                                        final isSell = lotDayIsSell[spot.x];
                                        if (isSell != null) {
                                          // Ortadaki işlem noktaları uçlardan
                                          // (5.5px) belirgin biçimde küçük —
                                          // yoğun işlem yapılan dönemde çizgi
                                          // boncuk dizisine dönüşmesin. Halka
                                          // da inceltildi: küçük yarıçapta 2px
                                          // kenar içi boş gösteriyordu.
                                          return FlDotCirclePainter(
                                            radius: 3.0,
                                            color: isSell
                                                ? context.c.loss
                                                : context.c.gain,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 1.2,
                                          );
                                        }
                                        return FlDotCirclePainter(
                                          radius: 3.0,
                                          color: context.c.amberText,
                                          strokeColor: context.c.background,
                                          strokeWidth: 1.5,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: seg.dashed
                                            ? [
                                                seg.areaGradientStart,
                                                seg.areaGradientEnd,
                                              ]
                                            : [
                                                context.c.amberText
                                                    .withValues(alpha: 0.22),
                                                context.c.amberText
                                                    .withValues(alpha: 0.06),
                                                Colors.transparent,
                                              ],
                                        stops: seg.dashed
                                            ? null
                                            : const [0.0, 0.5, 1.0],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  );
                              }),
                          ],
                          // Built-in tooltip kapalı — crosshair TEK KAYNAK.
                          // fl_chart tooltip'i ile ZoomableChart crosshair'ı
                          // paralel çalışınca X hesabı farklı olup değerler
                          // uyumsuz görünüyordu.
                          lineTouchData: LineTouchData(
                            enabled: false,
                            handleBuiltInTouches: false,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  context.c.surface1.withValues(alpha: 0.95),
                              tooltipRoundedRadius: 10,
                              tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (touchedSpots) {
                                final valueFmt =
                                    NumberFormat('#,##0.000', 'tr_TR');
                                // Passive + active segmentler anchor noktasında
                                // aynı (x, y) spot'unu paylaşır → aynı tooltip
                                // iki kere görünür. Yakın olanları filtrele.
                                final seen = <String>{};
                                return touchedSpots.map<LineTooltipItem?>((spot) {
                                  final key =
                                      '${spot.x.toStringAsFixed(2)}|${spot.y.toStringAsFixed(2)}';
                                  if (!seen.add(key)) return null;
                                  final date = startDate
                                      .add(Duration(days: spot.x.toInt()));
                                  final dateLabel = DateFormat('d MMM', 'tr_TR')
                                      .format(date);
                                  final tipText = compareOn
                                      ? '${(spot.y - 100).toStringAsFixed(2)}%'
                                      : '${valueFmt.format(fromY(spot.y))} ₺';
                                  return LineTooltipItem(
                                    tipText,
                                    context.t.numSmall.copyWith(
                                      color: context.c.text90,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '\n$dateLabel',
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          color: context.c.text58,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        );
                            },
                            crosshairSnapX: (x) {
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return x;
                              final clamped =
                                  x.clamp(spots.first.x, spots.last.x);
                              // Sıralı seri → ikili arama. Parmak her
                              // kaydığında çağrılıyor (bkz. nearestSpotIndex).
                              return spots[nearestSpotIndex(spots, clamped)].x;
                            },
                            crosshairLabelBuilder: (x) {
                              // x zaten snap edildi — spot'u bul.
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return null;
                              final snapped =
                                  spots[nearestSpotIndex(spots, x)];
                              final date = startDate.add(Duration(
                                  minutes:
                                      (snapped.x * 1440).round()));
                              final title = compareOn
                                  ? '${(snapped.y - 100).toStringAsFixed(2)}%'
                                  : NumberFormat.currency(
                                          locale: 'tr_TR',
                                          symbol: '₺',
                                          decimalDigits: 2)
                                      .format(fromY(snapped.y));
                              // Gün içinde okunacak bilgi SAATTİR; tarih
                              // zaten sekmenin kendisinden belli.
                              final subtitle = DateFormat(
                                      isIntraday
                                          ? 'd MMM · HH:mm'
                                          : 'd MMM yyyy',
                                      'tr_TR')
                                  .format(date);
                              return (title, subtitle);
                            },
                          );
                          }),
                        ),
                            ); // AnimatedOpacity (bayat seri solukluğu)
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                // Miktar Bilgisi
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.c.overlay,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(color: context.c.hairline),
                  ),
                  // Etiket + değer yan yana; ikisi de sınırsızdı ve büyük
                  // miktarlarda satır taşıyordu (105px). Etiket kırpılabilir,
                  // değer ise FittedBox ile küçülerek sığar — rakam kırpmak
                  // yanlış okumaya yol açar.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'TOPLAM MİKTAR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelLarge?.copyWith(
                              color: context.c.amberText,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${fmtNum(_currentQuantity, digits: 2)} ${widget.asset.unitType}',
                            maxLines: 1,
                            style: context.t.numLarge.copyWith(
                                color: context.c.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.asset.type != AssetType.mevduat)
                  TechnicalSignalPanel.forAsset(widget.asset,
                      key: _sinyalPaneliKey, detayli: true),
                // Push'a dokunup gelen kullanıcının aradığı ayrıntı: EN ALTTA
                // ve yalnızca aktif kayıt varsa. Mevduatta sinyal üretilmez.
                if (widget.asset.type != AssetType.mevduat)
                  AktifSinyalBolumu(
                      asset: widget.asset, icerikKey: _aktifSinyalKey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PnL özet strip'i (alış → şimdi + değişim) ────────────────────────────────

/// Seçili periyodun değişimi — tek satır, üstteki [_PnlSummaryStrip]'in
/// altında durur.
///
/// İkisi farklı soruları yanıtlar ve bilerek ayrı tutulmuştur:
/// - [_PnlSummaryStrip]: "aldığımdan bugüne ne kazandım?" (toplam PnL)
/// - Bu satır: "seçtiğim dönemde ne oldu?" (dönemsel değişim)
///
/// Değişim ham fiyat farkıdır (son − ilk) × miktar. Grafikteki çizginin iki
/// ucuyla birebir tutarlıdır.
class _PeriodChangeRow extends StatelessWidget {
  final String label;
  final double changeTRY;
  final double? changePct;

  const _PeriodChangeRow({
    required this.label,
    required this.changeTRY,
    required this.changePct,
  });

  @override
  Widget build(BuildContext context) {
    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr — yeşil/kırmızı
    // göstermek "hareket var" yanılgısı yaratır.
    final isFlat =
        changeTRY.abs().round() == 0 && (changePct?.abs() ?? 0) < 0.005;
    final positive = changeTRY >= 0;
    final color =
        isFlat ? context.c.text36 : (positive ? context.c.gain : context.c.loss);
    final tryFmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          // Etiket de kırpılabilmeli: dar ekranda tam genişliği alıp sağdaki
          // tutarı taşırıyordu (320pt'de 54px). Değer zaten Flexible.
          Flexible(
            child: Text(
              '$label DEĞİŞİM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.c.text36,
              ),
            ),
          ),
          const Spacer(),
          if (!isFlat) ...[
            Icon(
              positive
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                isFlat
                    ? 'Değişim yok'
                    : '${positive ? '+' : '−'}${tryFmt.format(changeTRY.abs())}',
                maxLines: 1,
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ),
          if (changePct != null && !isFlat) ...[
            const SizedBox(width: SandikSpace.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: SandikRadius.smAll,
              ),
              child: Text(
                fmtPct(changePct!.abs(), digits: 2),
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PnlSummaryStrip extends StatelessWidget {
  final double anchorUnitPrice;
  final double currentUnitPrice;
  final double pnlPct;
  final double totalPnl;
  final String unitLabel;
  final bool isPositive;

  const _PnlSummaryStrip({
    required this.anchorUnitPrice,
    required this.currentUnitPrice,
    required this.pnlPct,
    required this.totalPnl,
    required this.unitLabel,
    required this.isPositive,
  });

  String _fmtPrice(double v) {
    // Birim fiyat — kullanıcı per-unit farkı algılayabilsin diye ondalık koru.
    // Grup ayraçlı, 2 ondalıklı (tr locale).
    final f = NumberFormat('#,##0.00', 'tr_TR');
    return '${f.format(v)} ₺';
  }

  String _fmtTotal(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1000000) return '$sign${fmtNum(abs / 1000000, digits: 2)}M ₺';
    if (abs >= 1000) return '$sign${fmtNum(abs / 1000, digits: 1)}k ₺';
    return '$sign${fmtNum(abs, digits: 0)} ₺';
  }

  @override
  Widget build(BuildContext context) {
    // Değişim yoksa (yuvarlanmış tutar ve yüzde ikisi de sıfırsa) nötr göster.
    final bool isFlat =
        totalPnl.abs().round() == 0 && pnlPct.abs() < 0.005;
    final Color accent = isFlat
        ? context.c.text36
        : (isPositive ? context.c.gain : context.c.loss);
    final String sign = isPositive ? '+' : '−';
    final IconData arrow = isPositive
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.8), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ALIŞ / $unitLabel',
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(anchorUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          color: context.c.text58)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded,
                size: 14, color: context.c.text36),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUGÜN / $unitLabel',
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(currentUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.c.text90)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isFlat)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border:
                    Border.all(color: context.c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.horizontal_rule_rounded,
                      size: 14, color: context.c.text58),
                  const SizedBox(width: 4),
                  Text('Değişim yok',
                      style: context.t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text58)),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(arrow, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$sign${_fmtTotal(totalPnl.abs())}',
                          style: context.t.numSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(
                          '$sign${_fmtPrice((currentUnitPrice - anchorUnitPrice).abs())} / $unitLabel',
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.2)),
                      const SizedBox(height: 1),
                      Text(fmtPct(pnlPct.abs(), digits: 2),
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.0)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fullscreen landscape moduna geçiren küçük ikon buton.
class _FullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _FullscreenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: context.c.overlay,
            ),
          ),
          child: Icon(
            Icons.fullscreen_rounded,
            size: 16,
            color: context.c.text58,
          ),
        ),
      ),
    );
  }
}

/// Grafik üzerine çizilen göstergeleri açıp kapatan küçük toggle chip.
class _OverlayChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OverlayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: AnimatedContainer(
          duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
          curve: SandikMotion.enter,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: active
                  ? context.c.amberFill.withValues(alpha: 0.55)
                  : context.c.overlay,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.check_rounded
                    : Icons.horizontal_rule_rounded,
                size: 12,
                color: active ? context.c.amberText : context.c.text58,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? context.c.amberText : context.c.text58,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Compare mode UI ─────────────────────────────────────────────────────────

/// Grafik container'ının üstünde: legend (rozet) + "Karşılaştır" ekle butonu.
/// Compare seçili değilse sadece + butonu görünür; seçiliyken rozet ve ✕.
class _CompareStrip extends StatelessWidget {
  final String primaryTicker;
  final Asset? compare;
  final VoidCallback onAddPressed;
  final VoidCallback onClearPressed;

  const _CompareStrip({
    required this.primaryTicker,
    required this.compare,
    required this.onAddPressed,
    required this.onClearPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Rozetler + "ekle" düğmesi sabit genişlikte değil: uzun ticker'lar
    // (TEFAS:YKT gibi) veya karşılaştırma rozeti eklenince satır taşıyordu
    // (15px). Yatay kaydırma, rozetleri kırpmadan sığdırır — hiçbir bilgi
    // gizlenmez, yalnızca gerekirse kaydırılır.
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          // Ana varlık rozeti — renk = context.c.amberText
          _LegendBadge(
            color: context.c.amberText,
            label: primaryTicker,
          ),
          const SizedBox(width: 8),
          if (compare != null) ...[
            _LegendBadge(
              color: _kCompareColor,
              label: compare!.ticker,
              onRemove: onClearPressed,
            ),
            const SizedBox(width: 8),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddPressed,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: context.c.overlay,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      compare == null
                          ? Icons.add_rounded
                          : Icons.swap_horiz_rounded,
                      size: 14,
                      color: context.c.text58,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compare == null ? 'Karşılaştır' : 'Değiştir',
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text58,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBadge extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback? onRemove;
  const _LegendBadge({
    required this.color,
    required this.label,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: onRemove == null ? 10 : 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close_rounded, size: 12, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compare picker satır kaynağı — hem portföydeki varlık hem de
/// katalog (BIST100 / döviz / altın) aynı yapıyla temsil edilir.
class _CompareChoice {
  final String ticker;
  final String name;
  final AssetType type;
  final String currency;
  final String source; // 'portfolio' | 'bist' | 'fx' | 'gold'

  const _CompareChoice({
    required this.ticker,
    required this.name,
    required this.type,
    required this.currency,
    required this.source,
  });

  /// HistoryService'in beklediği minimum alanları sağlayan sanal Asset.
  /// Grafik için sadece ticker/type/currency kullanılıyor.
  /// addedDate çok geriye ayarlanır — HistoryService `addedTs > dayTs` ise
  /// quantity=0 döndürüyor, bu compare için tüm dönemde quantity=1 olsun.
  Asset toVirtualAsset() {
    return Asset(
      id: 'compare-$ticker',
      userId: '',
      name: name,
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 1,
      currency: currency,
      notes: '',
      addedDate: DateTime(2000, 1, 1),
    );
  }
}

/// Katalog seçenekleri — kullanıcının portföyde tutmadığı varlıklarla
/// da karşılaştırma yapabilsin diye statik olarak sağlanır.
List<_CompareChoice> _catalogChoices() {
  final out = <_CompareChoice>[];
  // BIST100 hisseleri
  bist100StocksMap.forEach((ticker, name) {
    out.add(_CompareChoice(
      ticker: ticker,
      name: name,
      type: AssetType.hisse,
      currency: 'TRY',
      source: 'bist',
    ));
  });
  // Major dövizler
  out.addAll(const [
    _CompareChoice(
        ticker: 'USDTRY=X',
        name: 'ABD Doları',
        type: AssetType.doviz,
        currency: 'USD',
        source: 'fx'),
    _CompareChoice(
        ticker: 'EURTRY=X',
        name: 'Euro',
        type: AssetType.doviz,
        currency: 'EUR',
        source: 'fx'),
    _CompareChoice(
        ticker: 'GBPTRY=X',
        name: 'İngiliz Sterlini',
        type: AssetType.doviz,
        currency: 'GBP',
        source: 'fx'),
  ]);
  // Altın (gram karşılığı, HistoryService altın için USD/gr → TRY dönüşümü yapar)
  out.add(const _CompareChoice(
    ticker: 'XAU',
    name: 'Altın (Gram)',
    type: AssetType.altin,
    currency: 'USD',
    source: 'gold',
  ));
  return out;
}

/// Compare için varlık seçim sheet — iki sekme: Portföyüm + Diğer.
/// Arama kutusu aktif sekmede filtreler.
class _ComparePickerSheet extends StatefulWidget {
  final List<Asset> choices; // portföy varlıkları
  final String? currentSelectionTicker;
  final void Function(_CompareChoice?) onSelected;

  const _ComparePickerSheet({
    required this.choices,
    required this.currentSelectionTicker,
    required this.onSelected,
  });

  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late TabController _tabController;
  late List<_CompareChoice> _catalog = _catalogChoices();
  late final List<_CompareChoice> _portfolio = widget.choices
      .map((a) => _CompareChoice(
            ticker: a.ticker,
            name: a.name,
            type: a.type,
            currency: a.currency,
            source: 'portfolio',
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _appendTefas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// TEFAS fonlarını katalog listesine ekle. Uygulama açılışında disk
  /// cache'ten hazır geldiği için pratikte anında döner; spinner gösterme.
  Future<void> _appendTefas() async {
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      if (!mounted || funds.isEmpty) return;
      final extra = funds.map((f) => _CompareChoice(
            ticker: 'TEFAS:${f.code}',
            name: f.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ));
      setState(() {
        _catalog = [..._catalog, ...extra];
      });
    } catch (_) {
      // Cache yoksa TEFAS sekmesi olmadan devam et.
    }
  }

  // TEFAS liste API'sinde olmayan (kurucu-only) fonlar için tek-fon
  // lookup — kullanıcı ALE / YLB gibi bir kod yazınca arka planda çağrılır.
  final Set<String> _lookupInFlight = {};
  final Set<String> _lookupTried = {};

  Future<void> _tryLookupTefas(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 3 || code.length > 6) return;
    if (_lookupTried.contains(code)) return;
    if (_lookupInFlight.contains(code)) return;
    if (_catalog.any((c) => c.ticker == 'TEFAS:$code')) return;
    _lookupInFlight.add(code);
    try {
      final fund = await TefasService.instance.lookupFund(code);
      _lookupTried.add(code);
      if (!mounted || fund == null) return;
      setState(() {
        _catalog = [
          ..._catalog,
          _CompareChoice(
            ticker: 'TEFAS:${fund.code}',
            name: fund.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ),
        ];
      });
    } catch (_) {
      _lookupTried.add(code); // spam engelle
    } finally {
      _lookupInFlight.remove(code);
    }
  }

  List<_CompareChoice> _filter(List<_CompareChoice> src) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((c) {
      return c.ticker.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();
  }

  Widget _list(List<_CompareChoice> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sonuç yok.',
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final selected = widget.currentSelectionTicker == c.ticker;
        return ListTile(
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c.type.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            c.ticker,
            style: context.t.titleMedium?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          trailing: selected
              ? Icon(Icons.check_rounded, color: context.c.amberText)
              : null,
          onTap: () => widget.onSelected(c),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.overlay,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Karşılaştır',
                      style: context.t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.c.text90,
                      ),
                    ),
                    const Spacer(),
                    if (widget.currentSelectionTicker != null)
                      TextButton(
                        onPressed: () => widget.onSelected(null),
                        child: const Text('Temizle'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  style: TextStyle(color: context.c.text90),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.c.text58),
                    hintText: 'Ticker veya isim ara…',
                    hintStyle:
                        TextStyle(color: context.c.text36, fontSize: 13),
                    filled: true,
                    fillColor: context.c.overlay,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _query = v);
                    // Kurucu-only TEFAS fonları (ör. ALE, YLB) fetchAllFunds
                    // içinde yok — kullanıcı kısa bir kod yazınca arka
                    // planda lookup yap, bulunursa katalog liste güncellenir.
                    _tryLookupTefas(v);
                  },
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: context.c.amberText,
                labelColor: context.c.amberText,
                unselectedLabelColor: context.c.text58,
                labelStyle: context.t.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Portföyüm'),
                  Tab(text: 'Diğer'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _list(_filter(_portfolio)),
                    _list(_filter(_catalog)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Color _kCompareColor = Sandik.info;

