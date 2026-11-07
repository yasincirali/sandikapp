import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/yillik_aralik.dart';
import '../services/varlik_istatistik.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// İstatistik ızgarası ve dönem aralığı çubuğu — varlık sayfasıyla portföy
/// varlık detayının ORTAK parçaları. Dönem çipi (`DonemCipi`) 2026-09-28'de
/// kalktı: tüm ekranlar tek seçiciyi çiziyor (`donem_secici.dart`), getiri
/// satırı oraya taşındı.
///
/// ## Neden ayrı dosya (kullanıcı kararı, 2026-09-28)
/// Portföy › varlık detayı için dört tasarım dilinden **A (varlık sayfası
/// ailesi)** seçildi: aynı varlık aramadan da portföyden de açılınca aynı
/// düzeni göstermeli. İki ekran bu parçaların kopyasını taşısaydı ilk
/// düzeltmede ayrışırlardı (bu projede tekrar eden hata sınıfı). Sayılar
/// burada HESAPLANMAZ: her ekran kendi kaynağından hazır değeri verir —
/// varlık sayfası sembol serisinden, detay ekranı birim seriden.

/// Yuvarlanmış yüzde sıfırsa değişim nötr gösterilir
/// ([DonemIstatistigi.isFlat] ile aynı eşik).
bool donemDuzMu(double pct) => pct.abs() < 0.005;

/// İstatistik ızgarası: dönem getirisi, bugün, en büyük düşüş, oynaklık.
/// Fiyatın altında zaten yazan sayı ve bilinmeyen oynaklık hücre almaz.
///
/// [donemPct] ve [bugunPct] çağırandan gelir: detay ekranı dönem yüzdesini
/// canlı birim fiyata göre ölçer (grafiğin sağ ucu ve başlıktaki sayı ile
/// aynı), varlık sayfası serinin son noktasına göre. `null` → "—".
class DonemIstatistikIzgarasi extends StatelessWidget {
  const DonemIstatistikIzgarasi({
    super.key,
    required this.ist,
    required this.gun,
    required this.donemPct,
    required this.bugunPct,
    this.donemGetirisiGizli = false,
    this.bugunGizli,
    this.gunIci = false,
  });

  /// GÜNLÜK görünüm mü. Günlükte "En büyük düşüş" hücresi çizilmez.
  final bool gunIci;

  /// "En büyük düşüş" hücresi çizilir mi (Ar-Ge 5 Kas 14:45 #3). Bugün
  /// görünümünde ve %0,05'in altında hücre "%0,00" yazıp ayrı kart
  /// kaplıyordu; bilgi yoktu. Yahoo ve Midas günlükte drawdown göstermez.
  /// Gizleme, uydurma sayı değil: değer bilinir ama söylenecek bir şey yok.
  static bool dususVar(DonemIstatistigi ist, {required bool gunIci}) =>
      !gunIci && ist.enBuyukDususPct.abs() >= 0.05;

  /// Izgarada kaç hücre çizilir — iskelet de aynı sayıyı kullanır, yoksa
  /// veri gelince kartın boyu zıplar (Ar-Ge 1 Kas 08:45 #3).
  static int hucreSayisi({
    required bool donemGetirisiGizli,
    required bool bugunGizli,
    required bool oynaklikVar,
    bool dususVar = true,
  }) =>
      (donemGetirisiGizli ? 0 : 1) +
      (bugunGizli ? 0 : 1) +
      (dususVar ? 1 : 0) +
      (oynaklikVar ? 1 : 0);

  /// "Bugün" hücresi gizli mi. `null` → eski kural: dönem getirisi gizliyken
  /// GÜNLÜK seçiliyse ([gun] 0) bugün aynı sayıdır, düşer. Varlık sayfası
  /// GÜNLÜK'ü `gun == 1` ile taşıdığı için kendi kararını açıkça verir.
  final bool? bugunGizli;

  bool get _bugunGizli => bugunGizli ?? (donemGetirisiGizli && gun == 0);

  final DonemIstatistigi ist;

  /// Dönem yüzdesi ekranda zaten fiyatın altında yazıyorsa `true`: ızgara
  /// onu ikinci kez yazmaz (Sadeleştirme 2, madde 7, 2026-10-04 — yalnız
  /// portföy varlık detayı verir). GÜNLÜK seçiliyken "Bugün" hücresi de aynı
  /// sayıdır, o da düşer. Kalan hücreler ikişerli satırlara dizilir; tek
  /// kalan satırı doldurur. Varsayılan `false`: varlık sayfası (takip /
  /// arama) 2×2.
  final bool donemGetirisiGizli;

  /// Seçili dönemin gün sayısı — kısa dönemde oynaklık notu için.
  final int gun;
  final double donemPct;
  final double? bugunPct;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Color yon(double v) =>
        donemDuzMu(v) ? context.c.text58 : context.signColor(v);
    final bugun = bugunPct;

    final hucreler = <(String, String, Color)>[
      if (!donemGetirisiGizli)
        (
          l.vsPeriodReturnUpper,
          fmtPctIsaretli(donemPct),
          yon(donemPct),
        ),
      if (!_bugunGizli)
        (
          l.vsTodayUpper,
          bugun == null ? '—' : fmtPctIsaretli(bugun),
          bugun == null ? context.c.text58 : yon(bugun),
        ),
      if (dususVar(ist, gunIci: gunIci))
        (
          l.vsMaxDrawdownUpper,
          fmtPctIsaretli(ist.enBuyukDususPct),
          context.c.loss,
        ),
      // Oynaklık bilinmiyorsa hücre hiç yok (Ar-Ge 1 Kas 08:45 #3, yasin
      // "yap"): "—" kutusu ve altındaki "kısa dönemde hesaplanmaz" notu yer
      // kaplayıp bir şey söylemiyordu. Uydurma sayı da yazılmaz.
      if (ist.oynaklikPct != null)
        (
          l.vsVolatilityUpper,
          fmtPct(ist.oynaklikPct!),
          context.c.text90,
        ),
    ];

    Widget hucre((String, String, Color) h) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(SandikSpace.smd),
            decoration: context.surfaceCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text36)),
                const SizedBox(height: SandikSpace.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(h.$2,
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(color: h.$3)),
                ),
              ],
            ),
          ),
        );

    if (hucreler.isEmpty) return const SizedBox.shrink();
    final satirlar = <Widget>[
      for (var i = 0; i < hucreler.length; i += 2) ...[
        if (i > 0) const SizedBox(height: SandikSpace.sm),
        Row(children: [
          hucre(hucreler[i]),
          if (i + 1 < hucreler.length) ...[
            const SizedBox(width: SandikSpace.sm),
            hucre(hucreler[i + 1]),
          ],
        ]),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: satirlar,
    );
  }
}

/// Seçili dönemin aralığı — [AralikKarti]'nın "Gün"/dönem satırı. Sayılar
/// çağırandan hazır gelir (bu dosyada hesap yok, bkz. dosya başı).
typedef DonemAraligi = ({
  double dusuk,
  double yuksek,

  /// 0 = dönem dibi, 1 = zirvesi.
  double konum,

  /// Bugünkü fiyat — yalnız ekran okuyucu etiketinde.
  double bugun,
});

/// "Aralık" kartı: seçili dönemin aralığı ("Gün" ya da "1 ay") ve 52
/// haftalık aralık alt alta, AYNI çubuk görünümüyle.
///
/// ## Neden tek kart (Ar-Ge 2026-11-07 14:00 #1, yasin "yap")
/// Yıllık aralık (#312) dönem çipleriyle grafiğin arasına girmişti: seçiciye
/// dokunan kullanıcının gözü değişen grafiği bulmak için seçili dönemden
/// bağımsız bir çubuğun üstünden atlıyordu. Gün aralığı ise sayfanın
/// altında, başka görünüşte (renkli çubuk, kart) duruyordu. İkisi yan yana
/// kıyaslanır; aynı görünen aynı davranır. Satırlar tek bileşeni
/// ([_AralikSatiri]) paylaşır — ikinci çubuk klonu yazılmaz.
///
/// Çubuk nötrdür (#312 kararı, renk körlüğü): eski gün çubuğunun
/// kırmızı→yeşil geçişi konumu renkle söylüyordu. Konumu nokta, anlamı
/// cümle verir. Her satır ekran okuyucuya tek etiket olarak okunur
/// (`yaSemantik`: başlık, uçlar, bugün, cümle).
///
/// Veri yoksa satır yok: [donem] null → dönem satırı yok, [yillik] null →
/// 52 hafta satırı yok; ikisi de yoksa kart hiç yer kaplamaz.
class AralikKarti extends StatelessWidget {
  const AralikKarti({
    super.key,
    this.donem,
    this.yillik,
    required this.bicim,
    this.gunIci = false,
    this.donemAdi,
  });

  final DonemAraligi? donem;
  final YillikAralik? yillik;

  /// Büyük fiyatla aynı biçim (aynı birim, aynı ondalık).
  final NumberFormat bicim;

  /// GÜNLÜK seçili mi: dönem satırı "Gün" der (Ar-Ge 1 Kas 08:45 #3 —
  /// "Dönem" bir günlük aralıkta yabancı geliyordu).
  final bool gunIci;

  /// GÜNLÜK dışında dönem satırının başlığı ("1 ay"); null → "Seçili dönem".
  final String? donemAdi;

  /// Kart çizilir mi — çağıranın aradaki boşluğu da atlaması için.
  static bool cizilir({DonemAraligi? donem, YillikAralik? yillik}) =>
      donem != null || yillik != null;

  @override
  Widget build(BuildContext context) {
    final d = donem;
    final y = yillik;
    if (d == null && y == null) return const SizedBox.shrink();
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: context.surfaceCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.aralikBaslik,
              style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600, color: context.c.text90)),
          if (d != null) ...[
            const SizedBox(height: SandikSpace.sm),
            _donemSatiri(context, d),
          ],
          if (y != null) ...[
            SizedBox(height: d != null ? SandikSpace.md : SandikSpace.sm),
            _yillikSatiri(context, y),
          ],
        ],
      ),
    );
  }

  Widget _donemSatiri(BuildContext context, DonemAraligi d) {
    final l = context.l10n;
    final k = d.konum.clamp(0.0, 1.0);
    final konumYuzde = '${(k * 100).round()}';
    final baslik = gunIci ? l.aralikGun : (donemAdi ?? l.aralikDonem);
    final cumle = gunIci
        ? l.vsDayRangePosition(konumYuzde)
        : l.vsRangePosition(konumYuzde);
    return _AralikSatiri(
      baslik: baslik,
      dusuk: bicim.format(d.dusuk),
      yuksek: bicim.format(d.yuksek),
      konum: k,
      cumle: cumle,
      semantik: l.yaSemantik(baslik, bicim.format(d.dusuk),
          bicim.format(d.yuksek), bicim.format(d.bugun), cumle),
    );
  }

  Widget _yillikSatiri(BuildContext context, YillikAralik a) {
    final l = context.l10n;
    final ay = a.ay;
    // Ekran okuyucu etiketi #312'deki gibi "Yıllık aralık: …" kalır;
    // görünen başlık kartın içinde "52 hafta" (kart zaten "Aralık" der).
    final semantikBaslik = ay == null ? l.yaBaslikYil : l.yaBaslikAy(ay);
    final baslik = ay == null ? l.ya52Hafta : l.yaBaslikAy(ay);
    final donem = ay == null ? l.yaDonemYil : l.yaDonemAy(ay);
    final cumle = a.yuksegeYakin
        ? (a.uctaMi
            ? l.yaYuksekte(donem)
            : l.yaYuksekAlti(donem, fmtPct(a.yuksektenUzaklikPct, digits: 1)))
        : (a.uctaMi
            ? l.yaDusukte(donem)
            : l.yaDusukUstu(donem, fmtPct(a.dusuktenUzaklikPct, digits: 1)));
    return _AralikSatiri(
      baslik: baslik,
      dusuk: bicim.format(a.dusuk),
      yuksek: bicim.format(a.yuksek),
      konum: a.konum,
      cumle: cumle,
      semantik: l.yaSemantik(semantikBaslik, bicim.format(a.dusuk),
          bicim.format(a.yuksek), bicim.format(a.bugun), cumle),
    );
  }
}

/// [AralikKarti]'nın tek satırı: başlık, nötr çubuk + konum noktası, uçlar,
/// cümle. Ekran okuyucu tek etiket duyar ([semantik]).
class _AralikSatiri extends StatelessWidget {
  const _AralikSatiri({
    required this.baslik,
    required this.dusuk,
    required this.yuksek,
    required this.konum,
    required this.cumle,
    required this.semantik,
  });

  final String baslik;
  final String dusuk;
  final String yuksek;

  /// 0 = dip, 1 = zirve.
  final double konum;
  final String cumle;
  final String semantik;

  @override
  Widget build(BuildContext context) {
    final k = konum.clamp(0.0, 1.0);
    Widget uc(String metin, Alignment hiza) => Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: hiza,
            child: Text(metin,
                maxLines: 1,
                style: context.t.numSmall.copyWith(color: context.c.text90)),
          ),
        );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semantik,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(baslik,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(color: context.c.text58)),
          const SizedBox(height: SandikSpace.xs2),
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: SandikSpace.smd,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: SandikSpace.xs2,
                    decoration: BoxDecoration(
                      color: context.c.hairline,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * k - SandikSpace.xs2)
                        .clamp(0.0, c.maxWidth - SandikSpace.smd),
                    child: Container(
                      width: SandikSpace.smd,
                      height: SandikSpace.smd,
                      decoration: BoxDecoration(
                        color: context.c.text90,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs2),
          // 320pt'de / büyük yazıda iki büyük tutar (ör. ₺1.234.567,89) yan
          // yana sığmaz; kırpılan fiyat yanlış okunur, küçülen okunur.
          Row(
            children: [
              uc(dusuk, Alignment.centerLeft),
              const SizedBox(width: SandikSpace.sm),
              uc(yuksek, Alignment.centerRight),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(cumle,
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
        ],
      ),
    );
  }
}
