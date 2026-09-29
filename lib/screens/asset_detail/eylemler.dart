part of '../asset_detail_screen.dart';

/// Ekran eylemleri ve seri hazırlığı: sinyal paneline geçiş, dönem seçimi,
/// karşılaştırma seçici, silme onayı, segment üretimi, eksen yuvarlama.
/// (Dönem çipleri 2026-09-28'de `ozet.dart`'a taşındı.) `asset_detail_screen.dart`'ın part'ı (2026-09-14): aynı
/// kütüphane, davranış AYNEN; `setState` yerine `_guncelle`.
extension _DetayEylemler on _AssetDetailScreenState {
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

  /// Şeritten aşağıdaki panele kaydır.
  ///
  /// Bir ara "Aktif Sinyal" bölümüne kaydırıyordu; o bölüm kullanıcı
  /// isteğiyle kaldırıldı (2026-09-10) ve hedef yine teknik panel.
  void _sinyalPaneline() {
    final ctx = _sinyalPaneliKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
      // Hedef ekranın üst kenarına yapışmasın; başlığı görünür kalsın.
      alignment: 0.1,
    );
  }

  void _selectPeriod(int idx) {
    // Eski sekme gün içi miydi? Index güncellenmeden ÖNCE okunmalı.
    final oncekiGunIci = _gunIciMi;
    _guncelle(() {
      _selectedPeriodIdx = idx;
      final days = _periods[idx].days;
      // Bayat seri periyotlar arasında köprü kurar (bkz. `_lastHistory`).
      // Gün içi ile günlük seriler AYNI ölçekte DEĞİL: biri 5 dakikalık
      // slot, öteki gün kapanışı. Birinden ötekine geçerken eski seriyi
      // taşımak, yeni eksene ait olmayan noktalar çizerdi.
      if ((days == 0) != oncekiGunIci) _lastHistory = null;
      // Dönem önbellekteyse (çipler açılışta paralel yüklendi) seri HEMEN
      // çizilir — bekleme çubuğu yok. Gün içi seri yine de sessizce
      // tazelenir (aşağıda `_nabizGeldi`); öteki dönemler günlük veridir.
      final onbellek = _donemSerileri[days];
      if (onbellek != null && onbellek.length >= 2) {
        if (days == 0) _gunIciBaslangic = _gunIciSeansOnbellek;
        _lastHistory = onbellek;
        _historyFuture = SynchronousFuture(onbellek);
      } else {
        _historyFuture = _loadHistory(days);
      }
      // Compare aktifse aynı yeni periyot için compare history'yi de yenile.
      if (_compareAsset != null) {
        _compareHistoryFuture = _karsilastirmaSerisi(_compareAsset!, days);
      }
    });
    if (_gunIciMi && _donemSerileri.containsKey(0)) {
      CrashReporter.arkaPlan(_nabizGeldi(), reason: 'AssetDetail.gunIciTazele');
    }
  }

  void _openComparePicker() {
    final pState = ref.read(portfolioProvider).valueOrNull;
    // `aktifLotlar`: tamamen satılmış pozisyon karşılaştırma listesinde
    // çıkmamalı — kullanıcı artık tutmadığı bir varlıkla kıyas kuramaz.
    final all = aktifLotlar(pState?.assets ?? const <Asset>[]);
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
            _guncelle(() {
              _compareAsset = vAsset;
              _compareHistoryFuture = vAsset == null
                  ? null
                  : _karsilastirmaSerisi(
                      vAsset, _periods[_selectedPeriodIdx].days);
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
    confirmAndDeletePosition(ctx, ref, name: widget.asset.name, lots: lots)
        .then((deleted) {
      // Varlık gitti — bu ekranın konusu kalmadı; listeye dön.
      if (deleted && mounted) Navigator.pop(context);
    });
  }

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    DateTime startDate,
    DateTime endDate, {
    double? currentUnitPriceOverride,
  }) {
    // `intraday` parametresi 2026-09-23'te kalktı: tek işi gün içinde ilk
    // noktayı maliyetle EZMEMEKTİ; artık hiçbir dönemde ezilmiyor.
    if (history.isEmpty) return [];

    final segments = <TransactionSegment>[];

    // [history] BİRİM fiyat serisidir (1 gram / 1 adet / 1 pay, TL) —
    // `FiyatKaynagi.birimVarlik` ile çekilir. Bölme YOK, miktar YOK.
    //
    // ## Kaldırılanlar (kullanıcı kararı, 2026-09-23)
    // *"Zaman aralığına göre 1 gram ya da bir lot varlığın grafiğini
    // göstermeli."*
    //
    //   · **Alım tarihinde kırpma.** Grafik eskiden ilk alımdan başlıyordu;
    //     1A seçip 3 gün önce alan kullanıcı 3 günlük bir çizgi görüyordu.
    //     Ürünün dönemi, sahibin alım tarihine bağlı değildir.
    //   · **İlk noktayı ortalama maliyetle ezmek.** Uzun dönemlerde ilk
    //     nokta ALIŞ fiyatına çekiliyordu: bir yıl önce alınmış altının 1H
    //     grafiği ₺4.000'den başlayıp ₺6.100'e "sıçrıyordu" — o sıçrama bu
    //     haftaya ait değildi. Alış→bugün kâr/zararı üstteki şeritte
    //     (`_PozisyonKarti`) ayrıca duruyor.
    //   · **Miktara bölmek** (`miktarDamgada`/`bolenDamgada`). Pozisyon
    //     serisini birime indirmeye çalışıyordu; motorun tarih kapısıyla
    //     uyuşmadığı için alım slotunda fiyat iki katına çıkıyordu (ölçüldü:
    //     Çeyrek ₺21.807 → ₺10.747).
    //
    // `v <= 0` slotlar ÇİZİLMEZ: birim fiyat için sıfır bir ölçüm değil,
    // verisiz kovadır (borsa açılmadan önce, kur yokken).
    final sortedTs = history.keys.toList()..sort();
    final activeSpots = <FlSpot>[];
    for (final ts in sortedTs) {
      final y = history[ts]!;
      if (y <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      // Saatlik veride (haftalık) her saat farklı X'e düşmeli — inDays saati
      // keser ve tüm saatler aynı X'e sıkışırdı, grafik dikey zigzag olurdu.
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      // Pencereden önceki nokta eksenin soluna düşer ve ekseni kaydırır.
      if (x < 0) continue;
      activeSpots.add(FlSpot(x, y));
    }

    // Son aktif spot'u canlı fiyat ile değiştir — böylece grafik bitiş
    // noktası ve üstteki PnL chip aynı değeri gösterir (Yahoo history son
    // bar'ı ile canlı `currentPrice` arasındaki gecikme/ölçek farkını kapat).
    // Tek spot varsa o dönem BAŞIdır — ezilirse başlangıç çizgisi yanlış
    // yere çizilir. O durumda canlı fiyat için ayrı bir "son" spot eklenir.
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
        // Ortak grafik stili (Performans ile aynı amber).
        lineColor: GrafikStili.cizgi(context),
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5, // Thicker active line
      ));
    }

    return segments;
  }
}
