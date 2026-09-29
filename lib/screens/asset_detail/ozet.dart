part of '../asset_detail_screen.dart';

/// Ekranın üst özeti ve dönem istatistikleri — A tasarımı.
///
/// ## Karar (kullanıcı, 2026-09-28)
/// "Varlık aramada detay ekranında gösterilen bazı özellikler portföy →
/// varlık detayında yok, tasarımı daha modern… halihazırda gösterilen hiçbir
/// veri kaybolmamalı." Dört tasarım dilinden **A (varlık sayfası ailesi)**
/// seçildi, B'den bir satırla: fiyatın hemen altında pozisyonun kâr/zararı.
/// Aynı varlık aramadan (varlık sayfası) ve portföyden (bu ekran) açılınca
/// aynı düzen görünür; burada ek olarak pozisyon, alarm ve ayrıntılı
/// analiz vardır. Ortak parçalar `widgets/donem_istatistik.dart`'ta.
///
/// Varlık sayfasından gelenler: büyük güncel fiyat, 5Y, her dönem çipinde o
/// dönemin getirisi, 2×2 istatistik, dönem aralığı çubuğu, izleme yıldızı
/// (yalnızca zaten takipteyse — çıkarmak için), yasal ibare.
///
/// ## Tek kaynak
/// Çiplerin, başlığın ve "dönem değişimi" satırının yüzdesi AYNI formülden
/// ve AYNI birim seriden gelir: `PeriodSummaryService.uclar` ile dönem başı,
/// canlı birim fiyatla son (grafiğin sağ ucu). Varlık sayfasındaki sembol
/// serisi burada KULLANILMAZ — iki kaynak aynı ekranda iki sayı yazardı.
///
/// ## Performans
/// Dönemlerin birim serileri açılışta PARALEL istenir (varlık sayfasıyla
/// aynı karar); seçili dönem önce ve ötekileri beklemeden çizilir. 6A, 1Y ve
/// 5Y aynı haftalık katmandan (`yahooRange: 5y`) beslenir; `HistoryService`
/// aynı isteği tekilleştirir, yani 5Y ağa ek istek çıkarmaz. Önbellekteki
/// döneme geçiş beklemesiz: seri `SynchronousFuture` ile hemen çizilir.
/// Pozisyonun sayıları — tek kayıt, üç tüketici: fiyat bloğundaki
/// "Pozisyonun" satırı, `_PozisyonKarti` ve grafiğin uç rengi. Üçü AYNI
/// kaydı okur; ayrı hesap yazılmaz (ana sayfa kartıyla aynı formül).
typedef _PnlOzeti = ({
  double anchorUnitTRY,
  double currentUnitTRY,
  double totalCostTRY,
  double currentValueTRY,
  double totalPnlTRY,
  double pnlPct,
  bool gainPositive,
});

extension _DetayOzet on _AssetDetailScreenState {
  /// Pozisyonun alış → bugün özeti (bkz. [_PnlOzeti]).
  _PnlOzeti _pnlOzeti(PortfolioState? pState) {
    // Canlı görünüm — açılış anının kopyası değil (bkz. `_canli`).
    final asset = _canli.asset;
    final qty = asset.quantity;
    final anchorUnitTRY = asset.purchasePrice * asset.purchaseFxRate;
    final currentValueTRY = pState != null
        ? pState.toTRY(asset.totalValue, asset.currency)
        : asset.totalValue;
    final currentUnitTRY = qty > 0 ? currentValueTRY / qty : 0.0;
    final totalCostTRY = asset.totalCostTRY;
    final totalPnlTRY = currentValueTRY - totalCostTRY;
    final pnlPct =
        totalCostTRY > 0 ? (totalPnlTRY / totalCostTRY) * 100 : 0.0;
    return (
      anchorUnitTRY: anchorUnitTRY,
      currentUnitTRY: currentUnitTRY,
      totalCostTRY: totalCostTRY,
      currentValueTRY: currentValueTRY,
      totalPnlTRY: totalPnlTRY,
      pnlPct: pnlPct,
      gainPositive: totalPnlTRY >= 0,
    );
  }

  /// Dönemin grafik penceresinin başı — grafikle AYNI kural (gün içi →
  /// çizilen seansın 00:00'ı, diğerleri Performans'ın takvim penceresi).
  DateTime _pencereBasi(int days, DateTime now, {DateTime? seansGunu}) =>
      days == 0
          ? (seansGunu ?? _gunIciBaslangic ?? dayKey(now))
          : _AssetDetailScreenState._donemBaslangici(days, now);

  /// Yüklenen dönem serisini önbelleğe yazar ve dönem başını / istatistiği
  /// BİR KEZ hesaplar (build'de değil). Boş ya da tek noktalı seri yazılmaz:
  /// "veri yok" bir ölçüm değildir, çip boş kalır.
  void _donemKaydet(int days, Map<int, double> seri, DateTime? seansGunu) {
    if (seri.length < 2) return;
    final now = DateTime.now();
    final fromMs =
        _pencereBasi(days, now, seansGunu: seansGunu).millisecondsSinceEpoch;
    final u = PeriodSummaryService.uclar(seri,
        fromMs: fromMs, toMs: now.millisecondsSinceEpoch);
    _donemSerileri[days] = seri;
    if (days == 0) _gunIciSeansOnbellek = seansGunu;
    _donemIlk[days] = u == null || u.firstTs == u.lastTs ? null : u.first;
    _donemIstatistikleri[days] = DonemIstatistigi.hesapla(
      {
        for (final e in seri.entries)
          if (e.key >= fromMs) e.key: e.value,
      },
      periodDays: days,
    );
  }

  /// Seçili dışındaki dönemleri paralel yükler — çip getirileri için.
  Future<void> _digerDonemleriYukle() async {
    // `_loadHistory` ile aynı sıra: süren fiyat turu `_canli` OKUNMADAN önce.
    await ref
        .read(portfolioProvider.notifier)
        .fiyatTurunuBekle(enFazla: TazelikRitmi.gunIciSeriOmru);
    if (!mounted) return;
    final birim = FiyatKaynagi.birimVarlik(_canli.asset);
    final secili = _periods[_selectedPeriodIdx].days;
    await Future.wait([
      for (final p in _periods)
        if (p.days != secili && !_donemSerileri.containsKey(p.days))
          _donemSerisi([birim], p.days).then((b) {
            if (!mounted) return;
            _guncelle(() => _donemKaydet(p.days, b.total, b.seansGunu));
          }, onError: (Object e, StackTrace st) {
            // Çip boş kalır; dönem seçilince `_loadHistory` yeniden dener.
            CrashReporter.report(e, st,
                reason: 'AssetDetail.digerDonemler');
          }),
    ]);
  }

  /// Dönemin yüzdesi: dönem başı (`uclar`) → canlı birim fiyat.
  double? _donemYuzdesi(int days, double canliBirim) {
    final ilk = _donemIlk[days];
    if (ilk == null || ilk <= 0) return null;
    final son = canliBirim > 0 ? canliBirim : null;
    if (son == null) return null;
    return (son / ilk - 1) * 100;
  }

  /// Seçili dönemin değişimi — "dönem değişimi" satırı.
  ///
  /// ## İki sayı, iki soru (kullanıcı kararı, 2026-09-23)
  /// *"Zaman aralığına göre 1 gram ya da bir lot varlığın grafiğini
  /// göstermeli, diğer alanlarda da kazanç hesaplanarak yazılmalı."*
  ///
  ///   · YÜZDE → ÜRÜNÜN hareketi: birim serinin (grafiğin) başı ile sonu.
  ///     Sahibin alımı, satımı, maliyeti onu oynatamaz; iki ortak aynı ürüne
  ///     aynı dönemde bakınca aynı yüzdeyi görür.
  ///   · TUTAR → SAHİBİN kazancı: pozisyonun PİYASA ETKİSİ, `son miktar ×
  ///     son birim − baş miktar × baş birim − dönem içi net alım`
  ///     (`birimPiyasaEtkisi`). Dönem içinde açılan lot ALIŞ fiyatından
  ///     ölçülür.
  ///
  /// Eskiden tutar `(son − baş) × SON miktar` idi: bugün alınan lot dönemin
  /// tamamını yaşamış sayılıyordu. `v <= 0` slotlar `uclar` içinde ELENİR
  /// (ölçüldü 2026-09-23: boş ilk slot 22 ayar gramda +₺612.621 yazdırdı).
  ///
  /// Grafiğin içinden buraya taşındı (A tasarımı, 2026-09-28): satır artık
  /// grafiğin altındaki pozisyon bölümünde. Seçili dönemin serisi henüz
  /// gelmediyse `null` — eski dönemin rakamı yeni dönemin etiketiyle
  /// yazılmaz.
  ({double tutar, double yuzde})? _donemDegisimi(
      int days, DateTime start, DateTime end, double canliBirim) {
    final seri = _donemSerileri[days];
    if (seri == null) return null;
    final u = PeriodSummaryService.uclar(seri,
        fromMs: start.millisecondsSinceEpoch,
        toMs: end.millisecondsSinceEpoch);
    if (u == null || u.firstTs == u.lastTs) return null;
    // Son = grafiğin sağ ucu (canlı birim fiyat).
    final son = canliBirim > 0 ? canliBirim : u.last;
    final tutar = PeriodSummaryService.birimPiyasaEtkisi(
      birimSeri: seri,
      lotlar: _seriDefteri,
      start: start,
      end: end,
      canliBirim: son,
    )?.piyasa;
    if (tutar == null) return null;
    return (tutar: tutar, yuzde: (son / u.first - 1) * 100);
  }

  /// Birim fiyat biçimi — ₺ kalır: fiyat bir DEĞER değildir, baz para
  /// birimine çevrilmez (`money_format_scope_test` değer/fiyat ayrımı).
  NumberFormat get _birimBicim => tryFormatter(digits: 2);

  // ── Başlık ───────────────────────────────────────────────────────────────

  Widget _baslik() {
    final a = widget.asset;
    final l = context.l10n;
    return Semantics(
      header: true,
      label: l.assetPerformanceSemantics(a.name),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _kimlik.kisaEtiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: context.c.text90),
          ),
          // Sembolü olmayan (elle fiyatlanan) varlıkta kısa etiket adın
          // kendisidir; alt satırda adı tekrarlamak "Kadıköy daire / Kadıköy
          // daire · Diğer" gibi okunur.
          Text(
            _kimlik.kisaEtiket == a.name
                ? a.type.labelOf(l)
                : '${a.name} · ${a.type.labelOf(l)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ),
    );
  }

  /// Takip listesi ve varlık sayfasıyla AYNI anahtar (`VarlikKimligi.key`).
  VarlikKimligi get _kimlik {
    final a = widget.asset;
    return VarlikKimligi(
      ticker: a.ticker,
      name: a.name,
      type: a.type,
      subCategory: a.subCategory,
      currency: a.currency,
    );
  }

  /// Güncel fiyat + seçili dönemin değişimi + pozisyon satırı.
  ///
  /// Fiyat CANLI birim fiyattır (grafiğin sağ ucu, pozisyon kartındaki
  /// "Bugünkü fiyat") — seri beklenmeden görünür.
  Widget _fiyatBlogu(_PnlOzeti pnl, BazPara baz) {
    final l = context.l10n;
    final days = _periods[_selectedPeriodIdx].days;
    final etiket = donemEtiketi(l, _periods[_selectedPeriodIdx].label);
    final canli = pnl.currentUnitTRY;
    final pct = _donemYuzdesi(days, canli);
    final ilk = _donemIlk[days];
    final bicim = _birimBicim;

    final String degisim;
    final Color degisimRenk;
    if (pct == null || ilk == null) {
      degisim = ' ';
      degisimRenk = context.c.text36;
    } else if (donemDuzMu(pct)) {
      degisim = l.periodNoChange(etiket);
      degisimRenk = context.c.text36;
    } else {
      final fark = canli - ilk;
      degisim = '${pct >= 0 ? '+' : '−'}${fmtPct(pct.abs())} · '
          '${fark >= 0 ? '+' : '−'}${bicim.format(fark.abs())} · $etiket';
      degisimRenk = context.signColor(pct);
    }

    final pnlDuz =
        pnl.totalPnlTRY.abs().round() == 0 && pnl.pnlPct.abs() < 0.005;
    final pnlRenk = pnlDuz
        ? context.c.text36
        : (pnl.gainPositive ? context.c.gain : context.c.loss);
    final isaret = pnlDuz ? '' : (pnl.gainPositive ? '+' : '−');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.currentPriceUpper,
              style: context.t.labelSmall?.copyWith(
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: context.c.text36),
            ),
            // Kripto fiyatı gecikmeli olabilir — etiket fiyatın yanında,
            // okunduğu yerde (eskiden grafiğin altındaydı).
            if (widget.asset.type == AssetType.kripto) ...[
              const SizedBox(width: SandikSpace.sm),
              Flexible(
                  child: KriptoGecikmeEtiketi(sembol: widget.asset.ticker)),
            ],
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            canli > 0 ? bicim.format(canli) : '—',
            maxLines: 1,
            style: context.t.numLarge.copyWith(color: context.c.gold),
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          degisim,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.numSmall.copyWith(color: degisimRenk),
        ),
        const SizedBox(height: SandikSpace.xs2),
        // B'den alınan satır: en önemli sayı ("param ne durumda") ilk bakışta.
        // Ayrıntısı aşağıdaki pozisyon bölümünde, aynı sayılarla.
        Text(
          l.adPositionLine(
            '$isaret${baz.compact(pnl.totalPnlTRY.abs())}',
            '$isaret${fmtPct(pnl.pnlPct.abs())}',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.numSmall
              .copyWith(color: pnlRenk, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // ── Dönem çipleri ────────────────────────────────────────────────────────

  /// Dönem seçici — ortak [DonemSecici], her segmentin altında o dönemin
  /// getirisi (eski çiplerin getiri şeridi korunur; tek görünüş kararı
  /// 2026-09-28). GÜNLÜK elle fiyatlanan varlıkta yine YOK
  /// (`_gunIciDestekli`) — orada gösterilecek bir gün içi seri yok.
  Widget _donemCipleri(double canliBirim) {
    final donemler = [
      for (final p in SummaryPeriod.values)
        if (!p.intraday || _gunIciDestekli) p,
    ];
    return DonemSecici(
      donemler: donemler,
      secili: _selectedPeriodIdx,
      getiriler: [
        for (final p in _periods) _donemYuzdesi(p.days, canliBirim),
      ],
      onSec: _selectPeriod,
    );
  }

  // ── İstatistikler ────────────────────────────────────────────────────────

  /// 2×2 istatistik + dönem aralığı. Seçili dönemin serisi gelmeden sayı
  /// yazılmaz (uydurma yok); gelince yerine oturur.
  ///
  /// Seri henüz yokken bölüm BOŞ DÖNMEZ, aynı boyda iskelet durur
  /// (2026-09-28): eskiden `[]` dönüyor, altındaki sinyal paneli yukarı
  /// sıçrayıp seri gelince geri iniyordu — dönem değiştirirken sayfa
  /// "yeniden yükleniyor" gibi görünüyordu. Kullanıcı kararı: dönem
  /// değişince yalnızca grafik ve ona bağlı alanlar yenilensin, yerleşim
  /// oynamasın.
  List<Widget> _istatistikler(double canliBirim) {
    final days = _periods[_selectedPeriodIdx].days;
    final ist = _donemIstatistikleri[days];
    final pct = _donemYuzdesi(days, canliBirim);
    if (ist == null || pct == null) return [_istatistikIskeleti()];
    // Aralık canlı fiyatı da kapsar: seri haftalıkken bugünkü fiyat son
    // kapanışın dışına taşabilir; imleç yine çubuğun içinde doğru yerde.
    final canli = canliBirim > 0 ? canliBirim : ist.son;
    final dusuk = math.min(ist.dusuk, canli);
    final yuksek = math.max(ist.yuksek, canli);
    final aralik = yuksek - dusuk;
    return [
      DonemIstatistikIzgarasi(
        ist: ist,
        gun: days,
        donemPct: pct,
        bugunPct: _gunIciDestekli ? _donemYuzdesi(0, canliBirim) : null,
      ),
      // Dip = zirve (elle fiyatlanan varlık, dönem boyunca kıpırdamamış
      // seri): çubuk "₺X — ₺X, %50 noktasında" der, yani hiçbir şey. Bilgi
      // ızgarada zaten var (getiri %0, düşüş %0); boş çubuk gürültüdür.
      if (aralik > 1e-9 * yuksek.abs()) ...[
        const SizedBox(height: SandikSpace.sm),
        DonemAralikCubugu(
          dusuk: dusuk,
          yuksek: yuksek,
          konum: (canli - dusuk) / aralik,
          bicim: _birimBicim,
        ),
      ],
    ];
  }

  // ── Temettü ──────────────────────────────────────────────────────────────

  /// "Son 12 ay temettü" kartı (plan §F5, 2026-09-29).
  ///
  /// Yalnız KENDİ varlığında: ortağın temettüsünü sen kaydedemezsin
  /// (`addDividend` oturum sahibine yazar). Defter sahibin tüm satırları —
  /// geçmişi soran hesap, `aktifLotlar` değil (CLAUDE.md "Kapanmış
  /// pozisyon"). Kart bayrak/tür/veri yoksa kendini tamamen gizler.
  Widget _temettuKarti(PortfolioState pState) => TemettuGecmisiKarti(
        varlik: _canli.asset,
        defter: pState.assets,
      );

  /// [DonemIstatistikIzgarasi] + aralık çubuğunun yer tutucusu — aynı kart
  /// kabuğu, aynı boy (`VarlikIskeleti`'nin kart deseni).
  Widget _istatistikIskeleti() {
    Widget kart() => Expanded(
          child: Container(
            padding: const EdgeInsets.all(SandikSpace.smd),
            decoration: context.surfaceCard(),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SandikSkeleton(width: 72, height: 10),
                SizedBox(height: SandikSpace.xs),
                SandikSkeleton(width: 56, height: 16),
              ],
            ),
          ),
        );
    return Semantics(
      label: context.l10n.loadingEllipsis,
      child: Column(
        children: [
          Row(children: [kart(), const SizedBox(width: SandikSpace.sm), kart()]),
          const SizedBox(height: SandikSpace.sm),
          Row(children: [kart(), const SizedBox(width: SandikSpace.sm), kart()]),
        ],
      ),
    );
  }
}
