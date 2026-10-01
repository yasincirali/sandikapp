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
    // Canlı toplam 0: elde pozisyon kalmadıysa ölçümdür (uç 0'a iner),
    // kaldıysa fiyat bilinmiyordur (uç ezilmez). Özet'teki
    // `piyasaEtkisi` ile aynı ayrım (2026-09-24).
    final canliUc = (currentTotal > 0 ||
            DailySummary.acikPozisyonYok(
                [for (final l in ownerLots) ...l]))
        ? currentTotal
        : null;

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
        currentTotalOverride: canliUc,
        simulate: _simulate,
        intraday: isIntraday,
        // Hafta sonu kuyruğu: kapanıştan sonrası gri + kesikli çizilir.
        piyasaKapaliBaslangicTs: breakdown.piyasaKapaliBaslangicTs);

    return RefreshIndicator.adaptive(
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
      // Üst dolgu 0: içerik başlık bloğunun hemen altında başlar — dört
      // sekmede aynı çizgi (kullanıcı bildirimi 2026-09-28: "Performans
      // biraz daha boşluk bırakıp başlıyor"). Portföy'de ilk kontrol
      // başlığın 4pt alt dolgusundan hemen sonra; burada 12 daha vardı.
      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 0,
          SandikSpace.screenH(context), SandikSpace.smd),
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
        // Dönem seçici grafiğin ÜSTÜNDE — üç grafik ekranında da (kullanıcı
        // kararı 2026-09-28, aynı gün içinde iki adım): önce "üç ekranda
        // aynı yerde olsun" denince seçici grafiğin altına indirilmişti;
        // sonra "üstte olsun: GÜNLÜK'ten öteki dönemlere geçerken grafiğin
        // boyu değişiyor, altındaki seçici zıplıyor, profesyonel durmuyor".
        // Üstteki seçici grafiğin altındaki hiçbir değişimden etkilenmez.
        // Varlık sayfası ve varlık detayı da aynı sırayı kullanır:
        // fiyat → seçici → grafik. Dönem değişince yalnızca grafik ve ona
        // bağlı kartlar yenilenir (bayat seri soluk kalır, iskelet yok).
        _buildPeriodRow(),
        const SizedBox(height: SandikSpace.md),
        // ── ÖZET sekmesi ──────────────────────────────────────────────────
        //
        // Erken `return` YOK: filtre denetimleri (ortak sekmeleri, tür
        // çipleri, dönem seçici) ağaçta KALMALI, yoksa kullanıcı Özet'e
        // geçtiğinde dönemini değiştiremez hale gelir. Aynı gerekçe
        // `_buildChartWithData`'nın koşulsuz çağrılmasının da sebebi.
        if (_ozetSekmesi) ...<Widget>[
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
          //
          // Gün dışı dönemlerde Özet grafiğin serisini DEĞİL kendi kanonik
          // serisini okur (`_OzetSerisi`): zoom/bar seçimi Özet'in dönem
          // başını kaydırmasın (müşteri testi 2026-10-01).
          if (isIntraday)
            (!hasData || stale)
                ? _ozetIskeleti(context)
                : _buildOzetSekmesi(
                    breakdown: breakdown,
                    targetAssets: targetAssets,
                    intraday: true,
                    seansBaslangici: cizimBaslangici,
                  )
          else
            _OzetSerisi(
              key: ValueKey('ozet|$_view|${_typeFilter?.name}|'
                  '$_selectedPeriodIdx|$_simulate|$_ozetYenileme|'
                  '${chartAssets.map((a) => a.id).join(",")}'),
              chartAssets: chartAssets,
              period: SummaryPeriod.fromIndex(_selectedPeriodIdx),
              simulate: _simulate,
              iskelet: _ozetIskeleti(context),
              builder: (bd) => _buildOzetSekmesi(
                breakdown: bd,
                targetAssets: targetAssets,
                intraday: false,
                seansBaslangici: cizimBaslangici,
              ),
            ),
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ].map((w) => _SekmeSolmasi(ozet: true, taze: _sekmeYeniDegisti, child: w))
        else ...<Widget>[
          // "Yeni çözünürlükte veri yükleniyor" göstergesi — zoom sırasında
          // eski veri ekranda kalır, üstte ince bir bar akıcı hisi verir.
          //
          // Yer HEP ayrılı, gösterge yalnız beklerken (animasyon denetimi
          // 2026-10-01): eskiden `if (waiting)` 2 pt'lik satırı listeye
          // EKLİYORDU — yakınlaştırma sırasında grafik parmağın altında 2 pt
          // kayıyor ve liste çocuklarının sırası değiştiği için grafiğin
          // State'i yeniden kuruluyordu ("0'dan çizim").
          SizedBox(
            height: 2,
            child: waiting
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: context.c.amberFill,
                  )
                : null,
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
            // Grafik yüklenirken grafik biçimli iskelet (UX denetimi
            // 2026-09-29): ortada dönen halka "bozuk" okunur.
            const SandikSkeletonChart(height: 300)
          // Portföy seçili dönemden GENÇ: ilk varlık bugün eklendiyse 1H/1A/
          // 6A/1Y serisi bugünün bir-iki noktasına iner. Eskiden grafik yine
          // çiziliyordu — yalnız fiyat ekseni, tarih ekseni yok, düz çizgi;
          // dönem kartı ya hiç yok ya "27 Eyl → 27 Eyl". Kullanıcı
          // "Performans çalışmıyor" diye okudu (2026-09-27, yeni hesap,
          // Pazar). Kapalı testteki HER yeni kullanıcı ilk gün bunu görür.
          // GÜNLÜK hariç: gün içi serisi bugünü kapsar, orada grafik doludur.
          // Karar `_portfoyDonemdenGenc`'te (neden nokta sayısı yetmedi).
          else if (!isIntraday &&
              _portfoyDonemdenGenc(segments, cizimBaslangici))
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: _ChartPlaceholder(
                icon: Icons.hourglass_top_rounded,
                title: context.l10n.youngPortfolioTitle,
                message: context.l10n.youngPortfolioBody,
              ),
            )
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
          if (_periodEndpoints(segments,
                  start: cizimBaslangici, intraday: isIntraday)
              case final ep?)
            _TypeBreakdownCard(
              baz: ref.watch(gosterimBazParaProvider),
              breakdown: breakdown,
              totalFirst: ep.first,
              totalLast: ep.last,
              ownerLots: ownerLots,
              start: cizimBaslangici,
              end: endDate,
              simulate: _simulate,
              // Üst kartla AYNI taban anı ve canlı uç (2026-09-24).
              tabanMs: ep.firstTs!,
              intraday: isIntraday,
              canliDeger: (lotlar) =>
                  DailySummary.kapsamToplami(pState, lotlar),
            ),
          // Zirvedeki portföyler — Yarış ekranından buraya taşındı
          // (kullanıcı kararı 2026-09-29): zirve bir KIYAS verisi, yarış
          // değil; kıyas ekranı burası. Ortak ya da yarışa katılım şartı
          // yok, küresel bayrak yeter. Dönem Performans seçicisinden en
          // yakın sunucu dönemine eşlenir (`ZirveDonem.yakin`); ekran o
          // dönemle açılır. Tür dökümü gibi koşula bağlı DEĞİL: kullanıcının
          // kendi serisi yokken de zirve vardır.
          // Demo (F1): Zirve sunucudan okunur, demoda çizilmez.
          if (RemoteConfigService.instance.globalLeaderboardEnabled &&
              !DemoModu.aktif) ...[
            const SizedBox(height: SandikSpace.md),
            TourAnchor(
              target: TourTarget.zirveKarti,
              child: ZirveKarti(
                donem: ZirveDonem.yakin(
                    _PortfolioPerformanceScreenState._periods[_selectedPeriodIdx].days),
                onAc: () => pushGuarded(
                  context,
                  adaptiveRoute<void>(
                    builder: (_) => ZirvePortfoylerScreen(
                      baslangic: ZirveDonem.yakin(
                          _PortfolioPerformanceScreenState
                              ._periods[_selectedPeriodIdx].days),
                    ),
                  ),
                ),
              ),
            ),
          ],
          // NOT: Portföy sinyal paneli KALDIRILDI (kullanıcı kararı,
          // 2026-08-31). Teknik sinyaller yalnızca varlık detay/performans
          // ekranında gösterilir. Bu panel senkron çalıştığı için gerçek fiyat
          // geçmişi çekemiyordu; uydurma seriye düşmesi engellendikten sonra
          // (bkz. `analyze(..., allowSimulation)`) zaten kalıcı olarak
          // "sinyal yok" gösteriyordu — yer kaplayan ölü bir yüzeydi.
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ].map((w) => _SekmeSolmasi(ozet: false, taze: _sekmeYeniDegisti, child: w)),
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
    final ep =
        _periodEndpoints(segments, start: start, intraday: intraday);
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
    // GÜNLÜK'te sınır gün başı değil açılış ölçümü, geçmiş seansta akış
    // yok — ana sayfayla aynı kural (`DailySummary.gunIciKatki`,
    // 2026-09-24). Tür dökümü de aynı fonksiyonu çağırır.
    double netInflow = 0;
    if (!_simulate) {
      netInflow = PeriodSummaryService.grafikKatkisi(targetAssets,
          start: start, end: end, tabanMs: ep.firstTs!, intraday: intraday);
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
    // **Her dönemde HAM birikim; piyasa etkisi AYRI SATIRDA (kullanıcı
    // kararı, 2026-09-24).**
    //
    // Karar geçmişi: 2026-08-31 "birikim büyümesini görmek istiyorum,
    // alım dahil" → 2026-09-23 GÜNLÜK'te arındırılmışa çevrildi ("ana
    // sayfa günlük kısmıyla aynı olmalı") → 2026-09-24 kullanıcı kartı
    // görüp geri aldı: *"Birikim değişimi... total birikim değişimine
    // alımlar bu ekranda eklenmeli; altına da bugün sadece piyasanın
    // toplam portföye etkisi yazılmalı."*
    //
    // Yani başlık ne diyorsa ana rakam odur: "birikim değişimi" alımları
    // İÇERİR (grafiğin ucundan ucuna ham fark). Ana sayfayla parite
    // kopmaz, aşağıdaki "Sadece piyasa etkisi" satırına taşınır — o satır
    // `DailySummary`/Özet ile AYNI formül ve AYNI yüzde tabanıdır
    // (`piyasa`, `piyasaPct`). `TECHNICAL_DEBT.md`'deki madde bu kararla
    // kapandı: seçenek (c) — iki rakam da kartta, ağırlıkları farklı.
    //
    // Tek kural, dönem ayrımı yok: 1H/1A/6A/1Y'de de ana rakam birikim,
    // akış varsa piyasa satırı gelir. Eskiden o dönemlerde piyasa etkisi
    // not metninin içine gömülüydü; satır olarak okunur olsun.
    final change = grossChange;
    final pctBase = firstY;
    final pct = pctBase > 0 ? (change / pctBase) * 100 : null;
    final positive = change >= 0;

    // Sadece piyasa etkisi — `PeriodSummaryService.piyasaEtkisi` ve
    // `DailySummary.from` ile aynı: (son − ilk) − katkı; yüzde tabanı
    // dönem başı + POZİTİF akış ("gün içinde portföyünü büyüten
    // kullanıcıda yüzdeyi şişirmemek için", bkz. `DailySummary.from`).
    final piyasa = grossChange - netInflow;
    // Yüzde: PARA AĞIRLIKLI getiri — Özet ve ana sayfayla TEK fonksiyon
    // (2026-10-01, best practice kıyası; "tüm zaman aralıklarında").
    // 1H ve üstünde `PeriodSummaryService.paraAgirlikliGetiri` (Özet'in
    // `piyasaEtkisi` yüzdesi), GÜNLÜK'te `DailySummary.gunIciGetiriPct`
    // (ana sayfa, widget, Live Activity). Simülasyonda akış yok: son/baş.
    double? piyasaPct;
    if (_simulate) {
      piyasaPct = firstY > 0 ? piyasa / firstY * 100 : null;
    } else if (intraday) {
      piyasaPct = DailySummary.gunIciGetiriPct(targetAssets,
          acilis: firstY,
          son: lastY,
          acilisMs: ep.firstTs!,
          seansGunu: start,
          now: end);
    } else {
      final akisSonuMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
          .millisecondsSinceEpoch;
      final sermaye = PeriodSummaryService.ortalamaSermaye(
        lotlar: targetAssets,
        bas: firstY,
        basTs: ep.firstTs!,
        sonTs: end.millisecondsSinceEpoch,
        akisSonuMs: akisSonuMs,
      );
      piyasaPct = sermaye == null
          ? null
          : PeriodSummaryService.paraAgirlikliGetiri(
              lotlar: targetAssets,
              bas: firstY,
              son: lastY,
              basTs: ep.firstTs!,
              sonTs: end.millisecondsSinceEpoch,
              akisSonuMs: akisSonuMs,
              piyasa: piyasa,
              sermaye: sermaye,
            );
    }
    final piyasaFlat =
        piyasa.abs().round() == 0 && (piyasaPct?.abs() ?? 0) < 0.005;

    // Temettü AYRI kalem (müşteri testi 2026-10-01): `netInflow` temettüyü
    // çıkış sayar (`getiriAkisi`), bu yüzden hiçbir şey yapmadığı günde
    // kullanıcı "Net katkın −₺86" görüyordu. "Yatırdığın" = alım − satış
    // (temettü hariç), temettü kendi kaleminde "cebine" — Özet köprüsüyle
    // aynı üç parça (`_KopruKarti.yatirdigin`).
    final temettu = _simulate
        ? 0.0
        : PeriodSummaryService.temettuArasi(
            targetAssets,
            sonrasiMs: ep.firstTs!,
            sonuMs: DateTime(end.year, end.month, end.day, 23, 59, 59)
                .millisecondsSinceEpoch,
          );
    final yatirilan = netInflow + temettu;
    final akisVar = netInflow.abs() > 0.5 || temettu.abs() > 0.5;
    final piyasaColor = piyasaFlat
        ? context.c.text36
        : (piyasa >= 0 ? context.c.gain : context.c.loss);

    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr renk — yeşil göstermek
    // "kazanç var" yanılgısı yaratır. _PeriodChangeRow ile aynı kural.
    final isFlat = change.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
    final color = isFlat
        ? context.c.text36
        : (positive ? context.c.gain : context.c.loss);

    final tryFmt = ref.watch(gosterimBazParaProvider).formatter(digits: 0);
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
      // Arayüz diliyle (emülatör testi #27: İngilizcede "29 Eyl").
      context.tarihDili,
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
    // Rozet yalnızca portföy TAMAMEN borsa ürünüyse (2026-10-01, bkz.
    // `yalnizcaBorsa`): karışık portföyde altın/kripto hafta sonu da
    // işler, "kapalı" demek yanlış bilgidir — `null` gelir, rozet çizilmez.
    final kapaliEtiketi =
        kapaliKuyruk ? piyasaKapaliEtiketiVarliklardan(targetAssets) : null;

    // Gün içi başlık, çizilen günü söyler. Kuyruk varsa aralık yazılır
    // ("11 Eyl → bugün"): eksen artık tek gün değil, kullanıcı isteği
    // gereği hafta sonunu da kapsıyor (2026-09-12).
    final gunIciBaslik = gunIciBugun
        ? context.l10n.todaysBalanceChange
        : kapaliKuyruk
            ? context.l10n.sinceDateToToday(
                DateFormat('d MMM', context.tarihDili).format(start))
            : context.l10n.balanceChangeSince(
                DateFormat('d MMMM', context.tarihDili).format(start));

    final title = intraday
        ? gunIciBaslik
        : _simulate
            ? context.l10n.periodChangeSim(periodLabel)
            : context.l10n.periodBalanceChange(periodLabel);

    // Düzen (2026-09-24, kullanıcı: "gözüme çok estetik gelmedi"):
    //
    //   başlık ····························· dönem aralığı
    //   +₺566.413  [↑ %102,09]
    //   ─────────────────────────────────────────────────
    //   KATKIN                  SADECE PİYASA ETKİSİ
    //   +₺561.927               +₺4.486 · %0,40
    //
    // Eski düzen beş satırı alt alta yığıyordu (başlık, tutar, tarih,
    // piyasa satırı, üç satırlık not) ve hepsi aynı ağırlıktaydı. Şimdi
    // üç kat var: sessiz üst bilgi, tek kahraman rakam, ince çizgi
    // altında iki eşit kalem. "Birikim = katkın + piyasa" denklemi
    // yazıyla değil yerleşimle anlatılıyor; not satırı bu yüzden kalktı.
    // Akış yoksa alt kat çizilmez — kahraman zaten piyasa etkisidir.
    final aralik = intraday
        ? (gunIciBugun ? null : '${dateFmt.format(start)} · son seans')
        : '${dateFmt.format(start)} → ${dateFmt.format(end)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.md, SandikSpace.md2, SandikSpace.md, SandikSpace.md2),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst bilgi: başlık solda, dönem aralığı sağda — ikisi de sessiz.
          // Başlık "1A birikim değişimi · simülasyon" gibi uzayabiliyor;
          // 320pt'de tek satıra sığmalı (taşma testi bunu kovalıyor).
          Row(
            children: [
              Expanded(
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
              if (kapaliEtiketi != null) ...[
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.c.text36.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    // Metin portföydeki TÜRLERE göre karar verilir:
                    // mevduat faizi, altın, kripto hafta sonu da işler,
                    // onlara "kapalı" demek yanlış bilgidir (bkz.
                    // `piyasaKapaliEtiketi`).
                    kapaliEtiketi,
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36,
                    ),
                  ),
                ),
              ],
              if (aralik != null) ...[
                const SizedBox(width: SandikSpace.sm),
                Text(
                  aralik,
                  maxLines: 1,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm2),
          // Kahraman: tutar en büyük tipografi. Yüzde rozeti YALNIZCA akış
          // yokken burada (o zaman birikim = piyasanın kattığı); akış
          // varken rozet aşağıdaki piyasa kaleminde. Müşteri testi
          // 2026-10-01: "+%106,66" (1Y) ve "+%934,47" (5Y) kahraman
          // rozetleri getiri diye okunuyordu — yatırılan parayı da sayan
          // birikim değişimiydi. Birikim tutar olarak kalır (kullanıcı
          // kararı 2026-09-24), yüzde yalnızca piyasaya ait.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // FittedBox: milyonluk portföyde dar ekranda taşmasın,
              // punto düşsün ama satır kırılmasın.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isFlat
                        ? context.l10n.noChange
                        : '${positive ? '+' : '−'}${tryFmt.format(change.abs())}',
                    maxLines: 1,
                    style: context.t.numMedium.copyWith(color: color),
                  ),
                ),
              ),
              if (pct != null && !isFlat && !akisVar) ...[
                const SizedBox(width: SandikSpace.sm),
                _YuzdeRozeti(pct: pct, renk: color),
              ],
            ],
          ),
          // Alt kat: akış varsa ana rakam alımı/satışı İÇERİR ve "+%100
          // kazandım" yanılgısı doğar. Üç kalem bunu kapatır — Özet
          // köprüsüyle AYNI üç parça (`_KopruKarti`):
          //   • Yatırdığın — alım − satış, temettü HARİÇ (nötr renk,
          //     Özet'teki mavi çubukla aynı anlam);
          //   • Cebine aldığın temettü — varsa, eksi (portföyden cebe);
          //   • Piyasanın kattığı — ana sayfa Bugün kartı ve Özet ile AYNI
          //     rakam ve yüzde; rozet burada.
          if (akisVar) ...[
            const SizedBox(height: SandikSpace.smd),
            Container(height: 1, color: context.c.hairline),
            const SizedBox(height: SandikSpace.sm2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (yatirilan.abs() > 0.5)
                  Expanded(
                    child: _DegisimKalemi(
                      etiket: context.l10n.investedRow,
                      deger: '${yatirilan > 0 ? '+' : '−'}'
                          '${tryFmt.format(yatirilan.abs())}',
                      renk: context.c.text58,
                    ),
                  ),
                if (yatirilan.abs() > 0.5 && temettu.abs() > 0.5)
                  const SizedBox(width: SandikSpace.md),
                if (temettu.abs() > 0.5)
                  Expanded(
                    child: _DegisimKalemi(
                      etiket: context.l10n.dividendPocketRow,
                      deger: '−${tryFmt.format(temettu.abs())}',
                      renk: context.c.text58,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SandikSpace.sm2),
            _DegisimKalemi(
              etiket: context.l10n.marketAddedRow,
              deger: piyasaFlat
                  ? context.l10n.noChange
                  : '${piyasa >= 0 ? '+' : '−'}'
                      '${tryFmt.format(piyasa.abs())}',
              rozet: piyasaPct != null && !piyasaFlat
                  ? _YuzdeRozeti(pct: piyasaPct, renk: piyasaColor)
                  : null,
              renk: piyasaColor,
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

    // Sağ uç CANLI kapsam toplamı — Grafik kartının ucuyla aynı sayı
    // (`currentTotal`); bkz. `compute` [canliSon]. Kıyas kartı da AYNI ucu
    // alır, yoksa "senin portföyün" satırı Özet'in yüzdesiyle ayrışır.
    final canliSon =
        pState == null ? null : DailySummary.kapsamToplami(pState, targetAssets);

    final summary = PeriodSummaryService.compute(
      period: period,
      assets: targetAssets,
      breakdown: breakdown,
      now: now,
      gunlukOzet: gunluk,
      canliSon: canliSon,
      canliDagilim: pState == null
          ? null
          : DailySummary.kapsamDagilimi(pState, targetAssets),
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

    // "Başka yere koysaydın" (PME, düzen A'nın 5. kartı). Girdiler Özet'le
    // AYNI: seri, kapsam lot'ları, `now` ve canlı uç — `KiyasGirdisi.kur`
    // notu. GÜNLÜK'te ya da seri iki uç taşımıyorsa kart yok.
    final kiyasGirdisi = KiyasGirdisi.kur(
      period: period,
      lotlar: targetAssets,
      seri: breakdown.total,
      now: now,
      canliSon: canliSon,
    );

    return _OzetYanVeri(
      period: period,
      summary: summary,
      assets: targetAssets,
      kiyasKarti:
          kiyasGirdisi == null ? null : KiyasKarti(girdi: kiyasGirdisi),
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

/// Dönem kartının alt katındaki tek kalem: küçük büyük harfli etiket,
/// altında tutar (ve varsa "· %x" eki). İki kalem yan yana eşit genişlikte
/// durur; tutar dar ekranda satır kırmak yerine punto düşürür.
class _DegisimKalemi extends StatelessWidget {
  const _DegisimKalemi({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.rozet,
  });

  final String etiket;
  final String deger;
  final Color renk;

  /// Değerin yanındaki yüzde rozeti (piyasanın kattığı kalemi).
  final Widget? rozet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Düz `toUpperCase` Türkçe'de "PIYASA ETKISI" verir; "i" → "İ"
          // için yerel yardımcı (ultrareview bulgusu, 2026-09-24).
          trBuyukHarf(etiket),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: context.c.text36,
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  deger,
                  maxLines: 1,
                  style: context.t.numSmall.copyWith(color: renk),
                ),
              ),
            ),
            if (rozet != null) ...[
              const SizedBox(width: SandikSpace.sm),
              rozet!,
            ],
          ],
        ),
      ],
    );
  }
}

/// Yüzde rozeti — yön ikonu renge ek bir sinyal taşır, renk körlüğünde de
/// okunur. Kahraman satırında (akış yokken) ve piyasa kaleminde aynı rozet.
class _YuzdeRozeti extends StatelessWidget {
  const _YuzdeRozeti({required this.pct, required this.renk});

  final double pct;
  final Color renk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.12),
          borderRadius: SandikRadius.smAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pct >= 0
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 12,
              color: renk,
            ),
            const SizedBox(width: 3),
            // İşaretli (emülatör doğrulaması 2026-09-30): ok ikonunun ekran
            // okuyucu etiketi yok, "−₺… | %0,03" okunuyordu; tutarla aynı
            // yön dili.
            Text(
              fmtPctIsaretli(pct, digits: 2),
              style: context.t.numSmall.copyWith(color: renk),
            ),
          ],
        ),
      );
}

/// Özet'in KENDİ serisi — grafiğin zoom çözünürlüğünden bağımsız.
///
/// ## Neden (müşteri testi 2026-10-01)
/// Özet, grafiğin `ZoomDataController` verisini okuyordu. Kullanıcı
/// grafiği yakınlaştırınca ya da elle bar seçince seri başka çözünürlükte
/// kuruluyor, "ilk dolu nokta" başka güne düşüyor ve Özet'in "Dönem başı"
/// değişiyordu (ölçüldü: 1Y'de ₺705.390 → ₺688.073, 1 Eki → 6 Eki). Aynı
/// dönem iki bakışta iki sayı söylüyordu. Özet artık dönemin KANONİK
/// serisini ister: pencere `PeriodSummaryService.pencere`, çözünürlük
/// `pickForSpan(period.days)` — Ana ekrandaki "Son 7 gün" ile birebir aynı
/// istek (`BugunYukleyici.haftalik`). `HistoryService._tierCache` sayesinde
/// varsayılan zoom'da ağa ikinci kez çıkılmaz.
///
/// Anahtar (dönem, kapsam, simülasyon, lot kimlikleri, yenileme sayacı)
/// değişince yeniden kurulur; o sırada iskelet çizilir — yanlış sayıdan
/// iyidir (`_ozetSekmesi` notu). GÜNLÜK bu yoldan geçmez: gün içi seri
/// canlıdır ve ana ekranla ortak katmandan gelir.
class _OzetSerisi extends StatefulWidget {
  const _OzetSerisi({
    super.key,
    required this.chartAssets,
    required this.period,
    required this.simulate,
    required this.iskelet,
    required this.builder,
  });

  final List<Asset> chartAssets;
  final SummaryPeriod period;
  final bool simulate;
  final Widget iskelet;
  final Widget Function(PortfolioHistoryBreakdown breakdown) builder;

  @override
  State<_OzetSerisi> createState() => _OzetSerisiState();
}

class _OzetSerisiState extends State<_OzetSerisi> {
  PortfolioHistoryBreakdown? _seri;
  int _istek = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final benim = ++_istek;
    final now = DateTime.now();
    final p = PeriodSummaryService.pencere(widget.period, now);
    try {
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: widget.chartAssets,
        from: p.start,
        to: p.end,
        tier: ResolutionTierMeta.pickForSpan(widget.period.days.toDouble()),
        simulate: widget.simulate,
      );
      if (!mounted || benim != _istek) return;
      setState(() => _seri = bd);
    } catch (e, st) {
      // Seri gelmezse iskelet kalır; sessiz değil — Crashlytics'e düşer.
      CrashReporter.report(e, st, reason: 'OzetSerisi.yukle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = _seri;
    if (bd == null || bd.total.isEmpty) return widget.iskelet;
    return widget.builder(bd);
  }
}

/// Grafik ↔ Özet geçişinde yeni sekmenin öğeleri kısa bir solmayla gelir
/// (animasyon denetimi 2026-10-01): eskiden içerik tek karede değişiyordu.
/// Her liste öğesi ayrı sarılır — tüm dalı tek `Column`'a toplamak
/// `ListView`'in tembel kurulumunu bozardı. Anahtar sekmeye bağlı: aynı
/// sekmede yeniden kurulumda (fiyat tiki, dönem) solma OYNAMAZ, yalnız
/// sekme değişince; [taze] değilse (ilk açılış, kaydırınca sonradan kurulan
/// öğe) başlangıç zaten tam opak. Hareketi azalt açıkken süre sıfır.
class _SekmeSolmasi extends StatelessWidget {
  const _SekmeSolmasi({
    required this.ozet,
    required this.taze,
    required this.child,
  });

  final bool ozet;
  final bool taze;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(ozet),
        tween: Tween<double>(begin: taze ? 0.35 : 1, end: 1),
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        child: child,
        builder: (_, v, c) => v >= 1 ? c! : Opacity(opacity: v, child: c),
      );
}
