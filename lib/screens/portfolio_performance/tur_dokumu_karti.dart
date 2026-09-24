part of '../portfolio_performance_screen.dart';

/// Tür dökümü kartı. `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
class _TypeBreakdownCard extends StatefulWidget {
  /// Grafiğin çizdiği seriyle AYNI istekten gelen dağılım.
  final PortfolioHistoryBreakdown breakdown;

  /// Üst kartın gösterdiği dönem başı/sonu değerleri. Döküm bunlara
  /// kalibre edilir — bkz. `_rows`.
  final double totalFirst;
  final double totalLast;

  final List<List<Asset>> ownerLots;
  final DateTime start;
  final DateTime end;
  final bool simulate;
  final BazPara baz;

  /// Üst kartın tabanını ölçtüğü an (ms) — satırların dönem başı değeri bu
  /// damgadaki seri değeridir, katkı da (gün içi dışında) bu andan SONRASI
  /// için sayılır. Üst kartla aynı kural (2026-09-24).
  final int tabanMs;

  /// Gün içi: üst kart ARINDIRILMIŞ rakam gösterir, satırlar da öyle.
  final bool intraday;

  /// Verilen lot'ların CANLI değeri (TRY) — üst kartın sağ ucuyla
  /// (`currentTotal`) aynı yol (`DailySummary.kapsamToplami`). Verilmezse
  /// serinin son noktası kullanılır.
  final double Function(List<Asset> lotlar)? canliDeger;

  const _TypeBreakdownCard({
    required this.baz,
    required this.breakdown,
    required this.totalFirst,
    required this.totalLast,
    required this.ownerLots,
    required this.start,
    required this.end,
    required this.simulate,
    required this.tabanMs,
    this.intraday = false,
    this.canliDeger,
  });

  @override
  State<_TypeBreakdownCard> createState() => _TypeBreakdownCardState();
}

/// Tek bir döküm satırı — tür ya da ürün.
class _BreakdownRow {
  final String label;
  final double first;
  final double last;

  /// Dönem içi net alım/satım (TRY). Yalnızca gerçek modda dolar.
  final double flow;

  const _BreakdownRow({
    required this.label,
    required this.first,
    required this.last,
    this.flow = 0,
  });

  double get change => last - first;
  double? get pct => first > 0 ? (change / first) * 100 : null;
}

class _TypeBreakdownCardState extends State<_TypeBreakdownCard> {
  /// Açık tür başlıkları. Varsayılan kapalı — kart uzun olmasın.
  final Set<AssetType> _expanded = {};

  /// Bir serinin dönem başı ve sonu değeri — ÜST KARTLA AYNI iki an.
  ///
  /// Baş: [_TypeBreakdownCard.tabanMs] damgasındaki (ya da ondan önceki son)
  /// ölçüm — değeri ne olursa olsun; o anda elde yoksa 0, dönem içinde
  /// açılan pozisyonun tamamı katkıdadır. Son: [_TypeBreakdownCard.canliDeger]
  /// (canlı), yoksa serinin son noktası.
  ///
  /// ## Neden (2026-09-24 dört ekran çapraz kontrolü)
  /// Eskiden serinin kırpılmamış İLK ve SON noktası alınıyordu. 88b04da üst
  /// kartı pencereye kırpıp ucunu canlıya bağlayınca satırlar ayrıştı
  /// (ölçüldü, 1A: satırlar +₺5.113, üst kart +₺18.198). Serinin son slotu
  /// bugünkü alımları içermiyor (`normalizeTs(now)`); o yüzden uç canlı.
  ///
  /// Taban anındaki 0 da bir ölçümdür (pozisyon o an kapalıydı): ilk
  /// sürüm son POZİTİF değeri alıyordu ve daha eski bir değeri taban
  /// sanıyordu (kod incelemesi, 2026-09-24).
  ({double first, double last})? _endpoints(
      Map<int, double>? series, List<Asset> lotlar) {
    if (series == null || series.isEmpty) return null;
    final ts = series.keys.toList()..sort();
    double first = 0;
    for (final k in ts) {
      if (k > widget.tabanMs) break;
      first = series[k] ?? 0;
    }
    if (first < 0) first = 0;
    final last = widget.canliDeger?.call(lotlar) ?? series[ts.last]!;
    if (first <= 0 && last <= 0) return null;
    return (first: first, last: last);
  }

  /// Dönem içi net para akışı — verilen lot'lar için.
  ///
  /// Not satırı için: kullanıcı "+%100" görünce ne kadarının kendi parası
  /// olduğunu bilmeli. Simülasyonda miktar sabit sayıldığı için akış yoktur.
  ///
  /// Kural üst kartla TEK fonksiyon (`PeriodSummaryService.grafikKatkisi`):
  /// gün içinde açılış ölçümünden, diğer dönemlerde taban anından
  /// ([_TypeBreakdownCard.tabanMs]) SONRASI. Eskiden her dönemde gün
  /// başından sayılıyordu; tabanın içinde olan alım katkıya da giriyordu
  /// (çifte sayım).
  double _flowOf(List<Asset> lotlar) {
    if (widget.simulate) return 0;
    return PeriodSummaryService.grafikKatkisi(lotlar,
        start: widget.start,
        end: widget.end,
        tabanMs: widget.tabanMs,
        intraday: widget.intraday);
  }

  /// Satırın GÖSTERDİĞİ kâr/zarar. Gün içinde üst kart ARINDIRILMIŞ rakam
  /// gösteriyor (2026-09-23 kullanıcı kararı, ana sayfa Bugün kartıyla
  /// aynı); satırlar da öyle, yoksa Σ satır üst rakamı tutmaz. Sıralama da
  /// bu sayıya göre — ham değişime göre sıralamak gün içinde "en çok
  /// kazandıran üstte" sözünü bozuyordu (kod incelemesi, 2026-09-24).
  bool get _net => widget.intraday && !widget.simulate;
  double _pnl(_BreakdownRow r) => r.change - (_net ? r.flow : 0);

  /// Tür satırları + her türün altındaki ürün satırları.
  ///
  /// ## "Diğer" satırı ve kalibrasyon
  /// Tür serilerinin toplamı üst kartın rakamını genellikle tutar ama HER
  /// ZAMAN değil: üst kart son noktayı canlı toplamla eziyor
  /// (`currentTotalOverride`) ve mevduat gibi fiyat serisi olmayan varlıklar
  /// hiçbir tür serisinde yer almıyor. Aradaki artık **"Diğer"** satırına
  /// yazılır. Böylece satırların toplamı üst kartı **tanım gereği** tutar:
  /// artık ne kadarsa o kadar, sıfırsa satır hiç çıkmaz.
  (
    List<({AssetType type, _BreakdownRow row})>,
    Map<AssetType, List<_BreakdownRow>>
  ) _rows() {
    final typeRows = <({AssetType type, _BreakdownRow row})>[];
    final childrenOf = <AssetType, List<_BreakdownRow>>{};

    double sumFirst = 0;
    double sumLast = 0;

    // Lot'lar TEK geçişte türe ve pozisyona bölünür. Eskiden her tür ve
    // her pozisyon satırı tüm defteri yeniden süzüyordu — iki kez (akış ve
    // canlı değer), üstelik `build()` içinde (kod incelemesi, 2026-09-24).
    final turLotlari = <AssetType, List<Asset>>{};
    final pozisyonLotlari = <String, List<Asset>>{};
    for (final l in widget.ownerLots) {
      for (final a in l) {
        turLotlari.putIfAbsent(a.type, () => []).add(a);
        pozisyonLotlari.putIfAbsent(positionKey(a), () => []).add(a);
      }
    }

    for (final e in widget.breakdown.byType.entries) {
      final turLot = turLotlari[e.key] ?? const <Asset>[];
      final ep = _endpoints(e.value, turLot);
      if (ep == null) continue;
      sumFirst += ep.first;
      sumLast += ep.last;
      typeRows.add((
        type: e.key,
        row: _BreakdownRow(
          label: e.key.labelOf(context.l10n),
          first: ep.first,
          last: ep.last,
          flow: _flowOf(turLot),
        ),
      ));

      // Ürün satırları — aynı türe ait pozisyonlar.
      final kids = <_BreakdownRow>[];
      for (final p in widget.breakdown.byPosition.entries) {
        if (widget.breakdown.positionType[p.key] != e.key) continue;
        final pozLot = pozisyonLotlari[p.key] ?? const <Asset>[];
        final pep = _endpoints(p.value, pozLot);
        if (pep == null) continue;
        kids.add(_BreakdownRow(
          label: _positionLabel(p.key, e.key, context.l10n),
          first: pep.first,
          last: pep.last,
          flow: _flowOf(pozLot),
        ));
      }
      if (kids.isNotEmpty) childrenOf[e.key] = kids;
    }

    // ── Artığı ORANSAL dağıt — sahte satır AÇMA ──────────────────────────
    //
    // Tür serilerinin toplamı üst kartı birebir tutmayabilir: üst kartın son
    // noktası canlı toplamla eziliyor (`currentTotalOverride`), tür serileri
    // ise ham seriden geliyor. Aradaki fark gerçek bir kategori DEĞİLDİR —
    // aynı varlıkların bir kaç dakikalık fiyat farkıdır.
    //
    // Eskiden bu artık "Diğer" adlı sentetik bir satıra yazılıyordu. İki
    // sebeple yanlıştı:
    //   1. `AssetType.diger` ZATEN var ("Diğer", mor) — kullanıcının gerçek
    //      bir kategorisi. Aynı adı taşıyan iki satır, biri gerçek biri
    //      hesap artığı, doğrudan yanlış bilgi verirdi.
    //   2. Her varlık zaten bir kategoriye ait; `mevduat` ve `diger` dahil
    //      hepsi `currentPrice` dalından değer alıyor. Kategorisiz bakiye
    //      diye bir şey yok.
    //
    // Doğrusu: artığı türlerin AĞIRLIĞINCA dağıtmak. Böylece
    // `Σ satır == üst kart` korunur ve fazladan kavram uydurulmaz.
    _calibrate(typeRows, childrenOf, sumFirst, sumLast);

    // En çok kazandıran üstte — GÖSTERİLEN sayıya göre ([_pnl]).
    typeRows.sort((a, b) => _pnl(b.row).compareTo(_pnl(a.row)));
    for (final kids in childrenOf.values) {
      kids.sort((a, b) => _pnl(b).compareTo(_pnl(a)));
    }
    return (typeRows, childrenOf);
  }

  /// Tür (ve ürün) satırlarını üst kartın uçlarına oransal olarak kalibre eder.
  ///
  /// Ölçek çarpanı `üstKart / serilerToplamı`. Her satır kendi ağırlığınca pay
  /// alır, dolayısıyla satırların toplamı üst kartı tutar ama satırlar arası
  /// oranlar (yani hangi tür ne kadar kazandırdı) hiç bozulmaz.
  ///
  /// Ürün satırları da AYNI çarpanla ölçeklenir — aksi halde bir tür açıldığında
  /// içindekilerin toplamı başlığı tutmazdı.
  void _calibrate(
    List<({AssetType type, _BreakdownRow row})> rows,
    Map<AssetType, List<_BreakdownRow>> childrenOf,
    double sumFirst,
    double sumLast,
  ) {
    // Sıfıra bölünemez; seri yoksa kalibre edilecek bir şey de yok.
    var kFirst = sumFirst.abs() > 0.01 ? widget.totalFirst / sumFirst : 1.0;
    var kLast = sumLast.abs() > 0.01 ? widget.totalLast / sumLast : 1.0;

    // ⚠️ ÇAPRAZ BULAŞMA SINIRI.
    //
    // Kalibrasyon TEK bir çarpanla çalışır: bir türdeki sapmayı tüm türlere
    // yayar. Küçük artıklarda (üst kart `pState.toTRY` kurlarını, servis
    // kendi kurunu kullanır — binde birkaç fark) bu zararsızdır ve toplamı
    // tutturur. Ama çarpan 1'den belirgin uzaklaşırsa satırlar YALAN söyler:
    // fiyatı hiç değişmemiş bir tür, başka bir tür oynadığı için oynamış
    // görünür. Bu hata gün içi serisinde ölçüldü (fon 25.000 → 16.716) ve
    // orada canlı değerleri tür bazında hesaplayarak kökten çözüldü.
    //
    // Burada kalan artık küçük olmalı; büyükse kalibre ETME. Toplamda birkaç
    // TL sapma göstermek, her satırı yanlış göstermekten iyidir.
    const maxSapma = 0.02; // %2
    if ((kFirst - 1).abs() > maxSapma) kFirst = 1.0;
    if ((kLast - 1).abs() > maxSapma) kLast = 1.0;

    // Çarpan 1'e çok yakınsa dokunma — kayan nokta gürültüsüyle oynamayalım.
    if ((kFirst - 1).abs() < 1e-9 && (kLast - 1).abs() < 1e-9) return;

    _BreakdownRow scaled(_BreakdownRow r) => _BreakdownRow(
          label: r.label,
          first: r.first * kFirst,
          last: r.last * kLast,
          flow: r.flow,
        );

    for (var i = 0; i < rows.length; i++) {
      rows[i] = (type: rows[i].type, row: scaled(rows[i].row));
    }
    for (final e in childrenOf.entries) {
      childrenOf[e.key] = [for (final k in e.value) scaled(k)];
    }
  }

  /// [_rows] sonucu — yalnızca kart YENİ girdiyle kurulduğunda yeniden
  /// hesaplanır. Bir türü açıp kapamak (`setState`) defteri yeniden
  /// taramaz; hesap `build()` içinde tekrarlanmaz (CLAUDE.md katmanlama).
  (
    List<({AssetType type, _BreakdownRow row})>,
    Map<AssetType, List<_BreakdownRow>>
  )? _onbellek;

  @override
  void didUpdateWidget(covariant _TypeBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onbellek = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Etiketler `context.l10n`'dan — dil değişirse yeniden kurulmalı.
    _onbellek = null;
  }

  @override
  Widget build(BuildContext context) {
    final (typeRows, childrenOf) = _onbellek ??= _rows();
    if (typeRows.isEmpty) return const SizedBox.shrink();

    final tryFmt = widget.baz.formatter(digits: 0);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 14),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.changeByTypeUpper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: context.c.text36,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          for (final entry in typeRows) ...[
            _typeTile(context, entry.type, entry.row, childrenOf, tryFmt),
            if (entry != typeRows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// Tür satırı — ürünü varsa dokunulabilir ve açılır.
  Widget _typeTile(
    BuildContext context,
    AssetType type,
    _BreakdownRow row,
    Map<AssetType, List<_BreakdownRow>> childrenOf,
    ParaBicimi tryFmt,
  ) {
    // Ürünü olan HER tür açılır — döviz, mevduat, "Diğer" dahil (kullanıcı
    // kararı, 2026-09-01).
    //
    // Eskiden eşik `kids.length > 1` idi: tek ürünlü tür açılmıyordu, çünkü
    // "kendi kopyasını göstermek bilgi katmaz" diye düşünülmüştü. Ama bu
    // *tutarlılığı* bozuyordu — Apple'ın "familiarity" ilkesi: aynı görünen
    // şeyler aynı davranmalı. Kullanıcı bir satırın açılıp açılmayacağını
    // önceden kestiremiyordu, üstelik tek ürünlü satır o ürünün ADINI
    // (ör. hangi fon olduğunu) göstermiyordu — bu bilgi kayıptı.
    final kids = childrenOf[type] ?? const <_BreakdownRow>[];
    final canExpand = kids.isNotEmpty;
    final isOpen = _expanded.contains(type);

    final header = _row(
      context,
      tryFmt,
      label: row.label,
      dotColor: type.color,
      value: row.last,
      cost: row.first,
      flow: row.flow,
      // Chevron GİDİLECEK yönü işaret eder (Apple: "hint in the direction of
      // the gesture"). Kapalıyken sağa bakar — "burada devamı var"; açıkken
      // 90° dönüp aşağıyı gösterir, yani içeriğin çıktığı yönü. Ara kareler
      // sonucu telegraflar, körlemesine interpolasyon yapmaz.
      trailing: canExpand
          ? AnimatedRotation(
              turns: isOpen ? 0.25 : 0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              child: Icon(Icons.chevron_right_rounded,
                  size: 18,
                  // Açıkken biraz belirginleşir: hangi başlığın açık olduğu
                  // renkten de okunur, yalnızca açıdan değil.
                  color: isOpen ? context.c.text58 : context.c.text36),
            )
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canExpand)
          // `SandikTappable`: basma geri bildirimi (scale), haptic ve
          // `Semantics(button: true)` bir arada. Ham `GestureDetector`
          // bunların HİÇBİRİNİ vermiyordu — dokunulabilir bir satırın
          // dokunulduğunu belli etmemesi ekranın geri kalanıyla da çelişiyordu.
          SandikTappable(
            semanticLabel: isOpen
                ? context.l10n.rowExpandedSemantics(row.label)
                : context.l10n.rowCollapsedSemantics(row.label),
            onTap: () => setState(() {
              if (!_expanded.remove(type)) _expanded.add(type);
            }),
            // 44pt dokunma hedefi: satır kendi başına ~36pt, dikey 6+6 ile
            // eşiğe çıkar (HIG minimumu). `ConstrainedBox` büyük metin
            // ayarında satır zaten uzadığında fazladan yer kaplamaz.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: header,
              ),
            ),
          )
        else
          header,
        // ── Ürün satırları ────────────────────────────────────────────────
        //
        // **Uzamsal süreklilik (Apple).** "Bir şey nasıl kayboluyorsa oradan
        // geri gelmeli." Ürünler başlığın ALTINDAN doğar: `align: -1.0` ile
        // üst kenardan açılır, düz bir opacity geçişi değil. Kapanırken de
        // aynı yolu izler — çıkış ve giriş simetriktir, yoksa içerik bir
        // yerden gelip başka yere gidiyormuş gibi kopuk hissedilir.
        //
        // `ClipRect` şart: açılırken taşan kısım başlığın üstüne binmesin.
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: isOpen ? 1.0 : 0.0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: AnimatedOpacity(
              opacity: isOpen ? 1.0 : 0.0,
              // Opaklık boyuttan biraz HIZLI kapanır: kapanırken içerik önce
              // soluklaşır, sonra yer kapanır — ters sırada olsaydı boş bir
              // beyaz alan bir an görünürdü.
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Column(
                  children: [
                    for (final k in kids) ...[
                      _row(
                        context,
                        tryFmt,
                        label: k.label,
                        dotColor: type.color.withValues(alpha: 0.45),
                        value: k.last,
                        cost: k.first,
                        flow: k.flow,
                        dense: true,
                      ),
                      if (k != kids.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ParaBicimi tryFmt, {
    required String label,
    required Color dotColor,
    required double value,
    required double cost,
    required double flow,
    Widget? trailing,
    bool dense = false,
  }) {
    // Gün içinde arındırılmış rakam — bkz. [_pnl]. Taban da üst kartla
    // aynı: baş + pozitif akış.
    final pnl = value - cost - (_net ? flow : 0);
    final taban = cost + (_net && flow > 0 ? flow : 0);
    final pct = taban > 0 ? (pnl / taban) * 100 : null;

    // Yuvarlanmış tutar sıfırsa nötr renk — yeşil "kazanç var" yanılgısı
    // yaratır. Ekranın geri kalanıyla aynı kural.
    final isFlat = pnl.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
    final color = isFlat
        ? context.c.text36
        : context.signColor(pnl);

    // Ekran okuyucu için tek parça cümle — `portfolio_summary_widget` ile aynı
    // kalıp. Parçalı okunursa "Altın", "+₺12.500", "%3,20" diye üç kopuk
    // duyuru olur ve yön bilgisi (kazanç mı kayıp mı) YALNIZCA renkte kalırdı;
    // renk tek başına bilgi taşıyamaz. Sayıların işareti görsel tarafta bu
    // rolü üstlenir ("+" / "−"), burada kelimeyle söylüyoruz.
    final semanticLabel = [
      label,
      if (isFlat)
        'değişim yok'
      else ...[
        pnl >= 0
            ? context.l10n.gainAmount(tryFmt.format(pnl.abs()))
            : context.l10n.lossAmount(tryFmt.format(pnl.abs())),
        if (pct != null) fmtPct(pct.abs(), digits: 2),
      ],
      if (!widget.simulate && flow.abs() > 0.5)
        flow > 0
            ? context.l10n.flowBuyLower(tryFmt.format(flow))
            : context.l10n.flowSellLower(tryFmt.format(flow.abs())),
    ].join(', ');

    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: _rowVisual(
          context,
          tryFmt,
          label: label,
          dotColor: dotColor,
          flow: flow,
          trailing: trailing,
          dense: dense,
          pnl: pnl,
          pct: pct,
          isFlat: isFlat,
          color: color,
        ),
      ),
    );
  }

  /// Satırın görsel gövdesi — semantik sarmalayıcıdan ayrı tutulur ki
  /// `ExcludeSemantics` altındaki ağaç sade kalsın.
  Widget _rowVisual(
    BuildContext context,
    ParaBicimi tryFmt, {
    required String label,
    required Color dotColor,
    required double flow,
    required Widget? trailing,
    required bool dense,
    required double pnl,
    required double? pct,
    required bool isFlat,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tür/ürün rozeti — renk tek başına bilgi taşımaz, etiket her zaman var.
        Container(
          width: dense ? 6 : 8,
          height: dense ? 6 : 8,
          margin: EdgeInsets.only(top: dense ? 6 : 5, right: 8),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dense
                    ? context.t.bodySmall?.copyWith(color: context.c.text58)
                    : context.t.bodyMedium?.copyWith(color: context.c.text90),
              ),
              // Gerçek modda dönem içi işlem varsa belirt. Simülasyonda bu
              // satır hiç çıkmaz — orada miktar sabit sayılır.
              if (!widget.simulate && flow.abs() > 0.5)
                Text(
                  flow > 0
                      ? context.l10n.flowBuyUpper(tryFmt.format(flow))
                      : context.l10n.flowSellUpper(tryFmt.format(flow.abs())),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall
                      ?.copyWith(color: context.c.text36, fontSize: 11),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Tutar + yüzde. FittedBox: milyonluk portföyde dar ekranda punto
        // düşsün, satır kırılmasın.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFlat
                      ? '—'
                      : '${pnl >= 0 ? '+' : '−'}${tryFmt.format(pnl.abs())}',
                  maxLines: 1,
                  style: context.t.numSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: dense ? 12 : null),
                ),
                if (pct != null && !isFlat)
                  Text(
                    fmtPct(pct.abs(), digits: 2),
                    maxLines: 1,
                    style: context.t.numSmall.copyWith(
                        color: color.withValues(alpha: 0.85), fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing,
        ],
      ],
    );
  }
}
