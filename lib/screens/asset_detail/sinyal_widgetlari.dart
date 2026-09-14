part of '../asset_detail_screen.dart';

/// Sinyal kartı, teknik sinyal paneli, sinyal dağılımı ve altın işlem modeli.
/// `asset_detail_screen.dart`'ın part'ı (2026-09-14); dışarıdan
/// `screens/asset_detail_screen.dart` ile import edilmeye devam eder.
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

/// Teknik göstergelerin istediği fiyat penceresi (gün).
///
/// ## Neden 90, neden 180 DEĞİL
/// 180 gün istemek göstergeleri TAMAMEN devre dışı bırakıyordu — hem
/// hisselerde hem fonlarda (ölçüldü 2026-09-10: THYAO 26 nokta, TEFAS:DPP
/// 26 nokta, eşik 30). Sebep pencerenin kendisi değil, `HistoryService`in
/// çözünürlük merdiveni: 180 gün HAFTALIK katmana düşüyor ve 125 günlük
/// nokta 26 haftalık kovaya iniyor.
///
/// Panel ise GÜNLÜK seri varsayıyor: MACD 26, Bollinger 20, ADX 2×14
/// nokta ister ve bunlar GÜN cinsinden düşünülmüştür. Haftalık kovalarda
/// 26 nokta yarım yıl değil, yarım yıllık **6 aylık** bir pencereye
/// karşılık gelir ve eşiğin altında kalır.
///
/// 90 gün günlük katmanda kalır ve 63 nokta verir (ölçüldü) — en uzun
/// göstergenin (ADX, 28) iki katından fazla.
///
/// Şerit ve panel AYNI değeri kullanmak zorunda: ikisi `HistoryService`
/// önbelleğini paylaşıyor ve farklı pencere isterlerse aynı varlık için
/// FARKLI sinyal gösterebilirler (bkz. `varlik_sinyal_karti_test.dart`).
const int kSinyalPenceresiGun = 90;

/// Bildirimin ne kadar önce geldiğini insan diliyle söyler ("10 dk önce").
///
/// ## Neden mutlak tarihin YANINDA, yerine değil
/// Kullanıcı iki şey istedi ve ikisi aynı anda geçerli: bildirimin zamanı
/// **kaçırılmamalı** (2026-09-10: "bildirim zaman ve tarihini ekle bunu
/// kaçırmaması lazım") ama şerit de tasarım örneğindeki gibi "10 dk önce"
/// okumalı. Göreli ifade tek başına bilgi KAYBEDER — "3 gün önce" hangi
/// gün, saat kaçta olduğunu söylemez ve aynı gün iki sinyal gelebilir.
/// Bu yüzden göreli metin sol satırda, mutlak tarih+saat sağ sütunda durur.
///
/// [now] dışarıdan verilir: içeride `DateTime.now()` çağrılsaydı eşik
/// dalları testte hiç çalışmazdı.
String goreliZaman(DateTime an, DateTime now) {
  final fark = now.difference(an);
  // Gelecek zaman: sunucu saati ile cihaz saati birkaç saniye kayabilir.
  // "-3 dk önce" yazmaktansa en yakın eşiğe yuvarlıyoruz.
  if (fark.inMinutes < 1) return 'az önce';
  if (fark.inMinutes < 60) return '${fark.inMinutes} dk önce';
  if (fark.inHours < 24) return '${fark.inHours} sa önce';
  return '${fark.inDays} gün önce';
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
        .getSymbolHistory(widget.asset.ticker, periodDays: kSinyalPenceresiGun)
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
                const CustomLoadingIndicator(size: 13),
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
  ///
  /// **Kabuk NÖTRDÜR.** Önceden zemin ve kenarlık sinyal rengiyle
  /// boyanıyordu (`renk` %7 dolgu, %28 kenarlık) ve şerit bir uyarı
  /// kutusuna dönüşüyordu: aşağı trendde ekranın üstünde kırmızı bir
  /// blok duruyordu. Sayfanın geri kalanı `surface1` + `hairline` sakin
  /// kartlardan oluşuyor; şerit tek başına bağırıyordu (kullanıcı
  /// bildirimi 2026-09-10: "tasarımı sayfa ve uygulamaya uygun olmalı,
  /// ahenk bozulmamalı").
  ///
  /// Renk KAYBOLMADI, yalnızca taşıdığı yere çekildi: ikon, başlık ve
  /// soldaki ince şerit hâlâ yön rengini kullanıyor. Anlamı renk taşır,
  /// zemin taşımaz.
  Widget _kabuk({required Color renk, required Widget child}) {
    final govde = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: SandikSpace.sm),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      // `IntrinsicHeight`: sol şerit içeriğin TAM boyunca uzanmalı. Sabit
      // yükseklik verilseydi büyük sistem yazı tipinde içerik uzayıp şerit
      // kısa kalırdı (ya da tersi).
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Yön göstergesi: sol kenarda ince dikey şerit. Ekranın
            // gösterge listesiyle aynı dil — kart nötr, sol şerit renkli.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: renk,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(SandikRadius.md),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: child,
              ),
            ),
          ],
        ),
      ),
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
    //
    // ## `canli` KOŞUL DEĞİL (2026-09-10'da ölçülerek bulundu)
    // Bu satır önce yalnızca `canli` iken çiziliyordu. Fiyat geçmişi
    // çekilemediğinde (çevrimdışı, kotasyondan kalkmış sembol) şerit
    // KAYDIN kendisini gösterir ve o durumda satır gizleniyordu: ekranda
    // yalnızca "10 Eyl · 23:15" kalıyor, bildirimin YÖNÜ ("▼ aşağı") ve
    // "10 dk önce" ifadesi tamamen kayboluyordu. Oysa push bildiriminin
    // açtığı ekran tam olarak burası — kaybolan şey kullanıcının geldiği
    // bilginin ta kendisiydi.
    //
    // Kayıt VARSA satır her iki yolda da çizilir; `canli` yalnızca sağ
    // sütunun "ŞU AN" mı yoksa tam tarih mi yazacağını belirler.
    final kayitSatiri = kayit != null
        ? 'Son bildirim: ${_kisaYon(kayit.signal)} · '
            '${goreliZaman(kayit.detectedAt, DateTime.now())}'
        : null;

    return _kabuk(
      renk: renk,
      child: Row(
        children: [
          // Yumuşak daire içinde ikon — ekranın gösterge listesiyle aynı
          // dil. Çıplak ikon nötr zeminde havada duruyordu.
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: renk.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(ikon, color: renk, size: 18),
          ),
          const SizedBox(width: 10),
          // Metin bloğu esner; sağdaki zaman etiketi sabit kalır. Uzun
          // varlık adlarında satır taşmasın diye Expanded şart.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst etiket: şeridin NE olduğunu söyler. Ekranın diğer
                // kartlarında ("BUGÜN / lot", "1H DEĞİŞİM") aynı kalıp
                // kullanılıyor — labelSmall + letterSpacing 0.8 + text36.
                // Sayfayla ahengi kuran şey bu tekrar.
                Text(
                  'TEKNİK GÖRÜNÜM',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: context.c.text36,
                  ),
                ),
                const SizedBox(height: 3),
                // Ton düşürüldü: `w800` + `letterSpacing 0.6` idi ve
                // kırmızı zeminle birleşince başlık bağırıyordu. Renk
                // korundu (yön bilgisini o taşıyor), ağırlık ekranın
                // diğer kart başlıklarıyla aynı seviyeye çekildi.
                Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
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
          // `Flexible` + `FittedBox`: sağdaki sütun sabit genişlik istiyordu
          // ve büyük yazı ölçeğinde satırı 39px taşırıyordu (ölçüldü:
          // 320pt × 1.6). Kayıt gösterilirken metin "ŞU AN" değil
          // "10 Eyl · 11:00" oluyor — iki katından uzun. Artık daralınca
          // küçülür, taşmaz.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Üst satır her zaman ZAMANI taşır. Canlı hesapta "ŞU AN",
                // kayıt gösterilirken TAM tarih+saat — göreli ifade soldaki
                // "Son bildirim" satırında duruyor, mutlak olan burada.
                // İkisi birlikte: hem hızlı okunur hem bilgi kaybı olmaz.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    canli
                        ? 'ŞU AN'
                        : DateFormat('d MMM · HH:mm', 'tr_TR')
                            .format(kayit!.detectedAt),
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Yön ikonunun TEKRARI. Soldaki daire içi ikonla aynı
                // sembol; tasarım örneğinde de böyle. Bilgi eklemiyor,
                // sağ sütunu görsel olarak dengeliyor — solda ikon+metin
                // varken sağda tek satır metin kalıyordu ve şerit sağa
                // doğru boşalıyordu.
                Icon(ikon, color: renk, size: 18),
              ],
            ),
          ),
          // Chevron sütunun ALTINDA değil YANINDA ve dikey ortada — "bu
          // karta dokunulabilir" işareti, zaman bilgisinin bir parçası
          // değil. Örnek tasarımda da ayrı bir sütun olarak duruyor.
          if (widget.onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: context.c.text36),
          ],
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

/// Teknik gösterge paneli.
///
/// **Bir `Asset` İSTEMEZ** — yalnızca sembol, tür ve alt kategori. Göstergeler
/// miktar/maliyet okumaz; sahiplikle ilgisi yoktur. Bu sayede aynı panel hem
/// sahip olunan varlıkta (`AssetDetailScreen`) hem de yalnızca izlenen
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
        .getSymbolHistory(widget.ticker, periodDays: kSinyalPenceresiGun)
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
                const CustomLoadingIndicator(size: 14),
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
                adaptiveRoute<void>(
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
