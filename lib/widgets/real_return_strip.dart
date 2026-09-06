import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../services/inflation_service.dart';
import '../services/leaderboard_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';

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

  /// Karşılaştırma penceresi.
  ///
  /// Bir yıl: enflasyon aylık yayımlandığı için kısa pencerede tek ayın
  /// gürültüsü sonucu belirler; yıllık pencere hem TÜİK'in "yıllık
  /// enflasyon" diliyle örtüşür hem de kullanıcının kafasındaki soruya
  /// ("bu yıl eridim mi") denk düşer.
  static const periodDays = 365;

  @override
  ConsumerState<RealReturnStrip> createState() => _RealReturnStripState();
}

class _RealReturnStripState extends ConsumerState<RealReturnStrip> {
  ({double nominal, double inflation})? _veri;
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

    // Enflasyon ÖNCE sorulur: tablo boşsa (olağan başlangıç durumu) pahalı
    // olan ROI hesabına hiç girilmez.
    final enflasyon = await InflationService.instance
        .inflationForPeriod(RealReturnStrip.periodDays);
    if (enflasyon == null || !mounted) return;

    final servis = LeaderboardService.instance;
    final nominal = await servis.computeROI(
      assets: widget.myAssets,
      periodDays: RealReturnStrip.periodDays,
      currentValueTRY: servis.totalValueTRY(widget.myAssets, widget.toTRY),
      toTRY: widget.toTRY,
      cacheKey: me.id,
    );
    if (nominal == null || !mounted) return;

    setState(() => _veri = (nominal: nominal, inflation: enflasyon));
  }

  @override
  Widget build(BuildContext context) {
    final veri = _veri;
    if (veri == null) return const SizedBox.shrink();

    final puan = InflationService.spreadPoints(veri.nominal, veri.inflation);
    final onde = puan >= 0;
    final mutlak = puan.abs().toStringAsFixed(1).replaceAll('.', ',');
    final c = context.c;
    final ton = onde ? c.gain : c.loss;

    return Padding(
      padding: widget.padding,
      child: Semantics(
        label: 'Son bir yılda portföyün enflasyonu yüzde $mutlak puan '
            '${onde ? "geçti" : "gerisinde kaldı"}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.text20.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              // Yön RENKLE anlatılmaz — ok her zaman yanında.
              Text(
                onde ? '▲' : '▼',
                style: context.t.labelLarge?.copyWith(
                  color: ton,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: context.t.bodyMedium
                        ?.copyWith(height: 1.35, color: c.text58),
                    children: [
                      const TextSpan(text: 'Son bir yılda enflasyonun '),
                      TextSpan(
                        text: '$mutlak puan ${onde ? "önündesin" : "gerisindesin"}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ton,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Ham iki sayı da verilir: kullanıcı puan farkını
              // doğrulayabilmeli, yoksa rozet bir kara kutu olur.
              Text(
                '%${veri.nominal.toStringAsFixed(0)} · '
                'TÜFE %${veri.inflation.toStringAsFixed(0)}',
                style: context.t.bodySmall?.copyWith(color: c.text36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
