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

  const _TypeBreakdownCard({
    required this.baz,
    required this.breakdown,
    required this.totalFirst,
    required this.totalLast,
    required this.ownerLots,
    required this.start,
    required this.end,
    required this.simulate,
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

  /// Bir serinin dönem başı ve sonu değeri.
  ///
  /// `null` dönerse o seri çizilemez (tek nokta ya da hiç nokta). Üst kartla
  /// aynı kural: iki nokta yoksa değişim tanımsızdır.
  ({double first, double last})? _endpoints(Map<int, double>? series) {
    if (series == null || series.length < 2) return null;
    final ts = series.keys.toList()..sort();
    return (first: series[ts.first]!, last: series[ts.last]!);
  }

  /// Dönem içi net para akışı — tür bazında.
  ///
  /// Not satırı için: kullanıcı "+%100" görünce ne kadarının kendi parası
  /// olduğunu bilmeli. Simülasyonda miktar sabit sayıldığı için akış yoktur.
  Map<AssetType, double> _flowByType() {
    final out = <AssetType, double>{};
    if (widget.simulate) return out;
    final startMs =
        dayKey(widget.start)
            .millisecondsSinceEpoch;
    final endMs =
        DateTime(widget.end.year, widget.end.month, widget.end.day, 23, 59, 59)
            .millisecondsSinceEpoch;
    for (final lots in widget.ownerLots) {
      for (final a in lots) {
        if (!a.isActive) continue;
        final ms = a.addedDate.millisecondsSinceEpoch;
        if (ms < startMs || ms > endMs) continue;
        final f = a.isBuy
            ? a.totalCostTRY
            : a.isSell
                ? -a.sellProceedsTRY
                : 0.0;
        if (f != 0) out[a.type] = (out[a.type] ?? 0) + f;
      }
    }
    return out;
  }

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
    final flowOf = _flowByType();
    final typeRows = <({AssetType type, _BreakdownRow row})>[];
    final childrenOf = <AssetType, List<_BreakdownRow>>{};

    double sumFirst = 0;
    double sumLast = 0;

    for (final e in widget.breakdown.byType.entries) {
      final ep = _endpoints(e.value);
      if (ep == null) continue;
      sumFirst += ep.first;
      sumLast += ep.last;
      typeRows.add((
        type: e.key,
        row: _BreakdownRow(
          label: e.key.label,
          first: ep.first,
          last: ep.last,
          flow: flowOf[e.key] ?? 0,
        ),
      ));

      // Ürün satırları — aynı türe ait pozisyonlar.
      final kids = <_BreakdownRow>[];
      for (final p in widget.breakdown.byPosition.entries) {
        if (widget.breakdown.positionType[p.key] != e.key) continue;
        final pep = _endpoints(p.value);
        if (pep == null) continue;
        kids.add(_BreakdownRow(
          label: _positionLabel(p.key, e.key),
          first: pep.first,
          last: pep.last,
        ));
      }
      kids.sort((a, b) => b.change.compareTo(a.change));
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

    // En çok kazandıran üstte.
    typeRows.sort((a, b) => b.row.change.compareTo(a.row.change));
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

  @override
  Widget build(BuildContext context) {
    final (typeRows, childrenOf) = _rows();
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
            'TÜRE GÖRE DEĞİŞİM',
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
                ? '${row.label}, açık. Kapatmak için çift dokun.'
                : '${row.label}, kapalı. İçindeki ürünleri görmek için '
                    'çift dokun.',
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
                        flow: 0,
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
    final pnl = value - cost;
    final pct = cost > 0 ? (pnl / cost) * 100 : null;

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
        '${pnl >= 0 ? 'kazanç' : 'kayıp'} ${tryFmt.format(pnl.abs())}',
        if (pct != null) fmtPct(pct.abs(), digits: 2),
      ],
      if (!widget.simulate && flow.abs() > 0.5)
        flow > 0
            ? 'dönem içi alım ${tryFmt.format(flow)}'
            : 'dönem içi satış ${tryFmt.format(flow.abs())}',
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
                      ? 'Dönem içi alım ${tryFmt.format(flow)}'
                      : 'Dönem içi satış ${tryFmt.format(flow.abs())}',
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
