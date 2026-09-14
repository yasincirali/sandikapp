part of '../asset_detail_screen.dart';

/// Ekran eylemleri ve seri hazırlığı: sinyal paneline geçiş, dönem seçimi,
/// karşılaştırma seçici, silme onayı, segment üretimi, dönem anahtarı, eksen
/// yuvarlama. `asset_detail_screen.dart`'ın part'ı (2026-09-14): aynı
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
      _historyFuture = _loadHistory(days);
      // Compare aktifse aynı yeni periyot için compare history'yi de yenile.
      if (_compareAsset != null) {
        _compareHistoryFuture = _karsilastirmaSerisi(_compareAsset!, days);
      }
    });
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
        dayKey(firstAssetDate);

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
}
