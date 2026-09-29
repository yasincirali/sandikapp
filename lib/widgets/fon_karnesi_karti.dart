import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_karnesi_provider.dart';
import '../services/analytics_service.dart';
import '../services/fon_karnesi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Fon karnesi kartı (F4, 2026-09-29) — fonun kendi kategorisindeki yeri.
///
/// Hesap `fon_karnesi.dart`'ta (saf), veri `fonKarnesiProvider`'da; bu dosya
/// yalnızca çizer. Kararların gerekçesi `fon_karnesi.dart` başlığında.
///
/// ## Ne zaman HİÇ çizilmez
///   · Bayrak (`fund_report_card_enabled`) kapalı,
///   · varlık fon değil,
///   · katalog yükleniyor ya da hata verdi,
///   · karne kurulamadı (kategori bilinmiyor, tek fonlu kategori…).
/// Yükleme için iskelet çizilmez: karne ek bilgidir, sayfanın dibinde durur;
/// "gelmeyebilecek" bir kutu için yer ayırmak boşluk bırakabilirdi.
///
/// ## Dönem seçimi yok
/// Üç dönem (1 ay, yılbaşından beri, 1 yıl) alt alta yazılır. Seçici bir
/// dokunuş daha ister ve üç satır 320pt'de rahat sığar; kullanıcı kısa ve
/// uzun vadede tutarlı mı, tek bakışta görür.
///
/// ## Dil: yüzde PUAN
/// "sen +4,2" yerine "Ortancanın 4,2 puan üstünde": fark yüzde değil puan
/// (bkz. `DonemSirasi.ortancayaFark`), cümle de bunu söyler.
class FonKarnesiKarti extends ConsumerStatefulWidget {
  const FonKarnesiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;

  /// Kart çizildiğinde çevresine bırakılan boşluk. Çizilmezse boşluk da
  /// yoktur — çağıran yerin kendi `SizedBox`'ı olsaydı kart yokken boş bir
  /// aralık kalırdı.
  final EdgeInsetsGeometry dis;

  @override
  ConsumerState<FonKarnesiKarti> createState() => _FonKarnesiKartiState();
}

class _FonKarnesiKartiState extends ConsumerState<FonKarnesiKarti> {
  // Olay kart başına BİR kez: kaydırma/yeniden çizim sayıyı şişirmesin.
  bool _bildirildi = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(fonKarnesiAcikProvider)) return const SizedBox.shrink();
    final kod = fonKoduOf(tur: widget.tur, ticker: widget.ticker);
    if (kod == null) return const SizedBox.shrink();
    final karne = ref.watch(fonKarnesiProvider(kod)).valueOrNull;
    if (karne == null) return const SizedBox.shrink();

    if (!_bildirildi) {
      _bildirildi = true;
      AnalyticsService.instance.logFundCardViewed(category: karne.kategori);
    }

    final l10n = context.l10n;
    return Padding(
      padding: widget.dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.fundReportTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.fundReportCategory(
                      karne.kategori, _adet(karne.kategoriFonSayisi)),
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90),
                ),
                for (final d in karne.donemler) ...[
                  const SizedBox(height: SandikSpace.smd),
                  Divider(height: 1, thickness: 1, color: context.c.hairline),
                  const SizedBox(height: SandikSpace.smd),
                  _DonemSatiri(sira: d),
                ],
                const SizedBox(height: SandikSpace.md),
                Text(
                  l10n.fundReportFootnote,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonemSatiri extends StatelessWidget {
  const _DonemSatiri({required this.sira});

  final DonemSirasi sira;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fark = sira.ortancayaFark;
    final (farkMetni, farkRengi) = _farkMetni(l10n, context.c, fark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                donemAdi(l10n, sira.donem),
                style: context.t.bodyMedium?.copyWith(color: context.c.text58),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Flexible(
              child: Text(
                l10n.fundReportRank(_adet(sira.kiyasSayisi), '${sira.sira}'),
                textAlign: TextAlign.end,
                style: context.t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: context.c.text90),
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          l10n.fundReportReturnVsMedian(
              fmtPct(sira.getiri), fmtPct(sira.ortanca)),
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
        const SizedBox(height: SandikSpace.xxs),
        Text(
          farkMetni,
          style: context.t.bodySmall
              ?.copyWith(color: farkRengi, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Portföy kartının açılır panelindeki tek satır:
/// "Kategorisinde 188 fondan 23. (1 yıl)". Kartla aynı provider ve aynı
/// bayrak; çizilmeme koşulları da aynı.
class FonKarnesiSatiri extends ConsumerWidget {
  const FonKarnesiSatiri({super.key, required this.tur, required this.ticker});

  final AssetType tur;
  final String ticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(fonKarnesiAcikProvider)) return const SizedBox.shrink();
    final kod = fonKoduOf(tur: tur, ticker: ticker);
    if (kod == null) return const SizedBox.shrink();
    final karne = ref.watch(fonKarnesiProvider(kod)).valueOrNull;
    if (karne == null) return const SizedBox.shrink();
    final d = karne.ozetDonemi;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm2),
      child: Text(
        l10n.fundReportPanelLine(
            _adet(d.kiyasSayisi), '${d.sira}', donemAdi(l10n, d.donem)),
        style: context.t.bodySmall
            ?.copyWith(color: context.c.text58, fontWeight: FontWeight.w500),
      ),
    );
  }
}

String donemAdi(AppLocalizations l10n, KarneDonemi d) => switch (d) {
      KarneDonemi.ay1 => l10n.fundReportPeriod1m,
      KarneDonemi.yilBasi => l10n.fundReportPeriodYtd,
      KarneDonemi.yil1 => l10n.fundReportPeriod1y,
    };

/// Fon sayısı — binlik ayraçlı (katalog 1.069 fon; kategori de büyüyebilir).
String _adet(int n) => fmtNum(n.toDouble(), digits: 0);

/// Ortancaya fark metni ve rengi. 0,05 puandan küçük fark bir ondalıkla
/// "0,0 puan üstünde" yazılırdı; o durumda "Ortancayla aynı" denir ve renk
/// nötr kalır (yeşil/kırmızı, olmayan bir farkı abartırdı).
(String, Color) _farkMetni(
    AppLocalizations l10n, SandikPalette c, double fark) {
  if (fark.abs() < 0.05) return (l10n.fundReportAtMedian, c.text58);
  final pts = fmtNum(fark.abs(), digits: 1);
  return fark > 0
      ? (l10n.fundReportAboveMedian(pts), c.gain)
      : (l10n.fundReportBelowMedian(pts), c.loss);
}
