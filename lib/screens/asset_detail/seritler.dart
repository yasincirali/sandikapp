part of '../asset_detail_screen.dart';

/// Pozisyon kartı, overlay çipi, karşılaştırma şeridi,
/// lejant rozeti. `asset_detail_screen.dart`'ın part'ı (2026-09-14).
/// Pozisyon kartı — "kaçtan aldım, ne oldu" (2026-09-28).
///
/// Yedi düz satır, hepsi "etiket · değer":
///   · miktar, alış fiyatın (ortalama), bugünkü fiyat          → birim
///   · ödediğin toplam, bugünkü değer                          → tutar
///   · toplam kâr/zarar                                        → alıştan bugüne
///   · {dönem} kâr/zarar                                       → seçili dönem
///
/// Son ikisi farklı soruları yanıtlar ve ikisi de durur: "aldığımdan bugüne
/// ne kazandım?" ile "seçtiğim dönemde ne oldu?". Eskiden iki ayrı şerit
/// (`_PnlSummaryStrip`, `_PeriodChangeRow`) ok işareti, rozet ve 10pt
/// sayılarla anlatıyordu; kullanıcı "okunaklı, basit ibare" istedi.
///
/// Birim fiyat ₺ kalır (borsadaki sayı; `money_format_scope_test` değer/
/// fiyat ayrımı), tutarlar baz para biriminde. Dönem tutarı pozisyonun
/// PİYASA ETKİSİ, yüzdesi birim serinin başı/sonu — bkz. `_donemDegisimi`
/// ve "Varlık Ekranı Birim Seri" kararı.
class _PozisyonKarti extends StatelessWidget {
  const _PozisyonKarti({
    required this.baz,
    required this.pnl,
    required this.miktarMetni,
    required this.birimEtiketi,
    required this.birimBicim,
    required this.donemEtiketi,
    required this.donem,
    this.birimGizli = false,
  });

  /// Miktar ve birim fiyat satırları gizlensin mi — mevduatta "250.000
  /// birim × 1,03 ₺/birim" kullanıcıya bir şey söylemez; tutar satırları
  /// (yatırdığın, bugünkü değer, kâr/zarar) aynı bilgiyi taşır.
  final bool birimGizli;

  final BazPara baz;
  final _PnlOzeti pnl;
  final String miktarMetni;
  final String birimEtiketi;
  final NumberFormat birimBicim;
  final String donemEtiketi;

  /// Seçili dönemin değişimi; seri gelmediyse `null` → satır "—".
  final ({double tutar, double yuzde})? donem;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tutar = baz.formatter(digits: 0);
    String birim(double v) => '${birimBicim.format(v)} / $birimEtiketi';

    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.xs),
      child: Column(
        children: [
          if (!birimGizli) ...[
            _PozisyonSatiri(etiket: l.posQuantity, deger: miktarMetni),
            _PozisyonSatiri(
                etiket: l.posBuyPrice, deger: birim(pnl.anchorUnitTRY)),
            _PozisyonSatiri(
                etiket: l.posTodayPrice,
                deger:
                    pnl.currentUnitTRY > 0 ? birim(pnl.currentUnitTRY) : '—'),
            Divider(height: SandikSpace.sm, color: context.c.hairline),
          ],
          _PozisyonSatiri(
              etiket: l.posTotalCost, deger: tutar.format(pnl.totalCostTRY)),
          _PozisyonSatiri(
              etiket: l.posCurrentValue,
              deger: tutar.format(pnl.currentValueTRY)),
          _PozisyonSatiri.kazanc(
            etiket: l.posTotalPnl,
            tutar: pnl.totalPnlTRY,
            yuzde: pnl.pnlPct,
            bicim: tutar,
            vurgulu: true,
          ),
          if (donem case final d?)
            _PozisyonSatiri.kazanc(
              etiket: l.posPeriodPnl(donemEtiketi),
              tutar: d.tutar,
              yuzde: d.yuzde,
              bicim: tutar,
              // Yalnız TUTAR (Sadeleştirme 2, madde 7, 2026-10-04): satırın
              // yüzdesi ürünün fiyat hareketidir — fiyatın altındaki dönem
              // yüzdesiyle AYNI sayı (`_donemDegisimi` ile `_donemYuzdesi`
              // aynı birim seri, aynı dönem başı). Tutar ise sahibin piyasa
              // etkisidir, başka bir ölçü: o kalır. Bayrak
              // `varlik_islem_cubugu` 2026-10-05'te kalktı; eski "₺0 · fiyat
              // −%7,55" yazımı (`posPeriodPriceMove`) onunla gitti.
              yuzdesiz: true,
            )
          else
            _PozisyonSatiri(etiket: l.posPeriodPnl(donemEtiketi), deger: '—'),
        ],
      ),
    );
  }
}

/// Kartın bir satırı: solda etiket, sağda değer. Etiket iki satıra
/// sarabilir; değer `FittedBox` ile küçülür, kırpılmaz (rakam kırpmak
/// yanlış okutur).
class _PozisyonSatiri extends StatelessWidget {
  const _PozisyonSatiri({
    required this.etiket,
    required this.deger,
    this.renk,
    this.vurgulu = false,
  });

  /// Kâr/zarar satırı: işaretli tutar + yüzde; bkz. [kazancSatiri].
  factory _PozisyonSatiri.kazanc({
    required String etiket,
    required double tutar,
    required double yuzde,
    required ParaBicimi bicim,
    bool vurgulu = false,
    bool yuzdesiz = false,
  }) {
    final k = kazancSatiri(
        tutar: tutar,
        yuzde: yuzde,
        tutarMetni: bicim.format,
        yuzdesiz: yuzdesiz);
    return _PozisyonSatiri(
      etiket: etiket,
      deger: k?.metin,
      renk: switch (k?.yon) {
        1 => _KazancRengi.gain,
        -1 => _KazancRengi.loss,
        _ => null,
      },
      vurgulu: vurgulu,
    );
  }

  final String etiket;

  /// `null` → nötr "Değişim yok".
  final String? deger;
  final _KazancRengi? renk;
  final bool vurgulu;

  @override
  Widget build(BuildContext context) {
    final degerRengi = switch (renk) {
      _KazancRengi.gain => context.c.gain,
      _KazancRengi.loss => context.c.loss,
      null => deger == null ? context.c.text36 : context.c.text90,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              etiket,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(
                  color: vurgulu ? context.c.text90 : context.c.text58,
                  fontWeight: vurgulu ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                deger ?? context.l10n.noChange,
                maxLines: 1,
                style: context.t.numSmall.copyWith(
                    color: degerRengi,
                    fontWeight: vurgulu ? FontWeight.w800 : FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _KazancRengi { gain, loss }

/// Pozisyon kartındaki kâr/zarar satırının metni ve yönü (`1` kâr, `-1`
/// zarar, `0` nötr); tutar da yüzde de sıfıra yuvarlanıyorsa `null`
/// ("Değişim yok").
///
/// ## Her sayı KENDİ işaretini taşır (2026-09-29 emülatör testi #1)
/// Eskiden işaret tutardan alınıp yüzdeye de yazılıyordu (`yuzde.abs()`).
/// Dönem satırında iki sayı farklı tabanlardan gelir (bkz.
/// `_donemDegisimi`): tutar pozisyonun PİYASA ETKİSİ, yüzde ürünün birim
/// fiyat hareketi. Bugün alınan fon 1H'de %7,55 düşmüşken piyasa etkisi
/// ₺0 (≥ 0) olduğu için satır yeşil "+₺0 · +%7,55" yazıyordu — yön tersti.
/// Şimdi yüzde [fmtPctIsaretli] ile kendi yönünü yazar. 2026-10-04'ten beri
/// dönem satırı yüzdeyi hiç yazmaz ([yuzdesiz]); "fiyat" etiketi
/// (`yuzdeEtiketi`) 2026-10-05'te o yolla birlikte kalktı.
///
/// Renk SATIRIN sorusundan gelir — "kâr/zarar" sahibin kazancıdır, yani
/// TUTARIN yönü. Tutar sıfıra yuvarlanıyorsa renk nötr (yeşil ₺0 "kazandın"
/// der) ve tutar işaretsiz yazılır.
///
/// Toplam satırında yüzde aynı tabandandır (kâr / maliyet), etiket yoktur;
/// iki sayının işareti zaten aynıdır.
///
/// [yuzdesiz]: yalnız tutar (dönem satırı — yüzde fiyatın altında zaten
/// yazıyor). Tutar sıfıra yuvarlanıyorsa
/// `null` ("Değişim yok"): satırın sorusu sahibin kazancıdır.
@visibleForTesting
({String metin, int yon})? kazancSatiri({
  required double tutar,
  required double yuzde,
  required String Function(double) tutarMetni,
  bool yuzdesiz = false,
}) {
  final tutarDuz = tutar.abs().round() == 0;
  if (yuzdesiz) {
    if (tutarDuz) return null;
    return (
      metin: '${tutar > 0 ? '+' : '−'}${tutarMetni(tutar.abs())}',
      yon: tutar > 0 ? 1 : -1,
    );
  }
  if (tutarDuz && donemDuzMu(yuzde)) return null;
  final t = tutarDuz
      ? tutarMetni(0)
      : '${tutar > 0 ? '+' : '−'}${tutarMetni(tutar.abs())}';
  final y = fmtPctIsaretli(yuzde);
  return (
    metin: '$t · $y',
    yon: tutarDuz ? 0 : (tutar > 0 ? 1 : -1),
  );
}

/// Fullscreen landscape moduna geçiren küçük ikon buton.
/// Grafik üzerine çizilen göstergeleri açıp kapatan küçük toggle chip.
class _OverlayChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OverlayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: active
                  ? context.c.amberFill.withValues(alpha: 0.55)
                  : context.c.overlay,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.check_rounded
                    : Icons.horizontal_rule_rounded,
                size: 12,
                color: active ? context.c.amberText : context.c.text58,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? context.c.amberText : context.c.text58,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grafik container'ının üstünde: legend (rozet) + "Karşılaştır" ekle butonu.
/// Compare seçili değilse sadece + butonu görünür; seçiliyken rozet ve ✕.
class _CompareStrip extends StatelessWidget {
  final String primaryTicker;
  final Asset? compare;
  final VoidCallback onAddPressed;
  final VoidCallback onClearPressed;

  const _CompareStrip({
    required this.primaryTicker,
    required this.compare,
    required this.onAddPressed,
    required this.onClearPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Rozetler + "ekle" düğmesi sabit genişlikte değil: uzun ticker'lar
    // (TEFAS:YKT gibi) veya karşılaştırma rozeti eklenince satır taşıyordu
    // (15px). Yatay kaydırma, rozetleri kırpmadan sığdırır — hiçbir bilgi
    // gizlenmez, yalnızca gerekirse kaydırılır.
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          // Ana varlık rozeti — renk = context.c.amberText
          _LegendBadge(
            color: context.c.amberText,
            label: primaryTicker,
          ),
          const SizedBox(width: 8),
          if (compare != null) ...[
            _LegendBadge(
              color: _kCompareColor,
              label: compare!.ticker,
              onRemove: onClearPressed,
            ),
            const SizedBox(width: 8),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddPressed,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: context.c.overlay,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      compare == null
                          ? Icons.add_rounded
                          : Icons.swap_horiz_rounded,
                      size: 14,
                      color: context.c.text58,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compare == null ? 'Karşılaştır' : 'Değiştir',
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text58,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBadge extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback? onRemove;
  const _LegendBadge({
    required this.color,
    required this.label,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: onRemove == null ? 10 : 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close_rounded, size: 12, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
