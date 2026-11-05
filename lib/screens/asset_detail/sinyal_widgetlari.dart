part of '../asset_detail_screen.dart';

/// Sinyal kartı, teknik sinyal paneli ve sinyal dağılımı.
/// `asset_detail_screen.dart`'ın part'ı (2026-09-14); dışarıdan
/// `screens/asset_detail_screen.dart` ile import edilmeye devam eder.
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

// Sinyal penceresi ve katmanı: `kSinyalPenceresiGun` / `kSinyalCozunurlugu`
// (`technical_analysis_service.dart`; provider da aynı değeri okur).

/// Özetin ekrandaki görünümü: etiket, ikon, renk.
///
/// Oyların çoğu ortalamaya dönüş göstergelerinden geliyorsa ([donus]) "al"
/// aşırı satım, "sat" aşırı alım demektir — fiyat DÜŞMÜŞ/YÜKSELMİŞTİR.
/// Bunu "YUKARI TREND" diye yazmak sert düşüşte yeşil yukarı oklu kart
/// gösteriyordu (denetim 2026-10-11, bulgu 1; simülasyonda %18'lik düşüşün
/// yarısında). Aşırılık durumu amber ve fiyatın son hareketinin oku ile
/// gösterilir; yön yalnız renkle anlatılmaz, metin her zaman yazılı.
({String etiket, IconData ikon, Color renk}) sinyalGorunumu(
    BuildContext context, SignalType signal, bool donus) {
  final l = context.l10n;
  final c = context.c;
  return switch ((signal, donus)) {
    (SignalType.buy, true) =>
      (etiket: l.sinyalAsiriSatim, ikon: Icons.trending_down_rounded, renk: c.amberText),
    (SignalType.sell, true) =>
      (etiket: l.sinyalAsiriAlim, ikon: Icons.trending_up_rounded, renk: c.amberText),
    (SignalType.buy, false) =>
      (etiket: l.trendUp, ikon: Icons.trending_up_rounded, renk: c.gain),
    (SignalType.sell, false) =>
      (etiket: l.trendDown, ikon: Icons.trending_down_rounded, renk: c.loss),
    _ => (etiket: l.trendFlat, ikon: Icons.remove_rounded, renk: c.text58),
  };
}

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
/// [l] sözlüğü çağıran verir: fonksiyon saf ve `BuildContext`'siz kalsın
/// (test onu doğrudan çağırıyor).
String goreliZaman(DateTime an, DateTime now, AppLocalizations l) {
  final fark = now.difference(an);
  // Gelecek zaman: sunucu saati ile cihaz saati birkaç saniye kayabilir.
  // "-3 dk önce" yazmaktansa en yakın eşiğe yuvarlıyoruz.
  if (fark.inMinutes < 1) return l.justNow;
  if (fark.inMinutes < 60) return l.minutesAgo(fark.inMinutes);
  if (fark.inHours < 24) return l.hoursAgo(fark.inHours);
  return l.daysAgo(fark.inDays);
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
        .getSymbolHistory(widget.asset.ticker,
            periodDays: kSinyalPenceresiGun, cozunurluk: kSinyalCozunurlugu)
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
    final izinli = ref.watch(izinliGostergelerProvider);
    final parametreler =
        ref.watch(etkinGostergeParametreleriProvider(widget.asset.type));
    final enabledIds = prefs[widget.asset.type] ??
        TechnicalAnalysisService.defaultEnabledFor(widget.asset.type);

    // Kullanıcı bu tür için hiçbir gösterge seçmemişse hesaplanacak bir
    // şey yok; alttaki panel bunu zaten açıklıyor, şeritte tekrar etmek
    // ekranın en değerli yerini bir uyarıya harcardı.
    if (enabledIds.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<double>>(
      future: _loadPrices(),
      builder: (context, snap) => SandikIcerikGecisi(
        // Hesaplanıyor satırı → sinyal çapraz solar (2026-10-14).
        anahtar: snap.connectionState == ConnectionState.waiting,
        child: ((BuildContext context, AsyncSnapshot<List<double>> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _kabuk(
            renk: context.c.text36,
            child: Row(
              children: [
                const CustomLoadingIndicator(size: 13),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.l10n.signalCalculating,
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
          izinli: izinli,
          parametreler: parametreler,
        );
        if (indicators.isEmpty) return const SizedBox.shrink();

        final ozet = TechnicalAnalysisService.summarize(indicators);
        return _satir(
          signal: ozet.signal,
          lehte:
              ozet.signal == SignalType.sell ? ozet.sellCount : ozet.buyCount,
          // Payda oylamaya giren TÜM göstergeler — güven yüzdesiyle ve
          // push metniyle aynı tanım (denetim bulgu 7).
          toplam: ozet.toplam,
          guven: ozet.confidence,
          canli: true,
          kayit: kayit,
          donus: ozet.donus,
          sayimlar: (
            yukari: ozet.buyCount,
            asagi: ozet.sellCount,
            notr: ozet.toplam - ozet.buyCount - ozet.sellCount,
          ),
        );
      })(context, snap),
      ),
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
    // Kabuk `SandikCard` (2. tur, 2026-10-08) — piksel aynı. Alt boşluk
    // kartın DIŞINDA ama `SandikBasma`'nın İÇİNDE kalır: eski `margin`
    // dokunma alanına dahildi, öyle kalsın.
    final govde = Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SizedBox(
        width: double.infinity,
        child: SandikCard(
          padding: EdgeInsets.zero,
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
        ),
      ),
    );
    if (widget.onTap == null) return govde;
    return SandikBasma(
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
    bool donus = false,
    ({int yukari, int asagi, int notr})? sayimlar,
  }) {
    // Yasal not: kesin "AL/SAT" yerine trend yönü ya da aşırılık bölgesi —
    // ekranın geri kalanıyla aynı dil (bkz. [sinyalGorunumu]). Kayıtlı
    // bildirim satırı (`donus` bilinmez) eski trend dilinde kalır: o metin
    // o gün gönderilen push'un kendisidir.
    final g = sinyalGorunumu(context, signal, donus);
    final renk = g.renk;
    final etiket = g.etiket;
    final ikon = g.ikon;

    // Canlı yolda sayım panelin özet kartıyla birebir aynı cümle. Kayıtlı
    // bildirimde nötr sayısı tutulmadığı için eski "x/y gösterge" kalır.
    final sayim = sayimlar;
    final detay = sayim != null
        ? context.l10n
            .buySellNeutralCounts(sayim.yukari, sayim.asagi, sayim.notr)
        : toplam > 0
            ? context.l10n.indicatorsConfidence(lehte, toplam, guven.round())
            : context.l10n.confidenceOnly(guven.round());

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
            '${goreliZaman(kayit.detectedAt, DateTime.now(), context.l10n)}'
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
                // Tek satır: "Teknik: YATAY  1 yukarı · 1 aşağı · 3 nötr"
                // (Ar-Ge 5 Kas 14:45 #1). Eski üst etiket "TEKNİK GÖRÜNÜM ·
                // GÜNLÜK" 390 pt'de "GÜN…" diye kesiliyordu ve sayım üç ayrı
                // dilde yazıyordu (şerit "1/5 gösterge aynı yönde", panel
                // "1 yukarı · 1 aşağı · 3 nötr"). Şerit artık panelin özet
                // kartıyla aynı sayımı yazar; güven yüzdesi panelde.
                // `Wrap`: sığmazsa sayım alt satıra iner, hiçbir parça
                // kesilmez (Dynamic Type 2×). Ağırlık w600 (unslop: en
                // fazla w600); renk yönü taşır, metin de yazılı.
                Wrap(
                  spacing: SandikSpace.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${context.l10n.technicalPrefix} ',
                          style: TextStyle(color: context.c.text58),
                        ),
                        TextSpan(text: etiket),
                      ]),
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: renk,
                      ),
                    ),
                    Text(
                      detay,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                  ],
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
          // Zaman etiketi tek bir sakin PİL içinde. Eskiden burada "ŞU AN"
          // yazısı + altında yön ikonunun TEKRARI duruyordu; ikon bilgi
          // eklemiyordu ("sağ sütunu dengelesin" diye konmuştu) ve solda
          // ikon, ortada metin, sağda yine ikon + chevron dizilince kart
          // dört parçaya bölünmüş görünüyordu (kullanıcı bildirimi
          // 2026-09-18: "estetikten uzak"). Pil tek parça, tek ağırlık.
          //
          // `Flexible` + `FittedBox` kalıyor: kayıt gösterilirken metin
          // "10 Eyl · 11:00" oluyor ve 320pt × 1.6 ölçekte taşıyordu.
          // Canlı hesapta "ŞU AN", kayıtta TAM tarih+saat — göreli ifade
          // soldaki "Son bildirim" satırında duruyor, mutlak olan burada.
          //
          // Canlı yolda pil YOK (Ar-Ge 5 Kas 14:45 #1): "ŞU AN" her açılışta
          // aynıydı, bilgi taşımıyordu ve şeridi kalabalıklaştırıyordu. Pil
          // yalnız kayıtlı bildirimde, o bildirimin tam zamanını yazar.
          if (!canli)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
                  decoration: BoxDecoration(
                    color: renk.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    DateFormat('d MMM · HH:mm', 'tr_TR')
                        .format(kayit!.detectedAt),
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: renk,
                    ),
                  ),
                ),
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
        SignalType.buy => context.l10n.arrowUp,
        SignalType.sell => context.l10n.arrowDown,
        SignalType.neutral => context.l10n.arrowFlat,
      };
}

/// Teknik gösterge paneli.
///
/// **Bir `Asset` İSTEMEZ** — yalnızca sembol, tür ve alt kategori. Göstergeler
/// miktar/maliyet okumaz; sahiplikle ilgisi yoktur. Bu sayede aynı panel hem
/// sahip olunan varlıkta (`AssetDetailScreen`) hem de yalnızca izlenen
/// varlıkta (varlık sayfası, `varlik_sayfasi.dart`) kullanılabiliyor — panelin ~400 satırlık
/// gösterge arayüzü kopyalanmadan.
class TechnicalSignalPanel extends ConsumerStatefulWidget {
  final String ticker;
  final AssetType type;
  final String? subCategory;

  const TechnicalSignalPanel({
    super.key,
    required this.ticker,
    required this.type,
    this.subCategory,
  });

  /// Sahip olunan bir varlıktan kurar — çağrı yerlerini kısaltır.
  TechnicalSignalPanel.forAsset(Asset asset, {Key? key})
      : this(
          key: key,
          ticker: asset.ticker,
          type: asset.type,
          subCategory: asset.subCategory,
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
    // Şeritle aynı pencere ve katman (bkz. [kSinyalPenceresiGun]).
    _pricesFuture = HistoryService.instance
        .getSymbolHistory(widget.ticker,
            periodDays: kSinyalPenceresiGun, cozunurluk: kSinyalCozunurlugu)
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
    final izinli = ref.watch(izinliGostergelerProvider);
    final parametreler = ref.watch(etkinGostergeParametreleriProvider(widget.type));
    final enabledIds = prefs[widget.type] ??
        TechnicalAnalysisService.defaultEnabledFor(widget.type);

    return FutureBuilder<List<double>>(
      future: _loadPrices(),
      builder: (context, snap) => SandikIcerikGecisi(
        // Hesaplanıyor satırı → sinyal çapraz solar (2026-10-14).
        anahtar: snap.connectionState == ConnectionState.waiting,
        child: ((BuildContext context, AsyncSnapshot<List<double>> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _panelShell(
            child: Row(
              children: [
                const CustomLoadingIndicator(size: 14),
                const SizedBox(width: 10),
                // Expanded + ellipsis: dar ekranda (320pt) satır taşmasın.
                Expanded(
                  child: Text(context.l10n.indicatorsCalculating,
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

        return _buildPanel(context, prices, enabledIds, izinli, parametreler);
      })(context, snap),
      ),
    );
  }

  Widget _panelShell({required Widget child}) => SandikCard(
        padding: const EdgeInsets.all(16),
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
                  context.l10n.indicatorsNoHistory,
                  style: context.t.bodySmall?.copyWith(color: p.text58),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          Align(
            alignment: Alignment.centerLeft,
            child: SandikBasma(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _deneme++),
              child: Container(
                // HIG'in en küçük dokunma hedefi 44pt; metin 11pt olduğu
                // için sarmalayıcı olmadan hedef ~14pt'ye düşerdi. Sabit
                // yükseklik değil ALT sınır: büyük yazıda (2×–3,1×) satır
                // büyür, metin kutudan taşmaz; dar kartta etiket alt satıra
                // iner (büyük yazı taraması 2026-10-12).
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: p.amberText),
                    const SizedBox(width: SandikSpace.xs2),
                    Flexible(
                      child: Text(
                        'Tekrar dene',
                        style: context.t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: p.amberText,
                        ),
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
    Set<String> izinli,
    Map<String, GostergeAyari>? parametreler,
  ) {
    final indicators = TechnicalAnalysisService.analyzeSeries(
      prices,
      widget.type,
      enabledIds: enabledIds,
      izinli: izinli,
      parametreler: parametreler,
    );

    final summary = TechnicalAnalysisService.summarize(indicators);
    // NOT: Push bildirimi burada tetiklenmez — bu widget her ekran açılışında
    // yeniden build olduğu için her tıklamada yeni push atardı. Sinyal push'u
    // artık sadece günlük cron (analyze-signals edge function → analyzePortfolio)
    // tarafından üretilir. Bu panel sadece göstergelerin özetini gösterir.

    if (indicators.isEmpty) {
      return SandikCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: context.c.text58, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.noIndicatorsSelected,
                style: context.t.titleSmall?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
    }
    final isNeutral = summary.signal == SignalType.neutral;

    // Yasal not: kesin "AL/SAT" ifadesi yerine trend yönü ya da aşırılık
    // bölgesi (bkz. [sinyalGorunumu]).
    final gorunum = sinyalGorunumu(context, summary.signal, summary.donus);
    final signalColor = gorunum.renk;
    final signalLabel = gorunum.etiket;
    final signalIcon = gorunum.ikon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Başlık ──────────────────────────────────────────────────────────
        // 390 pt'de "TEKNİK ANALİZ · GÜNLÜK" kırpılıyordu (Ar-Ge 1 Kas 08:45
        // #2, yasin "yap"): başlık tam okunur, ayar bağlantısı kısa "Ayarla ›"
        // ve 44 pt dokunma alanı alır, sayaç kendi satırına iner. Ekran
        // okuyucu bağlantıyı tam adıyla ("Göstergeleri Ayarla") duyar.
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.technicalAnalysisUpper,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.c.text58,
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Semantics(
              button: true,
              label: context.l10n.configureIndicators,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Demo (F1): sinyal ayarları sunucuya yazılır.
                onTap: () => DemoModu.yazmaKapisi('ayarlar')
                    ? null
                    : pushGuarded(
                        context,
                        adaptiveRoute<void>(
                            settings:
                                const RouteSettings(name: 'signal_settings'),
                            builder: (_) => const SignalSettingsScreen()),
                      ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: SandikTouch.min, minWidth: SandikTouch.min),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        context.l10n.configureShort,
                        style: context.t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.amberText,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: context.c.amberText),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          context.l10n.nOfMIndicators(indicators.length, IndicatorId.all.length),
          style: context.t.bodySmall?.copyWith(color: context.c.text36),
        ),
        // Yasal ibare panelin İÇİNDE değil, panelin hemen ALTINDA, onu
        // barındıran ekranda (asset_detail_screen, varlik_sayfasi) durur.
        // Panel üstte ve altta birer ibare daha basıyordu; ekranınkiyle
        // birlikte varlık sayfasında aynı uyarı ÜÇ kez okunuyordu (emülatör
        // testi #20, 2026-09-29). "Sinyal gösteren her yüzey ibare taşır"
        // kuralı ekran düzeyinde korunur: `signal_disclaimer_coverage_test`
        // paneli kullanan her ekranı tarar, panelin ibare basmadığını da.
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
                      context.l10n.buySellNeutralCounts(summary.buyCount, summary.sellCount,
                          summary.toplam - summary.buyCount - summary.sellCount),
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
                    context.l10n.confidenceWord,
                    style: context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Dağılım çubuğu ("AL %20·1 SAT %20·1 NÖTR %60·3") KALKTI (Ar-Ge
        // 5 Kas 14:45 #2; yasin müşteri thread'ine bıraktı: "ihtiyacı varsa
        // kalsın yoksa kaldır"). 2026-09-10'da "hangi algoritmalar al/sat
        // dedi ve yüzdesi" isteğiyle eklenmişti; o isteğin "hangi" kısmını
        // aşağıdaki düz liste, oran kısmını üstteki özet kart ("1 yukarı ·
        // 1 aşağı · 3 nötr") ve şerit zaten veriyordu. Aynı sayım üç kez
        // okunuyordu, "%20" de güven yüzdesiyle karışıyordu.
        // ── Gösterge listesi (düz) ──────────────────────────────────────────
        SandikCard(
          padding: EdgeInsets.zero,
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
        // Paywall açık, ücretsiz: üç gösterge hesaplandı; kalan beşi ve
        // bildirimler Premium (yasin 2026-10-10). Kilit listenin hemen
        // altında, neyin eksik olduğunu adıyla söyleyerek.
        if (ref.watch(premiumKilitliProvider)) ...[
          const SizedBox(height: SandikSpace.sm),
          KilitSatiri(
              metin: context.l10n.sgnPremiumGostergeSatiri,
              kaynak: 'sinyal_gosterge'),
        ],
        // İbare burada da basılmaz — bkz. panelin başındaki not (#20).
      ],
    );
  }
}

