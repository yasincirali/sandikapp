part of '../portfolio_performance_screen.dart';

/// Seri hazırlığı: geçmişten segment üretimi, gün içi tick, viewport ve
/// zoom denetleyicisi. `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
extension _PerformansSeriler on _PortfolioPerformanceScreenState {
  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    List<Asset> allAssets,
    DateTime startDate,
    DateTime endDate, {
    double? currentTotalOverride,
    bool simulate = false,
    bool intraday = false,
    int? piyasaKapaliBaslangicTs,
  }) {
    if (history.isEmpty || allAssets.isEmpty) return [];

    // Intraday (günlük): X ekseni = 00:00'dan itibaren dakika. Aktif segment
    // tek parça — bugünün başından şu ana kadar tüm noktalar aynı sarı çizgi
    // üstünde gider. Şimdi'den sonraki (gelecek) slotları göstermeyiz.
    if (intraday) {
      final sortedTs = history.keys.toList()..sort();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // "Şimdi" bu eksende VAR MI?
      //
      // Eskiden koşul "çizilen gün bugün mü" idi: piyasa kapalıyken seri
      // son seansa ait olduğu için canlı uç noktası eklenemiyordu.
      //
      // Kuyruk geldikten sonra bu artık doğru değil — seri son seanstan
      // BUGÜNE uzanıyor (`gunIciSagUc`), yani "şimdi" eksenin içinde.
      // Koşulu gün eşitliğine bağlı bırakmak, hafta sonunda son noktayı
      // canlı değere sabitlemeyi engelliyordu. Kullanıcı isteği
      // (2026-09-12): "şu an noktasında izlenen anın değeri gösterilmeli."
      //
      // Ölçüt artık takvim değil GEOMETRİ: "şimdi" eksenin sağ ucunda mı?
      final nowMinutesX = (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
      final simdiEksendeVar = nowMinutesX >= 0;
      final spots = <FlSpot>[];
      // BAŞTAKİ sıfırlar atlanır, SONRAKİLER çizilir.
      //
      // Eskiden koşulsuz `if (y <= 0) continue;` vardı ve iki farklı şeyi
      // aynı sayıyordu: borsa açılmadan önceki VERİSİZ slotlar ile
      // portföyün gerçekten sıfırlandığı slotlar. Tamamı satılan bir
      // portföyde satış sonrası noktalar çizimden düşüyordu ve çizgi son
      // değerde asılı kalıyordu — kullanıcı "varlığımın 0'a indiğini
      // görmüyorum" dedi (2026-09-16). Ölçüldü: gün içi seri 16:45'ten
      // sonra 0 üretiyordu ama grafikte o noktalar yoktu.
      //
      // Ayrım ilk gerçek değere göre: ondan ÖNCEKİ sıfırlar veri yokluğu,
      // SONRAKİLER ölçümdür ve sıfır da bir ölçümdür.
      var ilkDegerGoruldu = false;
      for (final ts in sortedTs) {
        if (ts > nowMs) break;
        final y = history[ts] ?? 0;
        if (y > 0) {
          ilkDegerGoruldu = true;
        } else if (!ilkDegerGoruldu) {
          continue;
        }
        final minutes = (ts - startDate.millisecondsSinceEpoch) / 60000.0;
        spots.add(FlSpot(minutes, y));
      }
      // Şu an'ı canlı toplamla sabitle — grafiğin son noktası "şu andaki
      // portföy değeri" olur.
      //
      // Kapalı kuyruk kaldırıldıktan sonra (2026-09-12) bu koşul sadeleşti:
      // serinin ucu HER ZAMAN canlı toplama sabitlenir. Kullanıcı isteği:
      // "güncel değer ne ise o şekilde göstersin."
      if (simdiEksendeVar &&
          currentTotalOverride != null &&
          currentTotalOverride > 0) {
        if (spots.isNotEmpty && (nowMinutesX - spots.last.x).abs() < 5) {
          spots[spots.length - 1] = FlSpot(nowMinutesX, currentTotalOverride);
        } else {
          spots.add(FlSpot(nowMinutesX, currentTotalOverride));
        }
      } else if (simdiEksendeVar && spots.isNotEmpty) {
        // Canlı toplam kullanılmıyor (ya yok ya da piyasa kapalı): son
        // ÇİZİLEN değer "şimdi"ye taşınır. Kuyruk böylece DÜZ kalır.
        final sonY = spots.last.y;
        if ((nowMinutesX - spots.last.x).abs() >= 5) {
          spots.add(FlSpot(nowMinutesX, sonY));
        }
      }
      if (spots.length < 2) return [];

      // ── Piyasa kapalı kuyruğu ayrı segment ────────────────────────────
      //
      // Hafta sonu serisi Cuma kapanışını bugüne kadar taşıyor. O kuyruk
      // gerçek işlem DEĞİL; tek fiyatın yayılması. Tek segment olarak
      // çizilseydi sarı çizgi düz devam eder ve "fiyat oynamadı" diye
      // okunurdu — oysa borsa kapalıydı.
      //
      // Kuyruk nötr renk + kesikli desenle ayrılıyor (bkz.
      // `TransactionSegment.piyasaKapali`).
      if (piyasaKapaliBaslangicTs != null) {
        final sinirX =
            (piyasaKapaliBaslangicTs - startDate.millisecondsSinceEpoch) /
                60000.0;
        final seans = [
          for (final s in spots)
            if (s.x <= sinirX) s
        ];
        final kapali = [
          for (final s in spots)
            if (s.x >= sinirX) s
        ];

        // İki segment de çizilebiliyorsa böl. Aksi halde (kuyruk tek
        // noktaysa ya da seans boşsa) bölmek kopuk çizgi üretirdi —
        // tek parça bırakmak daha doğru.
        if (seans.length >= 2 && kapali.length >= 2) {
          return [
            TransactionSegment(
              spots: seans,
              lineColor: context.c.amberText,
              areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
              areaGradientEnd: Colors.transparent,
              thickness: 3.5,
            ),
            TransactionSegment(
              spots: kapali,
              // Nötr ton: kuyruk bir kazanç/kayıp anlatmıyor.
              lineColor: context.c.text36,
              // Alan doldurulmaz — dolgu "bu bölge de birikim" derdi.
              areaGradientStart: Colors.transparent,
              areaGradientEnd: Colors.transparent,
              thickness: 2.5,
              piyasaKapali: true,
            ),
          ];
        }
      }

      return [
        TransactionSegment(
          spots: spots,
          lineColor: context.c.amberText,
          areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
          areaGradientEnd: Colors.transparent,
          thickness: 3.5,
        ),
      ];
    }

    final segments = <TransactionSegment>[];
    // Simülasyon modu: tüm dönem tek aktif segment (sarı çizgi). Anchor
    // yok, passive segment yok; her nokta "o gün bugünkü net pozisyon
    // tutulsaydı" değeri.
    if (simulate) {
      final sortedTs = history.keys.toList()..sort();
      final spots = <FlSpot>[];
      for (final ts in sortedTs) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        // Saatlik veri için kesirli gün (24 → 1.0 gün). inDays saati keser
        // ve tüm saatler aynı X'e düşerdi → grafik zigzag olurdu.
        final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
        spots.add(FlSpot(x, history[ts]!));
      }
      // Son spot ŞU ANA taşınır (gerçek seride olduğu gibi — bkz. aşağıdaki
      // aktif segment dalı). Yalnızca Y güncellenirse "ŞİMDİ" çizgisi son
      // kovanın gün başına düşer ve bir önceki güne bitişik görünür.
      if (currentTotalOverride != null && currentTotalOverride > 0) {
        final nowX = endDate.difference(startDate).inMinutes / (60.0 * 24.0);
        if (spots.isNotEmpty) {
          final last = spots.last;
          final yeniX = nowX > last.x ? nowX : last.x;
          spots[spots.length - 1] = FlSpot(yeniX, currentTotalOverride);
        } else {
          spots.add(FlSpot(nowX, currentTotalOverride));
        }
      }
      if (spots.length < 2) return [];
      segments.add(TransactionSegment(
        spots: spots,
        lineColor: context.c.amberText,
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
      return segments;
    }

    // Aktif segment başlangıcı = ilk BUY lot tarihi. Sell/deleteLog dahil
    // edilirse edge case'lerde yanlış tarih seçilebilir; buy yoksa segment
    // zaten çizilmeyecek.
    final buyLots = allAssets.where((a) => a.isBuy && a.isActive).toList();
    if (buyLots.isEmpty) return [];
    final firstAssetDate =
        buyLots.map((a) => a.addedDate).reduce((a, b) => a.isBefore(b) ? a : b);

    // Normalize firstAssetDate to midnight for comparison
    final firstAssetMidnight =
        dayKey(firstAssetDate);

    final sortedTs = history.keys.toList()..sort();

    // Sadece aktif segment (ilk alımdan bugüne). TradingView tarzı: ilk
    // noktanın Y değeri o günün gerçek piyasa değeri (history[ts]). Alım
    // maliyeti tarihsel Y'yi bastırıp yapay atlama üretmez.
    final activeSpots = <FlSpot>[];

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      final y = history[ts]!;
      activeSpots.add(FlSpot(x, y));
    }

    // Son noktayı, kullanıcının şu an ekranda gördüğü toplam mal varlığı
    // değerine sabitle. X ekseni kesirli gün cinsinden (saatlik veride
    // 1 saat = 1/24 gün). Basit strateji: son spot'un Y değerini canlı
    // toplama override et — X'i değiştirme, böylece grafik zigzag/kırık
    // olmaz. Nokta yoksa endDate'in tam anına yeni bir spot ekle.
    if (currentTotalOverride != null && currentTotalOverride > 0) {
      final nowX = endDate.difference(startDate).inMinutes / (60.0 * 24.0);
      if (activeSpots.isNotEmpty) {
        final last = activeSpots.last;
        // Son nokta ŞU ANA taşınır — yalnızca Y'yi güncellemek yetmiyordu.
        //
        // Günlük seride son kova GÜN BAŞINA normalize ediliyor (12 Eylül
        // 00:00). X'e dokunulmayınca "ŞİMDİ" dikey çizgisi o gece yarısına
        // düşüyor ve 11 Eylül'e bitişik duruyordu: kullanıcı tüm
        // dönemlerde "şu an" noktasında 11 Eylül görüyordu
        // (bildirim 2026-09-12).
        //
        // Sıçrama riski yok: X yalnızca İLERİ taşınıyor ve Y aynı kalıyor,
        // yani son segment gün başından şu ana yatay uzar.
        final yeniX = nowX > last.x ? nowX : last.x;
        activeSpots[activeSpots.length - 1] =
            FlSpot(yeniX, currentTotalOverride);
      } else {
        activeSpots.add(FlSpot(nowX, currentTotalOverride));
      }
    }

    if (activeSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: activeSpots,
        lineColor: context.c.amberText,
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
    }

    return segments;
  }

  Future<PortfolioHistoryBreakdown> _intradayHistory(List<Asset> chartAssets) {
    final key = chartAssets.map((a) => a.id).join(',');
    if (_intradayKey == key && _intradayFuture != null) return _intradayFuture!;
    _intradayKey = key;
    _intradayFuture = HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown(chartAssets, 24)
      ..then((v) {
        if (mounted && v.total.isNotEmpty) _lastIntradayData = v;
      });
    return _intradayFuture!;
  }

  void _startIntradayTickIfNeeded() {
    _intradayTick?.cancel();
    if (_PortfolioPerformanceScreenState._periods[_selectedPeriodIdx].intraday) {
      // 30 sn'de bir canlı fiyat çek — son noktanın Y değeri anlık portföy
      // toplamına oturur. refreshPrices bir sonraki portfolio state'ini
      // provider üzerinden yayar, ekran otomatik yeniden build olur.
      _intradayTick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        ref.read(portfolioProvider.notifier).refreshPrices();
        _guncelle(() {
          // Memoize edilen intraday future'ı bilerek düşür — tick'in amacı
          // zaten seriyi tazelemek. Yeni future yüklenirken eski veri
          // `hasData` sayesinde ekranda kalır, spinner'a düşülmez.
          _intradayKey = null;
        });
      });
    }
  }

  /// Grafik viewport'unu period/asset key değişince yenile.
  /// Aynı key + aynı minX/maxX → controller aynı kalır (kullanıcı zoom'unu
  /// kaybetmez). fullRange değiştiyse controller'ı reset et.
  ChartViewport _ensureViewport({
    required String key,
    required double fullMinX,
    required double fullMaxX,
  }) {
    if (_viewportKey != key || _viewport == null) {
      _viewport?.dispose();
      _viewport = ChartViewport(fullMinX: fullMinX, fullMaxX: fullMaxX);
      _viewportKey = key;
    } else if (_viewport!.fullMinX != fullMinX ||
        _viewport!.fullMaxX != fullMaxX) {
      _viewport!.updateFullRange(fullMinX, fullMaxX);
    }
    return _viewport!;
  }

  /// Chart assets/period/simülasyon değiştiğinde controller'ı yeniden kur.
  /// Aynı key gelirse mevcut controller korunur — kullanıcı zoom yaptığı
  /// yerden çalışmaya devam eder.
  void _ensureController({
    required List<Asset> chartAssets,
    required DateTime from,
    required DateTime to,
    required bool intraday,
  }) {
    final key = '${_view ?? "all"}|${_typeFilter?.name ?? "*"}'
        '|$_selectedPeriodIdx|$_simulate|${chartAssets.length}'
        '|${chartAssets.map((a) => a.id).join(",")}';
    if (_zoomKey == key && _zoomController != null) return;
    // Eski controller'ı HEMEN dispose etme. Yeni controller'ın verisi boş
    // başlar; dispose edersek "veri yok + loading" durumu oluşur ve ekran
    // tam sayfa spinner'a düşer — kullanıcı filtre değiştirdiğinde grafiğin
    // (ve altındaki filtre butonlarının) kaybolmasının sebebi buydu.
    // Bunun yerine eski veriyi tohum olarak yeni controller'a veriyoruz:
    // yeni seri gelene kadar soluk haliyle ekranda kalır.
    final previous = _zoomController;
    // Tohum, ÖNCEKİ pencereye ait zaman damgaları içerir. Yeni pencere daha
    // darsa (örn. 1Y → 1A) dışarıda kalan noktalar `startDate`'ten önceye
    // düşer ve grafikte NEGATİF X'e çizilirdi — eksen kayar, çizgi sola
    // taşardı. Bu yüzden tohumu yeni aralığa kırpıyoruz; kalan noktalar
    // doğru X'e oturur, yenisi gelene kadar geçerli bir önizleme olur.
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final rawSeed = previous?.data ?? const <int, double>{};
    final seed = <int, double>{
      for (final e in rawSeed.entries)
        if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
    };
    _zoomKey = key;
    _zoomController = ZoomDataController(
      assets: chartAssets,
      initialFrom: from,
      initialTo: to,
      simulate: _simulate,
      // İki noktadan az kalırsa çizilecek bir şey yok — boş geç ki
      // "veri var" sanılıp bozuk bir çizgi gösterilmesin.
      seedData: seed.length >= 2 ? seed : const {},
    );
    previous?.dispose();
  }
}
