import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../services/inflation_service.dart';
import '../services/real_return_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

/// Reel getiri rozeti — "portföyün TÜFE'yi kaç puan geçti".
///
/// **Neden bu, ana ekranın en değerli bir satırı:** Türk tasarrufçusunun
/// sorusu "kaç kazandım" değil, **"eridim mi?"**. Nominal getiri o soruya
/// cevap vermiyor. Rakiplerin hiçbiri bunu portföy seviyesinde birinci sınıf
/// metrik yapmıyor.
///
/// Üç kapı: Remote Config bayrağı, portföyün 365 günlük getirisinin
/// hesaplanabilmesi (yeterli geçmiş), ve `inflation_index` tablosunda hem
/// başlangıç hem bitiş ayının bulunması. Biri eksikse rozet HİÇ çizilmez —
/// eksik veriyle tahmin yürütmek, hesap yapmamaktan kötüdür.
///
/// **Sayı `RealReturnService`'ten gelir, yarış ROI'sinden DEĞİL** (2026-09-16):
/// eskiden `LeaderboardService.computeROI` (simülasyon, nakit akışı yok)
/// kullanılıyordu ve rozet Performans/paylaşım kartıyla farklı bir puan
/// söylüyordu (5,7 önde / 1,0 geride). Artık üçü aynı hesabı okuyor.
class RealReturnStrip extends ConsumerStatefulWidget {
  final List<Asset> myAssets;
  final double Function(double value, String currency) toTRY;
  final EdgeInsets padding;

  const RealReturnStrip({
    super.key,
    required this.myAssets,
    required this.toTRY,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  /// Karşılaştırma penceresi — `RealReturnService.periodDays` (365).
  ///
  /// Bir yıl: enflasyon aylık yayımlandığı için kısa pencerede tek ayın
  /// gürültüsü sonucu belirler; yıllık pencere hem TÜİK'in "yıllık
  /// enflasyon" diliyle örtüşür hem de kullanıcının kafasındaki soruya
  /// ("bu yıl eridim mi") denk düşer.
  static const periodDays = RealReturnService.periodDays;

  @override
  ConsumerState<RealReturnStrip> createState() => _RealReturnStripState();
}

class _RealReturnStripState extends ConsumerState<RealReturnStrip> {
  ({double nominal, double inflation, InflationWindow pencere})? _veri;
  bool _istendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (_istendi || !mounted) return;
    _istendi = true;

    if (!RemoteConfigService.instance.realReturnEnabled) return;
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;

    RealReturn? r;
    try {
      r = await RealReturnService.yillik(widget.myAssets);
    } catch (_) {
      // Rozet ikincil: seri kurulamazsa hiç çizilmez, ana ekran bozulmaz.
      // (Eski ROI yolu da aynı sessiz sözleşmeyi taşıyordu.)
      return;
    }
    if (r == null || !mounted) return;

    setState(() => _veri =
        (nominal: r!.nominal, inflation: r.inflation, pencere: r.pencere));
  }

  @override
  Widget build(BuildContext context) {
    final veri = _veri;
    if (veri == null) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: RealReturnBadge(
        nominal: veri.nominal,
        inflation: veri.inflation,
        pencere: veri.pencere,
      ),
    );
  }
}

/// Pencere uçlarını kısa ay biçiminde yazar ("Ağu 2025 – Ağu 2026").
///
/// Rozet tek satır ve `ellipsis` ile kırpılıyor; uzun ay adları sayıları
/// taşırdı. Kart (`_ReelGetiriKarti`) aynı bilgiyi uzun biçimde yazıyor —
/// orada yer var.
String _aralik(BuildContext context, InflationWindow w) {
  final loc = Localizations.localeOf(context).toString();
  final f = DateFormat('MMM yyyy', loc);
  return '${f.format(w.seriBaslangici)} – ${f.format(w.seriBitisi)}';
}

/// Rozetin görsel gövdesi — veri kaynağından ayrı.
///
/// `RealReturnStrip` Remote Config + auth + iki servis arkasında; yerleşimi
/// onun üzerinden test etmek o yığının tamamını kurmayı gerektiriyordu.
/// Bu parça saf: iki sayı alır, rozeti çizer. Yerleşim testleri (dar ekran,
/// büyük metin ölçeği, negatif yön) buraya bakar.
class RealReturnBadge extends StatelessWidget {
  const RealReturnBadge({
    super.key,
    required this.nominal,
    required this.inflation,
    this.pencere,
  });

  final double nominal;
  final double inflation;

  /// İki sayının ÖLÇÜLDÜĞÜ aralık.
  ///
  /// Alt satır eskiden sabit "son 1 yıl" yazıyordu; TÜFE aylık yayımlandığı
  /// için pencere bugüne kadar GELMEZ (son açıklanmış ayda biter). Sabit
  /// etiket, kullanıcının rakamı bugüne kadarki bir aralık sanmasına yol
  /// açıyordu. Verildiğinde gerçek uçlar yazılır. Yerleşim testleri bunu
  /// vermeden de kurabilsin diye opsiyonel.
  final InflationWindow? pencere;

  @override
  Widget build(BuildContext context) {
    final puan = InflationService.spreadPoints(nominal, inflation);
    final onde = puan >= 0;
    // Puan farkı da yuvarlanmaz: yanındaki iki ham sayı iki ondalıklı ve
    // kullanıcı farkı elle doğruluyor (nominal − TÜFE). Tek ondalıkta
    // çıkarma tutmuyordu — 48,20 − 31,51 = 16,69 iken rozet "16,7 puan"
    // yazıyordu ve rozetin kendi kara kutu olmama amacı zedeleniyordu.
    final mutlak = fmtNum(puan.abs(), digits: 2);
    final c = context.c;
    final ton = onde ? c.gain : c.loss;
    final l = context.l10n;

    return Semantics(
      label: onde
          ? l.realReturnSemanticsAhead(mutlak)
          : l.realReturnSemanticsBehind(mutlak),
      // Alt parçalar ayrı ayrı okunmaz: rozet TEK bir cümle anlatıyor
      // ("enflasyonu şu kadar geçtin"), parçalara bölünmüş hâli ekran
      // okuyucuda anlamsız sayı dizisine dönerdi.
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd,
            vertical: SandikSpace.smd,
          ),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: SandikRadius.mdAll,
            border: Border.all(color: c.text20.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Üst satır: ÖNCE rakam ─────────────────────────────
              //
              // Önceki hâli tek akan cümleydi ("Son bir yılda
              // enflasyonun **5,89 puan** önündesin") ve dar ekranda
              // rakam satır sonunda kalıp "puan önündesin" alt satıra
              // düşüyordu: rozetin tek önemli bilgisi ikiye bölünüyordu.
              //
              // Rakam artık cümlenin içinde değil, başında ve kendi
              // tipografik sınıfında (`numMedium`). Cümle onu takip eden
              // niteleyici oldu; sardığında bölünen şey artık açıklama.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // Yön RENKLE anlatılmaz — ok her zaman yanında.
                  // `Icon` yerine metin oku korunuyor: baseline'a oturan
                  // tek yön göstergesi bu, `Icon` satırda yüzüyordu.
                  Text(
                    onde ? '▲' : '▼',
                    style: context.t.labelLarge?.copyWith(
                      color: ton,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: SandikSpace.xs2),
                  Text(
                    mutlak,
                    style: context.t.numMedium.copyWith(color: ton),
                  ),
                  const SizedBox(width: SandikSpace.xs),
                  Text(
                    l.realReturnPointsUnit,
                    style: context.t.bodyMedium?.copyWith(
                      color: ton,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: SandikSpace.xs2),
                  // Niteleyici esner: dar ekranda kırpılan bu, rakam değil.
                  Expanded(
                    child: Text(
                      onde
                          ? l.realReturnAheadOfInflation
                          : l.realReturnBehindInflation,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyMedium?.copyWith(
                        color: c.text58,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.sm),
              // ── Alt satır: doğrulama ──────────────────────────────
              //
              // Kendi satırına indi. Eskiden aynı `Row`'un sağ ucundaydı
              // ve sol taraf iki satıra çıkınca dikeyde kayık duruyordu;
              // ayrıca iki farklı ağırlıktaki bilgi (mesaj + denetim
              // sayıları) aynı yatay düzlemde yarışıyordu.
              //
              // Ham iki sayı verilmeye devam ediyor: kullanıcı puan
              // farkını elle doğrulayabilmeli, yoksa rozet kara kutu
              // olur. Etiketlendiler ("Senin %… · TÜFE %…") — çıplak
              // yüzde ikilisi hangisinin ne olduğunu söylemiyordu.
              //
              // **YUVARLAMA YOK — iki ondalık.** Önceden `digits: 0` idi
              // ve TÜFE %31,51 ekranda "%32" görünüyordu; kullanıcı bunu
              // TÜİK'in açıkladığı rakamla karşılaştırdığında tutmuyor ve
              // doğrulama amacı boşa çıkıyordu. Daha kötüsü: yuvarlama
              // ARIZAYI GİZLİYORDU — pencere bir ay eksik sayıldığı için
              // gelen %27,68 de, doğrusu olan %31,51 de yuvarlanınca
              // "makul" bir tam sayıya dönüşüyordu (2026-09-14'te ekran
              // görüntüsüyle yakalandı). Ham sayı tam yazılırsa sapma
              // gözle görünür.
              //
              // `_ReelGetiriKarti` de iki ondalık yazıyor (`fmtPct`
              // varsayılanı); iki yüzey aynı sayıyı farklı yuvarlarsa
              // kullanıcı hangisine güveneceğini bilemez.
              Text(
                '${l.realReturnYours} %${fmtNum(nominal, digits: 2)}'
                '  ·  ${l.realReturnCpi} %${fmtNum(inflation, digits: 2)}'
                '  ·  ${pencere == null ? l.realReturnLastYear : _aralik(context, pencere!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(color: c.text36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
