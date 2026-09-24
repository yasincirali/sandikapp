part of '../portfolio_performance_screen.dart';

/// Kartlar: grafik + değişim kartı + Özet sekmesi yerleşimi.
/// `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
extension _PerformansKartlar on _PortfolioPerformanceScreenState {
  Widget _buildChartWithData(
    Map<int, double> historyMap,
    List<Asset> targetAssets,
    List<List<Asset>> ownerLots,
    List<Asset> chartAssets,
    DateTime startDate,
    DateTime endDate,
    bool isIntraday,
    PortfolioState pState,
    List<AppUser> activePartners, {
    required bool waiting,
    required bool hasData,

    /// Seçili türde NET pozisyon var mı (satılıp bitmişler ve temettü gibi
    /// miktarsız satırlar hariç). Boş durumun "hiç yok" ile "var ama
    /// çizilemiyor" ayrımı buna dayanır.
    required bool holdsSelectedType,
    bool stale = false,
    bool settled = false,

    /// `historyMap` ile AYNI istekten gelen tür/pozisyon dağılımı — tür dökümü
    /// kartını besler. Her iki veri yolu da doldurur: diğer periyotlar
    /// `getPortfolioHistoryBreakdownAtResolution`, gün içi ise
    /// `getPortfolioHistoryHourlyBreakdown`.
    PortfolioHistoryBreakdown breakdown =
        const PortfolioHistoryBreakdown.empty(),
  }) {
    // Ana ekranla birebir aynı TRY hesabı: targetAssets grafik için ham buy
    // lot'ları içeriyor (satılan miktarı geçmişte düşürmemek için). Ancak
    // GÜNCEL toplam net pozisyondan gelmeli — aggregate ile sell'leri düşüp
    // asDisplayAsset.totalValue'yu topla.
    // Sahipler ayrı aggregate edilir — havuzlanırsa aynı hisseye sahip iki
    // ortak tek pozisyona düşer ve toplam, tekil sekmelerin toplamını tutmaz.
    // `sonFiyat` ŞART — `DailySummary` ile AYNI yol (2026-09-22). Ayrışırsa
    // grafiğin ucu ile özetin toplamı farklı kümeleri ölçer.
    final currentTotal = ownerScopedTotalValue(ownerLots,
        toTRY: pState.toTRY, sonFiyat: PriceService.instance.sonBilinenFiyat);

    // TradingView "auto range" davranışı: kullanıcı seçilen periyot içinde
    // hiç varlığı yoksa (örn. 1Y seçtiği ama 3 gün önce başladı), chart
    // ilk alım tarihinden itibaren çizilir. Böylece kısa geçmişli portföyde
    // grafik boş değil, sıkışık şekilde ilk alıştan bugüne yayılır.
    //
    // Simülasyonda UYGULANMAZ — yukarıdaki fetch tarafıyla aynı gerekçe:
    // sabit pozisyon senaryosunda ilk alım tarihi aralığı daraltmamalı.
    // İki taraf aynı koşulu kullanmalı, aksi halde fetch penceresi ile
    // çizim penceresi ayrışır ve X ekseni kayar.
    DateTime effectiveStart = startDate;
    if (!isIntraday && !_simulate) {
      final buys = chartAssets.where((a) => a.isBuy);
      if (buys.isNotEmpty) {
        final firstBuy = buys
            .map((a) => a.addedDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        // Sadece ilk alım, seçili periyot başlangıcından SONRAYSA
        // startDate'i geç kaydır. Aksi halde tam periyodu göster.
        if (firstBuy.isAfter(startDate)) {
          effectiveStart =
              dayKey(firstBuy);
        }
      }
    }

    // Grafik HAM portföy değerini çizer — arındırma YAPILMAZ.
    //
    // Bir ara seri para giriş/çıkışından arındırılıyordu (alım anındaki dikey
    // sıçrama düzleşsin diye). Kullanıcı kararı: sıçramalar KALSIN. Gerekçesi
    // sağlam — çizgi "portföyümde şu an ne kadar var" sorusunun cevabıdır ve
    // alım/satış anındaki basamak gerçek bir olayı temsil eder. Ayrıca o
    // noktalarda zaten lot dot'u + tooltip var ("Alım +₺X" / "Satış −₺Y"),
    // yani sıçramanın sebebi grafiğin üstünde okunabiliyor.
    //
    // ⚠️ Bu not BAYATTI, düzeltildi (2026-09-20): "değişim kartı net akıştan
    // arındırılmış rakamı gösterir" artık DOĞRU DEĞİL. 2026-08-31 kullanıcı
    // kararıyla kart HAM (birikim) değişimi gösteriyor ve akışı yalnızca alt
    // not satırında ayırıyor (bkz. `_buildPeriodChangeCard`). Sonuç: GÜNLÜK
    // dönemde bu kart, kilit ekranı / widget / Özet sekmesinin gösterdiği
    // arındırılmış günlük rakamdan ALIM YAPILAN GÜNLERDE ayrışıyor
    // (`daily_summary.dart` "Değişmezler" bölümü hâlâ eşitlik iddia ediyor).
    // Karar kullanıcıya bırakıldı — `TECHNICAL_DEBT.md`.
    // Gün içi X ekseni ÇİZİLEN GÜNÜN 00:00'ından başlar — bugünün değil.
    //
    // Piyasa kapalıyken seri son seanstan (Cuma) bugüne uzanıyor
    // (`gunIciSagUc`). Eksen bugünün 00:00'ına kurulursa Cuma noktaları
    // NEGATİF X'e düşer ve `fl_chart` onları çizim alanının dışında bırakır:
    // grafik boş ya da yarım görünür. Kullanıcı bildirimi 2026-09-12:
    // "hâlâ grafiklerde 12 Eylül datalarını göremiyorum."
    //
    // `seansGunu` breakdown'dan geliyor ve tam ekran grafiği (satır ~699)
    // bunu zaten kullanıyordu; ana grafik kullanmıyordu — iki yüzey
    // ayrışmıştı.
    final cizimBaslangici =
        isIntraday ? (breakdown.seansGunu ?? effectiveStart) : effectiveStart;

    final segments = _convertHistoryToSegments(
        historyMap, chartAssets, cizimBaslangici, endDate,
        currentTotalOverride: currentTotal,
        simulate: _simulate,
        intraday: isIntraday,
        // Hafta sonu kuyruğu: kapanıştan sonrası gri + kesikli çizilir.
        piyasaKapaliBaslangicTs: breakdown.piyasaKapaliBaslangicTs);

    return RefreshIndicator(
      color: context.c.amberText,
      onRefresh: () async {
        // Kullanıcı yenilemesi — fiyat önbelleği atlanır, gün içi future sıfırlanır.
        await ref.read(portfolioProvider.notifier).refreshPrices(force: true);
        if (mounted) _retryChartData();
      },
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      controller: _scrollController,
      // Yan dolgu başlık çubuğuyla AYNI (`screenH`: 16, dar ekranda 12).
      // 2026-09-15: 20'den indi — kullanıcı bildirimi, kart kenarındaki
      // boşluk "sağdan ve soldan azaltılmalı"; başlıkla kart kenarı artık
      // aynı hizada, grafik 8pt daha geniş.
      padding: EdgeInsets.symmetric(
          horizontal: SandikSpace.screenH(context), vertical: SandikSpace.smd),
      children: [
        // ── Kontroller: İKİ satır (+ ortak varsa kişi satırı) ────────────
        //
        // Kim: ortak varsa en üstte, tek dokunuşluk segmentler — ekranın
        // öznesi, sık değiştirilir (gerekçe `KapsamKisiSecici`). Yüzey
        // anahtarı kapsam çipiyle AYNI satırda: dönem ikisi için de geçerli,
        // yüzey ise hangi sunumu gördüğünü belirler. Seyrek kullanılan ikili
        // (hangi tür / hangi mod) çipin arkasında. Gerekçe `_buildScopeBar`.
        if (activePartners.isNotEmpty) ...[
          KapsamKisiSecici(
            partners: activePartners,
            selectedId: _view,
            // Kapsam değişiminde gün içi TOHUMU da at.
            //
            // **Neden (kullanıcı bildirimi 2026-09-22):** "diğer zaman
            // aralıklarındaki gibi çalışmalı, sadece günlükte hatalı
            // gösteriliyor — yanlış dolup sonradan düzeltiliyor."
            //
            // Bu ipucu belirleyiciydi: 1H/1A/6A/1Y doğru çalışıyor çünkü o
            // yol kapsam değişince YENİ BİR CONTROLLER kuruyor
            // (`_ensureController` anahtarı `_view` taşır). Yeni controller
            // `_stale = true` ile başlar ve `breakdown`'ı BOŞ döndürür —
            // tohumda dağılım yoktur. Özet böylece `hasData` kapısına
            // takılıp iskelete düşer.
            //
            // Gün içi yolunda tohum (`_lastIntradayData`) bir STATE ALANI:
            // controller gibi atılmıyor, ekranın ömrü boyunca yaşıyordu.
            // Kapsam değişince önceki defterin verisi bir kare boyunca
            // kullanılabiliyordu. Burada atmak, iki yolu aynı davranışa
            // getirir.
            onChanged: (v) => _guncelle(() {
              _view = v;
              _gunIciTohumuAt();
            }),
          ),
          const SizedBox(height: SandikSpace.sm),
        ],
        _buildScopeBar(),
        _buildScopePanel(isIntraday),
        const SizedBox(height: SandikSpace.sm),
        _buildPeriodRow(),
        const SizedBox(height: SandikSpace.md),
        // ── ÖZET sekmesi ──────────────────────────────────────────────────
        //
        // Erken `return` YOK: filtre denetimleri (ortak sekmeleri, tür
        // çipleri, dönem seçici) ağaçta KALMALI, yoksa kullanıcı Özet'e
        // geçtiğinde dönemini değiştiremez hale gelir. Aynı gerekçe
        // `_buildChartWithData`'nın koşulsuz çağrılmasının da sebebi.
        if (_ozetSekmesi) ...[
          // Seri HAZIR DEĞİLKEN sayı çizilmez — iskelet durur
          // (kullanıcı bildirimi 2026-09-22: "ekran render olup sonradan
          // başka değere güncelleniyor, direkt açılırken doğru şekilde
          // açılmalı").
          //
          // Grafik dalı `waiting`/`stale`/`hasData` kapılarını baştan beri
          // kullanıyordu; Özet dalı HİÇBİRİNİ kullanmıyordu. Sonuç: ilk
          // karede boş ya da BAŞKA FİLTREYE ait (`stale`) bir `breakdown`
          // gerçek veri sanılıp tam bir özet olarak çiziliyor, seri gelince
          // rakamlar yerinden zıplıyordu. Kullanıcı yanlış sayıyı okumuş
          // oluyordu — iskelet, yanlış sayıdan iyidir.
          //
          // `hasData` tek başına yetmez: tohum veri de "veri" sayılır ama
          // `stale` iken BAŞKA bir kapsamın/periyodun serisidir.
          if (!hasData || stale)
            _ozetIskeleti(context)
          else
            _buildOzetSekmesi(
              breakdown: breakdown,
              targetAssets: targetAssets,
              intraday: isIntraday,
              seansBaslangici: cizimBaslangici,
            ),
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ] else ...[
          // "Yeni çözünürlükte veri yükleniyor" göstergesi — zoom sırasında
          // eski veri ekranda kalır, üstte ince bir bar akıcı hisi verir.
          if (waiting)
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: context.c.amberFill,
              ),
            ),
          // ── Akıcı geçiş tasarımı ────────────────────────────────────────
          // `LineChart` bir ImplicitlyAnimatedWidget: yeni `LineChartData`
          // verildiğinde eski veriden yenisine kendi lerp'liyor (150ms).
          // Ama bu ancak widget AĞAÇTA KALIRSA çalışır. Grafiği spinner ile
          // değiştirmek (veya sarmalayıcı yapıyı değiştirmek) State'i yok
          // eder, tween sıfırlanır ve geçiş "0'dan yeniden çizim" gibi
          // görünür. Bu yüzden:
          //   • Grafik konteyneri HER ZAMAN aynı konumda kalır.
          //   • Özet kartı bayatken gizlenmez — yerini korusun diye
          //     opaklığı düşer (layout zıplaması da olmaz).
          //   • Spinner yalnızca hiç veri yokken (ilk açılış) görünür.
          AnimatedOpacity(
            opacity: stale ? 0.45 : 1.0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: _buildPeriodChangeCard(
              segments,
              // Segmentlerle AYNI başlangıç: X ekseni bu tarihe göre
              // yorumlanıyor, ayrışırsa kart yanlış günü anlatır.
              cizimBaslangici,
              endDate,
              targetAssets,
              intraday: isIntraday,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          // Grafik alanı üç hâlden birinde: boş durum, yükleme, grafik.
          //
          // "Boş durum" ayrımı ŞART: seçili tür portföyde yoksa (ya da türün
          // fiyat geçmişi hiç izlenmiyorsa) `HistoryService` boş varlık
          // listesine boş seri döndürür — veri ASLA gelmez. Eskiden bu da
          // `!hasData` sayılıp spinner çiziliyordu ve sonsuza kadar dönüyordu;
          // kullanıcı yüklenmeyi bekliyor sanıyordu.
          //
          // Yükseklik `minHeight` ile kurulur, SABİT değil: grafik alanı kadar
          // yer tutsun ama büyük metin ölçeğinde (AX5) içerik taşmasın.
          if (_chartEmptyState(holdsSelectedType, chartAssets)
              case final empty?)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: empty,
            )
          else if (!hasData && settled)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: _ChartPlaceholder(
                icon: Icons.cloud_off_rounded,
                title: context.l10n.chartDataFailed,
                message: context.l10n.chartDataFailedBody,
                onRetry: _retryChartData,
              ),
            )
          else if (!hasData)
            const SizedBox(height: 300, child: CustomLoadingView())
          else
            AnimatedOpacity(
              opacity: stale ? 0.45 : 1.0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              // Grafik tipi değişince YENİDEN çizilmeli. Notifier widget
              // ağacının dışında yaşıyor (oturum durumu), bu yüzden
              // dinleyici burada kuruluyor — `setState` yerine bu, yalnızca
              // grafiği yeniler, tüm sayfayı değil.
              child: ValueListenableBuilder<GrafikTipi>(
                valueListenable: grafikTipiNotifier,
                builder: (context, _, __) => _buildChartContainer(
                    segments, cizimBaslangici, endDate, chartAssets,
                    intraday: isIntraday, allTargetAssets: targetAssets),
              ),
            ),
          // Gün içi verisi HİÇ alınamayan türler için açık uyarı.
          //
          // Bu türler grafikte son bilinen fiyatla sabit çizilir; uyarı
          // olmadan kullanıcı düz çizgiyi "piyasa durgun" diye okur ve
          // uygulamanın bozuk olup olmadığını anlayamaz ("altın değeri mi
          // alınamıyor acaba" — 2026-09-07). Fon/mevduat gibi gün içi fiyatı
          // ZATEN olmayan türler bu listeye girmez, yoksa uyarı kalıcı
          // gürültüye dönerdi.
          if (isIntraday && breakdown.gunIciVerisiYokTurler.isNotEmpty) ...[
            const SizedBox(height: SandikSpace.sm),
            _GunIciVeriYokNotu(turler: breakdown.gunIciVerisiYokTurler),
          ],
          const SizedBox(height: 24),
          // Tür bazlı kâr/zarar dökümü — seçili dönem ve sekmeye göre.
          //
          // Üst kartla AYNI iki sayıdan (`_periodEndpoints`) ve AYNI istekten
          // gelen dağılımdan beslenir; satırların toplamı bu yüzden üst rakamı
          // tutar. Endpoint yoksa üst kart da çizilmiyordur — döküm de çıkmaz.
          // Pencere GEÇİLİR: üst kartla aynı tabanı kullanmalı, yoksa
          // dökümün toplamı üst rakamı tutmaz (2026-09-23).
          if (_periodEndpoints(segments, start: cizimBaslangici)
              case final ep?)
            _TypeBreakdownCard(
              baz: ref.watch(bazParaProvider),
              breakdown: breakdown,
              totalFirst: ep.first,
              totalLast: ep.last,
              ownerLots: ownerLots,
              start: cizimBaslangici,
              end: endDate,
              simulate: _simulate,
              // Üst kartla AYNI taban anı ve canlı uç (2026-09-24). X
              // ekseni gün içinde DAKİKA, diğer dönemlerde GÜN birimi.
              tabanMs: cizimBaslangici.millisecondsSinceEpoch +
                  (ep.firstX *
                          (isIntraday
                              ? Duration.millisecondsPerMinute
                              : Duration.millisecondsPerDay))
                      .round(),
              intraday: isIntraday,
              canliDeger: (suzgec) => ownerScopedTotalValue(
                  [for (final l in ownerLots) l.where(suzgec).toList()],
                  toTRY: pState.toTRY,
                  sonFiyat: PriceService.instance.sonBilinenFiyat),
            ),
          // NOT: Portföy sinyal paneli KALDIRILDI (kullanıcı kararı,
          // 2026-08-31). Teknik sinyaller yalnızca varlık detay/performans
          // ekranında gösterilir. Bu panel senkron çalıştığı için gerçek fiyat
          // geçmişi çekemiyordu; uydurma seriye düşmesi engellendikten sonra
          // (bkz. `analyze(..., allowSimulation)`) zaten kalıcı olarak
          // "sinyal yok" gösteriyordu — yer kaplayan ölü bir yüzeydi.
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ],
      ],
    ),
    );
  }

  Widget _buildPeriodChangeCard(
    List<TransactionSegment> segments,
    DateTime start,
    DateTime end,
    List<Asset> targetAssets, {
    required bool intraday,
  }) {
    // Pencere GEÇİLİR — Özet sekmesiyle AYNI dönem başı.
    //
    // Eskiden `spots.first` olduğu gibi alınıyordu ve seri çekme penceresi
    // dönem penceresinden geniş olabildiği için taban geriye kayıyordu:
    // ölçüldü ₺2.258.332 yerine ₺2.354.650 olmalıydı (₺96.318 fark,
    // kullanıcı bildirimi 2026-09-23).
    final ep = _periodEndpoints(segments, start: start);
    if (ep == null) return const SizedBox.shrink();

    final firstY = ep.first;
    final lastY = ep.last;

    // Grafik HAM portföy değerini çizer (sıçramalar bilinçli — bkz. çizim
    // tarafındaki not), dolayısıyla uçtan uca fark yatırılan parayı da
    // içerir. Kart bunu ham göstermez.
    final grossChange = lastY - firstY;

    // ── Dönem içi net akış ───────────────────────────────────────────────
    //
    // Silinen varlıklar HİÇ VAR OLMAMIŞ sayılır: `deleteLog` atlanır ve
    // orijinal lot zaten DB'den silinmiştir (bkz. `deleteAsset`).
    //
    // **Katkı, tabanın ölçüldüğü ANDAN sonrası için sayılır** (2026-09-23,
    // 1H/1A/6A/1Y). Eskiden pencere GÜN BAŞINDAN sayılıyordu; taban ise
    // serinin ilk DOLU noktası. Filtrelenen tür dönem başında boşsa (ör.
    // altını bu hafta ilk kez aldın) ilk dolu nokta alımı zaten İÇERİR ve
    // aynı alım katkıya da giriyordu: "Yalnızca piyasa hareketi" satırı
    // alım tutarı kadar eksiye düşüyordu. Özet sekmesi bu çifte sayımı
    // 2026-09-16'da kapatmıştı (`startExclusiveMs`), bu kart almamıştı.
    // Kural `PeriodSummaryService.piyasaEtkisi` ile aynı; varlık ekranı da
    // onu kullanıyor — "piyasa etkisi" üç yüzeyde tek tanım.
    //
    // GÜNLÜK dokunulmadı: ana sayfa (`DailySummary`) ile hizası ayrı bir
    // sözleşme (bkz. aşağıdaki GÜNLÜK notu).
    double netInflow = 0;
    if (!_simulate) {
      netInflow = intraday
          ? PeriodSummaryService.netInflow(targetAssets, start, end)
          : PeriodSummaryService.netInflow(
              targetAssets,
              start,
              end,
              startExclusiveMs: start.millisecondsSinceEpoch +
                  (ep.firstX * Duration.millisecondsPerDay).round(),
            );
    }

    // ── Ana rakam: BİRİKİM değişimi — (son − ilk) / ilk ──────────────────
    //
    // Kart, grafiğin ucundan ucuna olan HAM farkı gösterir; alımlar düşülmez.
    // Yani "portföyüm ne kazandı" değil, **"birikimim ne kadar büyüdü"**
    // sorusunu yanıtlar. Dönem içinde alım yapıldıysa bu rakam simülasyon
    // sekmesinden belirgin biçimde YÜKSEK çıkar — aradaki fark yatırılan
    // paradır ve kullanıcı bunu görmek ister (kullanıcı kararı, 2026-08-31).
    //
    // Formül iki sekmede de aynıdır; fark girdide:
    //   • Gerçek     → miktar alım anında artar, seri basamak yapar
    //   • Simülasyon → bugünkü net pozisyon sabit, basamak yok
    //
    // ⚠️ Bu rakam KAZANÇ DEĞİLDİR. Düz seyreden bir fona 100.000 TL
    // yatırıldığında kart +%100 yazar. Bu yüzden başlık "birikim" der ve
    // aşağıdaki not satırı, ne kadarının alımdan geldiğini AÇIKÇA söyler.
    // Etiket olmadan bu rakam "kazandım" diye okunurdu.
    // **GÜNLÜK'te ARINDIRILMIŞ (kullanıcı kararı, 2026-09-23).**
    //
    // Kullanıcı kuralı açık koydu: *"aynı zamanda ana sayfa günlük
    // kısmıyla da aynı olmalı."* Ana sayfa (`DailySummary`) nakit
    // akışından ARINDIRILMIŞ rakam gösteriyor; bu kart HAM birikim
    // gösteriyordu ve alım yapılan günde ikisi ayrışıyordu.
    //
    // Bu, `TECHNICAL_DEBT.md`'de AÇIK duran maddenin (Şu ana kadar iki
    // kullanıcı kararı çelişiyordu: 2026-08-31 "birikim göster" ve
    // kilit ekranının arındırılmış rakamı) çözümüdür: seçenek (a)
    // uygulandı — GÜNLÜK'te ana rakam arındırılmış, birikim alt
    // satırda kalır. DİĞER dönemler 2026-08-31 kararında kalır
    // ("birikimim ne kadar büyüdü" sorusu orada anlamlı).
    //
    // Neden yalnızca GÜNLÜK: ana sayfa Bugün kartı yalnızca o dönemi
    // anlatıyor. 1H/1A/6A/1Y'nin ana sayfada bir karşılığı yok, yani
    // orada ayrışma da yok.
    final change = intraday ? grossChange - netInflow : grossChange;

    // Yüzde tabanı:
    //   • GÜNLÜK   → dönem başı + POZİTİF akış (ana sayfayla AYNI taban,
    //     bkz. `DailySummary.from`: "gün içinde portföyünü büyüten
    //     kullanıcıda yüzdeyi şişirmemek için").
    //   • diğer     → yalnızca dönem başı (birikim sorusu).
    final pctBase =
        intraday ? firstY + (netInflow > 0 ? netInflow : 0) : firstY;
    final pct = pctBase > 0 ? (change / pctBase) * 100 : null;
    final positive = change >= 0;

    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr renk — yeşil göstermek
    // "kazanç var" yanılgısı yaratır. _PeriodChangeRow ile aynı kural.
    final isFlat = change.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
    final color = isFlat
        ? context.c.text36
        : (positive ? context.c.gain : context.c.loss);

    final tryFmt = ref.watch(bazParaProvider).formatter(digits: 0);
    final periodLabel = donemEtiketi(context.l10n,
        _PortfolioPerformanceScreenState._periods[_selectedPeriodIdx].label);
    // Yıl, iki uç FARKLI yıla düşüyorsa yazılır.
    //
    // Sabit `d MMM` biçimi 1Y periyodunda "31 Ağu → 31 Ağu" üretiyordu:
    // aralık doğruydu (2025 → 2026) ama yıl gizlendiği için aynı güne
    // bakılıyormuş gibi görünüyordu. Kısa periyotlarda yıl gereksiz
    // gürültüdür, o yüzden koşullu.
    final dateFmt = DateFormat(
      start.year == end.year ? 'd MMM' : 'd MMM y',
      'tr_TR',
    );
    // Başlık "birikim" der: rakam alımları İÇERİR, dolayısıyla saf getiri
    // değildir. Simülasyonda miktar sabit olduğu için orada birikim etkisi
    // yoktur ve etiket sade kalır.
    // Gün içi kart BUGÜNÜ anlatmayabilir: piyasa kapalıyken grafik son
    // seansı çizer (bkz. `PortfolioHistoryBreakdown.seansGunu`). Başlık
    // "Bugünkü" derken Cuma'nın rakamını göstermek düpedüz yanlış bilgidir.
    final simdi = DateTime.now();
    final gunIciBugun = start.year == simdi.year &&
        start.month == simdi.month &&
        start.day == simdi.day;
    // Piyasa kapalı kuyruğu çizilmiş mi? Ayrı bir parametre GEÇİRMİYORUZ:
    // segmentler zaten bu kartın girdisi ve kuyruk orada işaretli. İkinci
    // bir yoldan sormak, iki kaynağın ayrışması demekti.
    final kapaliKuyruk = segments.any((s) => s.piyasaKapali);

    // Gün içi başlık, çizilen günü söyler. Kuyruk varsa aralık yazılır
    // ("11 Eyl → bugün"): eksen artık tek gün değil, kullanıcı isteği
    // gereği hafta sonunu da kapsıyor (2026-09-12).
    final gunIciBaslik = gunIciBugun
        ? context.l10n.todaysBalanceChange
        : kapaliKuyruk
            ? context.l10n.sinceDateToToday(
                DateFormat('d MMM', 'tr_TR').format(start))
            : context.l10n.balanceChangeSince(
                DateFormat('d MMMM', 'tr_TR').format(start));

    final title = intraday
        ? gunIciBaslik
        : _simulate
            ? context.l10n.periodChangeSim(periodLabel)
            : context.l10n.periodBalanceChange(periodLabel);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 14),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık "1A birikim değişimi · simülasyon" gibi uzayabiliyor;
          // 320pt'de tek satıra sığmalı (taşma testi bunu kovalıyor).
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.t.titleSmall?.copyWith(color: context.c.text58),
                ),
              ),
              // "PİYASA KAPALI" rozeti — grafikteki gri kesikli kuyruğun
              // ne olduğunu SÖZLE de anlatır. Desen tek başına yeterli
              // değil: kullanıcı düz çizgiyi "fiyat oynamadı" diye
              // okuyabilir, oysa borsa kapalıydı.
              if (kapaliKuyruk) ...[
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.c.text36.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    // Metin portföydeki TÜRLERE göre daralır: mevduat
                    // faizi hafta sonu da işler, ona "piyasa kapalı"
                    // demek yanlış bilgidir (bkz. `piyasaKapaliEtiketi`).
                    piyasaKapaliEtiketiVarliklardan(targetAssets),
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tutar — bloğun ana bilgisi, en büyük tipografi.
              // FittedBox: milyonluk portföyde dar ekranda taşmasın,
              // punto düşsün ama satır kırılmasın.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isFlat
                        ? 'Değişim yok'
                        : '${positive ? '+' : '−'}${tryFmt.format(change.abs())}',
                    maxLines: 1,
                    style: context.t.numMedium.copyWith(color: color),
                  ),
                ),
              ),
              if (pct != null && !isFlat) ...[
                const SizedBox(width: SandikSpace.sm),
                // Yüzde rozeti — yön ikonu renge ek bir sinyal taşır,
                // renk körlüğünde de okunur.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: SandikRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        positive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        fmtPct(pct.abs(), digits: 2),
                        style: context.t.numSmall.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            intraday
                ? (gunIciBugun
                    ? 'Bugün'
                    : '${dateFmt.format(start)} · son seans')
                : '${dateFmt.format(start)} → ${dateFmt.format(end)}',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
          // Not satırı ana rakamın NE OLDUĞUNU söyler ve iki dönem
          // türünde TERS çalışır (2026-09-23):
          //
          //   • GÜNLÜK  → ana rakam ARINDIRILMIŞ, akışı İÇERMEZ.
          //     Not "şu kadar alım yaptın ama bu rakama girmedi" der,
          //     yoksa kullanıcı eksik bir şey olduğunu sanar.
          //   • diğer   → ana rakam HAM birikim, akışı İÇERİR.
          //     Not "+%100 kazandım" yanılgısını önler: ne kadarı
          //     yatırılan para, ne kadarı piyasa.
          //
          // Etiket tek başına yetmez — sayının kaynağı yazılmalı.
          if (netInflow.abs() > 0.5) ...[
            const SizedBox(height: SandikSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: context.c.text36),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    intraday
                        ? (netInflow > 0
                            ? context.l10n.inflowExcludedNote(
                                tryFmt.format(netInflow))
                            : context.l10n.outflowExcludedNote(
                                tryFmt.format(netInflow.abs())))
                        : (netInflow > 0
                            ? context.l10n.inflowIncludedNote(
                                tryFmt.format(netInflow),
                                tryFmt.format(grossChange - netInflow))
                            : context.l10n.outflowIncludedNote(
                                tryFmt.format(netInflow.abs()),
                                tryFmt.format(grossChange - netInflow))),
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Özet sekmesinin YÜKLEME hâli — gerçek kartların yerini tutar.
  ///
  /// Yükseklikler gerçek kartlara yakın seçildi ki seri gelince liste
  /// zıplamasın: üstte dönem kartı (büyük rakam + alt satır), altında
  /// "Nereden geldi" köprüsünün dört çubuğu.
  Widget _ozetIskeleti(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SandikSkeleton(width: 140, height: 12),
                SizedBox(height: SandikSpace.xs2),
                SandikSkeleton(width: 80, height: 10),
                SizedBox(height: SandikSpace.smd),
                SandikSkeleton(width: 200, height: 30),
                SizedBox(height: SandikSpace.sm),
                SandikSkeleton(width: 240, height: 12),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SandikSkeleton(width: 110, height: 12),
                const SizedBox(height: SandikSpace.smd),
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(height: SandikSpace.sm),
                  const SandikSkeleton(width: double.infinity, height: 14),
                ],
              ],
            ),
          ),
        ],
      );

  /// Özet sekmesinin gövdesi.
  ///
  /// Hesap `PeriodSummaryService.compute`'ta — burada yalnızca girdiler
  /// toplanır. Servis saf olduğu için `now` ve `breakdown` dışarıdan
  /// veriliyor ve testler ağsız koşabiliyor.
  ///
  /// **GÜNLÜK dönemde `DailySummary.from()` DELEGE edilir.** Widget, Live
  /// Activity, üst kart ve bu sekme aynı rakamı göstermek zorunda
  /// (bkz. `daily_summary.dart` "Değişmezler"); ikinci bir günlük hesap
  /// kurmak o değişmezi sessizce kırardı.
  Widget _buildOzetSekmesi({
    required PortfolioHistoryBreakdown breakdown,
    required List<Asset> targetAssets,
    required bool intraday,
    required DateTime seansBaslangici,
  }) {
    final period = SummaryPeriod.fromIndex(_selectedPeriodIdx);
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final now = DateTime.now();

    // GÜNLÜK'te ortak katmanın özeti hazırlanır. `seansGunu` breakdown'dan
    // gelir: piyasa kapalıyken çizilen seans BUGÜN DEĞİLDİR ve pencere de
    // o güne kurulmalı (hafta sonu → Cuma).
    DailySummary? gunluk;
    if (intraday && pState != null) {
      gunluk = DailySummary.from(
        state: pState,
        series: breakdown.total,
        now: now,
        seansGunu: breakdown.seansGunu ?? seansBaslangici,
        // KAPSAM: seri hangi sahiplere göre çekildiyse canlı uç ve nakit
        // akışı da onlardan okunmalı. `pState.assets` verilseydi (eski
        // davranış) ortak sekmesinde ortağın eğrisinin ucuna HERKESİN
        // toplamı yazılır, gün başı ile uç farklı kümeleri ölçtüğü için
        // kâr/zarar ve birikim saçmalardı (kullanıcı bildirimi 2026-09-22).
        kapsamLotlari: targetAssets,
      );
    }

    final summary = PeriodSummaryService.compute(
      period: period,
      assets: targetAssets,
      breakdown: breakdown,
      now: now,
      gunlukOzet: gunluk,
      // Sağ uç CANLI kapsam toplamı — Grafik kartının ucuyla aynı sayı
      // (`currentTotal`); bkz. `compute` [canliSon].
      canliSon: pState == null
          ? null
          : DailySummary.kapsamToplami(pState, targetAssets),
      // `_positionLabel` ham `positionKey`'i insan-okunur hale getirir;
      // yoksa ekranda "altin|sub:çeyrek|TRY" görünürdü.
      etiket: (k) =>
          _positionLabel(k, breakdown.positionType[k] ?? AssetType.diger,
              context.l10n),
    );

    // Tür dağılımı ve "en sabırlı" AÇIK pozisyonlardan okunur.
    //
    // Ham `isBuy` filtresi SATIŞ lot'larını düşmez: kısmi sattığında
    // dağılım ₺720 yerine ₺1.200 (ölçüldü, denetim 2026-09-22) — karakter
    // etiketi elde olmayan varlığa göre seçiliyordu. "En sabırlı" ise
    // 2020'de alınıp 2020'de SATILMIŞ bir varlığı, bugün hâlâ elde olanın
    // önüne geçiriyordu: soru "ne kadar süredır TUTUYORUM", geçmişte ne
    // aldığım değil.
    //
    // `aktifLotlar` + `aggregatePositionsByOwner`: net miktarı 0'a düşen
    // pozisyon elenir, sahip sınırı korunur (`positionKey` sahip taşımaz).
    final acikPozisyonlar = aggregatePositionsByOwner(
        [for (final l in lotlarSahibeGore(targetAssets)) aktifLotlar(l)]);

    final valueByType = <AssetType, double>{};
    if (pState != null) {
      for (final p in acikPozisyonlar) {
        final a = p.asDisplayAsset();
        valueByType[a.type] =
            (valueByType[a.type] ?? 0) + pState.toTRY(a.totalValue, a.currency);
      }
    }

    // En sabırlı varlık — 1Y bloğu. `firstBuyDate` pozisyonun İLK alımıdır
    // (temsilci en YENİ alımdır; onun tarihi "ne zamandır tutuyorum"u
    // kısaltırdı — üstüne alım yapan kullanıcı sabırsız görünürdü).
    Asset? enEski;
    DateTime? enEskiTarih;
    for (final p in acikPozisyonlar) {
      final t = p.firstBuyDate;
      if (enEskiTarih == null || t.isBefore(enEskiTarih)) {
        enEskiTarih = t;
        enEski = p.asDisplayAsset();
      }
    }

    return _OzetYanVeri(
      period: period,
      summary: summary,
      assets: targetAssets,
      // Karakter/sabır yalnızca 1Y'de gösterilir; başka dönemde
      // hesaplanmış olsa da view onları çizmez.
      karakter: period == SummaryPeriod.birYil
          ? RecapService.characterFor(valueByType)
          : null,
      enSabirli: period == SummaryPeriod.birYil && enEski != null
          ? RecapAsset(enEski.name, 0)
          : null,
      enSabirliGun: period == SummaryPeriod.birYil && enEski != null
          // `enEskiTarih` = pozisyonun ilk alımı. `enEski.addedDate` aynı
          // değeri taşır (`asDisplayAsset` onu `firstBuyDate`'ten kurar) ama
          // o bağ uzak bir değişmez; burada ölçtüğümüz tarihi doğrudan
          // kullanıyoruz ki ileride kopmasın.
          ? now.difference(enEskiTarih!).inDays
          : null,
    );
  }
}
