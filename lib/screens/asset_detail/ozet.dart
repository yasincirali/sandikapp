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

/// Grafiğin altındaki kartların üst boşluğu (eski yığın). Katmanlı düzen
/// (`katmanlar.dart`) kendi daha sıkı boşluğunu verir.
const _kartBoslugu = EdgeInsets.only(top: SandikSpace.lg);

extension _DetayOzet on _AssetDetailScreenState {
  /// Pozisyonun canlı lot kimlikleri — bekleyen fon alımı işareti lot
  /// kimliğiyle tutulur (Ar-Ge 7 Kas 14:30 #1).
  List<String> get _fonLotIdleri => [for (final l in _canli.lots) l.id];

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
    final pnlPct = totalCostTRY > 0 ? (totalPnlTRY / totalCostTRY) * 100 : 0.0;
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

  /// Elde tutma süresi ve yıllık ortalama getiri (Ar-Ge 7 Kas 20:30 #6).
  /// Yalnız bugün açık pozisyonda (kapanmışta satır yok); mevduatın getirisi
  /// sözleşmeden okunur, burada çizilmez. Lot listesi ya da değer
  /// değişmedikçe hesap tekrar koşmaz.
  EldeTutma? _eldeTutma(_PnlOzeti pnl) {
    final canli = _canli;
    if (!canli.acik || widget.asset.type == AssetType.mevduat) return null;
    final o = _eldeTutmaOnbellek;
    if (o != null &&
        identical(o.lots, canli.lots) &&
        o.deger == pnl.currentValueTRY) {
      return o.sonuc;
    }
    final sonuc = eldeTutma(
      lotlar: canli.lots,
      guncelDegerTRY: pnl.currentValueTRY,
      simdi: DateTime.now(),
    );
    _eldeTutmaOnbellek =
        (lots: canli.lots, deger: pnl.currentValueTRY, sonuc: sonuc);
    return sonuc;
  }

  /// "Portföyündeki payı" (Ar-Ge 11 Kas 19:04 #7) — hesap `portfoyPayi`'de
  /// (model katmanı, Portföy halkasıyla aynı toplam). Yalnız KENDİ açık
  /// pozisyonunda: kapalı pozisyonun bugünkü payı yoktur, ortağın
  /// pozisyonu bu kullanıcının portföyünün parçası değildir. Defter ya da
  /// fiyat durumu değişmedikçe yeniden hesaplanmaz.
  double? _portfoyPayi(
      _PnlOzeti pnl, PortfolioState? pState, bool isOwnAsset) {
    if (!isOwnAsset || pState == null || !_canli.acik) return null;
    final defter = _canliDefter;
    if (defter == null) return null;
    final o = _portfoyPayiOnbellek;
    if (o != null &&
        identical(o.defter, defter) &&
        identical(o.pState, pState) &&
        o.deger == pnl.currentValueTRY) {
      return o.pay;
    }
    final pay = portfoyPayi(
        degerTRY: pnl.currentValueTRY, defter: defter, toTRY: pState.toTRY);
    _portfoyPayiOnbellek =
        (defter: defter, pState: pState, deger: pnl.currentValueTRY, pay: pay);
    return pay;
  }

  /// Para piyasası fonunda "Son 30 günde günde ortalama ~₺X" (müşteri raporu
  /// 7 Kas 22:30 #1, ücretsiz). Yalnız bugün açık pozisyonda ve TEFAS
  /// kategorisi bilinen para piyasası fonunda; kategori tahmin edilmez.
  /// Seriler dönem çipleri için zaten yüklenen birim serilerdir (3A önce:
  /// günlük çözünürlük, 30 günü kapsar); yeni istek yok.
  double? _gunlukGetiri(_PnlOzeti pnl) {
    if (!_canli.acik) return null;
    final kod = fonKoduOf(tur: widget.asset.type, ticker: widget.asset.ticker);
    if (kod == null || !ref.watch(paraPiyasasiFonuProvider(kod))) return null;
    final seriler = [
      _donemSerileri[SummaryPeriod.ucAy.days],
      _donemSerileri[SummaryPeriod.birAy.days],
      _donemSerileri[SummaryPeriod.altiAy.days],
    ];
    final o = _gunlukGetiriOnbellek;
    if (o != null &&
        o.deger == pnl.currentValueTRY &&
        o.birim == pnl.currentUnitTRY &&
        identical(o.seriler[0], seriler[0]) &&
        identical(o.seriler[1], seriler[1]) &&
        identical(o.seriler[2], seriler[2])) {
      return o.sonuc;
    }
    final sonuc = gunlukOrtalamaGetiri(
      seriler: seriler,
      guncelBirim: pnl.currentUnitTRY,
      guncelDegerTRY: pnl.currentValueTRY,
      simdi: DateTime.now(),
    );
    _gunlukGetiriOnbellek = (
      seriler: seriler,
      deger: pnl.currentValueTRY,
      birim: pnl.currentUnitTRY,
      sonuc: sonuc,
    );
    return sonuc;
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
  ///
  /// [veriYok]: GÜNLÜK seride gerçek nokta yok, seri tohumdur. Dönem başı
  /// yazılmaz — tohumdan çıkan %0 bir ölçüm değildir.
  void _donemKaydet(int days, Map<int, double> seri, DateTime? seansGunu,
      {bool veriYok = false}) {
    if (days == 0) _gunIciVeriGelmedi = veriYok && seri.isNotEmpty;
    if (seri.length < 2) return;
    final now = DateTime.now();
    final fromMs =
        _pencereBasi(days, now, seansGunu: seansGunu).millisecondsSinceEpoch;
    final u = PeriodSummaryService.uclar(seri,
        fromMs: fromMs, toMs: now.millisecondsSinceEpoch);
    _donemSerileri[days] = seri;
    if (days == 0) _gunIciSeansOnbellek = seansGunu;
    _donemIlk[days] =
        u == null || u.firstTs == u.lastTs || veriYok ? null : u.first;
    _donemIstatistikleri[days] = DonemIstatistigi.hesapla(
      {
        for (final e in seri.entries)
          if (e.key >= fromMs) e.key: e.value,
      },
      periodDays: days,
      simdi: now,
    );
    // Yıllık aralık 1Y serisinden — seçili dönemden bağımsız, çip değişince
    // satır oynamaz. Yeni kaynak/istek yok: aynı birim seri.
    if (days == SummaryPeriod.birYil.days) {
      _yillikUclar = YillikUclar.hesapla(seri, simdi: now);
    }
  }

  /// Seri dönemin başına ulaşmıyorsa kapsanan gün (`kapsamEksik`); mevduat
  /// seriden değil sözleşmeden hesaplandığı için hep `null`.
  int? _donemKapsami(int days) => widget.asset.type == AssetType.mevduat
      ? null
      : _donemIstatistikleri[days]?.kapsananGun;

  /// Önce eski seri, sonra taze (2026-10-24, Ar-Ge raporu §1).
  ///
  /// Soğuk açılışta bellek boş; grafik ağ yanıtına kadar (en çok 8 sn)
  /// iskeletteydi. Aynı birim seri motoru burada AĞA ÇIKMADAN, diskteki son
  /// ölçülmüş serilerle koşar (`HistoryService.eldekiSeriyle`); sonuç
  /// `_lastHistory`'ye yazılır ve FutureBuilder'ın var olan bayat-seri yolu
  /// onu SOLUK çizer (`isStale`). Taze seri gelince `_loadHistory` yerine
  /// yazar, grafik ve göstergeler (MA/EMA, özel göstergeler) taze seriden
  /// yeniden kurulur.
  ///
  /// Gün içi (`days == 0`, 2026-10-25'ten beri, yasin onayı): saatlik
  /// döküm motoru yurt içi gün içi kaynağına ve TEFAS yayın gözlemine de
  /// gider; ikisi de eldeki-kipte ağa çıkmaz (yurt içi kayıt bellek/diskten
  /// BUGÜNÜN kaydı, gözlem yalnız bellekte bugün alınmışsa) ve biri yoksa
  /// eski seri hiç gösterilmez. Çizilen seans bugün değilse de gösterilmez
  /// — GÜNLÜK eski seri yalnız bugünden
  /// (`HistoryService.getPortfolioHistoryHourlyBreakdownEldeki`).
  ///
  /// Dönen değer: eski seri çizildi mi (açılış kapısı tazeyi beklemesin).
  Future<bool> _eldekiSeriyiGoster(int days) async {
    final birim = FiyatKaynagi.birimVarlik(_canli.asset);
    final ({PortfolioHistoryBreakdown sonuc, DateTime zaman})? e;
    try {
      e = days == 0
          ? await HistoryService.instance
              .getPortfolioHistoryHourlyBreakdownEldeki([birim])
          : await HistoryService.eldekiSeriyle(
              () => _donemSerisi([birim], days));
    } catch (err, st) {
      CrashReporter.report(err, st, reason: 'AssetDetail.eldekiSeri');
      return false;
    }
    if (e == null || !mounted) return false;
    final seri = e.sonuc.total;
    final zaman = e.zaman;
    // Taze seri önce geldiyse, dönem değiştiyse ya da ekranda zaten bir
    // seri varsa eski kopya yok sayılır.
    if (seri.length < 2 ||
        _periods[_selectedPeriodIdx].days != days ||
        _donemSerileri.containsKey(days) ||
        _lastHistory != null) {
      return false;
    }
    final seans = days == 0 ? e.sonuc.seansGunu : null;
    _guncelle(() {
      _lastHistory = seri;
      if (days == 0) _gunIciBaslangic = seans;
      _eskiSeri = (days: days, zaman: zaman, yolda: true, seans: seans);
    });
    return true;
  }

  /// Ölçeği canlı kura hizalanan varlıkta canlı kur henüz yoksa dönem
  /// serileri de fiyat turunu bekler — gerekçe `_loadHistory` ve
  /// `FiyatKaynagi.olcekCanliKuraBagli`.
  bool get _olcekTuruBekler =>
      FiyatKaynagi.olcekCanliKuraBagli(_canli.asset) &&
      !HistoryService.canliKurBiliniyor;

  /// [days] dönemini (gün içi DEĞİL) tur bitince yeni fiyatla yeniden
  /// kurulacaklar arasına yazar. Birden çok dönem tek bekleyişte toplanır.
  void _turSonrasiUcuYenile(int days, Future<void> tur) {
    assert(days != 0); // gün içi seri turu bekler, burada yenilenmez
    _turSonrasiDonemler.add(days);
    if (_turSonrasiYenileme != null) return;
    final yenileme = tur.then<void>((_) => _turSonrasiUclariYenile());
    _turSonrasiYenileme = yenileme;
    CrashReporter.arkaPlan(yenileme, reason: 'AssetDetail.turSonrasiUc');
  }

  /// Fiyat turu bitti: turu beklemeden çizilen dönem serileri yeni
  /// `currentPrice` (uç) ve yeni ölçek hizasıyla yeniden kurulur. Tarihî
  /// noktalar `HistoryService` önbelleğinden gelir, ağa çıkılmaz.
  ///
  /// TEK `setState`: seçili dönem ve çipler birlikte yazılır. Seçili
  /// dönemin grafiği yalnız bu arada yeni bir yükleme başlamadıysa
  /// (`_yuklemeSirasi`) değişir; çip önbelleği sıradan bağımsız (bkz.
  /// `_loadHistory`). Başarısız ya da boş kurulum eldekini EZMEZ.
  Future<void> _turSonrasiUclariYenile() async {
    final donemler = _turSonrasiDonemler.toList();
    _turSonrasiDonemler.clear();
    _turSonrasiYenileme = null;
    if (!mounted || donemler.isEmpty) return;
    final sira = _yuklemeSirasi;
    final birim = FiyatKaynagi.birimVarlik(_canli.asset);
    final sonuclar = await Future.wait([
      for (final d in donemler)
        _donemSerisi([birim], d).then<(int, PortfolioHistoryBreakdown)?>(
            (b) => (d, b), onError: (Object e, StackTrace st) {
          CrashReporter.report(e, st, reason: 'AssetDetail.turSonrasiUc');
          return null;
        }),
    ]);
    if (!mounted) return;
    final gecerli = [
      for (final s in sonuclar)
        if (s != null && s.$2.total.length >= 2) s,
    ];
    if (gecerli.isEmpty) return;
    AssetDetailScreen.debugTurSonrasiYenilemeler
        .add([for (final (d, _) in gecerli) d]);
    _guncelle(() {
      for (final (d, b) in gecerli) {
        _donemKaydet(d, b.total, b.seansGunu,
            veriYok: b.gunIciVerisiYokTurler.isNotEmpty);
        if (sira == _yuklemeSirasi &&
            _periods[_selectedPeriodIdx].days == d) {
          // `_eskiSeri` (bayat etiketi) dokunulmaz: yenileme aynı
          // önbellekten kurulur, verinin tazeliği değişmedi.
          _lastHistory = b.total;
          _historyFuture = SynchronousFuture(b.total);
        }
      }
    });
  }

  /// Seçili dışındaki dönemleri paralel yükler — çip getirileri için.
  ///
  /// `_loadHistory` ile aynı kural: gün içi çip süren fiyat turunu `_canli`
  /// OKUNMADAN önce bekler; öteki dönemler beklemez, tur bitince uçları
  /// yenilenir. Dönen Future (açılış kapısı bunu bekler) tur sürerken
  /// gün içi çipi BEKLEMEZ: kapı turun süresi kadar kapalı kalmasın;
  /// GÜNLÜK çipinin getirisi tur bitince kendi yerinde dolar (kapı
  /// açıldıktan sonra `_guncelle` dalı).
  Future<void> _digerDonemleriYukle() async {
    final notifier = ref.read(portfolioProvider.notifier);
    final turSuruyor = notifier.fiyatTuruSuruyor;
    final tur =
        notifier.fiyatTurunuBekle(enFazla: TazelikRitmi.gunIciSeriOmru);
    if (!turSuruyor || _olcekTuruBekler) {
      await tur;
      if (!mounted) return;
      await _donemleriYukle(gunIci: true, gunlukler: true);
      return;
    }
    // Gün içi çip turdan sonra, arka planda.
    CrashReporter.arkaPlan(
      tur.then<void>((_) {
        if (mounted) return _donemleriYukle(gunIci: true, gunlukler: false);
      }),
      reason: 'AssetDetail.digerDonemler',
    );
    var turBitti = false;
    CrashReporter.arkaPlan(tur.then<void>((_) => turBitti = true),
        reason: 'varlik_seri_tur_paralel');
    await _donemleriYukle(
        gunIci: false, gunlukler: true, turBittiMi: () => turBitti, tur: tur);
  }

  /// [_digerDonemleriYukle]'nin gövdesi: seçili dışındaki dönemlerden
  /// [gunIci] (days == 0) ve/veya [gunlukler] (öteki dönemler) yüklenir.
  /// [tur] verilmişse dönemler süren turun ortasında kuruluyor demektir:
  /// tur o arada bittiyse ([turBittiMi]) seri bir kez daha (önbellekten)
  /// kurulur, bitmediyse dönem tur sonrası yenilemeye yazılır.
  Future<void> _donemleriYukle({
    required bool gunIci,
    required bool gunlukler,
    bool Function()? turBittiMi,
    Future<void>? tur,
  }) async {
    final secili = _periods[_selectedPeriodIdx].days;
    await Future.wait([
      for (final p in _periods)
        if (p.days != secili &&
            !_donemSerileri.containsKey(p.days) &&
            (p.days == 0 ? gunIci : gunlukler))
          _donemSerisi([FiyatKaynagi.birimVarlik(_canli.asset)], p.days)
              .then((b) async {
            if (!mounted) return;
            if (tur != null) {
              if (turBittiMi?.call() ?? false) {
                b = await _donemSerisi(
                    [FiyatKaynagi.birimVarlik(_canli.asset)], p.days);
                if (!mounted) return;
              } else {
                _turSonrasiUcuYenile(p.days, tur);
              }
            }
            // Açılış kapısı henüz açılmadıysa yalnız kaydet: kapının tek
            // `setState`'i hepsini birlikte çizer. Eskiden altı dönemin her
            // biri ayrı tam ekran yeniden kurulum yapıyordu — sayfa kayarak
            // girerken (animasyon denetimi 2026-10-01).
            if (!_acildi) {
              _donemKaydet(p.days, b.total, b.seansGunu,
                  veriYok: b.gunIciVerisiYokTurler.isNotEmpty);
              return;
            }
            _guncelle(() => _donemKaydet(p.days, b.total, b.seansGunu,
                veriYok: b.gunIciVerisiYokTurler.isNotEmpty));
          }, onError: (Object e, StackTrace st) {
            // Çip boş kalır; dönem seçilince `_loadHistory` yeniden dener.
            CrashReporter.report(e, st, reason: 'AssetDetail.digerDonemler');
          }),
    ]);
  }

  /// Mevduatın grafik serisi: birim seriden TOPLAM TL tutarı (gerekçe
  /// `MevduatHesabi.tutarSerisi`). Defter `_seriDefteri` — dönem değişimi
  /// tutarıyla aynı ham lot listesi. Girdi aynıysa önbellekten.
  Map<int, double> _mevduatTutarSerisi(Map<int, double> birim) {
    final defter = _seriDefteri;
    final o = _mevduatTutarOnbellek;
    if (o != null &&
        identical(o.birim, birim) &&
        listEquals(o.defter, defter)) {
      return o.tutar;
    }
    final tutar = MevduatHesabi.tutarSerisi(birimSeri: birim, lotlar: defter);
    _mevduatTutarOnbellek = (birim: birim, defter: defter, tutar: tutar);
    return tutar;
  }

  /// Dönemin yüzdesi: dönem başı (`uclar`) → canlı birim fiyat.
  double? _donemYuzdesi(int days, double canliBirim) {
    // Mevduat: seriden değil sözleşmeden (bkz. `mevduatDegisimi`).
    if (widget.asset.type == AssetType.mevduat) {
      final now = DateTime.now();
      final m = SozlesmeDeposu.instance.mevduatDegisimi(
          widget.asset.ticker,
          days == 0
              ? dayKey(now)
              : _AssetDetailScreenState._donemBaslangici(days, now),
          now);
      if (m != null) return m;
    }
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
    if (seri == null || (days == 0 && _gunIciVeriGelmedi)) return null;
    final u = PeriodSummaryService.uclar(seri,
        fromMs: start.millisecondsSinceEpoch, toMs: end.millisecondsSinceEpoch);
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
  ///
  /// Ondalık [fiyatOndaligi]'ndan: 1 ₺ altındaki fiyat 2 haneyle
  /// okunmuyordu (BES fonu KED ₺0,179147 → "₺0,18", haftalık değişim
  /// "+₺0,00"; 2026-10-04 kullanıcı bildirimi). 1 ₺ ve üstü yine 2 hane.
  ///
  /// `goz_alici` açıkken kaynak hassasiyeti ([fiyatBicimi]): fon ₺1,234567.
  ///
  /// Hane sayısı [birimFiyat]'ın EKRANDAKİ yazılışından gelir ve bu
  /// biçimle yazılan her sayı aynı haneyi kullanır
  /// ([ayniOndalikFiyatBicimi], Ar-Ge 2026-11-07 14:00 #2): başlık ₺312,40
  /// yazarken aralık uçları ₺263,9333, önceki kapanış ₺303,1833, lot başı
  /// değişim ₺9,2167 yazıyordu. Çağıranlar büyük fiyatı ([_PnlOzeti.
  /// currentUnitTRY]) referans verir; kendi kendini biçimleyen sayıda
  /// (ortalama maliyet) çıktı eskisiyle aynıdır.
  NumberFormat _birimBicimi(double birimFiyat) =>
      ayniOndalikFiyatBicimi(birimFiyat,
          azami: widget.asset.type.fiyatHassasiyeti);

  // ── Başlık ───────────────────────────────────────────────────────────────

  /// Başlık — ortak [VarlikBasligi] (varlık sayfasıyla aynı parça,
  /// Sadeleştirme 2 madde 6). Sembolü olmayan varlıkta alt satır adı
  /// tekrarlamaz (`adTekrariniAtla`).
  Widget _baslik() => VarlikBasligi(
        kimlik: _kimlik,
        adTekrariniAtla: true,
        heroEtiketi: widget.heroEtiketi,
        semantikEtiket:
            context.l10n.assetPerformanceSemantics(widget.asset.name),
      );

  /// Büyük fiyatın gövdede yazdığı dizge — [_fiyatBlogu] ile üst çubuk
  /// başlığı ([_cubukBasligi]) AYNI dizgeyi yazsın diye tek yer: aynı canlı
  /// birim fiyat (`pnl.currentUnitTRY`, `_canli.asset`'ten), aynı biçim
  /// (`_birimBicimi`). Mevduatta kişisel bakiye (`baz.fmt`, "Bakiyeyi gizle"
  /// açıkken maskeli). Fiyat yoksa `null` — uydurma sayı yazılmaz.
  String? _buyukFiyatMetni(_PnlOzeti pnl, BazPara baz) {
    if (widget.asset.type == AssetType.mevduat) {
      return baz.fmt(pnl.currentValueTRY);
    }
    final canli = pnl.currentUnitTRY;
    return canli > 0 ? _birimBicimi(canli).format(canli) : null;
  }

  /// Üst çubuk başlığı: "THYAO · ₺312,40" (Ar-Ge 11 Kas 19:04 #1).
  ///
  /// Yalnız gövdedeki başlık bloğu çubuğun altına girince görünür
  /// (`_baslikCubukta`); görünürken başlık iki kez yazılmaz. Metin ekranın
  /// kendi kurulumunda bir kez hazırlanır ve `child` olarak geçer:
  /// kaydırmada yalnız saydamlık yeniden kurulur. Soluklaşma `state`
  /// süresi (durum değişimi), hareketi azalt açıkken anında. Gizliyken
  /// semantikten çıkar — VoiceOver varlık adını tek kez okur; görünürken
  /// başlık (header) olarak okunur.
  Widget _cubukBasligi(_PnlOzeti pnl, BazPara baz) {
    final fiyat = _buyukFiyatMetni(pnl, baz);
    final metin = Text(
      fiyat == null ? _kimlik.kisaEtiket : '${_kimlik.kisaEtiket} · $fiyat',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.t.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: context.c.text90,
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: _baslikCubukta,
      child: metin,
      builder: (context, gorunur, child) => ExcludeSemantics(
        excluding: !gorunur,
        child: Semantics(
          header: true,
          child: AnimatedOpacity(
            key: const ValueKey('varlikCubukBasligi'),
            opacity: gorunur ? 1 : 0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Gövde başlığının alt kenarı kaydırma alanının üst kenarını geçti mi —
  /// geçtiyse başlık üst çubuğun altındadır. Eşik ÇİZİLMİŞ başlık bloğundan
  /// ölçülür (sabit piksel değil): Dynamic Type, uzun ad, iPad sütunu
  /// bloğun boyunu değiştirir. Aşağı çekip yenilemede (negatif kaydırma)
  /// başlık görünür, çubuk boş kalır.
  void _baslikEsiginiDenetle() {
    if (!mounted) return;
    final baslik = _baslikAnahtari.currentContext?.findRenderObject();
    final alan = _kaydirmaAnahtari.currentContext?.findRenderObject();
    if (baslik is! RenderBox ||
        alan is! RenderBox ||
        !baslik.attached ||
        !baslik.hasSize ||
        !alan.attached) {
      return;
    }
    final alt = baslik
        .localToGlobal(Offset(0, baslik.size.height), ancestor: alan)
        .dy;
    _baslikCubukta.value = alt <= 0;
  }

  /// Başlık ve büyük fiyat uzun basınca kodu/fiyatı kopyalar
  /// ([KopyalaUzunBasma], 2026-11-10). Fiyat [_fiyatBlogu]'nun yazdığı
  /// dizgenin aynısı (aynı `_birimBicimi(canli)`). Mevduatta yok: kod
  /// sözleşme adıdır, büyük sayı birim fiyat değil kişisel bakiye.
  Widget _kopyalanir(_PnlOzeti pnl, Widget child) {
    if (widget.asset.type == AssetType.mevduat) return child;
    final canli = pnl.currentUnitTRY;
    return KopyalaUzunBasma(
      kod: _kimlik.kisaEtiket,
      fiyat: canli > 0 ? _birimBicimi(canli).format(canli) : null,
      child: child,
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
    final kapsam = _donemKapsami(days);
    final etiket = kapsam != null
        ? donemKapsamEtiketi(context, kapsam)
        : donemEtiketi(l, _periods[_selectedPeriodIdx].label);
    final canli = pnl.currentUnitTRY;
    final pct = _donemYuzdesi(days, canli);
    final ilk = _donemIlk[days];
    final bicim = _birimBicimi(canli);
    // Mevduatta büyük sayı birim değer değil (₺1,37 — iç hesabın payı,
    // 2026-10-01 emülatör testi) pozisyonun bugünkü değeridir; değişim
    // satırı da yalnız yüzdeyi yazar.
    final mevduat = widget.asset.type == AssetType.mevduat;

    // Biçim ve düz-değişim kuralı varlık sayfasıyla ORTAK
    // (`donemDegisimSatiri`); sayılar burada, birim seriden.
    final degisim = donemDegisimSatiri(
      context,
      pct: ilk == null && !mevduat ? null : pct,
      donem: etiket,
      fark: mevduat || ilk == null ? null : canli - ilk,
      bicim: bicim,
      veriGelmedi: days == 0 && _gunIciVeriGelmedi && !mevduat,
      // Tutar lot/pay başınadır; altındaki Pozisyonun tablosu toplamı yazar.
      birim: widget.asset.type == AssetType.hisse ||
              widget.asset.type == AssetType.fon
          ? widget.asset.unitLabel
          : null,
    );

    final pnlDuz =
        pnl.totalPnlTRY.abs().round() == 0 && pnl.pnlPct.abs() < 0.005;
    final pnlRenk = pnlDuz
        ? context.c.text36
        : (pnl.gainPositive ? context.c.gain : context.c.loss);
    final isaret = pnlDuz ? '' : (pnl.gainPositive ? '+' : '−');

    final blok = VarlikFiyatBlogu(
      etiket: mevduat ? l.currentValueUpper : l.currentPriceUpper,
      kimlik: widget.asset.id,
      // Kripto fiyatı gecikmeli olabilir — etiket fiyatın yanında,
      // okunduğu yerde (eskiden grafiğin altındaydı).
      // Fonda fiyatın GÜNÜ (bugünün değilse "· Fiyat 30 Eki"; müşteri
      // raporu 30 Eki #2). Elle fiyatta TEFAS günü anlamsız, yazılmaz.
      etiketYani: widget.asset.type == AssetType.kripto
          ? KriptoGecikmeEtiketi(sembol: widget.asset.ticker)
          : fonFiyatliMi(widget.asset.type) && !widget.asset.isManualPrice
              // Tutarla bugün alınan fonda yanında "· Fiyat yarın
              // kesinleşir" (Ar-Ge 7 Kas 14:30 #1); büyük yazıda sarar.
              ? Wrap(
                  spacing: SandikSpace.xs,
                  children: [
                    FonFiyatGunuEtiketi(tarih: fonFiyatGunu(widget.asset.ticker)),
                    BekleyenFonAlimiEtiketi(lotIdleri: _fonLotIdleri),
                  ],
                )
              : null,
      // Üst çubuk başlığıyla aynı dizge (`_buyukFiyatMetni`).
      fiyat: _buyukFiyatMetni(pnl, baz) ?? '—',
      fiyatRengi: context.c.gold,
      degisim: degisim,
      // Grafikte gezinirken fiyat ve tarih imleçten (bayrak `goz_alici`).
      // Mevduatta başlık pozisyon değeri; grafik de toplam tutarı çizdiği
      // için (2026-10-26, `MevduatHesabi.tutarSerisi`) imleç aynı ölçekte.
      imlec: RemoteConfigService.instance.gozAlici ? _imlec : null,
      // Maliyet kesişim günü sözü (2026-11-11), aynı bayrakla.
      imlecNotu: RemoteConfigService.instance.gozAlici ? _imlecNotu : null,
      // B'den alınan satır: en önemli sayı ("param ne durumda") ilk bakışta.
      // Ayrıntısı aşağıdaki pozisyon bölümünde, aynı sayılarla — ve AYNI
      // biçimle (UX raporu 30 Eki §5, yasin "yap"): başlık "+₺36,0K",
      // kart "+₺36.022" yazıyordu; tam tutar, kısaltma yok (hareketlerdeki
      // portföy önce → sonra kararıyla aynı). Sığmazsa üç nokta.
      altSatir: Text(
        l.adPositionLine(
          '$isaret${baz.fmt(pnl.totalPnlTRY.abs())}',
          pnlDuz ? fmtPct(0) : fmtPctIsaretli(pnl.pnlPct),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.numSmall
            .copyWith(color: pnlRenk, fontWeight: FontWeight.w600),
      ),
    );
    // Altın/döviz: "Bozdurursan · Alırsan · fark" (2026-10-25; gerekçe
    // [BozdurAlSatiri]). Büyük fiyat ve pozisyon değeri alışta kalır; satır
    // kapı reddederse hiç çizilmez. Pozisyon satırının ALTINDA: o satır
    // "param ne durumda"yı söyler, bu satır ek bilgidir.
    if (mevduat) return blok;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        blok,
        if (_eldeTutma(pnl) case final e?) EldeTutmaSatiri(ozet: e),
        // Para piyasası fonunda günlük ortalama kazanç (ücretsiz); bakiye
        // gizliyken ve sayı yokken satır kendi içinde susar.
        if (widget.asset.type == AssetType.fon)
          GunlukGetiriSatiri(tutarTRY: _gunlukGetiri(pnl), baz: baz),
        // Alım gününün fiyatı geldiyse tek dokunuşluk adet önerisi; yoksa
        // yer kaplamaz (Ar-Ge 7 Kas 14:30 #1).
        if (widget.asset.type == AssetType.fon)
          FonAlimOneriSatiri(lotIdleri: _fonLotIdleri),
        BozdurAlSatiri(
          ticker: widget.asset.ticker,
          paraBirimi: widget.asset.currency,
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
    // YB yok: `_donemler` ile aynı küme (gerekçe enum'daki "YB" notu).
    final donemler = [
      for (final p in SummaryPeriod.sembolDonemleri)
        if (!p.intraday || _gunIciDestekli) p,
    ];
    return DonemSecici(
      donemler: donemler,
      secili: _selectedPeriodIdx,
      getiriler: [
        for (final p in _periods) _donemYuzdesi(p.days, canliBirim),
      ],
      eksik: [for (final p in _periods) _donemKapsami(p.days) != null],
      onSec: _ortakDonemSec,
    );
  }

  // ── Yıllık aralık ────────────────────────────────────────────────────────

  /// 52 haftalık aralık (Ar-Ge 2026-11-07 12:30 #1, ücretsiz — fon risk
  /// satırı gibi eşitleyici, mevcut veri). 14:00 #1'de dönem çiplerinin
  /// altından "Aralık" kartına indi ([AralikKarti], [_istatistikler]).
  /// Mevduatta yok: birim değer yalnız artar, "yılın dibi" bir şey
  /// söylemez (dönem aralığıyla aynı kural). Seri yoksa `null` → satır yok.
  YillikAralik? _yillikAralik(double canliBirim) =>
      widget.asset.type == AssetType.mevduat
          ? null
          : _yillikUclar?.bugunle(canliBirim);

  /// Alarm sayfasının "52 hafta zirvesi / dibi" çipleri (Ar-Ge 2026-11-11,
  /// ücretsiz): kartın 52 hafta satırıyla AYNI uçlar, yeni istek yok — 1Y
  /// serisi henüz gelmediyse `null`, çip çıkmaz.
  ///
  /// Yalnız tam yılda (`ay == null`): "12 ay" satırının uçları "52 hafta"
  /// diye satılmaz. Yalnız TL varlıkta: seri TL birim fiyattır, alarm ise
  /// varlığın kendi para biriminde kurulur ([AlarmAdayi.guncelFiyat] =
  /// `currentPrice`); ABD hissesinde geçmiş TL zirvesini bugünkü kurla
  /// dolara çevirmek o günün dolar zirvesi DEĞİLDİR (uydurma sayı). Canlı
  /// fiyat da alarmın gördüğü fiyat: uçlar onu kapsar ([YillikUclar.bugunle]).
  ({double zirve, double dip})? get _alarmYil52 {
    if (widget.asset.type == AssetType.mevduat) return null;
    if (_canli.asset.currency != 'TRY') return null;
    final a = _yillikUclar?.bugunle(_canli.asset.currentPrice);
    if (a == null || a.ay != null) return null;
    return (zirve: a.yuksek, dip: a.dusuk);
  }

  /// "Aralık" kartı — dönem satırı [donem], 52 hafta satırı seriden.
  /// Biçim büyük fiyatla AYNI (`_birimBicimi`, canlı birim fiyat): ekrandaki
  /// fiyatla aynı ölçek ve aynı ondalık.
  List<Widget> _aralikKarti(double canliBirim,
      {DonemAraligi? donem, bool ustBosluk = true, double? referans}) {
    final yillik = _yillikAralik(canliBirim);
    if (!AralikKarti.cizilir(donem: donem, yillik: yillik)) return const [];
    final days = _periods[_selectedPeriodIdx].days;
    return [
      if (ustBosluk) const SizedBox(height: SandikSpace.sm),
      AralikKarti(
        donem: donem,
        yillik: yillik,
        gunIci: days == 0,
        donemAdi:
            donemEtiketi(context.l10n, _periods[_selectedPeriodIdx].label),
        bicim: _birimBicimi(
            referans ?? (canliBirim > 0 ? canliBirim : (yillik?.bugun ?? 0))),
      ),
    ];
  }

  // ── İstatistikler ────────────────────────────────────────────────────────

  /// İstatistik ızgarası + dönem aralığı. Seçili dönemin serisi gelmeden sayı
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
    // Veri gelmedi (GÜNLÜK seri tohum): beklenecek bir ölçüm yok, iskelet
    // sonsuza dek dönerdi. Bölüm çizilmez; başlık durumu cümleyle söyler.
    // 52 haftalık satır seriden bağımsız durur (kart yalnız onunla çizilir).
    if (days == 0 && _gunIciVeriGelmedi) {
      return _aralikKarti(canliBirim, ustBosluk: false);
    }
    // Dönem yüzdesi yalnız fiyatın altında (madde 7, 2026-10-04; bayrak
    // `varlik_islem_cubugu` 2026-10-05'te kalktı); ızgara onu (GÜNLÜK'te
    // "Bugün"ü de) yazmaz — bkz. `DonemIstatistikIzgarasi.donemGetirisiGizli`.
    if (ist == null || pct == null) {
      // İskelet gerçek ızgarayla aynı boyda kalsın (yerleşim oynamasın).
      // Hücre sayısı ızgaranın kuralından gelir (Ar-Ge 1 Kas 08:45 #3):
      // oynaklık kısa dönemde hiç hesaplanmaz, hücresi de çizilmez.
      final hucre = DonemIstatistikIzgarasi.hucreSayisi(
        donemGetirisiGizli: true,
        bugunGizli: days == 0,
        oynaklikVar: days >= DonemIstatistigi.oynaklikIcinAsgariDonemGun,
        // Değer bilinmeden yalnız günlük kuralı uygulanır; ~%0 düşüş
        // gelirse hücre düşer (nadir, küçük zıplama kabul).
        dususVar: days != 0,
      );
      // Dönem satırı seri gelince eklenir; 52 hafta beklemez.
      return [_istatistikIskeleti(hucre), ..._aralikKarti(canliBirim)];
    }
    // Aralık canlı fiyatı da kapsar: seri haftalıkken bugünkü fiyat son
    // kapanışın dışına taşabilir; imleç yine çubuğun içinde doğru yerde.
    final canli = canliBirim > 0 ? canliBirim : ist.son;
    final dusuk = math.min(ist.dusuk, canli);
    final yuksek = math.max(ist.yuksek, canli);
    final aralik = yuksek - dusuk;
    // GÜNLÜK'te ızgara boş kalabilir (Bugün = fiyat altı, düşüş ve oynaklık
    // yok); o zaman çubuğun üstünde boşluk da kalmaz.
    final izgaraDolu = DonemIstatistikIzgarasi.hucreSayisi(
          donemGetirisiGizli: true,
          bugunGizli: days == 0,
          oynaklikVar: ist.oynaklikPct != null,
          dususVar: DonemIstatistikIzgarasi.dususVar(ist, gunIci: days == 0),
        ) >
        0;
    // Dip = zirve (elle fiyatlanan varlık, dönem boyunca kıpırdamamış
    // seri): satır "₺X — ₺X, %50 noktasında" der, yani hiçbir şey. Bilgi
    // ızgarada zaten var (getiri %0, düşüş %0); boş çubuk gürültüdür.
    // Mevduatta "dönem düşüğü/yükseği" birim değerdir (₺1,37 / ₺1,41) —
    // kullanıcıya bir şey söylemez; değer zaten yalnız artar.
    final DonemAraligi? donem =
        aralik > 1e-9 * yuksek.abs() && widget.asset.type != AssetType.mevduat
            ? (
                dusuk: dusuk,
                yuksek: yuksek,
                konum: (canli - dusuk) / aralik,
                bugun: canli,
              )
            : null;
    return [
      DonemIstatistikIzgarasi(
        ist: ist,
        gun: days,
        donemPct: pct,
        bugunPct: _gunIciDestekli ? _donemYuzdesi(0, canliBirim) : null,
        donemGetirisiGizli: true,
        gunIci: days == 0,
      ),
      ..._aralikKarti(canliBirim,
          donem: donem, ustBosluk: izgaraDolu, referans: canli),
    ];
  }

  /// Fon karnesi (F4) — istatistiklerin hemen altında. Bayrak kapalıysa,
  /// varlık fon değilse ya da karne kurulamıyorsa kart hiç yer kaplamaz
  /// (boşluk `dis` ile kartın içinde; çizilmezse o da yok). Hub'a yalnızca
  /// çağrı satırı girer — gövde bu part'ta (CLAUDE.md: yeni kod part'a).
  Widget _fonKarnesi({EdgeInsetsGeometry dis = _kartBoslugu}) =>
      FonKarnesiKarti(
          tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

  /// Fon X-Ray (Premium, 2026-10-10) — fon karnesinin hemen altında: karne
  /// "kategorisinde nerede", bu kart "parası nerede duruyor". Premium
  /// özellikleri görünmüyorsa (paywall kapalı, admin değil) hiç yer
  /// kaplamaz; çizilme koşulları kartta (`FonDagilimiKarti`).
  Widget _fonDagilimi({EdgeInsetsGeometry dis = _kartBoslugu}) =>
      FonDagilimiKarti(
          tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

  /// Para akışı (Balina B1) — fon karnesinin hemen altında: karne "getirisi
  /// nasıl", bu kart "parası nereye gidiyor" sorusunu yanıtlar. Çizilmeme
  /// koşulları ve boşluk kuralı karneyle aynı (bkz. `ParaAkisiKarti`).
  Widget _paraAkisi({EdgeInsetsGeometry dis = _kartBoslugu}) => ParaAkisiKarti(
      tur: widget.asset.type,
      ticker: widget.asset.ticker,
      // Bağlantı yalnız kendi varlığında: "fonlarım" ortağın fonunu
      // kapsamaz.
      haftaBaglantisi: widget.asset.userId ==
          ref.read(portfolioProvider).valueOrNull?.ownerId,
      dis: dis);

  /// Hacim radarı (Balina B2) — yalnız BIST hissesinde çizilir (koşul
  /// widget'ta); fon kartıyla aynı bayrak, aynı boşluk kuralı.
  Widget _hacimRadari({EdgeInsetsGeometry dis = _kartBoslugu}) =>
      HacimRadariKarti(
          tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

  /// Alıcı baskısı (Balina B3) — yalnız kripto varlıkta çizilir.
  Widget _kriptoBaski({EdgeInsetsGeometry dis = _kartBoslugu}) =>
      KriptoBaskiKarti(
          tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

  /// Haftalık yapay zekâ notu (Balina F2, S15-B) — radar kartlarının hemen
  /// altında: kartlar sayıyı, not o sayıların hikâyesini verir. Yayında not
  /// yoksa hiç yer kaplamaz.
  Widget _analizNotu({EdgeInsetsGeometry dis = _kartBoslugu}) =>
      AnalizNotuKutusu(
          tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

  /// Seçili dönemin AI yorumu (0151, 2026-10-14; yasin: "varlık detayında
  /// … seçili dönem için data detaylı yorum"). Yalnız KENDİ varlığında:
  /// ortağın pozisyonu başkasının verisidir, modele gönderilmez. Görünürlük
  /// (Premium görünürlüğü, bayraksız) Performans kartıyla aynı.
  ///
  /// Paketin sayıları ekranın gösterdikleri: dönem istatistiği (2×2 ızgara),
  /// fiyatın altındaki dönem yüzdesi, pozisyon kartının kâr/zararı. Paket
  /// yalnız düğmeye basınca kurulur (`VarlikYorumuKarti.paketKur`).
  Widget _aiYorumu({
    required bool isOwnAsset,
    required PortfolioState? pState,
    EdgeInsetsGeometry dis = _kartBoslugu,
  }) {
    if (!isOwnAsset || !PortfoyYorumuKarti.gorunur) {
      return const SizedBox.shrink();
    }
    final idx = _selectedPeriodIdx.clamp(0, _donemler.length - 1);
    final period = _donemler[idx];
    final days = _periods[idx].days;
    final ist = _donemIstatistikleri[days];
    final canli = _canli;
    final pnl = _pnlOzeti(pState);
    final donemPct = _donemYuzdesi(days, pnl.currentUnitTRY);
    final anahtar = positionKey(widget.asset);

    double? pay;
    if (pState != null) {
      final toplam = DailySummary.kapsamToplami(pState, pState.assets);
      if (toplam > 0) pay = pnl.currentValueTRY / toplam * 100;
    }
    DateTime? ilkAlim;
    for (final l in canli.lots) {
      if (ilkAlim == null || l.addedDate.isBefore(ilkAlim)) {
        ilkAlim = l.addedDate;
      }
    }

    return Padding(
      padding: dis,
      child: VarlikYorumuKarti(
        period: period,
        positionKey: anahtar,
        miktar: canli.asset.quantity,
        varlikAdi: widget.asset.name,
        veriHazir: ist != null && donemPct != null,
        seviyeler: ist?.destekDirenc,
        fiyatYaz: (v) => _birimBicimi(v).format(v),
        paketKur: () => PortfoyYorumuService.instance.varlikPaketHazirla(
          period: period,
          positionKey: anahtar,
          miktar: canli.asset.quantity,
          varlikAdi: widget.asset.name,
          pozisyonLotlari: canli.lots,
          ist: ist,
          donemPct: donemPct,
          canliBirim: pnl.currentUnitTRY,
          portfoyPayi: pay,
          pozisyonGetirisi: pnl.totalCostTRY > 0 ? pnl.pnlPct : null,
          eldeGun: ilkAlim == null
              ? null
              : DateTime.now().difference(ilkAlim).inDays,
        ),
      ),
    );
  }

  /// "KAP bildirimleri ↗" (karar 7.2, 2026-09-30). Yalnız BIST hissesinde
  /// çizilir (koşul widget'ta); ortağın hissesinde de — KAP sayfası kişiye
  /// değil şirkete ait.
  /// Mevduat / BES sözleşme kartı (2026-09-30): dönem, vade, yenileme;
  /// BES'te birikim dökümü, hak ediş ve aylık katkı. Yalnız KENDİ
  /// varlığında — eylemler sözleşmeye yazar, ortak yalnız okur (RLS).
  Widget _sozlesmeKarti({EdgeInsets dis = _kartBoslugu}) =>
      SozlesmeKarti(varlik: _canli.asset, dis: dis);

  Widget _kapBaglantisi({EdgeInsets dis = _kartBoslugu}) => KapBaglantisi(
      tur: widget.asset.type, ticker: widget.asset.ticker, dis: dis);

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

  // ── Eurobond ─────────────────────────────────────────────────────────────

  /// "Tahvil bilgileri" kartı — pozisyon kartının hemen altında: kullanıcı
  /// "ne kadar kazandım"dan sonra "bu tahvil ne veriyor, ne zaman, bankaya
  /// satsam kaç eder" diye sorar. Yalnız eurobond lotunda; tür bayrak
  /// (`eurobond`) kapalıyken eklenemediğinden bayrakla eski ekran birebir.
  /// Ortağın varlığında da çizilir — sözleşme kişiye değil tahvile ait.
  /// Nominal `_canli`'den: açık pozisyonun miktarı.
  Widget _eurobondKarti() {
    if (widget.asset.type != AssetType.eurobond) return const SizedBox.shrink();
    return EurobondBilgiKarti(
      ticker: widget.asset.ticker,
      nominal: _canli.asset.quantity,
    );
  }

  // ── Masraflar ────────────────────────────────────────────────────────────

  /// "Masraflar" kartı (bayrak `varlik_masraflari`, 2026-10-08). Yalnız
  /// KENDİ varlığında — komisyon kaydı sahibin defterinden. Hesap servis
  /// tarafında (`varlikMasraflari`); burada yalnız girdiler toplanır.
  ///
  /// Lot'lar `_canli` pozisyonundan: açık pozisyonun alım, satım ve temettü
  /// satırları — komisyon onların hepsinde ödenmiş olabilir. Kur, durumda
  /// henüz ölçülmemişse (`usdTry` varsayılanı 1,0) `null` geçer: ABD
  /// tahmini kalemleri bilinmeyen kurla tutar üretmez, bilgiye iner.
  Widget _masrafKarti(PortfolioState pState) {
    final canli = _canli;
    return MasrafKarti(
      ozet: varlikMasraflari(
        varlik: canli.asset,
        lotlar: canli.lots,
        usdTry: pState.usdTry > 1.0 ? pState.usdTry : null,
        temettuStopajOrani: RemoteConfigService.instance.temettuStopajOrani,
      ),
      kilitli: ref.watch(premiumKilitliProvider),
    );
  }

  /// [DonemIstatistikIzgarasi]'nın yer tutucusu — aynı kart
  /// kabuğu, aynı boy (`VarlikIskeleti`'nin kart deseni). [hucre] ızgaranın
  /// çizeceği hücre sayısı: ikişerli satır, tek kalan satırı doldurur.
  Widget _istatistikIskeleti(int hucre) {
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
          for (var i = 0; i < hucre; i += 2) ...[
            if (i > 0) const SizedBox(height: SandikSpace.sm),
            Row(children: [
              kart(),
              if (i + 1 < hucre) ...[
                const SizedBox(width: SandikSpace.sm),
                kart(),
              ],
            ]),
          ],
        ],
      ),
    );
  }
}
