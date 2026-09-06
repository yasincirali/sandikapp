import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show leaderboardOptInProvider;
import '../services/analytics_service.dart';
import '../services/leaderboard_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';

/// Ana ekranda anonim yüzdelik dilim şeridi.
///
/// **Neden ana ekranda?** Karşılaştırma zaten Yarış ekranında var
/// (`_GlobalPercentileTeaser`) ama oraya kullanıcı bilerek gider — yani
/// zaten gelmiş olanı görür. Tutundurmaya katkı, uygulamayı açan HERKESİN
/// görmesiyle olur; şeridin varlık sebebi budur.
///
/// **Neden tutar değil dilim?** Para üstünden karşılaştırma hem mahremiyeti
/// hem motivasyonu bozar (alttakini demotive eder, üsttekini teşhir eder).
/// Dilim, sosyal karşılaştırmanın motive eden yarısını verir.
///
/// Üç kapı: Remote Config bayrağı, kullanıcının yarış opt-in'i ve sunucudaki
/// k-anonimlik eşiği. Üçünden biri kapalıysa şerit HİÇ çizilmez —
/// "yakında" plaseholderi ana ekranda yer işgal etmeye değmez.
class PercentileStrip extends ConsumerStatefulWidget {
  /// Kullanıcının kendi ham lot'ları (ortak varlıkları DEĞİL).
  final List<Asset> myAssets;

  /// Tutarı TRY'ye çeviren dönüştürücü — `PortfolioState.toTRY`.
  final double Function(double value, String currency) toTRY;

  /// Görünürken uygulanacak dolgu.
  ///
  /// Dolgu ÇAĞIRANDA değil burada durur: şerit çoğu zaman hiç çizilmez
  /// (bayrak kapalı, opt-in yok ya da k-anonimlik eşiği dolmamış) ve dışarıda
  /// bir `Padding` olsaydı o durumlarda ana ekranda sebepsiz bir boşluk
  /// kalırdı.
  final EdgeInsets padding;

  const PercentileStrip({
    super.key,
    required this.myAssets,
    required this.toTRY,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  /// Karşılaştırma penceresi. Plan "son 30 gün" diyor: 7 gün gürültülü,
  /// 365 gün yeni kullanıcıyı dışarıda bırakır.
  static const periodDays = 30;

  @override
  ConsumerState<PercentileStrip> createState() => _PercentileStripState();
}

class _PercentileStripState extends ConsumerState<PercentileStrip> {
  ({int percentile, int total})? _data;
  bool _istendi = false;

  @override
  void initState() {
    super.initState();
    // Build içinde değil: hesap ağ çağrısı içeriyor ve `initState` sırasında
    // provider okumak güvenli değil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (_istendi || !mounted) return;
    _istendi = true; // tek atış: her rebuild'de ROI hesaplatma

    if (!RemoteConfigService.instance.percentileStripEnabled) return;
    if (!ref.read(leaderboardOptInProvider)) return;
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;

    // Snapshot'ı BURADA tazele.
    //
    // `get_percentile_bucket` yalnızca son 24 saatte snapshot atmış
    // kullanıcıları karşılaştırır. Yükleme eskiden sadece Yarış ekranında
    // yapılıyordu; ana ekran şeridi ona bağlı kalsaydı yalnızca "bugün
    // Yarış'a uğramış" kullanıcıda çalışır, yani hiç görünmezdi.
    final servis = LeaderboardService.instance;
    final roi = await servis.computeROI(
      assets: widget.myAssets,
      periodDays: PercentileStrip.periodDays,
      currentValueTRY: servis.totalValueTRY(widget.myAssets, widget.toTRY),
      toTRY: widget.toTRY,
      cacheKey: me.id,
    );
    if (roi == null) return; // geçmiş veri yetersiz — karşılaştırma yapılamaz
    await servis.uploadRoiSnapshot(
      userId: me.id,
      periodDays: PercentileStrip.periodDays,
      roiPct: roi,
    );

    final data = await servis.fetchPercentile(PercentileStrip.periodDays);
    if (!mounted || data == null) return;

    AnalyticsService.instance.logPercentileViewed(
      bucket: data.percentile,
      periodDays: PercentileStrip.periodDays,
    );
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    // RPC'de 1 = en üst, 100 = en alt. Kullanıcıya "kaçından iyisin"
    // demek "ilk %X'tesin"den daha anlaşılır ve daha az yarışmacı bir dil.
    final ustundeOlduklari = 100 - data.percentile;
    final iyiTaraf = data.percentile <= 50;

    return Padding(
      padding: widget.padding,
      child: Semantics(
        label: 'Son 30 günde katılımcıların yüzde $ustundeOlduklari '
            'kadarının üstündesin',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.c.text20.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: iyiTaraf ? context.c.gain : context.c.text58,
              ),
              const SizedBox(width: 10),
              Expanded(
                // Stiller `context.t`'den türer: sistem "Kalın Metin"
                // erişilebilirlik ayarı orada tek noktada çözülür; elle
                // yazılmış bir `TextStyle` o yolu atlardı
                // (bkz. bold_text_support_test).
                child: RichText(
                  text: TextSpan(
                    style: context.t.bodyMedium?.copyWith(
                      height: 1.35,
                      color: context.c.text58,
                    ),
                    children: [
                      const TextSpan(text: 'Son 30 günde senin gibi '),
                      TextSpan(
                        text: "yatırımcıların %$ustundeOlduklari'inden",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: iyiTaraf ? context.c.gain : context.c.text90,
                        ),
                      ),
                      const TextSpan(text: ' iyi getirdin'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Katılımcı sayısı: karşılaştırmanın kaç kişilik havuzdan
              // geldiğini söylemek hem güveni artırır hem k-anonimliği
              // görünür kılar.
              Text(
                '${data.total} kişi',
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: context.c.text36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
