part of '../asset_detail_screen.dart';

/// Katmanlı varlık detayı (Sadeleştirme 2, S4; bayrak `varlik_detay_katmanli`,
/// varsayılan KAPALI). `asset_detail_screen.dart`'ın part'ı.
///
/// ## Neden katman
/// Grafiğin altı düz bir yığındı: pozisyonun yedi satırı, istatistikler,
/// sonra varlığa göre altı-yedi analiz kartı, sözleşme, temettü, KAP. Her
/// kart kendi başlığıyla tam boy çiziliyordu; "param ne durumda" sorusunun
/// cevabı ile "hacim radarı ne diyor" aynı ağırlıkta duruyordu. Robinhood
/// düzeni: üstte fiyat + grafik (değişmedi), sonra pozisyonun ÖZETİ (üç
/// sayı, ayrıntısı bir dokunuşta), sonra analiz başlıkları kapalı satır
/// olarak, en altta geçmiş ve belgeler. Hiçbir kart kaldırılmadı —
/// yalnızca katlandı ya da yer değiştirdi (kullanıcı şartı: veri kaybı yok).
///
/// Varlık sayfası (`varlik_sayfasi.dart`) bu düzene GEÇMEZ: kullanıcı kararı
/// 2026-10-08, iki varlık yüzeyi ayrı kalır.
///
/// Bayrak kapalıyken bu dosyadaki hiçbir şey çağrılmaz; eski yığın
/// `build()` içinde birebir duruyor.
extension _DetayKatmanlar on _AssetDetailScreenState {
  /// Grafiğin altındaki katmanlar: Pozisyonun → istatistik → Analiz →
  /// Geçmiş ve belgeler → yasal ibare.
  ///
  /// [ayrinti] eski pozisyon kartının satırları (`kabuksuz`); çağıran kurar
  /// çünkü dönem etiketi ve dönem değişimi `build()`'in yerelleridir.
  List<Widget> _katmanliGovde({
    required BazPara baz,
    required _PnlOzeti pnl,
    required Widget ayrinti,
    required bool isOwnAsset,
    required PortfolioState? pState,
  }) {
    final l = context.l10n;
    final analiz = _analizKatmanlari();
    // İleri seviyede analiz satırları AÇIK başlar: o kullanıcı göstergeleri
    // okumak için gelir, her girişte altı dokunuş istemek ceza olur.
    // Seviye ekran açıkken değişirse açık/kapalı hâl korunur (satırın kendi
    // durumu) — kullanıcının elle açtığı satır kapanmasın.
    final ileri =
        ref.watch(yatirimciSeviyesiProvider) == YatirimciSeviyesi.ileri;
    final birimGizli = widget.asset.type == AssetType.mevduat;

    return [
      // ── 2. Pozisyonun ──
      SandikSectionHeader(title: l.adPositionUpper),
      const SizedBox(height: SandikSpace.sm),
      _KatmanliPozisyonKarti(
        baz: baz,
        pnl: pnl,
        // Mevduatta miktar "250.000 birim" kullanıcıya bir şey söylemez
        // (`_PozisyonKarti.birimGizli` ile aynı karar) — iki sayı kalır.
        miktarMetni: birimGizli
            ? null
            : widget.asset.miktarMetni(
                _canli.asset.quantity, (v, d) => fmtNum(v, digits: d)),
        ayrinti: ayrinti,
      ),
      // Eski yığındaki yeri: pozisyonun hemen altı. #113 (eurobond) ile #116
      // (bu düzen) aynı gün ayrı dallarda yazıldı; katmanlı gövdeye
      // taşınmamıştı ve iki bayrak birlikte açılınca tahvil kartı
      // kayboluyordu (2026-10-09, bulut denemesi).
      _eurobondKarti(),
      const SizedBox(height: SandikSpace.lg),
      ..._istatistikler(pnl.currentUnitTRY),

      // ── 3. Analiz ── (başlık yalnız en az bir kart varsa)
      if (analiz.isNotEmpty) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.s4AnalysisUpper),
        for (final k in analiz) ...[
          const SizedBox(height: SandikSpace.sm),
          _AnalizKatmani(
            // Anahtar başlıktan: varlığa göre satır sayısı değişince (ör.
            // not geç gelir) açık/kapalı durum yanlış satıra kaymasın.
            key: ValueKey(k.baslik),
            baslik: k.baslik,
            acikBaslar: ileri,
            child: k.kart,
          ),
        ],
      ],

      // Masraflar (bayrak `varlik_masraflari`) kendi başlığıyla gelir;
      // Analiz'den sonra, belgelerden önce — eski yığında da sözleşme ve
      // temettünün yanındaydı. Eurobond kartıyla aynı nedenle eksikti.
      if (isOwnAsset &&
          pState != null &&
          RemoteConfigService.instance.varlikMasraflari)
        _masrafKarti(pState),

      // ── 4. Geçmiş ve belgeler ──
      // Kartların üçü de kendini gizleyebilir ve ikisi (temettü, KAP)
      // veriyi kendi içinde ASENKRON çeker; "çizilecek mi" önceden
      // bilinemez. Başlığı çizilen yüksekliğe bağlamak (`_BosIseGizle`)
      // koşulları burada kopyalamaktan dürüst: kart kuralı değişirse başlık
      // kendiliğinden uyar.
      _BosIseGizle(
        baslik: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: SandikSpace.lg),
            SandikSectionHeader(title: l.s4HistoryDocsUpper),
          ],
        ),
        govde: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isOwnAsset)
              _sozlesmeKarti(dis: const EdgeInsets.only(top: SandikSpace.sm)),
            if (isOwnAsset && pState != null) _temettuKarti(pState),
            _kapBaglantisi(dis: const EdgeInsets.only(top: SandikSpace.sm)),
          ],
        ),
      ),

      // Yasal ibare sayfanın EN ALTINDA, sinyal paneli katlı olsa da:
      // AL/SAT gösteren yüzey (kapalı satır da onun girişidir) ibareyi
      // taşır. Sayfadaki tek ibare budur (#20).
      if (_sinyalYuzeyleri) ...[
        const SizedBox(height: SandikSpace.lg),
        const DisclaimerWidget(),
      ],
    ];
  }

  /// Bu varlıkta GERÇEKTEN çizilecek analiz kartları, eski sırayla.
  ///
  /// Kapalı satır "burada bir kart var" der; açınca boş çıkması yalan olur.
  /// Bu yüzden her kartın çizilmeme koşulu burada aynen sorulur (aynı
  /// sağlayıcılar, aynı sırada). Kartlar kendi `build`'lerinde aynı koşulu
  /// yine uygular — buradaki yalnızca satırın var olup olmadığını seçer.
  /// Bir kartın koşulu değişirse burası da değişmeli (kart dosyasındaki
  /// `SizedBox.shrink` dönüşleri).
  ///
  /// İzlemek (watch) maliyet eklemez: eski düzende kartlar aynı
  /// sağlayıcıları zaten ekran açılır açılmaz izliyordu.
  List<({String baslik, Widget kart})> _analizKatmanlari() {
    final l = context.l10n;
    final tur = widget.asset.type;
    final ticker = widget.asset.ticker;
    const dis = EdgeInsets.only(top: SandikSpace.sm);
    final radar = ref.watch(balinaRadariAcikProvider);
    final fonKodu = fonKoduOf(tur: tur, ticker: ticker);

    bool fonKarnesiVar() =>
        ref.watch(fonKarnesiAcikProvider) &&
        fonKodu != null &&
        ref.watch(fonKarnesiProvider(fonKodu)).valueOrNull != null;
    bool paraAkisiVar() =>
        radar &&
        fonKodu != null &&
        ref.watch(fonAkisiProvider(fonKodu)).valueOrNull != null;
    bool hacimVar() {
      final s = bistSembolu(tur: tur, ticker: ticker);
      return radar &&
          s != null &&
          ref.watch(hisseHacmiProvider(s)).valueOrNull != null;
    }

    bool kriptoVar() {
      final k = kriptoTickeri(tur: tur, ticker: ticker);
      if (!radar || k == null) return false;
      final ozet = ref.watch(kriptoBaskiProvider(k)).valueOrNull;
      return ozet != null && kriptoOkunusu(ozet) != null;
    }

    bool notVar() {
      final a = notAnahtari(tur: tur, ticker: ticker);
      return radar &&
          a != null &&
          ref.watch(varlikNotOzetiProvider(a)).valueOrNull != null;
    }

    return [
      // Sinyal kartı ve gösterge paneli TEK satır: kart panelin özetidir,
      // dokununca panele kaydırır (`_sinyalPaneline`) — ikisi ayrı katlansa
      // kart kapalı bir panele işaret ederdi. Seviye kapısı eskisi gibi.
      if (_sinyalYuzeyleri)
        (
          baslik: l.s4RowSignals,
          kart: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: SandikSpace.sm),
              AssetSignalCard(asset: widget.asset, onTap: _sinyalPaneline),
              TechnicalSignalPanel.forAsset(widget.asset,
                  key: _sinyalPaneliKey, detayli: true),
            ],
          ),
        )
      else if (_sinyalKilidi)
        (baslik: l.s4RowSignals, kart: const SinyalKilitKarti()),
      if (fonKarnesiVar())
        (baslik: l.s4RowFundReport, kart: _fonKarnesi(dis: dis)),
      if (paraAkisiVar()) (baslik: l.s4RowFlow, kart: _paraAkisi(dis: dis)),
      if (hacimVar()) (baslik: l.s4RowVolume, kart: _hacimRadari(dis: dis)),
      if (kriptoVar()) (baslik: l.s4RowCrypto, kart: _kriptoBaski(dis: dis)),
      if (notVar()) (baslik: l.s4RowNote, kart: _analizNotu(dis: dis)),
    ];
  }
}

/// Pozisyonun özet kartı: bugünkü değer, toplam kâr/zarar, miktar — ve
/// "Ayrıntı" ile açılan eski yedi satır.
///
/// Dönem kâr/zararı yalnız ayrıntıda: seçili dönemin yüzdesi fiyatın
/// altında zaten yazıyor; ilk bakışta ikinci kez görünmesin (madde 7'nin
/// "aynı sayı iki yerde" kararı). Sayılar `_pnlOzeti`'nden — hesap yok.
class _KatmanliPozisyonKarti extends StatefulWidget {
  const _KatmanliPozisyonKarti({
    required this.baz,
    required this.pnl,
    required this.miktarMetni,
    required this.ayrinti,
  });

  final BazPara baz;
  final _PnlOzeti pnl;

  /// `null` → miktar sütunu yok (mevduat).
  final String? miktarMetni;
  final Widget ayrinti;

  @override
  State<_KatmanliPozisyonKarti> createState() => _KatmanliPozisyonKartiState();
}

class _KatmanliPozisyonKartiState extends State<_KatmanliPozisyonKarti> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final tutar = widget.baz.formatter(digits: 0);
    final pnl = widget.pnl;
    final k = kazancSatiri(
        tutar: pnl.totalPnlTRY, yuzde: pnl.pnlPct, tutarMetni: tutar.format);
    final kRenk = switch (k?.yon) {
      1 => c.gain,
      -1 => c.loss,
      _ => c.text36,
    };

    Widget sayi(String etiket, String deger, {Color? renk}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etiket,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs),
              // Rakam kırpılmaz, küçülür (`_PozisyonSatiri` ile aynı kural).
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(deger,
                    maxLines: 1,
                    style: context.t.numSmall.copyWith(
                        color: renk ?? c.text90, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return SandikCard(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.md, SandikSpace.smd, SandikSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sayi(l.posCurrentValue, tutar.format(pnl.currentValueTRY)),
              const SizedBox(width: SandikSpace.smd),
              sayi(l.posTotalPnl, k?.metin ?? l.noChange, renk: kRenk),
              if (widget.miktarMetni case final m?) ...[
                const SizedBox(width: SandikSpace.smd),
                sayi(l.posQuantity, m),
              ],
            ],
          ),
          _AcKapaSatiri(
            baslik: l.s4Details,
            acik: _acik,
            ikincil: true,
            onTap: () => setState(() => _acik = !_acik),
          ),
          SandikAcilir(
            acik: _acik,
            child: Padding(
              padding: const EdgeInsets.only(bottom: SandikSpace.xs),
              child: widget.ayrinti,
            ),
          ),
        ],
      ),
    );
  }
}

/// Analiz bölümünün bir satırı: kapalıyken tek satır (başlık + ok),
/// dokununca yerinde eski kartı açar. Hareket ortak [SandikAcilir] —
/// "Hareketi azalt"ta anında.
class _AnalizKatmani extends StatefulWidget {
  const _AnalizKatmani({
    super.key,
    required this.baslik,
    required this.acikBaslar,
    required this.child,
  });

  final String baslik;
  final bool acikBaslar;
  final Widget child;

  @override
  State<_AnalizKatmani> createState() => _AnalizKatmaniState();
}

class _AnalizKatmaniState extends State<_AnalizKatmani> {
  late bool _acik = widget.acikBaslar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SandikCard(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
          child: _AcKapaSatiri(
            baslik: widget.baslik,
            acik: _acik,
            onTap: () => setState(() => _acik = !_acik),
          ),
        ),
        SandikAcilir(acik: _acik, child: widget.child),
      ],
    );
  }
}

/// Başlık + dönen ok; tüm satır dokunulur, en az 44 pt.
class _AcKapaSatiri extends StatelessWidget {
  const _AcKapaSatiri({
    required this.baslik,
    required this.acik,
    required this.onTap,
    this.ikincil = false,
  });

  final String baslik;
  final bool acik;
  final VoidCallback onTap;

  /// Kart içindeki "Ayrıntı" bağlantısı: daha silik, küçük yazı.
  final bool ikincil;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final renk = ikincil ? c.text58 : c.text90;
    return Semantics(
      button: true,
      expanded: acik,
      child: SandikTappable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  baslik,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (ikincil ? context.t.labelLarge : context.t.titleSmall)
                      ?.copyWith(color: renk, fontWeight: FontWeight.w600),
                ),
              ),
              SandikAcilirOk(
                acik: acik,
                child: Icon(Icons.expand_more_rounded, size: 20, color: renk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [baslik]'ı yalnız [govde] gerçekten bir şey çizdiğinde gösterir.
///
/// Gövdedeki kartlar veriyi kendi içinde asenkron çekip boşken
/// `SizedBox.shrink` döner; "bu bölümde kart var mı" ancak yerleşimde
/// bilinir. Gövde önce ölçülür, yüksekliği sıfırsa başlık çizilmez ve
/// bölüm sıfır yer kaplar — boş başlık kalmaz, kart gelince başlık
/// kendiliğinden belirir.
class _BosIseGizle extends MultiChildRenderObjectWidget {
  _BosIseGizle({required Widget baslik, required Widget govde})
      : super(children: [baslik, govde]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBosIseGizle();
}

class _BosIseGizleVerisi extends ContainerBoxParentData<RenderBox> {}

class _RenderBosIseGizle extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BosIseGizleVerisi>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BosIseGizleVerisi> {
  bool _bos = true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BosIseGizleVerisi) {
      child.parentData = _BosIseGizleVerisi();
    }
  }

  @override
  void performLayout() {
    final baslik = firstChild!;
    final govde = childAfter(baslik)!;
    final en = constraints.maxWidth;
    final c = BoxConstraints.tightFor(width: en);
    govde.layout(c, parentUsesSize: true);
    baslik.layout(c, parentUsesSize: true);
    _bos = govde.size.height <= 0;
    final baslikBoyu = _bos ? 0.0 : baslik.size.height;
    (baslik.parentData! as _BosIseGizleVerisi).offset = Offset.zero;
    (govde.parentData! as _BosIseGizleVerisi).offset = Offset(0, baslikBoyu);
    size = constraints.constrain(Size(en, baslikBoyu + govde.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_bos) return;
    defaultPaint(context, offset);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    // Gizli başlık ekran okuyucuya da okunmasın.
    if (!_bos) super.visitChildrenForSemantics(visitor);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      !_bos && defaultHitTestChildren(result, position: position);
}
