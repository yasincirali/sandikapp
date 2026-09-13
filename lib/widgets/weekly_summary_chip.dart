import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../screens/portfolio_performance_screen.dart';
import '../services/analytics_service.dart';
import '../services/history_service.dart';
import '../services/period_summary_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Ana ekrandaki kompakt "Bu hafta" kartı.
///
/// `RealReturnStrip` / `PercentileStrip` komşusu ve aynı kabuğu kullanıyor —
/// üçü yan yana duruyor, ayrı görünmeleri onları farklı sınıf bilgiler gibi
/// gösterirdi.
///
/// **Gösterdiği rakam SAF PİYASA getirisi**, portföy değeri değişimi değil.
/// Ana ekranın üstündeki toplam zaten değeri gösteriyor; bu satırın katkısı
/// "o değişimin ne kadarı piyasadan geldi" sorusunu yanıtlamak. Tıklanınca
/// Özet sekmesinin 1H dönemine düşüyor ve orada aynı rakamın kırılımı var.
///
/// Üç kapı: Remote Config bayrağı, en az iki uçlu bir hafta serisi, ve
/// ölçülebilir bir yüzde. Biri eksikse kart HİÇ çizilmez — eksik veriyle
/// tahmin yürütmek hesap yapmamaktan kötüdür (`InflationService` ile aynı
/// disiplin).
class WeeklySummaryChip extends ConsumerStatefulWidget {
  final List<Asset> myAssets;
  final EdgeInsets padding;

  const WeeklySummaryChip({
    super.key,
    required this.myAssets,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  @override
  ConsumerState<WeeklySummaryChip> createState() => _WeeklySummaryChipState();
}

class _WeeklySummaryChipState extends ConsumerState<WeeklySummaryChip> {
  PeriodSummary? _ozet;
  bool _istendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (_istendi || !mounted) return;
    _istendi = true;

    if (!RemoteConfigService.instance.periodSummaryEnabled) return;
    if (widget.myAssets.isEmpty) return;

    try {
      final now = DateTime.now();
      final p = PeriodSummaryService.pencere(SummaryPeriod.birHafta, now);
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: widget.myAssets,
        from: p.start,
        to: p.end,
        // Merdiven tek yerde: 7 günlük pencere `hourly` tier'a düşüyor.
        // Elle tier seçmek, çözünürlük kuralının ikinci bir kopyasını
        // yaratırdı.
        tier: ResolutionTierMeta.pickForSpan(
            SummaryPeriod.birHafta.days.toDouble()),
      );
      if (!mounted) return;

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: widget.myAssets,
        breakdown: bd,
        now: now,
      );
      if (s.getiriPct == null) return;
      setState(() => _ozet = s);
    } catch (_) {
      // Sessizce vazgeç: ikincil bir satır, ana ekranı düşürmemeli.
    }
  }

  void _ac() {
    AnalyticsService.instance
        .logPeriodSummaryViewed(period: SummaryPeriod.birHafta.name);
    Navigator.push(
      context,
      adaptiveRoute(
        builder: (_) => const PortfolioPerformanceScreen(
          showBackButton: true,
          initialOzet: true,
          // 1H — kartın gösterdiği dönemin kendisi. Başka bir döneme
          // düşmek, tıklanan rakamı bulamayan bir kullanıcı bırakırdı.
          initialPeriodIdx: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _ozet;
    if (s == null) return const SizedBox.shrink();

    final c = context.c;
    // Sıfır bir YÖN taşımaz — nötr tonda yazılır.
    final ton = s.isFlat ? c.text36 : (s.isNegative ? c.loss : c.gain);
    final pct = s.getiriPct!;
    final yazi = fmtPct(pct.abs(), digits: 1);

    return Padding(
      padding: widget.padding,
      child: Semantics(
        button: true,
        label: 'Bu hafta portföyün piyasa getirisi '
            '${s.isFlat ? "değişmedi" : "yüzde $yazi ${s.isNegative ? "ekside" : "artıda"}"}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _ac,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: c.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.text20.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  // Yön RENKLE anlatılmaz — ok her zaman yanında
                  // (RealReturnStrip ile aynı kural, renk körlüğü).
                  if (!s.isFlat)
                    Text(
                      s.isNegative ? '▼' : '▲',
                      style: context.t.labelLarge
                          ?.copyWith(color: ton, fontWeight: FontWeight.w700),
                    )
                  else
                    Icon(Icons.remove_rounded, size: 16, color: ton),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      // Stil `context.t`'den türer: sistem "Kalın Metin"
                      // ayarı orada tek noktada çözülüyor.
                      text: TextSpan(
                        style: context.t.bodyMedium
                            ?.copyWith(height: 1.35, color: c.text58),
                        children: [
                          const TextSpan(text: 'Bu hafta piyasadan '),
                          TextSpan(
                            text: s.isFlat
                                ? 'değişim yok'
                                : '%$yazi ${s.isNegative ? "eksi" : "artı"}',
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
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.text36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
